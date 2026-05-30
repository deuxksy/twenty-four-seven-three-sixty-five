FROM alpine:3.23

# 1. 필수 패키지 및 사용자님이 검증하신 오리지널 패키지(opentofu, sops) 인스톨
RUN apk update && apk add --no-cache \
    bash \
    curl \
    git \
    openssh-client \
    sudo \
    opentofu \
    sops \
    && rm -rf /var/cache/apk/*

# 2. 🎯 [핵심] GitHub Codespaces가 요구하는 vscode 유저 생성 및 sudo 권한 부여
# shadow 패키지 없이 alpine 규격(adduser)으로 안정적인 유저 생성
RUN adduser -D -s /bin/bash vscode \
    && echo "vscode ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/vscode \
    && chmod 0440 /etc/sudoers.d/vscode

# Codespaces 기본 작업 디렉토리 설정
WORKDIR /workspace