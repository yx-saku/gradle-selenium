#!/bin/bash -e

function existsStack() {
    local STACK_NAME=$1

    EXISTS=$(aws cloudformation list-stacks --query 'StackSummaries[?StackStatus != `DELETE_COMPLETE`].StackName' |
        jq --arg s "$STACK_NAME" 'unique | index($s) != null')

    echo "$EXISTS"
}