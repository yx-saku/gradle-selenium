#!/bin/bash -e

# 指定したスタックに含まれるリソースの識別子を取得し、インポート時に指定するresources to importのjson形式で出力する

SHELL_PATH=$(cd $(dirname $0); pwd)
. "$SHELL_PATH/common.sh"

STACK_NAME=("$@")

RESOURCES_TO_IMPORTS="[]"
for s in $@; do
    STACK_NAME=$s
    if [ "$(existsStack $s)" != "true" ]; then
        # 削除済みのスタックの場合は、履歴のIDで取得する
        s=$(aws cloudformation list-stacks --query "StackSummaries[?StackName=='$s']" | jq -r '[.[] |
            select(.StackStatus == "DELETE_COMPLETE")] | .[0].StackId // ""')
    fi

    # describe stack resourcesとtemplate summaryから取得する
    DESCRIBE_STACK_RESOURCES=$(aws cloudformation describe-stack-resources --stack-name $s)
    TEMPLATE_SUMMARY=$(aws cloudformation get-template-summary --stack-name $s)

    RESOURCES_TO_IMPORT=$(jq -n \
        --argjson r "$DESCRIBE_STACK_RESOURCES" \
        --argjson s "$TEMPLATE_SUMMARY" \
        '$s.ResourceIdentifierSummaries[] |
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
                ($idKey): ($pid)
            }
        }')

    RESOURCES_TO_IMPORTS=$(echo "$RESOURCES_TO_IMPORTS" | \
        jq --argjson r "$RESOURCES_TO_IMPORT" '. + [$r]')
done

echo "$RESOURCES_TO_IMPORT" > "$SHELL_PATH/resources-to-import.json"
