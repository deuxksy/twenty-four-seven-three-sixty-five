# Ansible 재적용 배포 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 기존 OCI 인프라에 Ansible Playbook을 재실행하여 최신 코드(Hermes, Discord, Docker 볼륨) 변경사항 반영

**Architecture:** OpenTofu 리소스는 유지, Ansible만 재실행. SOPS로 복호화한 환경변수를 Ansible template에 주입.

**Tech Stack:** Ansible, SOPS(age), Tailscale SSH

**Spec:** `docs/superpowers/specs/2026-06-04-ansible-reapply-design.md`

---

### Task 1: 사전 확인 — 로컬 환경 검증

**Files:**
- Read: `keys.txt` (존재 여부)
- Read: `ansible/inventory/hosts.ini` (유효성)

- [ ] **Step 1: keys.txt 존재 확인**

```bash
test -f keys.txt && echo "OK: keys.txt 존재" || echo "FAIL: keys.txt 없음"
```

Expected: `OK: keys.txt 존재`

- [ ] **Step 2: Ansible inventory 유효성 확인**

```bash
cat ansible/inventory/hosts.ini
```

Expected: lt, brla 호스트 정의가 포함된 INI 형식. lt의 `ansible_host`가 공인 IP.

- [ ] **Step 3: lt SSH 연결 확인**

```bash
ssh -o ConnectTimeout=5 ubuntu@193.123.246.91 'hostname && tailscale status | head -1'
```

Expected: `lt` hostname + Tailscale 연결 상태

- [ ] **Step 4: brla SSH 연결 확인 (lt 경유)**

```bash
ssh -o ConnectTimeout=10 -o ProxyJump=ubuntu@193.123.246.91 ubuntu@100.99.163.97 'hostname && uptime'
```

Expected: `brla` hostname + uptime 정보

- [ ] **Step 5: 커밋 — 변경사항 없음 (skip)**

---

### Task 2: SOPS 복호화 및 환경변수 로드

**Files:**
- Read: `secrets/.env.sops` (암호화됨)
- Write: `.env` (복호화 결과, `.gitignore` 등록됨)

- [ ] **Step 1: SOPS 함수 로드**

```bash
source .env.local && echo "SOPS_AGE_KEY_FILE=$SOPS_AGE_KEY_FILE"
```

Expected: `SOPS_AGE_KEY_FILE=/home/crong/git/twenty-four-seven-three-sixty-five/keys.txt`

- [ ] **Step 2: .env 복호화**

```bash
source .env.local && sops-dec && test -f .env && echo "OK: .env 복호화 완료" || echo "FAIL"
```

Expected: `OK: .env 복호화 완료`

- [ ] **Step 3: 환경변수 로드 및 필수 변수 확인**

```bash
source .env.local && sops-load && echo "HERMES_API_SERVER_KEY=${HERMES_API_SERVER_KEY:0:4}..." && echo "DISCORD_BOT_TOKEN=${DISCORD_BOT_TOKEN:0:4}..." && echo "ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY:0:4}..."
```

Expected: 각 변수의 앞 4자리 출력 (非空). `HERMES_API_SERVER_KEY=test...`, `DISCORD_BOT_TOKEN=MTUx...`, `ANTHROPIC_API_KEY=ark-...`

- [ ] **Step 4: OCI_PRIVATE_KEY unset (tofu 충돌 방지)**

```bash
unset OCI_PRIVATE_KEY && echo "OCI_PRIVATE_KEY 해제 완료"
```

Expected: `OCI_PRIVATE_KEY 해제 완료`

- [ ] **Step 5: 커밋 — 변경사항 없음 (.env는 .gitignore)**

---

### Task 3: Ansible playbook-lt.yml 실행

**Files:**
- Read: `ansible/playbook-lt.yml`
- Read: `ansible/roles/tailscale/tasks/main.yml`

- [ ] **Step 1: lt playbook 실행**

