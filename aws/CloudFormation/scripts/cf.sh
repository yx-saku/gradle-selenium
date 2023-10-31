#!/bin/bash -e

SHELL_PATH=$(
    cd "$(dirname $0)"
    pwd
)

#############################################################################################################
# 関数定義
#

function yqjq() {
    local INPUT=$(cat -)

    echo "$INPUT" |
        sed "s/!/__EXCLAMATION__/g" |
        yq -o json |
        jq "$@" |
        yq -P |
        sed "s/__EXCLAMATION__/!/g"
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

rm -rf ${SHELL_PATH}/templates
mkdir -p ${SHELL_PATH}/templates

function executeChangeSet() {
    local STACK_NAME="$1"
    local CHANGE_SET_NAME="$2"
    local TEMPLATE_BODY="$3"
    local MESSAGE="$4"
    local RESOURCES_TO_IMPORT="$5"

    if [[ "$TEMPLATE_BODY" == file://* ]]; then
        cat "${TEMPLATE_BODY#file://}" > ${SHELL_PATH}/templates/${STACK_NAME}_${CHANGE_SET_NAME}.yml
    else
        echo "$TEMPLATE_BODY" > ${SHELL_PATH}/templates/${STACK_NAME}_${CHANGE_SET_NAME}.yml
    fi

    local CHANGE_SET_NAME_OPTIONS=(--stack-name "$STACK_NAME" --change-set-name "$CHANGE_SET_NAME")
    local COMMAND=update
    if [ "$RESOURCES_TO_IMPORT" != "" ]; then
        local IMPORT_OPTIONS=(--change-set-type IMPORT --resources-to-import "$RESOURCES_TO_IMPORT")
        COMMAND=import
        echo "$RESOURCES_TO_IMPORT" > ${SHELL_PATH}/templates/${STACK_NAME}_${CHANGE_SET_NAME}.json
    fi

    # 失敗した変更セットが残っていたら削除
    if [ $(checkExists $STACK_NAME $CHANGE_SET_NAME) -eq 0 ]; then
        echo "delete change set"
        aws cloudformation delete-change-set "${CHANGE_SET_NAME_OPTIONS[@]}"
    fi

    echo "create change set $MESSAGE"
    aws cloudformation create-change-set \
        "${CHANGE_SET_NAME_OPTIONS[@]}" \
        --template-body "$TEMPLATE_BODY" \
        --capabilities CAPABILITY_IAM \
        "${IMPORT_OPTIONS[@]}"

    echo "... wait create change set ..."
    set +e
    ERROR=$(aws cloudformation wait change-set-create-complete "${CHANGE_SET_NAME_OPTIONS[@]}" 2>&1 > /dev/null)
    set -e
    echo

    CHANGE_COUNT=$(aws cloudformation describe-change-set "${CHANGE_SET_NAME_OPTIONS[@]}" | jq ".Changes | length")
    if [ "$CHANGE_COUNT" != "0" ]; then
        if [ "$ERROR" != "" ]; then
            echo $ERROR 1>&2
            exit 1
        fi

        echo "execute change set $MESSAGE"
        aws cloudformation execute-change-set "${CHANGE_SET_NAME_OPTIONS[@]}"

        echo "... wait stack $COMMAND complete ..."
        aws cloudformation wait stack-$COMMAND-complete --stack-name $STACK_NAME
        echo
    else
        echo "update not exists. delete change set"
        aws cloudformation delete-change-set "${CHANGE_SET_NAME_OPTIONS[@]}"
    fi
}

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

while getopts "c:r:a:" optKey; do
    case "$optKey" in
    c) CHANGE_STACK_NAME="${OPTARG}" ;;
    r) RESOURCES_TO_IMPORT_PATH="${OPTARG}" ;;
    a) APPEND_RESOURCES_TO_IMPORT_PATH="${OPTARG}" ;;
    esac
done

if [ "$CHANGE_STACK_NAME" == "" ]; then
    CHANGE_STACK_NAME=$STACK_NAME
fi

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

# スタックの最新情報を取得
echo "get stack information"
{
    read -r STACK_ID
    read -r STACK_STATUS
} <<< $(aws cloudformation list-stacks --query "StackSummaries[?StackName=='$STACK_NAME']" | jq -rb ".[0].StackId, .[0].StackStatus")

