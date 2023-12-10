#!/bin/bash -e

S3_BUCKET=$1
BROWSER=$2
TESTCASE=$3

# テストを実行する前にブラウザをインストールしなおす
~/scripts/installBrowser.sh $BROWSER

aws s3 cp s3://$S3_BUCKET/modules/screenshot-comopare-test.jar ~/screenshot-comopare-test.jar
java Main \
    -cp ~/screenshot-comopare-test.jar \
    -Dselenium.browser=$BROWSER \
    -Dtestcase.csv=$TESTCASE