#!/bin/bash -e

SHELL_PATH=$(cd $(dirname $0); pwd)
. "$SHELL_PATH/common.sh"

TARGET=$1
STACK_NAME=user-bsdxxxx-${ENV}-${TARGET}
CHANGE_SET_NAME=user-bsdxxxx-${ENV}-${TARGET}-import

# パラメータをAWS CLIで使用できる形式に変換
PARAMETERS_PATH="$SHELL_PATH/../parameters.yml"
PARAMETERS=$(rain fmt "$PARAMETERS_PATH" --json |
    jq -r '[.Parameters | to_entries | .[] |
        "ParameterKey=" + .key + ",ParameterValue=" + .value] | join(",")')

# Resources to importを取得
RESOURCES_TO_IMPORT=$(cat "$SHELL_PATH/resourcesToImport/$TARGET.json")
IMPORT_RESOURCE_IDS=$(echo "$RESOURCES_TO_IMPORT" | jq "[.[].LogicalResourceId]")

# テンプレートをimportできるよう変換し、S3にアップロード
S3_TEMPLATE_URI="s3://$CF_S3_BUCKET/import-$TARGET-$(date +%Y%m%d%H%M%S).json"
rain pkg "$SHELL_PATH/../templates/$TARGET.yml" \
    --s3-bucket $CF_S3_BUCKET \
    --s3-prefix $RAIN_S3_PREFIX |
    rain fmt --json |
    jq --argjson i "$IMPORT_RESOURCE_IDS" '.Resources |= with_entries(select(.key as $key | $i | index($key)))' |
    jq '.Resources |= with_entries(.value.DeletionPolicy = "Retain")' |
    jq 'del(.Outputs)' |
    aws s3 cp - "$S3_TEMPLATE_URI"

aws cloudformation create-change-set \
    --stack-name $STACK_NAME \
    --change-set-name $CHANGE_SET_NAME \
    --template-uri "$S3_TEMPLATE_URI" \
    --parameters "$PARAMETERS" \
    --change-set-type IMPORT \
    --resources-to-import "$RESOURCES_TO_IMPORT" \
    --capabilities CAPABILITY_NAMED_IAM

aws cloudformation wait change-set-create-complete \
    --stack-name $STACK_NAME \
    --change-set-name $CHANGE_SET_NAME

aws cloudformation execute-change-set \
    --stack-name $STACK_NAME \
    --change-set-name $CHANGE_SET_NAME

aws cloudformation wait stack-import-complete --stack-name $STACK_NAME
