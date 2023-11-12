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
CACHE_GET_PATH="$CACHE_DIR/${STACK_NAME}_get.json"

function cacheCli() {
    local COMMAND="$1"
    local STACK_NAME="$2"
    local NO_CACHE="$3"

    if [ ! -e "$CACHE_GET_PATH" ]; then
        echo "{}" > "$CACHE_GET_PATH"
    fi

    if [ "$NO_CACHE" == "" ]; then
        RET=$(cat "$CACHE_GET_PATH" | jq -r \
            --arg command "$COMMAND" \
            --arg stackName "$STACK_NAME" \
            '.[$command].[$stackName] // ""'
        )
    fi

    if [ "$RET" == "" ]; then
        case $COMMAND in
        describe-stack)
            RET=$(aws cloudformation describe-stacks --stack-name $STACK_NAME)
            ;;
        stack-status)
            RET=$(aws cloudformation list-stacks --query "StackSummaries[?StackName=='$STACK_NAME']" | jq -r \
                '.[0].StackStatus // ""')
            ;;
        parameters)
            RET=$(cacheCli describe-stack $STACK_NAME  | jq -c \
                '[(.Stacks[].Parameters // [])[].ParameterKey | { "ParameterKey": ., "UsePreviousValue": true } ]')
            ;;
        capabilities)
            RET=$(cacheCli describe-stack $STACK_NAME  | jq -r '(.Stacks[].Capabilities // []) | join(" ")')
            ;;
        describe-stack-resources)
            STACK_ID=$(cacheCli last-stack-id $STACK_NAME)
            RET=$(aws cloudformation describe-stack-resources --stack-name $STACK_ID)
            ;;
        get-template)
            RET=$(aws cloudformation get-template --stack-name $STACK_NAME | jq -r ".TemplateBody" | rain fmt --json)
            ;;
        get-template-summary)
            STACK_ID=$(cacheCli last-stack-id $STACK_NAME)
            RET=$(aws cloudformation get-template-summary --stack-name $STACK_ID)
            ;;
        last-stack-id)
            RET=$(aws cloudformation list-stacks --query "StackSummaries[?StackName=='$STACK_NAME']" | jq -r '[.[] |
                select(.StackStatus != "REVIEW_IN_PROGRESS" and .StackStatus != "ROLLBACK_COMPLETE")] |
                .[0].StackId // ""')
            ;;
        esac

        local ARG=
        set +e
        if echo "$RET" | jq . >/dev/null 2>&1; then
            ARG=argjson
        else
            ARG=arg
        fi
        set -e

        CACHE_GET=$(cat "$CACHE_GET_PATH" | jq \
            --arg command "$COMMAND" \
            --arg stackName "$STACK_NAME" \
            --$ARG ret "$RET" \
            '(.[$command].[$stackName] = $ret)')

         echo "$CACHE_GET" > "$CACHE_GET_PATH"
    fi

    echo "$RET"
}

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

    local DESCRIBE_STACK_RESOURCES=$(cacheCli describe-stack-resources $STACK_NAME)
    local TEMPLATE_SUMMARY=$(cacheCli get-template-summary $STACK_NAME)

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
    shift 1
    local REPLACE_TARGET_IDS=("$@")

    local STACK_STATUS=$(cacheCli stack-status $STACK_NAME)

    if [[ "$STACK_STATUS" != "DELETE_COMPLETE" ]]; then
        if [ "$STACK_STATUS" != "ROLLBACK_COMPLETE" ] ; then
            local STACK_TEMPLATE=$(cacheCli get-template $STACK_NAME)
            local STACK_PARAMETERS=$(cacheCli parameters $STACK_NAME)
            local STACK_CAPABILITIES=$(cacheCli capabilities $STACK_NAME)

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
            updateStack "$STACK_NAME" "$STACK_TEMPLATE" "$STACK_PARAMETERS" "$STACK_CAPABILITIES" \
                "for DeletionPolicy=Retain update $STACK_NAME"
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
                updateStack "$STACK_NAME" "$STACK_TEMPLATE" "$STACK_PARAMETERS" "$STACK_CAPABILITIES" \
                    "for delete old resources $STACK_NAME"
            fi
        fi
    fi
}

