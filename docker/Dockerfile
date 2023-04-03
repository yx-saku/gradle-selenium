# syntax=docker/dockerfile:1

FROM openjdk:11-jdk-slim

SHELL ["/bin/bash", "-c"]

ENV DEBIAN_FRONTEND=noninteractive

# パッケージインストール
RUN apt-get update
RUN apt-get install -y --no-install-recommends git curl unzip zip wget gnupg sudo xvfb fonts-noto-cjk

# 作業ユーザー作成
ARG UID=1000
ARG GID=1000
ARG USER=docker
ARG GROUP=docker
RUN <<EOF
    groupadd -g $GID $GROUP
    useradd -u $UID -g $GROUP -m -s /bin/bash $USER
    echo "${USER}:${USER}" | chpasswd
    adduser $USER sudo
    echo "${USER} ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
EOF

USER ${USER}

# gradle実行環境
RUN <<EOF
    curl -s "https://get.sdkman.io" | bash
    source ~/.sdkman/bin/sdkman-init.sh
    sdk install gradle 8.0.2
EOF

# ブラウザをインストールするための準備
RUN <<EOF
    # Chromeのリポジトリ追加
    curl -fsSL https://dl.google.com/linux/linux_signing_key.pub | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/google-chrome.gpg
    sudo sh -c "echo 'deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main' > /etc/apt/sources.list.d/google-chrome.list"

    # Firefoxインストールのため必要なリポジトリ追加
    sudo  sh -c "echo 'deb http://deb.debian.org/debian/ unstable main contrib non-free' > /etc/apt/sources.list.d/debian.list"

    # Microsoftのリポジトリ追加
    curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/microsoft.gpg
    sudo sh -c "echo 'deb [arch=amd64] https://packages.microsoft.com/repos/edge/ stable main' > /etc/apt/sources.list.d/microsoft-edge.list"
EOF

WORKDIR /src

COPY ./entrypoint.sh /entrypoint.sh
RUN sudo chmod +x /entrypoint.sh

# ビルド時にもインストールしておく
RUN /entrypoint.sh

# 実行時に各ブラウザをインストール
ENTRYPOINT ["/bin/bash", "/entrypoint.sh"]

EXPOSE 8088