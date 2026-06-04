# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

OCI Free-Tier(AMD Micro + ARM A1) 인프라 구성 프로젝트. Web Browser만 접근 가능한 환경에서 OpenTofu + Ansible로 프로비저닝하고, Tailscale HTTPS로 code-server에 접속해 개발. OpenTofu로 Oracle Cloud 리소스를 관리하고, Ansible로 인스턴스 설정. SOPS(age)로 시크릿을 암호화한다. GitHub Codespaces에서 초기 프로비저닝 후 Tailscale HTTPS로 code-server에 접속한다.

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

# Ansible (Tailscale 연결결 실행)
cd opentofu
tofu output -raw ansible_inventory_ini > ../ansible/inventory/hosts.ini
cd ../ansible
ansible-playbook playbook-lt.yml       # AMD Micro(lt): exit node 설정
ansible-playbook playbook-brla.yml     # ARM A1(brla): Docker + 서비스 배포

# Ansible 운영 관리 (inventory 생성 후)
ansible-playbook playbook-ops.yml --tags reboot          # lt/brla 병렬 재부팅
ansible-playbook playbook-ops.yml --tags system-update   # apt 업데이트 (lt/brla)
ansible-playbook playbook-ops.yml --tags docker-update   # Docker 이미지 pull + 컨테이너 재시작 (brla)
ansible-playbook playbook-ops.yml --tags health          # health check (uptime, load, disk)

# 전체 배포 (setup.sh)
bash setup.sh

# SSH 접속 (IP는 inventory에서 동적 획득)
LT_IP=$(grep 'ansible_host=' ansible/inventory/hosts.ini | head -1 | sed 's/.*ansible_host=\([^ ]*\).*/\1/')
BRLA_IP=$(grep 'ansible_host=' ansible/inventory/hosts.ini | tail -1 | sed 's/.*ansible_host=\([^ ]*\).*/\1/')
ssh ubuntu@$LT_IP                                                     # lt 직접
ssh -o ProxyJump=ubuntu@$LT_IP ubuntu@$BRLA_IP                        # brla (lt 경유)

# 서비스 검증 (brla에서)
curl -s -o /dev/null -w '%{http_code}' http://localhost:8080           # code-server
curl -s -o /dev/null -w '%{http_code}' http://localhost:9119           # Hermes dashboard
```

## Architecture

```mermaid
graph TD
  subgraph OCI[Oracle Cloud Infrastructure]
    subgraph VCN[VCN 10.210.0.0/16]
      IGW[Internet Gateway]
      SGW[Service Gateway]

      subgraph lt-subnet[lt-subnet 10.210.0.0/24]
        lt[AMD Micro lt<br/>Ubuntu 24.04<br/>Tailscale Exit Node]
        lt-sl[lt-sl<br/>SSH 22, Tailscale 41641]
      end

      subgraph brla-subnet[brla-subnet 10.210.1.0/24]
        brla[ARM A1 brla<br/>Ubuntu 24.04 ARM<br/>Docker Compose]
        brla-sl[brla-sl<br/>Tailscale 41641]
        BV[Block Volume 64GB<br/>/data]
      end

      IGW --> lt-subnet
      IGW --> brla-subnet
      SGW --> brla-subnet
    end
  end

  Internet --> IGW
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

- `setup.sh`가 실행 후 `.env`를 자동 삭제함 → Ansible 재실행 시 `sops -d` 재복호화 필요
- `setup.sh`에서 `tofu init`/`tofu plan`/`tofu apply` 자동 실행 (전체 프로비저닝)
- `.env.local`은 SOPS 유틸리티 (함수 + alias: `dec`, `enc`, `load`). `source .env.local`로 로드. `setup.sh`도 내부적으로 호출
- 인프라 변경 후 스펙과 실제 코드 동기화 필수

## Gotchas