if [ "$STACK_ID" != "null" ]; then
    DESCRIBE_STACK_RESOURCES=$(aws cloudformation describe-stack-resources --stack-name $STACK_ID)
fi

# インポート時に指定する各リソースの識別子を取得
if [ "$RESOURCES_TO_IMPORT_PATH" != "" ]; then
    RESOURCES_TO_IMPORT=$(cat "$RESOURCES_TO_IMPORT_PATH")
elif [ "$STACK_ID" != "null" ]; then
    echo "get stack template summary"
    STACK_TEMPLATE_SUMMARY=$(aws cloudformation get-template-summary --stack-name $STACK_ID)

    RESOURCES_TO_IMPORT=$(
        jq -n \
            --argjson r "$DESCRIBE_STACK_RESOURCES" \
            --argjson s "$STACK_TEMPLATE_SUMMARY" \
            '[
                $s.ResourceIdentifierSummaries[] |
                .ResourceType as $type |
                .ResourceIdentifiers[0] as $idKey |
                .LogicalResourceIds[] |
                . as $lid |
                {
                    "ResourceType": $type,
                    "LogicalResourceId": $lid,
                    "ResourceIdentifier": {
                        ($idKey): (($r.StackResources[] | select(.LogicalResourceId == $lid)).PhysicalResourceId)
                    }
                }
            ]'
    )
else
    RESOURCES_TO_IMPORT="[]"
fi

if [ "$APPEND_RESOURCES_TO_IMPORT_PATH" != "" ]; then
    RESOURCES_TO_IMPORT=$(cat "$APPEND_RESOURCES_TO_IMPORT_PATH" | jq --argjson r "$RESOURCES_TO_IMPORT" '$r+.')
fi

# 既存のスタックに存在しないLogicalIdのリソースに、どの既存リソースをインポートするか選択する
TEMPLATE_RESOURCES=$(cat "$TEMPLATE_PATH" | yq -o json '.Resources | to_entries | .[]' | jq -cb)
TEMPLATE_RESOURCE_IDS=$(echo "$TEMPLATE_RESOURCES" | jq -cs "[.[].key]")

echo "get local template summary"
TEMPLATE_SUMMARY=$(aws cloudformation get-template-summary --template-body "file://$TEMPLATE_PATH")

NEW="なし（新規作成）"
INPUT="リソースIDを入力する"
PS3="番号を入力: "

IMPORT_RESOURCE_IDS=()
REPLACE_TARGET_IDS=()
EXISTS_IMPORT_RESOURCE_IDS=()

