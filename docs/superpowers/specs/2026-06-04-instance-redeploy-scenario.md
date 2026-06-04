# 인스턴스만 Destroy → 재배포 시나리오

> **Date**: 2026-06-04
> **Status**: Reference
> **Scope**: OpenTofu 인스턴스만 destroy/recreate, Block Volume 데이터 유지

## 개요

인스턴스(lt, brla)만 교체하고 Block Volume(64GB)은 유지하여 데이터 유실 없이 재배포.

```mermaid
graph LR
  A[1. 사전 확인] --> B[2. 백업 강제 실행]
  B --> C[3. 인스턴스 destroy]
  C --> D[4. 인스턴스 재생성]
  D --> E[5. Inventory 갱신]
  E --> F[6. Ansible 구성]
  F --> G[7. 서비스 검증]
```

## 리소스별 동작

| 리소스 | destroy 대상 | 유지/변경 |
|:---|:---|:---|
| VCN, Subnet, SG, Gateway | ❌ | 유지 |
| Block Volume 64GB (`/data`) | ❌ | 유지 (detach → re-attach) |
| Volume Attachment | ✅ (연쇄) | 재생성 (기존 볼륨에 재연결) |
| lt 인스턴스 (boot volume) | ✅ | 새 공인 IP |
| brla 인스턴스 (boot volume) | ✅ | 새 사설 IP (Tailscale IP는 동일) |

## 리스크: lt 공인 IP 변경

lt의 `assign_public_ip = true`는 ephemeral IP. 재생성 시 새 IP 할당.

영향 범위:
- `ansible/ssh_config` → lt HostName 변경
- `ansible/inventory/hosts.ini` → `tofu output`으로 자동 갱신
- 외부에서 lt로 직접 접속하는 모든 경로

해결: `tofu output`으로 새 IP를 자동 추출하므로 수동 개입 불필요.

---

## Step 1: 사전 확인

```bash
cd opentofu
tofu state list
tofu output lt_public_ip
tofu output brla_private_ip
```

## Step 2: 백업 강제 실행 (안전망)

```bash
# brla에서 수동 백업
ssh brla 'sudo /data/hermes/backup.sh'

# GitHub 백업 확인
ssh brla 'cd /data/hermes/data && git log --oneline -3'
```

## Step 3: 인스턴스 destroy

```bash
cd opentofu

# 인스턴스 + 종속 리소스(volume attachment)만 삭제
tofu destroy \
  -target=oci_core_instance.lt \
  -target=oci_core_instance.brla
```

- 삭제: lt 인스턴스, brla 인스턴스, volume attachment (detach)
- 유지: VCN, Subnet, Security List, Gateway, Block Volume (64GB + 데이터)

## Step 4: 인스턴스 재생성

```bash
cd opentofu

# OCI 자격증명 로드
source ../.env.local && sops-dec && sops-load
unset OCI_PRIVATE_KEY

# 인스턴스 재생성 + 볼륨 재연결
tofu apply -auto-approve -var-file=terraform.tfvars
```

재생성 과정:
1. cloud-init → Tailscale 설치 + exit node 구성 (lt)
2. cloud-init → Tailscale 설치 (brla)
3. 기존 Block Volume → 새 brla 인스턴스에 re-attach
4. Tailscale 동일 hostname(`lt`, `brla`)으로 재등록 → Tailscale IP 동일

## Step 5: Inventory + SSH Config 갱신

```bash
# 새 공인 IP 반영
tofu output -raw ansible_inventory_ini > ../ansible/inventory/hosts.ini

# ssh_config 업데이트 (lt 새 공인 IP)
cd ../ansible
LT_IP=$(grep 'ansible_host=' inventory/hosts.ini | head -1 | grep -oP 'ansible_host=\K[0-9.]+')
sed -i "s/HostName .*/HostName $LT_IP/" ssh_config
```

## Step 6: Ansible 구성

```bash
cd ansible

# Hermes 환경변수 로드
source ../.env.local && sops-dec && sops-load

# lt: exit node 설정
ansible-playbook playbook-lt.yml

# brla: Docker, 마운트, code-server, Hermes
ansible-playbook playbook-brla.yml
```

Ansible 처리:
- `filesystem` 모듈 → 이미 포맷된 볼륨은 멱등성으로 스킵 (데이터 유지)
- `mount` 모듈 → `/etc/fstab` 등록 + 마운트 (기존 데이터 그대로)
- Hermes → 기존 `/data/hermes/data/` 유지, `.env`/`config.yaml`만 재생성
- Git 백업 → `.git` 히스토리 포함 그대로 유지

## Step 7: 서비스 검증

```bash
# Health check
ansible-playbook playbook-ops.yml --tags health

# 서비스 상태
ssh brla 'curl -s -o /dev/null -w "%{http_code}" http://localhost:8080'        # code-server (302)
ssh brla 'curl -s -o /dev/null -w "%{http_code}" http://localhost:8642/health'  # Hermes (200)
ssh brla 'curl -s -o /dev/null -w "%{http_code}" http://localhost:9119'         # Dashboard (200)

# 데이터 무결성 (Block Volume)
ssh brla 'ls -la /data/hermes/data/state.db'
ssh brla 'sudo -u \#10000 git -C /data/hermes/data log --oneline -3'
```

## 롤백

인스턴스 재생성 실패 시:
```bash
tofu apply -auto-approve -var-file=terraform.tfvars
```

Block Volume은 항상 유지되므로 재시도만 하면 됨.

## 주의사항

- **Tailscale auth key**: 재사용 가능한 키여야 함 (1회용이면 `terraform.tfvars` 갱신 필요)
- **Hermes `.env`**: `when: not hermes_env.stat.exists` 조건 → 기존 파일 있으면 덮어쓰지 않음
- **Ansible SSH**: `ANSIBLE_SSH_ARGS="-F ./ssh_config"` 필수 (IdentitiesOnly 이슈)
