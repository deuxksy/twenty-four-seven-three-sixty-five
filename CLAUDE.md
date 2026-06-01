# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

OCI Free-Tier 인프라 프로비저닝 프로젝트. OpenTofu로 Oracle Cloud 리소스를 관리하고, Ansible로 인스턴스 설정. SOPS(age)로 시크릿을 암호화한다. GitHub Codespaces에서 개발한다.

## Prerequisites

- **도구**: `tofu` (OpenTofu), `sops`, `age` (암호화 키), `ansible`
- **키 파일**: 프로젝트 루트에 `keys.txt` (age 개인키, `.gitignore`에 등록됨)
- **환경**: Codespaces(`.devcontainer/`) 또는 로컬
- **R2 자격 증명**: Cloudflare R2의 Access Key ID / Secret Access Key (환경변수 `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` — `tofu init` 시 필요)

## Commands

```bash
# SOPS 시크릿 관리 (keys.txt 필요)
source .env.local          # enc/dec/load alias 로드
dec                        # .env.sops → .env 복호화
enc                        # .env → .env.sops 암호화
load                       # .env 변수를 쉘 환경에 주입

# OpenTofu (opentofu/ 디렉토리에서 실행)
cd opentofu
tofu init                  # Cloudflare R2 backend로 초기화
tofu plan -var-file=terraform.tfvars
tofu apply -auto-approve -var-file=terraform.tfvars

# Ansible (Tailscale 연결 후 실행)
cd ansible
tofu output -raw ansible_inventory_ini > inventory/hosts.ini
ansible-playbook playbook-lt.yml       # AMD Micro(lt): exit node 설정
ansible-playbook playbook-brla.yml     # ARM A1(brla): Docker + 서비스 배포

# 전체 배포 (setup.sh)
bash setup.sh
```

## Architecture

```
인터넷 ─→ AMD Micro (lt, Ubuntu 24.04)
           lt-subnet (10.210.0.0/24), 공용 IP
           Tailscale exit node + subnet router
                │
                │ VCN (10.210.0.0/16)
                │
                └→ ARM A1 (brla, Ubuntu 24.04 ARM, 4 OCPU / 24GB RAM)
                   brla-subnet (10.210.1.0/24), 공용 IP
                   Block Volume 64GB → /data
                   Docker Compose: code-server + Hermes Agent
```

- **Provisioning**: OpenTofu(cloud-init으로 Tailscale 설치) → Ansible(Tailscale 네트워크로 전체 설정)
- **Secret Flow**: `.env.sops`(암호화, git 추적) → `sops -d` → `.env`(평문, `.gitignore`) → `setup.sh`가 `terraform.tfvars`와 OCI PEM 키 자동 생성
- **SOPS binary 모드**: `.env`에 PEM 키, 멀티라인 값 등 특수문자가 포함되어 `--input-type binary`로 인코딩 문제를 우회함
- **State Backend**: Cloudflare R2 (S3-compatible). 버킷(`terraform-state`)은 수동 생성
- **Hostnames**: `lt`(L-T, 조명 로봇), `brla`(BRL-A, 파라솔 로봇) — WALL-E 세계관
- **HTTPS**: Tailscale 내장 HTTPS (`*.bun-bull.ts.net`)
- **Region**: OCI `ap-chuncheon-1` (춘천)

## Key Variables

`terraform.tfvars`에 필요한 변수 (`.env`에서 자동 주입):

| 변수 | 출처 |
| :--- | :--- |
| `oci_tenancy_ocid` | OCI 콘솔 |
| `oci_user_ocid` | OCI 콘솔 |
| `oci_fingerprint` | OCI API 키 |
| `oci_private_key_path` | `.env` → PEM 추출 |
| `compartment_ocid` | OCI 콘솔 |
| `oci_region` | 기본값 `ap-chuncheon-1` |
| `tailscale_auth_key` | Tailscale |
| `ssh_public_key` | 로컬 SSH 공개키 |

## Notes

- `setup.sh`의 `rm -f .env` 라인이 현재 주석 처리됨 (보안상 활성화 권장)
- `tofu apply`도 `setup.sh`에서 주석 처리됨 (수동 실행 필요)
- `.env.local`은 Codespaces 전용 alias 파일 (로컬에서도 `source .env.local`로 사용 가능)
- 인프라 변경 후 `docs/superpowers/specs/` 스펙과 실제 코드 동기화 필수

## Gotchas

- `OCI_PRIVATE_KEY` 환경변수가 OCI Terraform provider와 충돌 → `tofu` 명령 전 `unset OCI_PRIVATE_KEY` 필수
- Tailscale cert DNS명에 trailing dot 포함 (`brla.bun-bull.ts.net.`) → `rstrip('.')` 처리
- Tailscale 인증서 경로는 `/var/lib/tailscale/certs/` (not `/etc/tailscale/`)
- Ansible inventory: brla 접속 시 lt를 ProxyJump로 사용 (`-o ProxyJump=ubuntu@<lt_ip>`)
- Block Volume `/data` 마운트 후 code-server 컨테이너에 `user: "1000:1000"` 필요
- Hermes 최초 배포 시 API 키 입력 필요 → `/data/hermes/.env`에 `ANTHROPIC_API_KEY` 등 사전 작성하면 setup 생략 가능

## Directory Structure

```
opentofu/                # OpenTofu
├── backend.tf           # Cloudflare R2 state backend
├── provider.tf          # OCI provider
├── variables.tf         # 변수 선언
├── data.tf              # Ubuntu 24.04 이미지 조회 (AMD/ARM)
├── vcn.tf               # VCN, Subnets, Security Lists, Gateway
├── compute.tf           # AMD Micro (lt) + ARM A1 (brla)
├── storage.tf           # Block Volume 64GB + Attachment
├── cloud-init-lt.yaml   # lt: Tailscale + exit node
└── cloud-init-brla.yaml # brla: Tailscale

ansible/                 # Ansible
├── ansible.cfg
├── inventory/hosts.ini  # tofu output으로 자동 생성
├── playbook-lt.yml      # lt: Tailscale exit node
├── playbook-brla.yml    # brla: Docker + code-server + Hermes
└── roles/
    ├── tailscale/       # exit node, IP forwarding, HTTPS cert
    ├── docker/          # Docker Engine + Compose, /data 마운트
    ├── code-server/     # codercom/code-server:latest (user 1000:1000)
    └── hermes/          # nousresearch/hermes-agent:latest, gateway run
```
