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
source .env.local    # alias 로드
dec                  # .env.sops → .env 복호화
```

### 2. OpenTofu 프로비저닝

```bash
cd opentofu
unset OCI_PRIVATE_KEY    # OCI provider 충돌 방지 (필수)
source ../.env
../setup.sh              # terraform.tfvars + PEM 키 생성

# 수동 apply (setup.sh에서 주석 처리됨)
tofu init
tofu plan -var-file=terraform.tfvars
tofu apply -auto-approve -var-file=terraform.tfvars
```

### 3. Ansible 인벤토리 생성

```bash
cd ansible
tofu output -raw ansible_inventory_ini > inventory/hosts.ini
```

### 4. Ansible 설정 적용

```bash
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
- Hermes 최초 배포 시 `/data/hermes/.env`에 API 키 사전 작성 필요
- Hermes 컨테이너는 UID 10000으로 `/data/hermes` 소유권 변경 → `sudo` 필요
