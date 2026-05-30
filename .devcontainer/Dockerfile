FROM alpine:3.23

# 필수 기본 도구 및 OpenTofu를 Alpine 공식 패키지 매니저로 한 방에 인스톨
RUN apk update && apk add --no-cache \
    bash \
    curl \
    git \
    openssh-client \
    sudo \
    tofu \
    && rm -rf /var/cache/apk/*

WORKDIR /workspace