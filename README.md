# 開発環境構築手順
## WSLのインストール
https://learn.microsoft.com/ja-jp/windows/wsl/install

## Dockerコンテナ作成
1. windows側で必要なソフトをインストール
    - Visual Studio Code

2. vscodeを起動し、`Remote Development`拡張機能をインストールする
// 画像

3. WSLを起動
// 画像

4. Ubuntu側で必要なソフトをインストール
```sh
apt update
apt install git docker -y
```

5. このリポジトリをクローンする
```sh
git clone #######
```

6. vscodeでクローンしたフォルダを開く
```sh
code ######
```

7. Ctrl+Shift+@ でターミナルを開き、下記コマンドを実行してDockerイメージをビルドする
```sh
docker compose build
```

7. vscode左下の緑色の部分をクリックし、 `Reopen in Container`を選択する
// 画像

8. Dockerコンテナ内に環境構築し、vscodeで開発ができるようになります。 ※初回は時間がかかります

## 二回目以降
6.以降の手順を実行すればコンテナ内の環境を開けます。

## テストの実行・デバッグ
左ペインの`Run and Debug`から実行します。
実行時にブラウザを選択できます。

## レポートの確認

# プロジェクト作成
1. コマンドパレット（Ctrl+Shift+p）を開き`Gradle: Create a Gradle Java Project...`をクリック

2. プロジェクトフォルダを選択（デフォルトはカレントディレクトリなのでそのままOKを押下でOK）

3. ビルドスクリプトで`Groovy`を選択

4. プロジェクト名に"gradle_selenium"を入力