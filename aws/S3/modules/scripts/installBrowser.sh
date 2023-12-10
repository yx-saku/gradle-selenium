#!/bin/bash -e

BROWSER=$1

# 現在インストールされているものより新しいボージョンがある場合、そのバージョンのパッケージのURLを返す
function getLatestPackageUrl(){
    case $BROWSER in
        chrome)
            # chromeのバージョン確認
            # https://github.com/GoogleChromeLabs/chrome-for-testing?tab=readme-ov-file#json-api-endpoints
            LATEST_STABLE_INFO=$(
                curl "https://googlechromelabs.github.io/chrome-for-testing/last-known-good-versions-with-downloads.json" |
                jq -r ".channels.Stable")

            LATEST_VERSION=$(echo "$LATEST_STABLE_INFO" | jq -r ".version")
            PACKAGE_URL=$(echo "$LATEST_STABLE_INFO" | jq -r '.downloads.chrome[] | select(.platform == "linux64") | .url')
            ;;
        firefox)
            # firefoxのバージョン確認
            # https://wiki.mozilla.org/Release_Management/Product_details#firefox_versions.json
            LATEST_VERSION=$(curl "https://product-details.mozilla.org/1.0/firefox_versions.json" |
                jq -r ".LATEST_FIREFOX_VERSION")
            PACKAGE_URL="https://ftp.mozilla.org/pub/firefox/releases/${LATEST_VERSION}/linux-x86_64/ja/firefox-${LATEST_VERSION}.tar.bz2"
            ;;
        edge)
            # edgeのバージョン確認
            # https://learn.microsoft.com/ja-jp/mem/configmgr/core/plan-design/network/internet-endpoints#deploy-microsoft-edge
            LATEST_STABLE_INFO=$(curl -L "https://aka.ms/cmedgeapi" |
                jq '.[] | select(.Product == "Stable") |
                    .Releases[] | select(.Platform == "Linux" and .Architecture == "x64")')

            LATEST_VERSION=$(echo "$LATEST_STABLE_INFO" | jq -r '.ProductVersion')
            PACKAGE_URL=$(echo "$LATEST_STABLE_INFO" | jq -r '.Artifacts[] | select(.ArtifactName == "rpm") | .Location')
            ;;
    esac

    CURRENT_VERSION=$(getCurrentVersion | aws '{ print $NF }' 2> /dev/null)
    if [ "$LATEST_VERSION" != "$CURRENT_VERSION" ]; then
        echo $PACKAGE_URL
    fi
}

# ブラウザをインストールする
function installBrowser(){
    PACKAGE_URL=$1

    case $BROWSER in
        chrome)
            wget $PACKAGE_URL
            unzip chrome-linux64.zip
            ln -sf "$(pwd)/chrome-linux64/chrome" /usr/bin/chrome
            ;;
        firefox)
            wget $PACKAGE_URL
            tar xjf firefox-*.tar.bz2
            ln -sf "$(pwd)/firefox/firefox" /usr/bin/firefox
            ;;
        edge)
            yum install $PACKAGE_URL -y
            ;;
    esac
}

# インストールされているバージョンを表示
function getCurrentVersion(){
    set +e
    case $BROWSER in
        chrome) chrome --version ;;
        firefox) firefox --version ;;
        edge) microsoft-edge --version ;;
    esac
    set -e
}

PACKAGE_URL=$(getLatestPackageUrl)

if [ "$PACKAGE_URL" != "" ]; then
    # 更新有り
    echo $BROWSER: 最新バージョンをインストールします。

    installBrowser $PACKAGE_URL

    echo $BROWSER: インストール完了。

    export BROWSER_UPDATED=true
else
    # 更新なし
    echo $BROWSER: 既に最新バージョンのため更新しません。
fi

getCurrentVersion