#!/bin/bash -e

STACK_NAME=user-bsdxxxx-evl-ScreenshotCompareTest

SHELL_PATH=$(cd $(dirname $0); pwd)

case $1 in
    cloudformation)
        rain deploy "$SHELL_PATH/CloudFormation/templates/cf-template.yml" \
            $STACK_NAME \
            --config "$SHELL_PATH/CloudFormation/templates/parameters.yml" \
            --s3-bucket user-bsdxxxx-evl-cf-packages \
            --yes
        ;;
    s3)
        BUCKET_NAME=$(aws cloudformation describe-stacks --stack-name $STACK_NAME \
            --query '(Stacks[0].Outputs[?OutputKey==`S3Bucket`])[0].OutputValue' --output text)
        aws s3 sync "$SHELL_PATH/S3/" s3://$BUCKET_NAME/
        ;;
    create-image)
        IMAGEPIPELINE_ARN=$(aws cloudformation describe-stacks --stack-name $STACK_NAME \
            --query '(Stacks[0].Outputs[?OutputKey==`ImagePipeline`])[0].OutputValue' --output text)
        aws imagebuilder start-image-pipeline-execution --image-pipeline-arn $IMAGEPIPELINE_ARN
        ;;
    *)
        echo "no supported command $1"
        ;;
esac