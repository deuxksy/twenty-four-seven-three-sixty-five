# OCI Free-Tier 인프라 설계

> **Date**: 2026-06-02
> **Status**: Approved

## 목표

Web Browser만으로 개발 가능한 환경에서 OCI Free-Tier 리소스를 활용해 24/7/365 인프라 구축.

## 아키텍처

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
                   Docker Compose:
                   ├── code-server (VSCode)
                   └── Hermes (AI Agent)
```

- 두 서브넷 모두 Internet Gateway로 아웃바운드 (brla-sl가 SSH를 VCN만 허용하여 간접 보호)
- brla SSH는 lt를 통한 ProxyJump로만 접근

## 인프라 리소스

### 네트워크 (VCN)

| 리소스 | CIDR / 설정 | 용도 |
| :--- | :--- | :--- |
| VCN | 10.210.0.0/16 | 전체 네트워크 |
| lt-subnet | 10.210.0.0/24 | AMD Micro (Public) |
| brla-subnet | 10.210.1.0/24 | ARM A1 (Public, SSH 제한) |
| Internet Gateway | VCN 연결 | 양쪽 서브넷 아웃바운드 |
| Route Table | 0.0.0.0/0 → Internet Gateway | 공용 |
| lt-sl (Security List) | SSH(22), Tailscale(41641/UDP) from 0.0.0.0/0 | lt 인바운드 |
| brla-sl (Security List) | Tailscale(41641/UDP) from 0.0.0.0/0, SSH(22) from VCN만 | brla 인바운드 |

### 컴퓨트 인스턴스

| 인스턴스 | 타입 | OS | CPU / RAM | Boot Vol | 용도 |
| :--- | :--- | :--- | :--- | :--- | :--- |
| AMD Micro (lt) | VM.Standard.E2.1.Micro | Ubuntu 24.04 LTS | 1/8 OCPU, 1GB | 50GB | Tailscale exit node, jumphost |
| ARM A1 (brla) | VM.Standard.A1.Flex | Ubuntu 24.04 LTS ARM | 4 OCPU, 24GB | 50GB | Docker Compose (Hermes + code-server) |

### 호스트명

| 인스턴스 | Tailscale 이름 | 출처 (WALL-E) | 도메인 |
| :--- | :--- | :--- | :--- |
| AMD Micro | `lt` | L-T (LighT, 조명 로봇) | `lt.bun-bull.ts.net` |
| ARM A1 | `brla` | BRL-A (umBReLlA, 파라솔 로봇) | `brla.bun-bull.ts.net` |

### 스토리지

| 볼륨 | 크기 | 마운트 | 용도 |
| :--- | :--- | :--- | :--- |
| AMD Micro boot | 50GB | / | 기본 |
| ARM A1 boot | 50GB | / | 기본 |
| Block Volume | 64GB | /data | Docker data, workspace (Paravirtualized) |

### DNS

Tailscale MagicDNS 사용. 외부 DNS 불필요.

### HTTPS

Tailscale 내장 HTTPS 사용. Let's Encrypt 자동 발급/갱신.

| 서비스 | URL |
| :--- | :--- |
| code-server | `https://brla.bun-bull.ts.net:8080` |
| Hermes | `https://brla.bun-bull.ts.net:8642` (Gateway), `:9119` (Dashboard) |

Ansible에서 `tailscale cert <hostname>.bun-bull.ts.net` 으로 인증서 발급 후 컨테이너에 경로 지정.
인증서 경로: `/etc/tailscale/<hostname>.bun-bull.ts.net.{crt,key}`

## 프로비저닝 흐름

```
1. OpenTofu
   ├── VCN, Subnets (lt-subnet, brla-subnet), Security Lists, Internet Gateway 생성
   ├── AMD Micro (lt) 인스턴스 + cloud-init (Tailscale 설치 + exit node)
   ├── ARM A1 (brla) 인스턴스 + cloud-init (Tailscale 설치)
   ├── Block Volume 64GB 생성 → brla에 Attach (Paravirtualized)
   └── outputs.tf → Ansible inventory 생성 (ProxyJump 포함)

2. Ansible (Tailscale 네트워크로 접근)
   ├── lt: Tailscale exit node + subnet router 활성화
   ├── brla: Block Volume 마운트 (/data, xfs)
   ├── brla: Docker + Docker Compose 설치
   ├── brla: Tailscale HTTPS 인증서 발급
   ├── brla: code-server 컨테이너 배포
   └── brla: Hermes 컨테이너 배포
```

