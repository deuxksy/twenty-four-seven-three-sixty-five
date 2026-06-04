# twenty-four-seven-three-sixty-five

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
ansible-playbook playbook-brla.yml    # brla: Docker + code-server + Hermes
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