function updateStack() {
    local STACK_NAME="$1"
    local TEMPLATE_BODY="$2"
    local PARAMETERS="$3"
    local CAPABILITIES="$4"
    local MESSAGE="$5"
    local RESOURCES_TO_IMPORT="$6"

    local CHANGE_SET_NAME="cf-script-import-resources-change-set"

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
    else
        # 更新
        COMMAND=update
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

    # 失敗した変更セットが残っていたら削除
    if [ $(checkExists $STACK_NAME $CHANGE_SET_NAME) -eq 0 ]; then
        echo "delete change set"
        aws cloudformation delete-change-set "${CHANGE_SET_NAME_OPTIONS[@]}"
    fi

    if [ "$COMMAND" == "import" ]; then
        # インポート（changeset）
        echo "create change set $MESSAGE $STACK_NAME"
        aws cloudformation create-change-set \
            "${CHANGE_SET_NAME_OPTIONS[@]}" \
            --template-body "$TEMPLATE_BODY" \
            "${OPTIONS[@]}"

        echo "... wait create change set ..."
        set +e
        local ERROR=$(aws cloudformation wait change-set-create-complete "${CHANGE_SET_NAME_OPTIONS[@]}" 2>&1 > /dev/null)
        set -e
        echo

        local DESCRIBE_CHANGE_SET=$(aws cloudformation describe-change-set "${CHANGE_SET_NAME_OPTIONS[@]}")
        local EXECUTION_STATUS=$(echo "$DESCRIBE_CHANGE_SET" | jq -r ".ExecutionStatus")
        local STATUS_REASON=$(echo "$DESCRIBE_CHANGE_SET" | jq -r ".StatusReason")

        if [ "$EXECUTION_STATUS" == "AVAILABLE" ]; then
            echo "execute change set $MESSAGE $STACK_NAME"
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
    else
        # 更新・作成
        echo "$COMMAND stack $MESSAGE $STACK_NAME"
        set +e
        aws cloudformation $COMMAND-stack \
            --stack-name $STACK_NAME \
            --template-body "$TEMPLATE_BODY" \
            "${OPTIONS[@]}" > /tmp/cf-error 2>&1
        local RET=$?
        set -e

        local ERROR=$(cat /tmp/cf-error)
        if [ $RET -eq 0 ]; then
            echo "... wait stack $COMMAND complete ..."
            aws cloudformation wait stack-$COMMAND-complete --stack-name $STACK_NAME
            echo
        elif [[ "$ERROR" == *"No updates are to be performed."* ]]; then
            echo "update not exists."
        else
            echo "$ERROR"
            exit 1
        fi
    fi
}

#############################################################################################################
# main
#

# 変更先スタックの存在確認　同じ名前でリプレイスする場合はスルー
if [ "$STACK_NAME" != "$CHANGE_STACK_NAME" ]; then
    echo "check exists $CHANGE_STACK_NAME"
    if [ $(checkExists $CHANGE_STACK_NAME) -eq 0 ]; then
        STACK_STATUS=$(cacheCli stack-status $CHANGE_STACK_NAME)
        if [ "$STACK_STATUS" != "REVIEW_IN_PROGRESS" ]; then
            echo "スタック $CHANGE_STACK_NAME は既に存在します。"
            exit
        fi
    fi
fi

# スタックの最新情報を取得
STACK_STATUS=$(cacheCli stack-status $STACK_NAME)

if [ "$STACK_STATUS" == "ROLLBACK_IN_PROGRESS" ]; then
    echo "... wait stack rollback complete ..."
    aws cloudformation wait stack-rollback-complete --stack-name $STACK_NAME
    echo
fi

# インポート時に指定する各リソースの識別子を取得
echo "get resources to import"
if [ "$RESOURCES_TO_IMPORT_PATH" != "" ]; then
    RESOURCES_TO_IMPORT=$(cat "$RESOURCES_TO_IMPORT_PATH")
elif [ "$STACK_STATUS" != "" ]; then
    RESOURCES_TO_IMPORT=$(getResourcesToImport $STACK_NAME)
