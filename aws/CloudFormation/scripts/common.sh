#!/bin/bash -e

export ENV=evl
export CF_S3_BUCKET=user-bsdxxxx-${ENV}-cf-templates
export RAIN_S3_PREFIX=rain-artifacts

function existsStack() {
    local STACK_NAME=$1

    EXISTS=$(aws cloudformation list-stacks --query 'StackSummaries[?StackStatus != `DELETE_COMPLETE`].StackName' |
        jq --arg s "$STACK_NAME" 'unique | index($s) != null')

    echo "$EXISTS"
}