#!/bin/bash

# ソースコードのディレクトリに移動
cd `dirname 0`

# プロジェクトをビルドしてJARを作成
./gradlew shadowJar

# JARファイルのパス
jarFile='app/build/libs/gradle_selenium.jar'

# Lambda関数の名前
functionName='GetTrainTimeByNavitimeScraping'

# AWS CLIを使用してJARをアップロードし、Lambda関数を更新
aws lambda update-function-code \
    --function-name $functionName \
    --zip-file fileb://$jarFile