#!/bin/bash -e

SHELL_PATH=$(cd $(dirname $0); pwd)
. "$SHELL_PATH/common.sh"

TARGET=$1

# スキーマファイル生成
cd "$SHELL_PATH/../modules/$TARGET"
cfn generate

# cfn submitだとS3バケットが自動作成されてしまうのでAWS CLIでモジュールを登録する

# zipファイルを生成しアップロード
ZIP_PATH_KEYWORD="Dry run complete: "
ZIP_PATH=$(cfn submit --dry-run | grep "$ZIP_PATH_KEYWORD" | sed -E "s/$ZIP_PATH_KEYWORD//")
ZIP_FILE=$(basename $ZIP_PATH)

SCHEMA_HANDLER_PACKAGE=s3://$CF_S3_BUCKET/$ZIP_FILE
aws s3 mv $ZIP_FILE $SCHEMA_HANDLER_PACKAGE

TYPE_NAME=$(cat ./.rpdk-config | jq -r ".typeName")

# モジュールを登録
REGISTRATION_TOKEN=$(aws cloudformation register-type --type MODULE \
    --type-name $TYPE_NAME \
    --schema-handler-package $SCHEMA_HANDLER_PACKAGE |
    jq -r ".RegistrationToken")

echo RegistrationToken: $REGISTRATION_TOKEN

aws cloudformation wait type-registration-complete --registration-token $REGISTRATION_TOKEN

# 登録したモジュールを最新バージョンをデフォルトとして設定
TYPE_VERSION_ARN=$(aws cloudformation describe-type-registration --registration-token $REGISTRATION_TOKEN |
    jq -r ".TypeVersionArn")

aws cloudformation set-type-default-version --arn $TYPE_VERSION_ARN

echo complated
