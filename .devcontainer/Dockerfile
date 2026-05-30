FROM mcr.microsoft.com/devcontainers/base:ubuntu-22.04

ENV DEBIAN_FRONTEND=noninteractive

# 1. 필수 패키지 및 age 설치
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl gnupg software-properties-common jq git age \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# 2. Mozilla SOPS 3.9.4 자동 인스톨 (빌드 에러를 막기 위해 sudo 제거)
RUN curl -LO https://github.com/getsops/sops/releases/download/v3.9.4/sops_3.9.4_amd64.deb \
    && dpkg -i sops_3.9.4_amd64.deb \
    && rm sops_3.9.4_amd64.deb

# 3. OpenTofu(테라포름 대체) 자동 인스톨
RUN curl -s https://packagecloud.io/install/repositories/opentofu/tofu/script.deb.sh | bash \
    && apt-get install -y tofu \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace