# .devcontainer/Dockerfile
FROM mcr.microsoft.com/devcontainers/base:ubuntu-22.04

ENV DEBIAN_FRONTEND=noninteractive

# 1. 필수 및 보안 패키지 (age 포함) 설치
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl gnupg software-properties-common jq git age \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# 2. Mozilla SOPS 설치 (GitHub Releases에서 안정 최신 버전 바이너리 다운로드)
RUN curl -LO https://github.com/getsops/sops/releases/download/v3.9.4/sops-v3.9.4.linux.amd64 \
    && mv sops-v3.9.4.linux.amd64 /usr/local/bin/sops \
    && chmod +x /usr/local/bin/sops

# 3. OpenTofu 설치
RUN curl -s https://packagecloud.io/install/repositories/opentofu/tofu/script.deb.sh | bash \
    && apt-get install -y tofu \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# 4. Ansible 및 Tailscale 설치
RUN apt-get update && apt-get install -y --no-install-recommends ansible \
    && apt-get clean && rm -rf /var/lib/apt/lists/* \
    && curl -fsSL https://tailscale.com/install.sh | sh

WORKDIR /workspace