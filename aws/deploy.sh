#!/bin/bash -e


SHELL_PATH=$(cd $(dirname $0); pwd)

case $1 in
    cloudformation)
#        STACK_NAME=user-bsdxxxx-evl-ScreenshotCompareTest
        CF_S3_BUCKET=user-bsdxxxx-evl-cf-packages
#        rain deploy "$SHELL_PATH/CloudFormation/templates/cf-template.yml" \
#            $STACK_NAME \
#            --config "$SHELL_PATH/CloudFormation/templates/parameters.yml" \
#            --s3-bucket $CF_S3_BUCKET \
#            --yes

        aws s3 sync "$SHELL_PATH/CloudFormation/templates/modules" s3://$CF_S3_BUCKET/modules
        REGISTRATION_TOKEN=$(aws cloudformation register-type --type MODULE \
            --type-name BBB::Logs::LogGroupAndPolicy::MODULE \
            --schema-handler-package s3://$CF_S3_BUCKET/modules/LogGroupAndPolicy.yml |
            jq -r ".RegistrationToken")

        echo $REGISTRATION_TOKEN
        aws cloudformation wait type-registration-complete --registration-token $REGISTRATION_TOKEN

        DIR="$SHELL_PATH/CloudFormation/templates/old_templates"
        rain deploy "$DIR/01_cloudformation-s3.yml" user-bsdxxxx-evl-s3 --s3-bucket user-bsdxxxx-evl-cf-packages --yes
        rain deploy "$DIR/02_cloudformation-image.yml" user-bsdxxxx-evl-imagebuilder --s3-bucket user-bsdxxxx-evl-cf-packages --yes
        rain deploy "$DIR/03_cloudformation-codebuild.yml" user-bsdxxxx-evl-codebuild --s3-bucket user-bsdxxxx-evl-cf-packages \
            --config "$SHELL_PATH/CloudFormation/templates/parameters.yml" --yes
        #rain deploy "$DIR/04_cloudformation-stepfunctions.yml" user-bsdxxxx-evl-stepfunctions --s3-bucket user-bsdxxxx-evl-cf-packages --yes
        #rain deploy "$DIR/05_cloudformation-cloudtrail.yml" user-bsdxxxx-evl-cloudtrail --s3-bucket user-bsdxxxx-evl-cf-packages --yes
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