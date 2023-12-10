#!/bin/bash -e

SHELL_PATH=$(cd $(dirname $0); pwd)
. "$SHELL_PATH/common.sh"

TARGET=$1
STACK_NAME=user-bsdxxxx-${ENV}-${TARGET}
CHANGE_SET_NAME=user-bsdxxxx-${ENV}-${TARGET}-delete

# importをサポートしているリソースを残してスタック削除
IMPORT_RESOURCE_IDS=$(aws cloudformation get-template-summary --stack-name $s | jq -rbc ".ResourceIdentifierSummaries[].LogicalResourceIds[]")

aws cloudformation delete-stack --stack-name $STACK_NAME --retain-resources $IMPORT_RESOURCE_IDS

aws cloudformation wait stack-delete-complete --stack-name $STACK_NAME