```bash
cd ansible && ansible-playbook playbook-lt.yml
```

Expected: `PLAY RECAP`에서 `lt` 호스트가 `ok` + `changed` (변경사항 있으면) 또는 `ok` (이미 최신이면). `unreachable=0`, `failed=0`.

- [ ] **Step 2: lt Tailscale 상태 확인**

```bash
ssh ubuntu@193.123.246.91 'tailscale status | head -3'
```

Expected: lt가 exit node로 표시, brla가 peers에 표시

- [ ] **Step 3: 커밋 — 변경사항 없음 (원격 서버만 변경)**

---

### Task 4: Ansible playbook-brla.yml 실행

**Files:**
- Read: `ansible/playbook-brla.yml`
- Read: `ansible/roles/docker/tasks/main.yml`
- Read: `ansible/roles/code-server/tasks/main.yml`
- Read: `ansible/roles/hermes/tasks/main.yml`

- [ ] **Step 1: brla playbook 실행**

```bash
cd ansible && ansible-playbook playbook-brla.yml
```

Expected: `PLAY RECAP`에서 `brla` 호스트가 `unreachable=0`, `failed=0`. tailscale, docker, code-server, hermes 4개 role 모두 성공.

- [ ] **Step 2: Docker 컨테이너 상태 확인**

```bash
ssh -o ProxyJump=ubuntu@193.123.246.91 ubuntu@100.99.163.97 'docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"'
```

Expected: `code-server` (Up, 0.0.0.0:8080->8080), `hermes` (Up, host network)

- [ ] **Step 3: 커밋 — 변경사항 없음 (원격 서버만 변경)**

---

### Task 5: Health Check + 서비스 검증

**Files:**
- Read: `ansible/playbook-ops.yml`

- [ ] **Step 1: Ansible health check 실행**

```bash
cd ansible && ansible-playbook playbook-ops.yml --tags health
```

Expected: 양 호스트 모두 uptime, load, disk 정보 출력. disk 90% 미만.

- [ ] **Step 2: code-server HTTP 검증**

```bash
ssh -o ProxyJump=ubuntu@193.123.246.91 ubuntu@100.99.163.97 'curl -s -o /dev/null -w "%{http_code}" http://localhost:8080'
```

Expected: `302` (password 인증 페이지로 redirect)

- [ ] **Step 3: Hermes gateway health 검증**

```bash
ssh -o ProxyJump=ubuntu@193.123.246.91 ubuntu@100.99.163.97 'curl -s -o /dev/null -w "%{http_code}" http://localhost:8642/health'
```

Expected: `200`

- [ ] **Step 4: Hermes dashboard 검증**

```bash
ssh -o ProxyJump=ubuntu@193.123.246.91 ubuntu@100.99.163.97 'curl -s -o /dev/null -w "%{http_code}" http://localhost:9119'
```

Expected: `200`

- [ ] **Step 5: 커밋 — 변경사항 없음**

---

### Task 6: 결과 기록 및 정리

**Files:**
- Modify: `docs/superpowers/specs/2026-06-04-ansible-reapply-design.md` (status 업데이트)

- [ ] **Step 1: 배포 결과 요약 출력**

```bash
echo "=== 배포 결과 ===" && echo "lt: $(ssh ubuntu@193.123.246.91 'hostname && uptime' 2>&1)" && echo "brla: $(ssh -o ProxyJump=ubuntu@193.123.246.91 ubuntu@100.99.163.97 'hostname && uptime' 2>&1)"
```

- [ ] **Step 2: Spec 상태를 Completed로 업데이트**

`docs/superpowers/specs/2026-06-04-ansible-reapply-design.md` 상단 `Status: Approved` → `Status: Completed`

- [ ] **Step 3: 커밋**

```bash
git add docs/superpowers/specs/2026-06-04-ansible-reapply-design.md
git commit -m "docs: Ansible 재적용 배포 완료"
```
