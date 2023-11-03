#!/bin/bash -e

SHELL_PATH=$(
    cd "$(dirname $0)"
    pwd
)

export AWS_CLI_FILE_ENCODING=UTF-8

LOGS_DIR="${SHELL_PATH}/logs"
rm -rf "$LOGS_DIR"
mkdir -p "$LOGS_DIR"

CACHE_DIR="${SHELL_PATH}/cache"
mkdir -p "$CACHE_DIR"

#############################################################################################################
# 引数
#

STACK_NAME=$1
if [ "$STACK_NAME" == "" ]; then
    echo "スタック名を指定してください"
    exit
fi

TEMPLATE_PATH=$2
if [ "$TEMPLATE_PATH" == "" ]; then
    echo "テンプレートファイルを指定してください"
    exit
fi

shift 2

PARAMETERS=()
while getopts "c:r:a:p:s:" optKey; do
    case "$optKey" in
    c) CHANGE_STACK_NAME="${OPTARG}" ;;
    r) RESOURCES_TO_IMPORT_PATH="${OPTARG}" ;;
    a) APPEND_RESOURCES_TO_IMPORT_PATH="${OPTARG}" ;;
    p) PARAMETERS+=(${OPTARG}); ;;
    s) PKG_S3_BUCKET="${OPTARG}" ;;
    esac
done

if [ "$CHANGE_STACK_NAME" == "" ]; then
    CHANGE_STACK_NAME=$STACK_NAME
fi

#############################################################################################################
# 関数定義
#

function checkExists() {
    set +e
    if [ "$2" == "" ]; then
        aws cloudformation describe-stacks --stack-name $1 > /dev/null 2>&1
    else
        aws cloudformation describe-change-set --stack-name $1 --change-set-name $2 > /dev/null 2>&1
    fi
    echo $?
    set -e
}

function getResourcesToImport(){
    local STACK_NAME=$1
    local DESCRIBE_STACK_RESOURCES="$2"
    local TEMPLATE_SUMMARY="$3"

    if [ "$DESCRIBE_STACK_RESOURCES" == "" ]; then
        DESCRIBE_STACK_RESOURCES=$(aws cloudformation describe-stack-resources --stack-name $STACK_NAME)
    fi

    if [ "$TEMPLATE_SUMMARY" == "" ]; then
        TEMPLATE_SUMMARY=$(aws cloudformation get-template-summary --stack-name $STACK_NAME)
    fi

    jq -n \
        --argjson r "$DESCRIBE_STACK_RESOURCES" \
        --argjson s "$TEMPLATE_SUMMARY" \
        '[
            $s.ResourceIdentifierSummaries[] |
            .ResourceType as $type |
            .ResourceIdentifiers[0] as $idKey |
            .LogicalResourceIds[] |
            . as $lid |
            ($r.StackResources[] | select(.ResourceStatus != "DELETE_COMPLETE" and
                .LogicalResourceId == $lid)).PhysicalResourceId as $pid |
            select($pid) |
            {
                "ResourceType": $type,
                "LogicalResourceId": $lid,
                "ResourceIdentifier": {
                    ($idKey): (($r.StackResources[] | select(.LogicalResourceId == $lid)).PhysicalResourceId)
                }
            }
        ]'
}

