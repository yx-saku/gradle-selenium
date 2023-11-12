#!/bin/bash -e

SHELL_PATH=$(cd $(dirname $0); pwd)

DELETE_STACK_NAMES=(
    user-bsdxxxx-evl-S3
    user-bsdxxxx-evl-CodeBuild
)

STACK_NAME=user-bsdxxxx-evl-ScreenshotCompareTest
PARAMETERS_PATH="$SHELL_PATH/templates/parameters.yml"
TEMPLATE_PATH="$SHELL_PATH/templates/cf-template.yml"

#
# get resources to import
#
"$SHELL_PATH/get-resources-to-import.sh" "${DELETE_STACK_NAMES[@]}"

#
# delete stuck
#
"$SHELL_PATH/delete-stack-for-import.sh" "${DELETE_STACK_NAMES[@]}"
#
# import
#

CHANGE_SET_NAME=user-bsdxxxx-evl-import
PARAMETERS=$(rain fmt "$PARAMETERS_PATH" --json |
    jq -r '[.Parameters | to_entries | .[] |
        "ParameterKey=" + .key + ",ParameterValue=" + .value] | join(",")')

RESOURCE_TO_IMPORT=$(cat "$SHELL_PATH/resources-to-import.json")
IMPORT_RESOURCES=$(echo "$RESOURCE_TO_IMPORT" | jq "[.[].LogicalResourceId]")

TEMPLATE=$(rain pkg "$TEMPLATE_PATH" | rain fmt --json |
    jq --argjson i "$IMPORT_RESOURCES" \
        '.Resources |= with_entries(select(.key as $key | $i | index($key)) |
        .value.DeletionPolicy = "Retain")')

aws cloudformation create-change-set \
    --stack-name $STACK_NAME \
    --change-set-name $CHANGE_SET_NAME \
    --template-body "$TEMPLATE" \
    --parameters "$PARAMETERS" \
    --change-set-type IMPORT \
    --resources-to-import "$RESOURCE_TO_IMPORT" \
    --capabilities CAPABILITY_NAMED_IAM

aws cloudformation wait change-set-create-complete \
    --stack-name $STACK_NAME \
    --change-set-name $CHANGE_SET_NAME

aws cloudformation execute-change-set \
    --stack-name $STACK_NAME \
    --change-set-name $CHANGE_SET_NAME

aws cloudformation wait stack-import-complete --stack-name $STACK_NAME

echo complete import.