### cloud-init (최소 부트스트랩)

- Tailscale 설치 + 인증 (`TAILSCALE_AUTH_KEY` 사용)
- ARM: 추가 패키지 없이 Tailscale만

### Ansible 역할

| Role | 대상 | 내용 |
| :--- | :--- | :--- |
| `tailscale` | lt, brla | Tailscale 설정, exit node (lt만), HTTPS cert (brla만) |
| `docker` | brla | Docker Engine + Compose 설치, Block Volume /data 마운트 |
| `code-server` | brla | code-server 컨테이너 (codercom/code-server:latest, user 1000:1000) |
| `hermes` | brla | Hermes AI Agent 컨테이너 (nousresearch/hermes-agent:latest, gateway + dashboard) |

## 디렉토리 구조

```
twenty-four-seven-three-sixty-five/
├── .env.sops
├── setup.sh
├── opentofu/
│   ├── backend.tf                # Cloudflare R2 state backend
│   ├── provider.tf               # OCI provider
│   ├── variables.tf              # 변수 선언
│   ├── data.tf                   # Ubuntu 24.04 이미지 조회 (AMD/ARM)
│   ├── vcn.tf                    # VCN, Subnets, Security Lists, Gateway
│   ├── compute.tf                # AMD Micro (lt) + ARM A1 (brla)
│   ├── storage.tf                # Block Volume + Attachment
│   ├── cloud-init-lt.yaml        # lt용 cloud-init (Tailscale + exit node)
│   ├── cloud-init-brla.yaml      # brla용 cloud-init (Tailscale)
│   └── outputs.tf                # Ansible inventory, IP, volume device
├── ansible/
│   ├── inventory/
│   │   └── hosts.ini             # OpenTofu outputs로 자동 생성
│   ├── playbook-lt.yml           # lt: Tailscale exit node 설정
│   ├── playbook-brla.yml         # brla: Docker + code-server + Hermes
│   └── roles/
│       ├── tailscale/            # exit node, IP forwarding, HTTPS cert
│       ├── docker/               # Docker Engine + Compose, Block Volume /data 마운트
│       ├── code-server/          # code-server 컨테이너
│       └── hermes/               # Hermes AI Agent 컨테이너
└── .devcontainer/                # Codespaces
```

## 시크릿 (.env.sops)

| 변수 | 용도 |
| :--- | :--- |
| `OCI_TENANCY_OCID` | OCI 인증 |
| `OCI_USER_OCID` | OCI 인증 |
| `OCI_FINGERPRINT` | OCI API 키 |
| `OCI_PRIVATE_KEY` | OCI PEM 키 (평문 변수, `unset OCI_PRIVATE_KEY` 후 PEM 파일로 사용) |
| `OCI_COMPARTMENT_OCID` | Compartment |
| `OCI_REGION` | ap-chuncheon-1 |
| `OCI_SSH_PUBLIC_KEY` | SSH 공개키 |
| `TAILSCALE_AUTH_KEY` | Tailscale 인증 (Ephemeral, Reusable, Pre-approved) |
| `AWS_ACCESS_KEY_ID` | Cloudflare R2 (Terraform state backend) |
| `AWS_SECRET_ACCESS_KEY` | Cloudflare R2 |

### 주의사항

- `OCI_PRIVATE_KEY` 환경변수가 OCI Terraform provider와 충돌 → `unset OCI_PRIVATE_KEY` 후 `setup.sh`에서 heredoc으로 PEM 파일 생성
- Block Volume `/data` 마운트 후 `chown 1000:1000` 필요 (code-server 권한)
- Tailscale cert DNS명에 trailing dot 포함 → `rstrip('.')` 처리
- Ansible inventory: brla 접속 시 lt를 ProxyJump로 사용 (`-o ProxyJump=ubuntu@<lt_ip>`)