function deleteStackWithRetainResources(){
    local STACK_NAME=$1
    local STACK_STATUS=$2
    local STACK_TEMPLATE_SUMMARY="$3"
    shift 3
    local REPLACE_TARGET_IDS="$@"

    if [ "$STACK_STATUS" == "" ]; then
        STACK_STATUS=$(aws cloudformation list-stacks --query "StackSummaries[?StackName=='$STACK_NAME']" |
            jq -rb '[.[] | select(.StackStatus != "REVIEW_IN_PROGRESS")] | .[0].StackStatus')
    fi

    if [ "$STACK_TEMPLATE_SUMMARY" == "" ]; then
        STACK_TEMPLATE_SUMMARY=$(aws cloudformation get-template-summary --stack-name $STACK_NAME)
    fi

    if [[ "$STACK_STATUS" != "DELETE_COMPLETE" ]]; then
        if [ "$STACK_STATUS" != "ROLLBACK_COMPLETE" ] ; then
            echo "get stack template"
            STACK_TEMPLATE=$(aws cloudformation get-template --stack-name $STACK_NAME | jq -r ".TemplateBody" | rain fmt --json)
            STACK_PARAMETERS=$(echo "$STACK_TEMPLATE_SUMMARY" | jq \
                '[.Parameters[].ParameterKey | { "ParameterKey": ., "UsePreviousValue": true } ]')
            STACK_CAPABILITIES=$(echo "$STACK_TEMPLATE_SUMMARY" | jq -r '(.Capabilities // []) | join(" ")')

            if [ ${#REPLACE_TARGET_IDS[@]} -eq 0 ]; then
                # 全てのリソースのDeletionPolicyをRetainに変更
                STACK_TEMPLATE=$(echo "$STACK_TEMPLATE" |
                    jq '.Resources |= with_entries(.value.DeletionPolicy = "Retain")')
            else
                # 論理ID変更対象のDeletionPolicyをRetainに変更
                REPLACE_TARGET_IDS=$(IFS=$'\n'; echo "${REPLACE_TARGET_IDS[*]}" | jq -csR 'split("\n")[:-1]')

                STACK_TEMPLATE=$(echo "$STACK_TEMPLATE" |
                    jq --argjson ids "$REPLACE_TARGET_IDS" \
                        '.Resources |= with_entries(
                            if (.key as $key | $ids | index($key)) then
                                .value.DeletionPolicy = "Retain"
                            end)')
            fi

            # スタックのDeletionPolicyを更新
            executeChangeSet "$STACK_NAME" "cf-script-update-deletion-policy-change-set" \
                "$STACK_TEMPLATE" "$STACK_PARAMETERS" "$STACK_CAPABILITIES" "for DeletionPolicy=Retain update $STACK_NAME"
        fi

        if [ ${#REPLACE_TARGET_IDS[@]} -eq 0 ]; then
            # 変更前のスタックを削除
            echo "delete old stack $STACK_NAME"
            aws cloudformation delete-stack --stack-name $STACK_NAME

            echo "... wait stack delete complete ..."
            aws cloudformation wait stack-delete-complete --stack-name $STACK_NAME
            echo
        else
            # 変更対象のリソースを削除
            STACK_TEMPLATE=$(echo "$STACK_TEMPLATE" |
                jq --argjson deleteKeys "$REPLACE_TARGET_IDS" \
                    'reduce $deleteKeys[] as $key (. ; .Resources |= del(.[ $key ]))')

            if [ "$(echo "$STACK_TEMPLATE" | jq '.Resources | to_entries | length')" != "0" ]; then
                executeChangeSet "$STACK_NAME" "cf-script-delete-old-resources-change-set" \
                    "$STACK_TEMPLATE" "$STACK_PARAMETERS" "$STACK_CAPABILITIES" "for delete old resources $STACK_NAME"
            fi
        fi
    fi
}

function executeChangeSet() {
    local STACK_NAME="$1"
    local CHANGE_SET_NAME="$2"
    local TEMPLATE_BODY="$3"
    local PARAMETERS="$4"
    local CAPABILITIES="$5"
    local MESSAGE="$6"
    local RESOURCES_TO_IMPORT="$7"

    # yamlに変換してファイル出力
    if [[ "$TEMPLATE_BODY" != file://* ]]; then
        TEMPLATE_BODY=$(echo "$TEMPLATE_BODY" | rain fmt)
        echo "$TEMPLATE_BODY" > "${LOGS_DIR}/${STACK_NAME}_${CHANGE_SET_NAME}.yml"
    fi

    local EXISTS_STACK=true
    if [ $(checkExists $STACK_NAME) -ne 0 ]; then
        EXISTS_STACK=false
    else
        local STACK_INFO=$(aws cloudformation describe-stacks --stack-name $STACK_NAME)
        if [ "$(echo "$STACK_INFO" | jq -r ".Stacks[].StackStatus")" == "REVIEW_IN_PROGRESS" ]; then
            EXISTS_STACK=false
        fi
    fi

    local CHANGE_SET_NAME_OPTIONS=(--stack-name "$STACK_NAME" --change-set-name "$CHANGE_SET_NAME")
    local COMMAND=
    local OPTIONS=
    if [ "$RESOURCES_TO_IMPORT" != "" ]; then
        # インポート
        COMMAND=import
        OPTIONS=(--change-set-type IMPORT --resources-to-import "$RESOURCES_TO_IMPORT")
        echo "$RESOURCES_TO_IMPORT" > "${LOGS_DIR}/${STACK_NAME}_${CHANGE_SET_NAME}.json"
    elif [ "$EXISTS_STACK" == "false" ]; then
        # 新規作成
        COMMAND=create
        OPTIONS=(--change-set-type CREATE)
    else
        # 更新
        COMMAND=update
    fi

    # 失敗した変更セットが残っていたら削除
    if [ $(checkExists $STACK_NAME $CHANGE_SET_NAME) -eq 0 ]; then
        echo "delete change set"
        aws cloudformation delete-change-set "${CHANGE_SET_NAME_OPTIONS[@]}"
    fi

    # パラメータ
    if [ "$PARAMETERS" != "" ]; then
        if echo "$PARAMETERS" | jq . >/dev/null 2>&1; then
            OPTIONS+=(--parameters "$PARAMETERS")
        else
            IFS=' ' read -ra PARAMETERS <<< "$PARAMETERS"
            if [ ${#PARAMETERS[@]} -ne 0 ]; then
                OPTIONS+=(--parameters "${PARAMETERS[@]}")
            fi
        fi
    fi

    # ケイパビリティ
    if [ "$CAPABILITIES" != "" ]; then
        CAPABILITIES=($CAPABILITIES)
        OPTIONS+=(--capabilities "${CAPABILITIES[@]}")
    fi

    echo "create change set $MESSAGE"
    aws cloudformation create-change-set \
        "${CHANGE_SET_NAME_OPTIONS[@]}" \
        --template-body "$TEMPLATE_BODY" \
        "${OPTIONS[@]}"

    echo "... wait create change set ..."
    set +e
    ERROR=$(aws cloudformation wait change-set-create-complete "${CHANGE_SET_NAME_OPTIONS[@]}" 2>&1 > /dev/null)
    set -e
    echo

    DESCRIBE_CHANGE_SET=$(aws cloudformation describe-change-set "${CHANGE_SET_NAME_OPTIONS[@]}")
    EXECUTION_STATUS=$(echo "$DESCRIBE_CHANGE_SET" | jq -r ".ExecutionStatus")
    STATUS_REASON=$(echo "$DESCRIBE_CHANGE_SET" | jq -r ".StatusReason")

    if [ "$EXECUTION_STATUS" == "AVAILABLE" ]; then
        echo "execute change set $MESSAGE"
        aws cloudformation execute-change-set "${CHANGE_SET_NAME_OPTIONS[@]}"

        echo "... wait stack $COMMAND complete ..."
        aws cloudformation wait stack-$COMMAND-complete --stack-name $STACK_NAME
        echo
    elif [[ "$STATUS_REASON" == "The submitted information didn't contain changes."* ]]; then
        echo "update not exists. delete change set"
        aws cloudformation delete-change-set "${CHANGE_SET_NAME_OPTIONS[@]}"
    else
        echo "$ERROR"
        exit 1
    fi
}

#############################################################################################################
# main
#

# 変更先スタックの存在確認　同じ名前でリプレイスする場合はスルー
if [[ "$STACK_NAME" != "$CHANGE_STACK_NAME" && $(checkExists $CHANGE_STACK_NAME) -eq 0 ]]; then
    STACK_STATUS=$(aws cloudformation describe-stacks --stack-name $CHANGE_STACK_NAME | jq -r ".Stacks[0].StackStatus")
    if [ "$STACK_STATUS" != "REVIEW_IN_PROGRESS" ]; then
        echo "スタック $CHANGE_STACK_NAME は既に存在します。"
        exit
    fi
fi

if [ "$PKG_S3_BUCKET" == "" ]; then
    TEMPLATE=$(cat "$TEMPLATE_PATH")
else
    TEMPLATE=$(rain pkg "$TEMPLATE_PATH" --s3-bucket "$PKG_S3_BUCKET")
fi

TEMPLATE=$(echo "$TEMPLATE" | rain fmt --json)

CACHE_TEMPLATE_PATH="${CACHE_DIR}/${CHANGE_STACK_NAME}_template.json"
if [[ "$STACK_NAME" == "$CHANGE_STACK_NAME" && -e "$CACHE_TEMPLATE_PATH" ]]; then
    if [ "$(echo "$TEMPLATE" | jq -cS)" == "$(cat "$CACHE_TEMPLATE_PATH" | jq -cS)" ]; then
        echo "テンプレートに変更はありませんでした。"
        exit
    fi
fi

# スタックの最新情報を取得
echo "get stack information"
{
    read -r STACK_ID
    read -r STACK_STATUS
} <<< $(aws cloudformation list-stacks --query "StackSummaries[?StackName=='$STACK_NAME']" |
    jq -rb '[.[] | select(.StackStatus != "REVIEW_IN_PROGRESS")] | .[0].StackId, .[0].StackStatus')

if [ "$STACK_STATUS" == "ROLLBACK_IN_PROGRESS" ]; then
    echo "... wait stack rollback complete ..."
    aws cloudformation wait stack-rollback-complete --stack-name $STACK_NAME
    echo
fi

if [ "$STACK_ID" != "null" ]; then
    DESCRIBE_STACK_RESOURCES=$(aws cloudformation describe-stack-resources --stack-name $STACK_ID)
fi

# インポート時に指定する各リソースの識別子を取得
echo "get resources to import"
if [ "$RESOURCES_TO_IMPORT_PATH" != "" ]; then
    RESOURCES_TO_IMPORT=$(cat "$RESOURCES_TO_IMPORT_PATH")
elif [ "$STACK_ID" != "null" ]; then
    STACK_TEMPLATE_SUMMARY=$(aws cloudformation get-template-summary --stack-name $STACK_NAME)
    RESOURCES_TO_IMPORT=$(getResourcesToImport $STACK_ID "$DESCRIBE_STACK_RESOURCES" "$STACK_TEMPLATE_SUMMARY")
else
    RESOURCES_TO_IMPORT="[]"
fi

if [ "$APPEND_RESOURCES_TO_IMPORT_PATH" != "" ]; then
    RESOURCES_TO_IMPORT=$(cat "$APPEND_RESOURCES_TO_IMPORT_PATH" | jq --argjson r "$RESOURCES_TO_IMPORT" '$r+.')
fi

# 既存のスタックに存在しないLogicalIdのリソースに、どの既存リソースをインポートするか選択する
TEMPLATE_RESOURCES=$(echo "$TEMPLATE" | jq -cb '.Resources | to_entries | .[]')
TEMPLATE_RESOURCE_IDS=$(echo "$TEMPLATE_RESOURCES" | jq -cs "[.[].key]")

echo "get local template summary"
LOCAL_TEMPLATE_SUMMARY=$(aws cloudformation get-template-summary --template-body "$TEMPLATE")

NEW="なし（新規作成）"
INPUT="リソースIDを入力する"
PS3="番号を入力: "

IMPORT_RESOURCE_IDS=()
REPLACE_TARGET_IDS=()

CACHE_CHOICES_PATH="${CACHE_DIR}/${STACK_NAME}_choices.json"
if [ -e "$CACHE_CHOICES_PATH" ]; then
    CHOICES=$(cat "$CACHE_CHOICES_PATH")
else
    CHOICES="{}"
fi

if [[ "$STACK_NAME" != "$CHANGE_STACK_NAME" || "$STACK_STATUS" == "DELETE_COMPLETE" || "$STACK_STATUS" == "ROLLBACK_COMPLETE" ]]; then
    # スタック名変える場合、もしくはスタックが既にない場合はスタックを削除して再作成
    DELETE_STACK=true
fi

_IFS="$IFS"
IFS=$'\n'
for r in $TEMPLATE_RESOURCES; do
    IFS="$_IFS"
    RESOURCE_ID=$(echo "$r" | jq -r ".key")
    RESOURCE_TYPE=$(echo "$r" | jq -r ".value.Type")

    if [ "$DESCRIBE_STACK_RESOURCES" != "" ]; then
        if echo "$DESCRIBE_STACK_RESOURCES" | jq --exit-status \
                --arg id "$RESOURCE_ID" \
                '.StackResources | any(.ResourceStatus != "DELETE_COMPLETE" and .LogicalResourceId == $id)' > /dev/null; then
            # 前のスタックに存在するリソースの場合
            if [ "$DELETE_STACK" == "true" ]; then
                IMPORT_RESOURCE_IDS+=($RESOURCE_ID)
                echo "$RESOURCE_ID: 同じリソースをインポート"
            else
                echo "$RESOURCE_ID: インポートなし"
            fi
            continue
        fi
    fi

    TARGET_RESOURCE_IDENTIFIER=$(echo "$RESOURCES_TO_IMPORT" | jq \
        --arg id "$RESOURCE_ID" \
        -r '[.[] | select(.LogicalResourceId == $id)] | .[0].ResourceIdentifier // ""')

    if [ "$TARGET_RESOURCE_IDENTIFIER" == "" ]; then
        CHOICE=$(echo "$CHOICES" | jq --arg id "$RESOURCE_ID" -r '.[$id] // ""')

        if [ "$CHOICE" == "" ]; then
            CANDIDATES=$(echo "$RESOURCES_TO_IMPORT" | jq \
                --arg type "$RESOURCE_TYPE" \
                --argjson ids "$TEMPLATE_RESOURCE_IDS" \
                -r '[.[] | select(.ResourceType == $type and
                    (.LogicalResourceId as $lid | $ids | index($lid) | not)) |
                    .LogicalResourceId] | join(" ")')

            echo
            echo "$RESOURCE_ID にインポートするリソースを選択してください"

            CANDIDATES="$NEW $INPUT $CANDIDATES"
            select CHOICE in $CANDIDATES; do
                if [ "$CHOICE" != "" ]; then
                    break
                fi
            done

            CHOICES=$(echo "$CHOICES" | jq --arg id "$RESOURCE_ID" --arg choice "$CHOICE" '.[$id] = $choice')
            echo "$CHOICES" > "$CACHE_CHOICES_PATH"
        fi

        case "$CHOICE" in
        $NEW) # 新規リソース
            continue
            ;;
        *) # 既存リソースのインポート
            IMPORT_RESOURCE_IDS+=($RESOURCE_ID)

            if [ "$CHOICE" != "$INPUT" ]; then
                REPLACE_TARGET_ID="$CHOICE"
                TARGET_RESOURCE_IDENTIFIER=$(echo "$RESOURCES_TO_IMPORT" | jq \
                    --arg targetId "$REPLACE_TARGET_ID" \
                    -r '[.[] | select(.LogicalResourceId == $targetId)] | .[0].ResourceIdentifier // ""')
            else
                TARGET_RESOURCE_IDENTIFIER="{}"
            fi
            ;;
        esac
    else
        REPLACE_TARGET_ID="$RESOURCE_ID"
        IMPORT_RESOURCE_IDS+=($RESOURCE_ID)
    fi

    # インポートするのに必要なプロパティのリストを取得
    RESOURCE_IDENTIFIER_KEYS=$(echo "$LOCAL_TEMPLATE_SUMMARY" | jq \
        --arg type "$RESOURCE_TYPE" \
        --argjson ridObj "$TARGET_RESOURCE_IDENTIFIER" \
        -cr '.ResourceIdentifierSummaries[] |
            select(.ResourceType == $type) | .ResourceIdentifiers[] |
            select((in($ridObj) | not) or $ridObj.[.] == null)')

    if [ "$RESOURCE_IDENTIFIER_KEYS" != "" ]; then
        # インポートするリソースのIDを入力する
        echo "$RESOURCE_ID のリソースIDを入力してください。"
        for idKey in $RESOURCE_IDENTIFIER_KEYS; do
            PHYSICAL_RESOURCE_ID=$(echo "$TARGET_RESOURCE_IDENTIFIER" | jq --arg idKey "$idKey" -r '.[$idKey] // ""')

            while [ "$PHYSICAL_RESOURCE_ID" == "" ]; do
                read -p "$idKey:" -r PHYSICAL_RESOURCE_ID
            done

            TARGET_RESOURCE_IDENTIFIER=$(echo "$TARGET_RESOURCE_IDENTIFIER" | jq \
                --arg idKey "$idKey" \
                --arg pid "$PHYSICAL_RESOURCE_ID" \
                '(.[$idKey] = $pid)')
        done

        if [ "$REPLACE_TARGET_ID" == "" ]; then
            # 同じリソースタイプで同じリソースIDが前のスタックにある場合は、それを使う（論理IDの変更）
            REPLACE_TARGET_ID=$(echo "$RESOURCES_TO_IMPORT" | jq \
                --arg type "$RESOURCE_TYPE" \
                --argjson ridObj "$TARGET_RESOURCE_IDENTIFIER" \
                -r '[.[] | select(.ResourceType == $type and .ResourceIdentifier == $ridObj) |
                    .LogicalResourceId] | .[0] // ""')
        fi
    fi

    if [ "$REPLACE_TARGET_ID" == "" ]; then
        # 既存リソースのインポート
        RESOURCES_TO_IMPORT=$(echo "$RESOURCES_TO_IMPORT" | jq \
            --arg type "$RESOURCE_TYPE" \
            --arg lid "$RESOURCE_ID" \
            --argjson ridObj "$TARGET_RESOURCE_IDENTIFIER" \
            '. |= .+[{
                "ResourceType": $type,
                "LogicalResourceId": $lid,
                "ResourceIdentifier": $ridObj
            }]')
        echo "$RESOURCE_ID: インポート（$REPLACE_TARGET_ID）"
    else
        # 前のスタックで作成したリソースをインポートする（論理IDの変更）
        RESOURCES_TO_IMPORT=$(echo "$RESOURCES_TO_IMPORT" | jq \
            --arg lid "$RESOURCE_ID" \
            --arg targetId "$REPLACE_TARGET_ID" \
            --argjson ridObj "$TARGET_RESOURCE_IDENTIFIER" \
            '.[] |= (if .LogicalResourceId == $targetId then
                .LogicalResourceId = $lid |
                .ResourceIdentifier = $ridObj
            else . end)')

        REPLACE_TARGET_IDS+=($REPLACE_TARGET_ID)
        echo "$RESOURCE_ID: 論理ID変更（$REPLACE_TARGET_ID）"
    fi
done

# 名称を変更するスタック、もしくはリソースを保持したまま削除する
if [[ "$DELETE_STACK" == "true" || ${#REPLACE_TARGET_IDS[@]} -ne 0 ]]; then
    deleteStackWithRetainResources $STACK_NAME $STACK_STATUS $STACK_TEMPLATE_SUMMARY "${REPLACE_TARGET_IDS[@]}"
fi

LOCAL_CAPABILITIES=$(echo "$LOCAL_TEMPLATE_SUMMARY" | jq -r '(.Capabilities // []) | join(" ")')

# リソースをインポートする
if [ ${#IMPORT_RESOURCE_IDS[@]} -ne 0 ]; then
    IMPORT_RESOURCE_IDS=$(IFS=$'\n'; echo "${IMPORT_RESOURCE_IDS[*]}" | jq -csR 'split("\n")[:-1]')

    IMPORT_RESOURCES_TEMPLATE=$(echo "$TEMPLATE" | jq \
        --argjson ids "$IMPORT_RESOURCE_IDS" \
        '.Resources |= with_entries(
            select(.key as $key | $ids | index($key)) |
            .value.DeletionPolicy = "Retain"
        ) | del(.Outputs)')

    if [ "$STACK_TEMPLATE" != "" ]; then
        # 既存スタックのリソースをテンプレートに追加
        IMPORT_RESOURCES_TEMPLATE=$(echo "$IMPORT_RESOURCES_TEMPLATE" | jq \
            --argjson stackTemplate "$STACK_TEMPLATE" \
            '.Resources |= $stackTemplate.Resources * .')
    fi

    # インポート対象でないリソースを削除
    RESOURCES_TO_IMPORT=$(echo "$RESOURCES_TO_IMPORT" |
        jq -r --argjson importResourceIds "$IMPORT_RESOURCE_IDS" \
            '[.[] | select(.LogicalResourceId as $lid | $importResourceIds | index($lid))]')

    # インポート
    executeChangeSet "$CHANGE_STACK_NAME" "cf-script-import-resources-change-set" \
        "$IMPORT_RESOURCES_TEMPLATE" "${PARAMETERS[*]}" "$LOCAL_CAPABILITIES" "for import resources" "$RESOURCES_TO_IMPORT"
fi

if [ "$STACK_ID" != "null" ]; then
    EXPORTS=$(aws cloudformation list-exports | jq --arg id "$STACK_ID" -r '.Exports[] | select(.ExportingStackId == $id) | .Name')
    for e in $EXPORTS; do
        if [ "$IMPORT_STACKS" != "" ]; then
            IMPORT_STACKS+=$'\n'
        fi
        set +e
        IMPORT_STACKS+=$(aws cloudformation list-imports --export-name $e 2> /dev/null | jq -r ".Imports[]")
        set -e
    done

    IMPORT_STACKS=$(echo "$IMPORT_STACKS" | sort | uniq)
    echo "$IMPORT_STACKS"

    for i in $IMPORT_STACKS; do
        deleteStackWithRetainResources $i "" $STACK_TEMPLATE_SUMMARY
    done
fi

# テンプレートと同じように更新
executeChangeSet "$CHANGE_STACK_NAME" "cf-script-update-by-template-change-set" \
    "$TEMPLATE" "${PARAMETERS[*]}" "$LOCAL_CAPABILITIES" "for update by template"

rm -f "$CACHE_CHOICES_PATH"
echo "$TEMPLATE" > "$CACHE_TEMPLATE_PATH"

echo "completed"
