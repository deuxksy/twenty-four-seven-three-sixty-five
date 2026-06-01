# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

OCI Free-Tier 인프라 프로비저닝 프로젝트. OpenTofu로 Oracle Cloud 리소스를 관리하고, SOPS(age)로 시크릿을 암호화한다. GitHub Codespaces에서 개발한다.

## Prerequisites

- **도구**: `tofu` (OpenTofu), `sops`, `age` (암호화 키)
- **키 파일**: 프로젝트 루트에 `keys.txt` (age 개인키, `.gitignore`에 등록됨)
- **환경**: Codespaces(`.devcontainer/`) 또는 로컬(Alpine Linux 필요)
- **R2 자격 증명**: Cloudflare R2의 Access Key ID / Secret Access Key (환경변수 `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` — `tofu init` 시 필요)

## Commands

```bash
# SOPS 시크릿 관리 (keys.txt 필요)
source .env.local          # enc/dec/load alias 로드
dec                        # .env.sops → .env 복호화
enc                        # .env → .env.sops 암호화
load                       # .env 변수를 쉘 환경에 주입

# OpenTofu (tf-infra/ 디렉토리에서 실행)
cd tf-infra
tofu init                  # Cloudflare R2 backend로 초기화
tofu plan -var-file=terraform.tfvars
tofu apply -auto-approve -var-file=terraform.tfvars

# 전체 배포 (setup.sh)
# keys.txt가 프로젝트 루트에 있어야 함
bash setup.sh
```

## Architecture

```
.env.sops ──(sops -d)──→ .env ──(source)──→ 쉘 환경변수
                                              │
tf-infra/                                    ├→ .oci/oci_api_key.pem
├── provider.tf  (OCI provider + 변수 정의)   ├→ terraform.tfvars (자동 생성)
├── backend.tf   (Cloudflare R2 state)       └→ tofu apply
└── .terraform.lock.hcl
```

- **Secret Flow**: `.env.sops`(암호화, git 추적) → `sops -d` → `.env`(평문, `.gitignore`) → `setup.sh`가 `terraform.tfvars`와 OCI PEM 키 자동 생성
- **SOPS binary 모드**: `.env`에 PEM 키, 멀티라인 값 등 특수문자가 포함되어 `--input-type binary`로 인코딩 문제를 우회함. 일반 텍스트 모드(`sops -d .env.sops`)로는 줄바꿈 손실 발생
- **State Backend**: Cloudflare R2 (S3-compatible). 버킷(`terraform-state`)은 수동 생성. `backend.tf`에 엔드포인트 하드코딩됨
- **R2 자격 증명**: `tofu init` 전 `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` 환경변수 필요 (Cloudflare R2 API 토큰)
- **DevContainer**: Alpine 3.23 기반. `opentofu`, `sops` 패키지 포함. `postStartCommand`에서 `SOPS_AGE_KEY` 환경변수로 자동 복호화
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
