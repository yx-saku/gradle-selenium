#!/bin/bash

libraries=
while true; do
    # Chromeのバージョンを取得
    output=$(chrome --version 2>&1)

    # エラーメッセージをチェック
    if [[ $output == *"error while loading shared libraries"* ]]; then
        # ライブラリ名を抽出
        library=$(echo $output | sed -n -e 's/^.*error while loading shared libraries: \(.*\): cannot open shared object file: No such file or directory$/\1/p')

        echo "Missing library: $library"

        # 対応するパッケージを探す
        package=$(sudo yum -q whatprovides $library | head -n 1 | awk '{print $1}' | sed 's/^[0-9]*://' | awk -F '-' -v OFS=- 'NF-=2')

        echo "Installing package: $package"

        # パッケージをインストール
        sudo yum -y install $package

        libraries="$libraries $package"
    else
        echo "No missing libraries found"
        break
    fi
done

echo $libraries