# 247365

OCI Free-Tier(AMD Micro + ARM A1) 인프라 구성 프로젝트. Web Browser만 접근 가능한 환경에서 OpenTofu + Ansible로 프로비저닝하고, Tailscale HTTPS로 code-server에 접속해 개발.

```
Web Browser → GitHub Codespaces → OpenTofu/Ansible 배포 → code-server (Tailscale HTTPS)
```

## Quick Start

```bash
# 사전 준비: keys.txt (age 개인키)를 프로젝트 루트에 배치
# 사전 준비: sops, age, tofu (opentofu), ansible 설치

# 1. SOPS 유틸리티 로드
source .env.local

# 2. 시크릿 복호화
dec        # .env.sops → .env
load       # 쉘 환경에 변수 주입

# 3. 전체 배포 (복호화 + tfvars 생성 + tofu apply + hosts.ini 생성)
bash setup.sh

# 4. Ansible 설정 적용
cd ansible
ansible-playbook playbook-lt.yml      # lt: Tailscale exit node
ansible-playbook playbook-brla.yml    # brla: Docker + code-server + monitoring + Hermes
```

## 구조

```
.env.sops          # 암호화된 시크릿 (git 추적)
.env.local         # SOPS 유틸리티 (sops-dec/enc/load 함수 + alias)
setup.sh           # 전체 배포 (.env.local 호출 → tfvars 생성 → tofu)
opentofu/          # OpenTofu (VCN, Compute, Storage)
ansible/           # Ansible (Tailscale, Docker, code-server, monitoring, Hermes)
.devcontainer/     # Codespaces 설정
```

## Monitoring Dashboard

`brla`에는 Heritage 설정을 복사한 Homepage/Gatus와 새 Beszel Hub를 배포한다.
기존 Heritage 배포와 설정은 그대로 유지한다.

| 서비스 | URL | 이전 범위 |
| :--- | :--- | :--- |
| Homepage | `https://brla.bun-bull.ts.net` | Heritage 설정 복사 |
| code-server | `https://brla.bun-bull.ts.net:8080` | 개발 환경 (Tailscale HTTPS) |
| Gatus | `https://brla.bun-bull.ts.net:8088` | endpoint 설정 복사, 이력 DB 신규 생성 |
| Beszel | `https://brla.bun-bull.ts.net:8090` | 계정과 데이터 모두 신규 생성 |

Homepage의 Transmission/Jellyfin/Aria2 링크는 기존 Heritage 서비스를 계속
가리킨다. Gatus와 Beszel 런타임 데이터는 대상 호스트에서 새로 생성된다.
새 Beszel 계정은 SOPS의 `HOMEPAGE_VAR_BESZEL_USERNAME` 및
`HOMEPAGE_VAR_BESZEL_PASSWORD`와 일치하게 생성하거나 해당 값을 갱신해야 한다.

## AI Agent (Hermes)

`brla`에 `nousresearch/hermes-agent` 컨테이너(`network_mode: host`)를 배포한다.
AI provider는 Tailscale Aperture 경유로 `glm-5-turbo`를 사용하며,
`deuxksy/ai-brla` repo에 하루 4회(03:10/09:10/15:10/21:10) SQLite dump를
자동 백업한다. 컨테이너는 UID 10000으로 `/data/hermes/data`를 소유한다.

| 컴포넌트 | 포트 | URL |
| :--- | :--- | :--- |
| Gateway | `8642` | health check용 (`127.0.0.1` bind, 컨테이너 내부) |
| Dashboard | `9119` | `https://brla.bun-bull.ts.net:9119` (basic_auth) |

Dashboard는 컨테이너 내 `9120` 포트에서 basic_auth로 동작하고(`HOST=0.0.0.0`),
Tailscale Serve가 `9119` HTTPS로 종단하여 `127.0.0.1:9120`으로 프록시한다.
인증 정보는 SOPS의 `HERMES_DASHBOARD_BASIC_AUTH_USERNAME` /
`HERMES_DASHBOARD_BASIC_AUTH_PASSWORD`를 사용한다.
