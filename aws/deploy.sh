#!/bin/bash -e

SHELL_PATH=$(cd $(dirname $0); pwd)

case $1 in
    cloudformation)
        "$SHELL_PATH/CloudFormation/scripts/moduleRegister.sh" LogGroupAndPolicy

        "$SHELL_PATH/CloudFormation/scripts/update.sh" s3
        "$SHELL_PATH/CloudFormation/scripts/update.sh" imagebuilder
        "$SHELL_PATH/CloudFormation/scripts/update.sh" codebuild
        "$SHELL_PATH/CloudFormation/scripts/update.sh" fargate
        "$SHELL_PATH/CloudFormation/scripts/update.sh" stepfunctions
        "$SHELL_PATH/CloudFormation/scripts/update.sh" cloudtrail
        ;;
    s3)
        BUCKET_NAME=$(aws cloudformation describe-stacks --stack-name user-bsdxxxx-evl-s3 \
            --query '(Stacks[0].Outputs[?OutputKey==`S3BucketName`])[0].OutputValue' --output text)
        aws s3 sync "$SHELL_PATH/S3/" s3://$BUCKET_NAME/
        ;;
    create-image)
        IMAGEPIPELINE_ARN=$(aws cloudformation describe-stacks --stack-name user-bsdxxxx-evl-imagebuilder \
            --query '(Stacks[0].Outputs[?OutputKey==`ImagePipelineArn`])[0].OutputValue' --output text)
        aws imagebuilder start-image-pipeline-execution --image-pipeline-arn $IMAGEPIPELINE_ARN
        ;;
    *)
        echo "no supported command $1"
        ;;
esac