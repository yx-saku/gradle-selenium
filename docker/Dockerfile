# syntax=docker/dockerfile:1

FROM public.ecr.aws/amazoncorretto/amazoncorretto:11

SHELL ["/bin/bash", "-c"]

ENV DEBIAN_FRONTEND=noninteractive

############################################################
# install packages
############################################################
RUN yum update -y
RUN yum install -y git wget timedatectl ipa-gothic-fonts sudo tar which jq unzip

RUN wget https://github.com/aws-cloudformation/rain/releases/download/v1.6.0/rain-v1.6.0_linux-amd64.zip \
    unzip rain-v1.6.0_linux-amd64.zip \
    ln -s /usr/bin/rain rain-v1.6.0_linux-amd64/rain-v1.6.0_linux-amd64/rain

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