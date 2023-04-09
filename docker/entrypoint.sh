# 実行時にブラウザをインストール&更新
sudo apt-get update
sudo apt-get install -y --no-install-recommends google-chrome-stable firefox microsoft-edge-stable

if [ "$IS_DOCKER_BUILD" != "true" ]; then
    echo "is not docker build"

    # Allureレポートのサーバーを起動
    nohup ./gradlew allureOpen --host 0.0.0.0 --port 8088 > allureOpen.log 2>&1 &

    # 無限待ち
    while true; do
        sleep 1
    done
else
    echo "is docker build"
fi