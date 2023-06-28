# syntax=docker/dockerfile:1

FROM amazonlinux:2

SHELL ["/bin/bash", "-c"]

ENV DEBIAN_FRONTEND=noninteractive

############################################################
# install packages
############################################################
RUN yum update -y
RUN yum install -y git wget timedatectl ipa-gothic-fonts

############################################################
# install Java11(Amazon Corretto 11)
############################################################
RUN yum install -y java-11-amazon-corretto

############################################################
# install chrome
############################################################
# リポジトリの出どころ
# https://magai.hateblo.jp/entry/2018/03/21/194425
COPY ./files/google-chrome.repo /etc/yum.repos.d/google-chrome.repo
RUN wget -nv -O linux_signing_key.pub https://dl.google.com/linux/linux_signing_key.pub 
RUN rpm --import linux_signing_key.pub
RUN yum --nogpgcheck install -y google-chrome-stable

# ロケールとタイムゾーン
ENV TZ=Asia/Tokyo
ENV LANG="ja_JP.UTF-8" \
    LANGUAGE="ja_JP:ja"

# allureコマンドのダウンロード
RUN <<EOF
    cd ..
    ./gradlew downloadAllure

    ln -s app/build/allure/commandline/bin/allure /usr/bin/allure
EOF

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

EXPOSE 8088