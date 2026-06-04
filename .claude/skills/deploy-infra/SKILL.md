---
name: deploy-infra
description: OCI 인프라 전체 재배포 (SOPS 복호화 → tofu apply → inventory 생성 → ansible-playbook → 검증)
disable-model-invocation: true
---

# 인프라 전체 재배포

OCI Free-Tier 인프라(lt + brla)를 처음부터 재배포하거나 변경사항을 적용.

## 사전 조건

- `keys.txt` (age 개인키)가 프로젝트 루트에 있어야 함
- Cloudflare R2 자격 증명 (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`)

## 배포 순서

### 1. 시크릿 복호화

```bash
source .env.local    # 함수 + alias 로드
sops-dec             # .env.sops → .env 복호화
sops-load            # .env 변수를 쉘 환경에 주입
```

### 2. OpenTofu 프로비저닝

```bash
cd opentofu
unset OCI_PRIVATE_KEY    # OCI provider 충돌 방지 (필수)

# OCI API 키 복호화
mkdir -p .oci
sops -d ../secrets/oci_api_key.pem.sops > .oci/oci_api_key.pem
chmod 600 .oci/oci_api_key.pem

# terraform.tfvars 자동 생성 + apply
../setup.sh
```

### 3. Ansible 인벤토리 생성

```bash
cd ansible
tofu output -raw ansible_inventory_ini > inventory/hosts.ini
```

### 4. Ansible 설정 적용

```bash
# IdentitiesOnly 충돌 방지용 ssh_config 사용
export ANSIBLE_SSH_ARGS="-F ./ssh_config"

# lt: Tailscale exit node
ansible-playbook playbook-lt.yml

# brla: Docker + code-server + Hermes
ansible-playbook playbook-brla.yml
```

### 5. 검증

`/verify-infra` 스킬로 전체 서비스 상태 확인.

## 주의사항

- `tofu` 명령 전 반드시 `unset OCI_PRIVATE_KEY`
- brla 인스턴스는 Always Free가 아닐 수 있음 — 비용 확인
- Hermes API 키/토큰은 docker-compose `environment:`에서 Ansible로 직접 주입 (별도 `.env` 파일 사전 작성 불필요)
- Hermes 컨테이너는 UID 10000으로 `/data/hermes/data` 소유권 변경 → 호스트에서 파일 조작 시 `sudo` 필요
- IP forwarding은 cloud-init에서 제거됨 → Ansible tailscale role에서만 설정. `tofu apply` 직후 Ansible 즉시 실행해야 exit node 정상 동작
- Docker 로그 로테이션은 `/etc/docker/daemon.json`으로 설정 (max-size: 10m, max-file: 3). 신규 컨테이너에만 적용 — 기존 컨테이너는 `down && up` 필요
- Hermes Git 백업은 Ansible에서 cron + GitHub remote 자동 등록. `GITHUB_HERMES_TOKEN` 필요 (`.env.sops`에서 SOPS 복호화)
