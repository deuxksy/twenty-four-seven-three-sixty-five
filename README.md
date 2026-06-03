# twenty-four-seven-three-sixty-five

OCI Free-Tier(AMD Micro + ARM A1) 인프라 구성 프로젝트. Web Browser만 접근 가능한 환경에서 OpenTofu + Ansible로 프로비저닝하고, Tailscale HTTPS로 code-server에 접속해 개발.

```
Web Browser → GitHub Codespaces → OpenTofu/Ansible 배포 → code-server (Tailscale HTTPS)
```

## Quick Start

```bash
# 1. Codespaces에서 열기 (keys.txt 필요)
# 2. SOPS 유틸리티 로드
source .env.local

# 3. 시크릿 복호화 (또는: bash setup.sh 로 전체 배포)
dec        # .env.sops → .env
load       # 쉘 환경에 변수 주입

# 4. 전체 배포 (복호화 + tfvars 생성 + tofu)
bash setup.sh
```

## 구조

```
.env.sops          # 암호화된 시크릿 (git 추적)
.env.local         # SOPS 유틸리티 (sops-dec/enc/load 함수 + alias)
setup.sh           # 전체 배포 (.env.local 호출 → tfvars 생성 → tofu)
opentofu/          # OpenTofu (VCN, Compute, Storage)
ansible/           # Ansible (Tailscale, Docker, code-server, Hermes)
.devcontainer/     # Codespaces 설정
```
