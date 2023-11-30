#!/bin/bash -e

SHELL_PATH=$(cd $(dirname $0); pwd)
. "$SHELL_PATH/common.sh"

STACK_NAME=("$@")
for s in $@; do
    if [ "$(existsStack $s)" != "true" ]; then
        continue
    fi

    TEMPLATE_SUMMARY=$(aws cloudformation get-template-summary --stack-name $s)

    IMPORT_SUPPORTED_TYPES=$(echo "$TEMPLATE_SUMMARY" | jq -rbc "[.ResourceIdentifierSummaries[].ResourceType]")

    # インポートするリソースのDeletionPolicyをRetainにする
    rain cat $s |
        rain fmt --json |
        jq --argjson ist "$IMPORT_SUPPORTED_TYPES" \
            '.Resources |= with_entries(if (. as $r | $ist | index($r.value.Type)) then .value.DeletionPolicy = "Retain" else . end)' \
        > "$SHELL_PATH/tmp-template.json"

    rain deploy "$SHELL_PATH/tmp-template.json" $s --ignore-unknown-params -y

    rm -rf "$SHELL_PATH/tmp-template.json"
done
#
#function delete_tree_stack(){
#    local STACK_NAME=$1
#
#    local EXPORTS=$(aws cloudformation describe-stacks --stack-name $STACK_NAME 2> /dev/null | jq -rb ".Stacks[].Outputs[].ExportName")
#    for ex in $EXPORTS; do
#        local IMPORT_STACKS=$(aws cloudformation list-imports --export-name $ex 2> /dev/null | jq -rb ".Imports[]")
#        for i in $IMPORT_STACKS; do
#            delete_tree_stack $i
#        done
#    done
#
#    rain rm $STACK_NAME -y
#}
#
#for s in $@; do
#    if [ "$(existsStack $s)" != "true" ]; then
#        continue
#    fi
#
#    delete_tree_stack $s
#done