for r in $TEMPLATE_RESOURCES; do
    RESOURCE_ID=$(echo "$r" | yq -r ".key")
    RESOURCE_TYPE=$(echo "$r" | yq -r ".value.Type")

    if [ "$DESCRIBE_STACK_RESOURCES" != "" ]; then
        if echo "$DESCRIBE_STACK_RESOURCES" | jq --exit-status \
            --arg id "$RESOURCE_ID" \
            '.StackResources | any(.LogicalResourceId == $id)' > /dev/null; then
            # 前のスタックに存在するリソースの場合
            EXISTS_IMPORT_RESOURCE_IDS+=($RESOURCE_ID)
            continue
        fi
    fi

    TARGET_RESOURCE_IDENTIFIER=$(echo "$RESOURCES_TO_IMPORT" | jq \
        --arg id "$RESOURCE_ID" \
        -r '[.[] | select(.LogicalResourceId == $id)] | .[0].ResourceIdentifier // ""')

    if [ "$TARGET_RESOURCE_IDENTIFIER" == "" ]; then
        echo "$TEMPLATE_RESOURCE_IDS"
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
    RESOURCE_IDENTIFIER_KEYS=$(echo "$TEMPLATE_SUMMARY" | jq \
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
    fi
done

# 処理方法を設定
if [[ "$STACK_NAME" != "$CHANGE_STACK_NAME" || "$STACK_STATUS" == "DELETE_COMPLETE" ]]; then
    # スタック名変える場合、もしくはスタックが既にない場合はスタックを削除して再作成
    DELETE_AND_CREATE_MODE="stack"
elif [ ${#REPLACE_TARGET_IDS[@]} -ne 0 ]; then
    # リソースの論理IDを変える場合はリソースを削除してインポート
    DELETE_AND_CREATE_MODE="resources"
else
    # それ以外は更新+インポート
    DELETE_AND_CREATE_MODE="no"
fi

if [ "$DELETE_AND_CREATE_MODE" == "stack" ]; then
    # 元々のスタックに既に存在したリソースをインポート対象とする
    IMPORT_RESOURCE_IDS+=($EXISTS_IMPORT_RESOURCE_IDS)
fi

echo "get stack template"
STACK_TEMPLATE=$(aws cloudformation get-template --stack-name $STACK_NAME | jq -r ".TemplateBody")

# 名称を変更するスタック、もしくはリソースを保持したまま削除する
if [[ "$STACK_STATUS" != "DELETE_COMPLETE" && "$DELETE_AND_CREATE" != "no" ]]; then
    if [ "$DELETE_AND_CREATE_MODE" == "stack" ]; then
        # 全てのリソースのDeletionPolicyをRetainに変更
        STACK_TEMPLATE=$(echo "$STACK_TEMPLATE" |
            yq '.Resources |= with_entries(.value.DeletionPolicy = "Retain")')
    else
        # 論理ID変更対象のDeletionPolicyをRetainに変更
        REPLACE_TARGET_IDS=$(IFS=$'\n'; echo "${REPLACE_TARGET_IDS[*]}" | jq -csR 'split("\n")[:-1]')

        STACK_TEMPLATE=$(echo "$STACK_TEMPLATE" |
            yqjq --argjson ids "$REPLACE_TARGET_IDS" \
                '.Resources |= with_entries(
                    if (.key as $key | $ids | index($key)) then
                        .value.DeletionPolicy = "Retain"
                    end)')
    fi

    # スタックのDeletionPolicyを更新
    executeChangeSet "$STACK_NAME" "cf-script-update-deletion-policy-change-set" \
        "$STACK_TEMPLATE" "for DeletionPolicy=Retain update"

    if [ "$DELETE_AND_CREATE_MODE" == "stack" ]; then
        # 変更前のスタックを削除
        echo "delete old stack"
        aws cloudformation delete-stack --stack-name $STACK_NAME

        echo "... wait stack delete complete ..."
        aws cloudformation wait stack-delete-complete --stack-name $STACK_NAME
        echo
    else
        # 変更対象のリソースを削除
        STACK_TEMPLATE=$(echo "$STACK_TEMPLATE" |
            yqjq --argjson deleteKeys "$REPLACE_TARGET_IDS" \
                'reduce $deleteKeys[] as $key (. ; .Resources |= del(.[ $key ]))')

        if [ "$(echo "$STACK_TEMPLATE" | yq '.Resources | to_entries | length')" != "0" ]; then
            executeChangeSet "$STACK_NAME" "cf-script-delete-old-resources-change-set" \
                "$STACK_TEMPLATE" "for delete old resources"
        fi
    fi
fi

# リソースをインポートする
if [ ${#IMPORT_RESOURCE_IDS[@]} -ne 0 ]; then
    IMPORT_RESOURCE_IDS=$(IFS=$'\n'; echo "${IMPORT_RESOURCE_IDS[*]}" | jq -csR 'split("\n")[:-1]')

    # 既存スタックのリソース+インポートリソースのテンプレートを作成
    IMPORT_RESOURCES_TEMPLATE=$(cat "$TEMPLATE_PATH" | yqjq \
        --argjson ids "$IMPORT_RESOURCE_IDS" \
        --argjson stackTemplate "$(echo "$STACK_TEMPLATE" | sed "s/!/__EXCLAMATION__/g" | yq -o json)" \
        '.Resources |= ((with_entries(
            select(.key as $key | $ids | index($key)) |
            .value.DeletionPolicy = "Retain"
        )) * $stackTemplate.Resources)')

    # インポート対象でないリソースを削除
    RESOURCES_TO_IMPORT=$(echo "$RESOURCES_TO_IMPORT" |
        jq -r --argjson importResourceIds "$IMPORT_RESOURCE_IDS" \
            '[.[] | select(.LogicalResourceId as $lid | $importResourceIds | index($lid))]')

    # インポート
    executeChangeSet "$STACK_NAME" "cf-script-import-resources-change-set" \
        "$IMPORT_RESOURCES_TEMPLATE" "for import resources" "$RESOURCES_TO_IMPORT"
fi

# 変更したDeletionPolicyを元に戻す
executeChangeSet "$STACK_NAME" "cf-script-update-by-template-change-set" \
    "file://$TEMPLATE_PATH" "for update by template"

echo "completed"
