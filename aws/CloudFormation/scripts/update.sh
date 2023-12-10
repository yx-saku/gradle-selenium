#!/bin/bash -e

SHELL_PATH=$(cd $(dirname $0); pwd)
. "$SHELL_PATH/common.sh"

TARGET=$1
STACK_NAME=user-bsdxxxx-${ENV}-${TARGET}

rain deploy "$SHELL_PATH/../templates/$TARGET.yml" $STACK_NAME \
    --config "$SHELL_PATH/../parameters.yml" \
    --s3-bucket $CF_S3_BUCKET \
    --s3-prefix $RAIN_S3_PREFIX \
    --ignore-unknown-params \
    -y