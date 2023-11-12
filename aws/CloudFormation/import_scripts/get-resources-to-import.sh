#!/bin/bash -e

SHELL_PATH=$(cd $(dirname $0); pwd)
. "$SHELL_PATH/common.sh"

STACK_NAME=("$@")

RESOURCES_TO_IMPORT="[]"
for s in $@; do
    if [ "$(existsStack $s)" != "true" ]; then
        s=$(aws cloudformation list-stacks --query "StackSummaries[?StackName=='$s']" | jq -r '[.[] |
            select(.StackStatus == "DELETE_COMPLETE")] | .[0].StackId // ""')
    fi

    DESCRIBE_STACK_RESOURCES=$(aws cloudformation describe-stack-resources --stack-name $s)
    TEMPLATE_SUMMARY=$(aws cloudformation get-template-summary --stack-name $s)

    RESOURCES_TO_IMPORT=$(echo "$RESOURCES_TO_IMPORT" | jq \
        --argjson r "$DESCRIBE_STACK_RESOURCES" \
        --argjson s "$TEMPLATE_SUMMARY" \
        '. + [
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
        ]')
done

echo "$RESOURCES_TO_IMPORT" > "$SHELL_PATH/resources-to-import.json"