- `.env.local`의 `dec`/`load`는 alias — Claude Code Bash(비대화형)에서 인식 안 됨. 직접 함수명 `sops-dec`, `sops-load` 또는 raw `sops -d` 명령 사용
- cloud-init(`user_data`) 변경 시 OCI 인스턴스 재생성(destroy+recreate) → **Public IP 변경**. cloud-init은 최소화(Tailscale 설치만)하고 설정은 Ansible로 처리
- `OCI_PRIVATE_KEY` 환경변수가 OCI Terraform provider와 충돌 → `tofu` 명령 전 `unset OCI_PRIVATE_KEY` 필수
- Tailscale cert DNS명에 trailing dot 포함 (`brla.bun-bull.ts.net.`) → `rstrip('.')` 처리
- Tailscale 인증서 경로는 `/var/lib/tailscale/certs/` (not `/etc/tailscale/`)
- Ansible inventory: brla 접속 시 lt를 ProxyJump로 사용 (`-o ProxyJump=ubuntu@<lt_ip>`)
- code-server 컨테이너는 ubuntu UID 1001과 매칭 (`user: "1001:1001"`) → 호스트에서 파일 조작 가능 (sudo 불필요)
- Hermes API 키/토큰은 docker-compose `environment:`에서 Ansible로 직접 주입 (별도 `.env` 파일 사전 작성 불필요)
- Hermes 컨테이너는 UID 10000으로 `/data/hermes/data` 소유권 변경 → 호스트에서 파일 조작 시 `sudo` 필요
- Hermes 데이터 구조: `/data/hermes/data/` (실제 데이터, 디렉토리 마운트), `/data/hermes/docker-compose.yml` (Ansible 생성)
- Hermes API server: `API_SERVER_KEY`(8자+) 필수, Dashboard: `HERMES_DASHBOARD_INSECURE=1` (Tailscale 내부망)
- Hermes AI: Ark Coding Plan provider, base URL `https://ark.ap-southeast.bytepluses.com/api/coding/v1`, model `ark-code-latest`
- Hermes Docker 볼륨: `/data/hermes/data:/opt/data` (디렉렉토리 마운트, rw). 파일 단위 `:ro` 마운트 시 atomic write 불가
- Hermes Git 백업: `deuxksy/ai-brla` repo에 하루 4회 자동 백업 (cron: 03:10, 09:10, 15:10, 21:10). SQL dump로 SQLite 백업. `GITHUB_HERMES_TOKEN` 필요 (`.env.sops`에서 SOPS 복호화)
- SSH IdentitiesOnly: 글로벌 `IdentitiesOnly yes` + `IdentityFile ~/.ssh/id_ed25519` + `IdentityFile ~/.ssh/AI/id_ed25519` 로 해결. 별도 `ansible/ssh_config` 불필요
- Docker 로그 로테이션: `/etc/docker/daemon.json`으로 `max-size: 10m`, `max-file: 3`. **신규 컨테이너에만 적용** — 기존 컨테이너는 `docker compose down && up`으로 재생성 필요
- IP forwarding: cloud-init에서 제거, Ansible tailscale role에서만 설정. `tofu apply` 직후 Ansible을 즉시 실행해야 exit node 정상 동작
- 결합점 (다중 파일 참조 값, 변경 시 동기화 필수): 디바이스 경로 `/dev/oracleoci/oraclevdb` (storage.tf, docker role), code-server 포트 `8080` (compose, tailscale serve), Docker 이미지명 (compose, ops playbook), 호스트명 `lt`/`brla` (variables.tf, cloud-init, playbook), CIDR `10.210.1.0/24` (variables.tf, cloud-init, playbook), UID `1001`/`10000` (compose, tasks), Tailscale `41641/UDP` (vcn.tf Security List)

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
├── outputs.tf           # Ansible inventory, output values
├── cloud-init-lt.yaml   # lt: Tailscale + exit node
└── cloud-init-brla.yaml # brla: Tailscale

ansible/                 # Ansible
├── ansible.cfg
├── inventory/hosts.ini  # tofu output으로 자동 생성
├── playbook-lt.yml      # lt: Tailscale exit node
├── playbook-brla.yml    # brla: Docker + code-server + Hermes
├── playbook-ops.yml     # 운영 관리 (reboot, update, health check)
└── roles/
    ├── tailscale/       # exit node, IP forwarding, HTTPS cert
    ├── docker/          # Docker Engine + Compose, /data 마운트
    ├── code-server/     # codercom/code-server:latest (user 1000:1000)
    └── hermes/          # nousresearch/hermes-agent:latest, gateway run
        ├── files/gitignore    # 백업 제외 규칙
        ├── templates/backup.sh.j2  # Git 백업 스크립트 (cron 실행)
        └── templates/docker-compose.yml.j2  # Ansible 생성

.claude/skills/          # Claude Code 스킬
├── deploy-infra/SKILL.md  # 전체 배포 파이프라인
└── verify-infra/SKILL.md  # 인프라 상태 검증
```
