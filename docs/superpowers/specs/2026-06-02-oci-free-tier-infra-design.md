# OCI Free-Tier 인프라 설계

> **Date**: 2026-06-02
> **Status**: Approved

## 목표

Web Browser만으로 개발 가능한 환경에서 OCI Free-Tier 리소스를 활용해 24/7/365 인프라 구축.

## 아키텍처

```
인터넷 ─→ AMD Micro (Ubuntu 24.04)
           Public Subnet (10.210.0.0/24), 공용 IP
           Tailscale exit node + subnet router
                │
                │ VCN (10.210.0.0/16)
                │
                └→ Private Subnet (10.210.1.0/24)
                   │
                   └→ ARM A1 (Ubuntu 24.04, 4 OCPU / 24GB RAM)
                       Block Volume 106GB → /home/ubuntu
                       Docker Compose:
                       ├── code-server (VSCode)
                       └── Hermes (AI Agent)

아웃바운드: ARM → Tailscale → AMD → 인터넷 (NAT Gateway 불필요)
```

## 인프라 리소스

### 네트워크 (VCN)

| 리소스 | CIDR / 설정 | 용도 |
| :--- | :--- | :--- |
| VCN | 10.210.0.0/16 | 전체 네트워크 |
| Public Subnet | 10.210.0.0/24 | AMD Micro |
| Private Subnet | 10.210.1.0/24 | ARM A1 |
| Internet Gateway | Public Subnet 연결 | AMD 인바운드/아웃바운드 |
| Service Gateway | Private Subnet 연결 | ARM → OCI 서비스 |
| Route Table (Public) | 0.0.0.0/0 → Internet Gateway | |
| Route Table (Private) | 0.0.0.0/0 → Tailscale (AMD 경유) | |
| Security List (Public) | SSH(22), Tailscale(41641/UDP) 인바운드 | |
| Security List (Private) | AMD(10.210.0.x)에서만 인바운드 허용 | |

### 컴퓨트 인스턴스

| 인스턴스 | 타입 | OS | CPU / RAM | 용도 |
| :--- | :--- | :--- | :--- | :--- |
| AMD Micro | VM.Standard.E2.1.Micro | Ubuntu 24.04 LTS | 1/8 OCPU, 1GB | Tailscale exit node, jumphost |
| ARM A1 | VM.Standard.A1.Flex | Ubuntu 24.04 LTS ARM | 4 OCPU, 24GB | Docker Compose (Hermes + code-server) |

### 스토리지

| 볼륨 | 크기 | 마운트 | 용도 |
| :--- | :--- | :--- | :--- |
| AMD Micro boot | 47GB | / | 기본 |
| ARM A1 boot | 47GB | / | 기본 |
| Block Volume | 106GB | /home/ubuntu | Docker data, workspace |

### DNS

Tailscale MagicDNS 사용. 외부 DNS 불필요.

## 프로비저닝 흐름

```
1. OpenTofu
   ├── VCN, Subnets, Security Lists, Gateways 생성
   ├── AMD Micro 인스턴스 + cloud-init (Tailscale 설치)
   ├── ARM A1 인스턴스 + cloud-init (Tailscale 설치)
   ├── Block Volume 생성 → ARM에 Attach
   └── outputs.tf → Ansible inventory 생성

2. Ansible (Tailscale 네트워크로 접근)
   ├── AMD: Tailscale exit node + subnet router 활성화
   ├── ARM: Block Volume 마운트 (/home/ubuntu)
   ├── ARM: Docker + Docker Compose 설치
   ├── ARM: code-server 컨테이너 배포
   └── ARM: Hermes 컨테이너 배포
```

### cloud-init (최소 부트스트랩)

- Tailscale 설치 + 인증 (`TAILSCALE_AUTH_KEY` 사용)
- ARM: 추가 패키지 없이 Tailscale만

### Ansible 역할

| Role | 대상 | 내용 |
| :--- | :--- | :--- |
| `tailscale` | AMD, ARM | Tailscale 설정, exit node (AMD만) |
| `docker` | ARM | Docker Engine + Compose 설치 |
| `code-server` | ARM | code-server 컨테이너 (이미지: codercom/code-server:latest) |
| `hermes` | ARM | Hermes AI Agent 컨테이너 |

## 디렉토리 구조

```
twenty-four-seven-three-sixty-five/
├── .env.sops
├── setup.sh
├── opentofu/                     # OpenTofu (tf-infra → 이름 변경)
│   ├── backend.tf                # Cloudflare R2 state (기존)
│   ├── provider.tf               # OCI provider (기존)
│   ├── variables.tf              # 변수 선언
│   ├── vcn.tf                    # VCN, Subnets, Security Lists, Gateways
│   ├── compute.tf                # AMD Micro + ARM A1 인스턴스
│   ├── storage.tf                # Block Volume + Attachment
│   ├── cloud-init-amd.yaml       # AMD용 cloud-init
│   ├── cloud-init-arm.yaml       # ARM용 cloud-init
│   └── outputs.tf                # Ansible용 inventory 출력
├── ansible/                      # Ansible
│   ├── inventory/
│   │   └── hosts.ini             # OpenTofu outputs로 자동 생성
│   ├── playbook-amd.yml          # AMD: Tailscale exit node 설정
│   ├── playbook-arm.yml          # ARM: Docker + code-server + Hermes
│   └── roles/
│       ├── tailscale/
│       ├── docker/
│       ├── code-server/
│       └── hermes/
└── .devcontainer/                # Codespaces (기존)
```

## 시크릿 (.env.sops)

| 변수 | 용도 |
| :--- | :--- |
| `OCI_TENANCY_OCID` | OCI 인증 |
| `OCI_USER_OCID` | OCI 인증 |
| `OCI_FINGERPRINT` | OCI API 키 |
| `OCI_PRIVATE_KEY` | OCI PEM 키 |
| `OCI_COMPARTMENT_OCID` | Compartment |
| `OCI_REGION` | ap-chuncheon-1 |
| `OCI_SSH_PUBLIC_KEY` | SSH 공개키 |
| `TAILSCALE_AUTH_KEY` | Tailscale 인증 |
| `AWS_ACCESS_KEY_ID` | Cloudflare R2 (Terraform state) |
| `AWS_SECRET_ACCESS_KEY` | Cloudflare R2 |
