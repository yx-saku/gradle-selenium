#!/bin/bash -e

echo "### S3 ###"
./CloudFormation/scripts/cf.sh user-bsdxxxx-evl-S3 ./CloudFormation/templates/S3.yml \
    -s user-bsdxxxx-evl-cf-packages

echo "### ImageBuilder ###"
./CloudFormation/scripts/cf.sh user-bsdxxxx-evl-ImageBuilder ./CloudFormation/templates/ImageBuilder.yml \
    -s user-bsdxxxx-evl-cf-packages

echo "### CodeBuild ###"
./CloudFormation/scripts/cf.sh user-bsdxxxx-evl-CodeBuild ./CloudFormation/templates/CodeBuild.yml \
    -s user-bsdxxxx-evl-cf-packages \
    -p "ParameterKey=GitHubToken,ParameterValue=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"