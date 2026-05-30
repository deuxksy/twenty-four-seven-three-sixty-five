FROM alpine:3.23

# 필수 기본 도구 및 사용자님이 직접 확인하신 오리지널 패키지 명칭(opentofu, sops)으로 주입
RUN apk update && apk add --no-cache \
    bash \
    curl \
    git \
    openssh-client \
    sudo \
    opentofu \
    sops \
    && rm -rf /var/cache/apk/*

WORKDIR /workspace