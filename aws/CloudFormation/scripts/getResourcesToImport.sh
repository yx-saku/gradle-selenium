#!/bin/bash -e

# 指定したスタックに含まれるリソースの識別子を取得し、インポート時に指定するresources to importのjson形式で出力する

SHELL_PATH=$(cd $(dirname $0); pwd)
. "$SHELL_PATH/common.sh"

TARGET=$1
STACK_NAME=user-bsdxxxx-${ENV}-${TARGET}

mkdir -p "$SHELL_PATH/resourcesToImport/"

DESCRIBE_STACK_RESOURCES=$(aws cloudformation describe-stack-resources --stack-name $s)
TEMPLATE_SUMMARY=$(aws cloudformation get-template-summary --stack-name $s)

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
                ($idKey): ($pid)
            }
        }
    ]' > "$SHELL_PATH/resourcesToImport/$STACK_NAME.json"