else
    RESOURCES_TO_IMPORT="[]"
fi

if [ "$APPEND_RESOURCES_TO_IMPORT_PATH" != "" ]; then
    RESOURCES_TO_IMPORT=$(cat "$APPEND_RESOURCES_TO_IMPORT_PATH" | jq --argjson r "$RESOURCES_TO_IMPORT" '$r+.')
fi

# 既存のスタックに存在しないLogicalIdのリソースに、どの既存リソースをインポートするか選択する
echo "choise import resources"
if [ "$PKG_S3_BUCKET" != "" ]; then
    S3_BUCKET_OPT=--s3-bucket "$PKG_S3_BUCKET"
fi

TEMPLATE=$(rain pkg "$TEMPLATE_PATH" $S3_BUCKET_OPT | rain fmt --json)
TEMPLATE_RESOURCES=$(echo "$TEMPLATE" | jq -cb '.Resources | to_entries | .[]')
TEMPLATE_RESOURCE_IDS=$(echo "$TEMPLATE_RESOURCES" | jq -cs "[.[].key]")

LOCAL_TEMPLATE_SUMMARY=$(aws cloudformation get-template-summary --template-body "$TEMPLATE")

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

NEW="なし（新規作成）"
INPUT="リソースIDを入力する"
PS3="番号を入力: "

IMPORT_RESOURCE_IDS=()
REPLACE_TARGET_IDS=()

DESCRIBE_STACK_RESOURCES=$(cacheCli describe-stack-resources $STACK_NAME)

_IFS="$IFS"
IFS=$'\n'
for r in $TEMPLATE_RESOURCES; do
    IFS="$_IFS"
    RESOURCE_ID=$(echo "$r" | jq -r ".key")
    RESOURCE_TYPE=$(echo "$r" | jq -r ".value.Type")

    if [ "$STACK_STATUS" != "" ]; then
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
    echo "update delete policy for prepare import"
    deleteStackWithRetainResources $STACK_NAME "${REPLACE_TARGET_IDS[@]}"
fi

LOCAL_CAPABILITIES=$(echo "$LOCAL_TEMPLATE_SUMMARY" | jq -r '(.Capabilities // []) | join(" ")')

# リソースをインポートする
if [ ${#IMPORT_RESOURCE_IDS[@]} -ne 0 ]; then
    echo "import resources"
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
    updateStack "$CHANGE_STACK_NAME" "$IMPORT_RESOURCES_TEMPLATE" "${PARAMETERS[*]}" "$LOCAL_CAPABILITIES" \
        "for import resources" "$RESOURCES_TO_IMPORT"
fi

# TODO うまくいかないので一旦ナシ
#if [ "$STACK_STATUS" != "" ]; then
#    # インポートされている値を実数値に直して更新する
#    STACK_ID=$(cacheCli describe-stack $STACK_NAME | jq -r ".Stacks[].StackId")
#    EXPORTS=$(aws cloudformation list-exports | jq --arg id "$STACK_ID" -rc '.Exports[] | select(.ExportingStackId == $id)')
#    for e in $EXPORTS; do
#        EXPORT_NAME=$(echo "$e" | jq -r ".Name")
#        EXPORT_VALUE=$(echo "$e" | jq -r ".Value")
#
#        if [ "$IMPORT_STACKS" != "" ]; then
#            IMPORT_STACKS+=$'\n'
#        fi
#
#        set +e
#        IMPORT_STACKS+=$(aws cloudformation list-imports --export-name $EXPORT_NAME 2> /dev/null | jq -r ".Imports[]")
#        set -e
#    done
#
#    IMPORT_STACKS=$(echo "$IMPORT_STACKS" | sort | uniq)
#
#    for i in $IMPORT_STACKS; do
#        deleteStackWithRetainResources $i
#    done
#fi

# テンプレートと同じように更新
updateStack "$CHANGE_STACK_NAME" "$TEMPLATE" "${PARAMETERS[*]}" "$LOCAL_CAPABILITIES" "for update by template"

rm -f "$CACHE_CHOICES_PATH"
rm -f "$CACHE_GET_PATH"

echo "completed"
