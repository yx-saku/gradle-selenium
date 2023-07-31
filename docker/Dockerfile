# syntax=docker/dockerfile:1

FROM public.ecr.aws/amazoncorretto/amazoncorretto:17

SHELL ["/bin/bash", "-c"]

ENV DEBIAN_FRONTEND=noninteractive

############################################################
# install packages
############################################################
RUN yum update -y
RUN yum install -y git wget timedatectl ipa-gothic-fonts sudo tar which

############################################################
# install chrome
############################################################
# リポジトリの出どころ
# https://magai.hateblo.jp/entry/2018/03/21/194425
RUN yum install -y atk at-spi2-atk cups-libs libdrm libxkbcommon libXcomposite libXdamage libXrandr mesa-libgbm pango alsa-lib
RUN <<EOF
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.3/install.sh | bash
    . ~/.nvm/nvm.sh
    nvm install 16

    CHROME_PATH=`npx @puppeteer/browsers install chrome@stable --path /opt/installs | awk '{ print $2 }' | xargs dirname`
    cp -rf $CHROME_PATH /opt/chrome
    ln -s /opt/chrome/chrome /usr/bin/chrome 
    rm -rf /opt/installs
EOF

# ロケールとタイムゾーン
ENV TZ=Asia/Tokyo

# 作業ユーザー作成
ARG UID=1000
ARG GID=1000
ARG USER
ARG GROUP
RUN <<EOF
    groupadd -g $GID $GROUP
    useradd -u $UID -g $GROUP -m -s /bin/bash $USER
    echo "${USER}:${USER}" | chpasswd
    echo "${USER} ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
EOF

USER ${USER}

EXPOSE 8088