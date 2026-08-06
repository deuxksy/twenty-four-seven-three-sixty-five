# Hermes 백업 재설계 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Hermes Git 백업을 컨테이너 내부 실행(UID 10000)으로 전환해 owner 변질과 push 실패를 근본 해결

**Architecture:** Hermes 컨테이너를 `user: "10000:10000"`으로 고정, SSH key를 `/data/hermes/ssh`(data 밖)에서 오버레이 마운트. 호스트 root crontab이 `flock` + `docker exec`로 컨테이너 내부 backup.sh를 일 1회 실행. gzip -9n 압축 + SQLite backup API로 100MB 이하/정합성 보장. (상세: [design spec v2](../specs/2026-06-28-hermes-backup-redesign-design.md))

**Tech Stack:** Ansible, Docker Compose, Jinja2, bash, Python3 sqlite3, git

## Global Constraints

- 컨테이너 UID/GID: `10000:10000` (호스트 hermes 계정 일치)
- 백업 실행 위치: 컨테이너 내부 `/opt/data` (= 호스트 `/data/hermes/data`)
- SSH 마운트: 호스트 `/data/hermes/ssh` → 컨테이너 `/opt/data/home/.ssh` (오버레이)
- 백업 빈도: cron `10 3 * * *` (일 1회)
- 압축: `gzip -9n` (mtime 제거)
- 백업 repo: `deuxksy/ai-brla`
- Token: 환경변수 `GITHUB_HERMES_TOKEN` (SOPS 관리), remote는 clean URL
- Lock: `/data/hermes/backup.lock` (flock)
- 파일 owner: 항상 `10000:10000`

---

## File Structure

| 파일 | 책임 |
| :--- | :--- |
| `ansible/roles/hermes/templates/docker-compose.yml.j2` | 컨테이너 user, SSH 마운트, token env |
| `ansible/roles/hermes/templates/backup.sh.j2` | 덤프/압축/commit/push 전체 (컨테이너 실행) |
| `ansible/roles/hermes/files/gitignore` | 백업 제외 규칙 (`.sql`, `backup.sh`) |
| `ansible/roles/hermes/files/gitattributes` | **삭제** (LFS 제외) |
| `ansible/roles/hermes/tasks/main.yml` | SSH 폴더, backup 배포, cron, 복원 import, remote |
| `scripts/migrate-hermes-backup.sh` | brla 마이그레이션 (수동 실행, 일회성) |

---

### Task 1: 사전 정리 — gitattributes 삭제, gitignore 보강

**Files:**
- Delete: `ansible/roles/hermes/files/gitattributes`
- Modify: `ansible/roles/hermes/files/gitignore`

**Interfaces:**
- Produces: gitignore에 `backup.sh` 제외 규칙 (Task 5에서 `/data/hermes/data/backup.sh`가 git 추적 안 됨을 보장)

- [ ] **Step 1: gitattributes 삭제**

```bash
git rm ansible/roles/hermes/files/gitattributes
```

- [ ] **Step 2: gitignore에 backup.sh + sql/*.sql 추가**

`ansible/roles/hermes/files/gitignore` 끝에 추가:

```text
# Backup script itself (배포 대상, 백업 제외)
backup.sh
```

(`sql/*.sql` 무시 규칙은 이미 추가됨 — 확인만)

- [ ] **Step 3: commit**

```bash
git add ansible/roles/hermes/files/gitignore ansible/roles/hermes/files/gitattributes
git commit -m "fix: hermes gitattributes 삭제(LFS 제외), gitignore에 backup.sh 추가"
```

---

### Task 2: docker-compose.yml.j2 — UID 10000 + SSH 마운트 + token env

**Files:**
- Modify: `ansible/roles/hermes/templates/docker-compose.yml.j2`

**Interfaces:**
- Produces: 컨테이너가 UID 10000으로 실행, `/opt/data/home/.ssh`가 `/data/hermes/ssh`를 가리킴, `GITHUB_HERMES_TOKEN` env 노출

- [ ] **Step 1: docker-compose.yml.j2 수정**

`ansible/roles/hermes/templates/docker-compose.yml.j2` 전체:

```yaml
services:
  hermes:
    image: nousresearch/hermes-agent:latest
    container_name: hermes
    restart: unless-stopped
    user: "10000:10000"
    command: gateway run
    network_mode: host
    volumes:
      - /data/hermes/data:/opt/data
      - /data/git:/opt/data/git
      - /data/hermes/ssh:/opt/data/home/.ssh
    environment:
      - TZ=Asia/Seoul
      - HERMES_DASHBOARD=1
      - HERMES_DASHBOARD_HOST=0.0.0.0
      - HERMES_DASHBOARD_PORT=9120
      - HERMES_DASHBOARD_BASIC_AUTH_USERNAME={{ lookup('env', 'HERMES_DASHBOARD_BASIC_AUTH_USERNAME') }}
      - HERMES_DASHBOARD_BASIC_AUTH_PASSWORD={{ lookup('env', 'HERMES_DASHBOARD_BASIC_AUTH_PASSWORD') }}
      - API_SERVER_KEY={{ lookup('env', 'HERMES_API_SERVER_KEY') }}
      - DISCORD_BOT_TOKEN={{ lookup('env', 'DISCORD_BOT_TOKEN') }}
      - DISCORD_ALLOWED_USERS={{ lookup('env', 'DISCORD_ALLOWED_USERS') }}
      - ANTHROPIC_API_KEY={{ lookup('env', 'ANTHROPIC_API_KEY') }}
      - ANTHROPIC_API_BASE={{ lookup('env', 'ANTHROPIC_API_BASE') }}
      - GITHUB_HERMES_TOKEN={{ lookup('env', 'GITHUB_HERMES_TOKEN') }}
```

변경점: `user: "10000:10000"` 추가, SSH 마운트를 `/home/ubuntu/.ssh` → `/data/hermes/ssh`로 교체, `GITHUB_HERMES_TOKEN` env 추가.

- [ ] **Step 2: Jinja2 syntax 검증**

```bash
ansible-playbook --syntax-check ansible/playbook-brla.yml -i ansible/inventory/hosts.ini
```

Expected: `playbook: ansible/playbook-brla.yml` (에러 없음)

- [ ] **Step 3: commit**

```bash
git add ansible/roles/hermes/templates/docker-compose.yml.j2
git commit -m "feat: hermes 컨테이너 UID 10000, SSH 마운트 분리, GITHUB_HERMES_TOKEN env"
```

---

### Task 3: backup.sh.j2 전면 재작성

**Files:**
- Modify: `ansible/roles/hermes/templates/backup.sh.j2`

**Interfaces:**
- Consumes: `GITHUB_HERMES_TOKEN` env (Task 2), `HERMES_BACKUP_REPO` (기본 `deuxksy/ai-brla`)
- Produces: `/opt/data/sql/*.sql.gz` (git 추적), 컨테이너 내부 `/opt/data` 기준 동작

- [ ] **Step 1: backup.sh.j2 전체 재작성**

`ansible/roles/hermes/templates/backup.sh.j2` 전체:

```bash
#!/bin/bash
# Hermes 데이터 Git 백업 스크립트 (컨테이너 내부 /opt/data 에서 실행)
# Ansible 자동 생성
# cron: 일 1회 (03:10), flock 동시 실행 방지

set -euo pipefail
cd /opt/data

# git identity (committer + author)
GIT_USER_NAME="{{ git_user_name | default('Crong') }}"
GIT_USER_EMAIL="{{ git_user_email | default('deuxksy@gmail.com') }}"
export GIT_AUTHOR_NAME="$GIT_USER_NAME" GIT_AUTHOR_EMAIL="$GIT_USER_EMAIL"
export GIT_COMMITTER_NAME="$GIT_USER_NAME" GIT_COMMITTER_EMAIL="$GIT_USER_EMAIL"

# SQL 덤프 (SQLite online backup API — WAL/write 중 정합성 보장)
mkdir -p sql
for db in state.db response_store.db kanban.db; do
    [ -f "$db" ] || continue
    python3 -c "
import sqlite3
src = sqlite3.connect('${db}')
dst = sqlite3.connect(':memory:')
src.backup(dst)
with open('sql/${db}.sql', 'w') as f:
    for line in dst.iterdump():
        f.write(line + '\n')
src.close()
dst.close()
"
    gzip -9nf sql/${db}.sql
done

# 크기 guard (GitHub 100MB 객체 제한)
for f in sql/*.sql.gz; do
    [ -f "$f" ] || continue
    size=$(stat -c%s "$f")
    if [ "$size" -gt 104857600 ]; then
        echo "ERROR: $f is $((size/1048576))MB, exceeds 100MB GitHub limit" >&2
        exit 1
    fi
done

# 변경사항 스테이징
git add -A

# commit (변경 있을 때만)
if ! git diff --cached --quiet; then
    TIMESTAMP=$(date +"%Y-%m-%d %H:%M")
    git -c user.name="$GIT_USER_NAME" -c user.email="$GIT_USER_EMAIL" \
        commit -m "backup: ${TIMESTAMP}"
fi

# push — origin/main 대비 ahead 일 때만, transient token (remote는 clean URL)
REPO="${HERMES_BACKUP_REPO:-deuxksy/ai-brla}"
ahead=$(git rev-list --count origin/main..HEAD 2>/dev/null || echo 0)
if [ "$ahead" -gt 0 ]; then
    git push "https://x-access-token:${GITHUB_HERMES_TOKEN}@github.com/${REPO}.git" HEAD:main
fi
```

- [ ] **Step 2: Jinja2 syntax 검증**

```bash
ansible-playbook --syntax-check ansible/playbook-brla.yml -i ansible/inventory/hosts.ini
```

Expected: 에러 없음

- [ ] **Step 3: commit**

```bash
git add ansible/roles/hermes/templates/backup.sh.j2
git commit -m "feat: backup.sh 컨테이너 실행화 - gzip -9n, SQLite backup API, 100MB guard, transient token, ahead 체크"
```

---

### Task 4: tasks/main.yml — SSH 폴더 생성 + key 복사

**Files:**
- Modify: `ansible/roles/hermes/tasks/main.yml` (`# --- .git 권한 수정` 섹션 앞에 삽입)

**Interfaces:**
- Produces: `/data/hermes/ssh`(UID 10000, 0700)에 호스트 SSH key 복사본. Task 2 마운트가 이를 컨테이너로 노출

- [ ] **Step 1: SSH 폴더 task 블록 추가**

`ansible/roles/hermes/tasks/main.yml`의 `# --- 컨테이너 내부 도구 설치` 섹션 **앞**에 삽입 (SSH config 배포 task 이후):

```yaml
# --- Hermes SSH 폴더 (UID 10000, data 밖 — secret 분리)

- name: Hermes SSH 폴더 생성 (/data/hermes/ssh)
  file:
    path: /data/hermes/ssh
    state: directory
    owner: "10000"
    group: "10000"
    mode: "0700"

- name: 호스트 SSH key를 Hermes SSH 폴더로 복사
  shell: cp -a /home/ubuntu/.ssh/. /data/hermes/ssh/ && chown -R 10000:10000 /data/hermes/ssh && chmod 700 /data/hermes/ssh
  args:
    creates: /data/hermes/ssh/id_ed25519
```

- [ ] **Step 2: syntax 검증**

```bash
ansible-playbook --syntax-check ansible/playbook-brla.yml -i ansible/inventory/hosts.ini
```

Expected: 에러 없음

- [ ] **Step 3: commit**

```bash
git add ansible/roles/hermes/tasks/main.yml
git commit -m "feat: hermes SSH 폴더(/data/hermes/ssh, UID 10000) 생성 + key 복사 task"
```

---

### Task 5: tasks/main.yml — backup.sh 배포 경로 + cron flock

**Files:**
- Modify: `ansible/roles/hermes/tasks/main.yml` (backup.sh 배포 task + cron task)

**Interfaces:**
- Consumes: Task 3의 backup.sh.j2, Task 4의 UID 10000 환경
- Produces: `/data/hermes/data/backup.sh`(= 컨테이너 `/opt/data/backup.sh`), root cron `flock` + `docker exec`

- [ ] **Step 1: backup.sh 배포 task 수정**

`ansible/roles/hermes/tasks/main.yml`의 "Hermes backup 스크립트 배포" task를 교체:

```yaml
- name: Hermes backup 스크립트 배포 (컨테이너 /opt/data/backup.sh)
  template:
    src: backup.sh.j2
    dest: /data/hermes/data/backup.sh
    owner: "10000"
    group: "10000"
    mode: "0755"
```

(dest를 `/data/hermes/backup.sh` → `/data/hermes/data/backup.sh`, owner root → 10000)

- [ ] **Step 2: cron task 수정 (flock + docker exec + 일 1회)**

"Hermes backup cron 설정" task를 교체:

```yaml
- name: Hermes backup cron 설정 (일 1회, flock + docker exec)
  cron:
    name: "hermes-backup"
    minute: "10"
    hour: "3"
    job: "flock -n /data/hermes/backup.lock docker exec hermes /opt/data/backup.sh >> /data/hermes/backup.log 2>&1"
    user: root
```

(cron name이 동일하므로 기존 4회/일 엔트리를 자동 교체)

- [ ] **Step 3: 기존 backup.sh 제거 task 추가 (마이그레이션)**

cron task 직후에 추가 (구 경로 정리):

```yaml
- name: 구 backup.sh 제거 (/data/hermes/backup.sh)
  file:
    path: /data/hermes/backup.sh
    state: absent
```

- [ ] **Step 4: syntax 검증**

```bash
ansible-playbook --syntax-check ansible/playbook-brla.yml -i ansible/inventory/hosts.ini
```

Expected: 에러 없음

- [ ] **Step 5: commit**

```bash
git add ansible/roles/hermes/tasks/main.yml
git commit -m "feat: backup.sh 배포경로 /data/hermes/data + cron flock/docker exec/일1회"
```

---

### Task 6: tasks/main.yml — 복원 import + clean remote + task 순서

**Files:**
- Modify: `ansible/roles/hermes/tasks/main.yml` (복원 block, remote 등록, 컨테이너 시작 순서)

**Interfaces:**
- Consumes: Task 2/3의 백업 포맷(`sql/*.sql.gz`), `GITHUB_HERMES_TOKEN`
- Produces: 신규 인스턴스 복원 시 `.sql.gz` → `.db` import, 컨테이너 시작 전 데이터 준비

- [ ] **Step 1: 컨테이너 시작 task를 복원 이후로 이동**

`ansible/roles/hermes/tasks/main.yml`에서 "Hermes 컨테이너 시작" task(`docker compose up -d`)와 그 이후 task(shell-gpt 설치 등)를 **복원 block 이후**로 재배치. 복원이 데이터를 채운 뒤 컨테이너가 기동하도록.

구조:
```
1. 디렉토리 생성, SSH config, compose 파일, 이미지 pull, .env, config.yaml
2. .git 권한, git_config, remote 확인, 복원 block (← 컨테이너 시작 전)
3. Hermes 컨테이너 시작 (← 이동)
4. shell-gpt 설치, SSH 폴더, backup.sh 배포, cron
```

- [ ] **Step 2: 복원 block에 SQL import 추가**

기존 "서버 복원 — ai-brla repo에서 데이터 복원" block 내, "데이터 복사" task 이후에 import task 추가:

```yaml
    - name: "SQL dump 압축 해제 + SQLite import"
      shell: |
        cd /data/hermes/data
        if ls sql/*.sql.gz 1>/dev/null 2>&1; then
          gunzip -kf sql/*.sql.gz
          for sql in sql/*.sql; do
            db=$(basename "$sql" .sql)
            python3 -c "import sqlite3; c=sqlite3.connect('$db'); c.executescript(open('$sql').read()); c.close()"
          done
        fi
      become: true
```

- [ ] **Step 3: remote 등록을 clean URL로 변경**

"GitHub remote 등록 (복원 후 또는 최초)" task와 "초기 커밋 + push" task 수정 — remote URL에서 token 제거:

```yaml
- name: GitHub remote 등록 (clean URL — token 없음)
  shell: >
    git remote get-url origin 2>/dev/null ||
    git remote add origin https://github.com/{{ hermes_backup_repo | default('deuxksy/ai-brla') }}.git
  args:
    chdir: /data/hermes/data
  when: lookup('env', 'GITHUB_HERMES_TOKEN') | default('') | length > 0

- name: 초기 커밋 + push (최초 1회, transient token)
  shell: >
    git add -A &&
    git diff --cached --quiet || (git -c user.name="{{ git_user_name | default('Crong') }}" -c user.email="{{ git_user_email | default('deuxksy@gmail.com') }}" commit -m "init: Hermes backup" &&
    git push "https://x-access-token:{{ lookup('env', 'GITHUB_HERMES_TOKEN') }}@github.com/{{ hermes_backup_repo | default('deuxksy/ai-brla') }}.git" HEAD:main)
  args:
    chdir: /data/hermes/data
  when: lookup('env', 'GITHUB_HERMES_TOKEN') | default('') | length > 0
```

- [ ] **Step 4: 복원 clone도 clean URL + transient token**

"ai-brla repo clone (token auth)" task의 repo URL을 clean + transient로 변경:

```yaml
    - name: "ai-brla repo clone (transient token)"
      git:
        repo: "https://x-access-token:{{ lookup('env', 'GITHUB_HERMES_TOKEN') }}@github.com/{{ hermes_backup_repo | default('deuxksy/ai-brla') }}.git"
        dest: /tmp/hermes-restore
        depth: 1
        force: yes
```

(clone 자체는 token 필요하지만, clone된 `.git/config`는 clean URL이 되도록 별도 처리. 단순화를 위해 clone 후 remote set-url):

```yaml
    - name: "clone된 repo remote를 clean URL로 정리"
      shell: git -C /tmp/hermes-restore remote set-url origin https://github.com/{{ hermes_backup_repo | default('deuxksy/ai-brla') }}.git
```

- [ ] **Step 5: syntax 검증**

```bash
ansible-playbook --syntax-check ansible/playbook-brla.yml -i ansible/inventory/hosts.ini
```

Expected: 에러 없음

- [ ] **Step 6: commit**

```bash
git add ansible/roles/hermes/tasks/main.yml
git commit -m "feat: 복원 SQL import 추가, clean remote + transient token, 컨테이너 시작을 복원 이후로"
```

---

### Task 7: 마이그레이션 스크립트 작성 (brla 수동 실행용)

**Files:**
- Create: `scripts/migrate-hermes-backup.sh`

**Interfaces:**
- Produces: brla에서 수동 실행하는 일회성 마이그레이션 스크립트. 기존 899MB `.git` 재초기화 + force push

- [ ] **Step 1: 마이그레이션 스크립트 작성**

`scripts/migrate-hermes-backup.sh`:

```bash
#!/bin/bash
# Hermes 백업 repo 마이그레이션 — 기존 .git(899MB) 재초기화 + force push
# brla에서 수동 실행 (일회성, 파괴적)
# 사용법: sudo bash scripts/migrate-hermes-backup.sh
# 사전 조건: GITHUB_HERMES_TOKEN 환경변수, 기존 backup.sh 신규 버전 배포 완료

set -euo pipefail

DATA_DIR=/data/hermes/data
REPO="deuxksy/ai-brla"
DATE=$(date +%Y%m%d)
TOKEN="${GITHUB_HERMES_TOKEN:?GITHUB_HERMES_TOKEN 환경변수 필요}"

echo "=== 1. remote history 보존 (archive tag) ==="
sudo -u '#10000' git -C "$DATA_DIR" tag "archive/pre-redesign-$DATE" || true
sudo -u '#10000' git -C "$DATA_DIR" push "https://x-access-token:${TOKEN}@github.com/${REPO}.git" "archive/pre-redesign-$DATE"

echo "=== 2. .git 로컬 백업 ==="
sudo cp -a "$DATA_DIR/.git" "$DATA_DIR/../.git.backup-$DATE"

echo "=== 3. 기존 raw dump 제거 ==="
sudo rm -f "$DATA_DIR/sql/*.sql"

echo "=== 4. .git 재초기화 ==="
sudo -u '#10000' rm -rf "$DATA_DIR/.git"
sudo -u '#10000' git -C "$DATA_DIR" init -b main
sudo -u '#10000' git -C "$DATA_DIR" remote add origin "https://github.com/${REPO}.git"

echo "=== 5. 신규 backup.sh 실행 (gzip dump + 첫 commit) ==="
sudo -u '#10000' docker exec hermes /opt/data/backup.sh

echo "=== 6. force push (archive tag로 rollback 가능) ==="
sudo -u '#10000' git -C "$DATA_DIR" push --force-with-lease "https://x-access-token:${TOKEN}@github.com/${REPO}.git" main

echo "=== 7. 검증 ==="
echo ".git/config (token 잔존 없음 확인):"
sudo grep -v 'access-token' "$DATA_DIR/.git/config" || true
echo ".git 크기:"
sudo du -sh "$DATA_DIR/.git"

echo "마이그레이션 완료. rollback 필요 시: .git.backup-$DATE 또는 archive/pre-redesign-$DATE tag"
```

- [ ] **Step 2: 실행 권한 부여 + commit**

```bash
chmod +x scripts/migrate-hermes-backup.sh
git add scripts/migrate-hermes-backup.sh
git commit -m "feat: hermes 백업 마이그레이션 스크립트 (.git 재초기화 + force push)"
```

---

### Task 8: brla 배포 + 검증

**Files:**
- 없음 (실행/검증 only)

**Interfaces:**
- Consumes: Task 1-7 산출물, SOPS `GITHUB_HERMES_TOKEN`

- [ ] **Step 1: SOPS 복호화 + env 로드**

```bash
export SOPS_AGE_KEY_FILE=keys.txt
eval "$(sops -d secrets/.env.sops)" 
```

(`GITHUB_HERMES_TOKEN` 포함 모든 env 주입 확인)

- [ ] **Step 2: Ansible brla 배포**

```bash
cd ansible
ansible-playbook playbook-brla.yml -i inventory/hosts.ini
```

Expected: hermes role 변경사항 적용, 컨테이너 재생성(user 10000), SSH 폴더 생성, cron 교체

- [ ] **Step 3: UID 10000 런타임 smoke 테스트**

```bash
BRLA_IP=$(grep 'ansible_host=' ansible/inventory/hosts.ini | tail -1 | sed 's/.*ansible_host=\([^ ]*\).*/\1/')
LT_IP=$(grep 'ansible_host=' ansible/inventory/hosts.ini | head -1 | sed 's/.*ansible_host=\([^ ]*\).*/\1/')
ssh -o ProxyJump=ubuntu@$LT_IP ubuntu@$BRLA_IP "
docker exec hermes id
docker exec hermes ls -la /opt/data/home/.ssh/
docker exec hermes git --version
docker exec hermes python3 -c 'import sqlite3; print(sqlite3.sqlite_version)'
"
```

Expected: `uid=10000`, `/opt/data/home/.ssh/`에 key 존재, git/python3 정상

- [ ] **Step 4: dashboard/gateway health**

```bash
ssh -o ProxyJump=ubuntu@$LT_IP ubuntu@$BRLA_IP "
curl -s -o /dev/null -w 'dashboard: %{http_code}\n' http://localhost:9120
curl -s -o /dev/null -w 'gateway: %{http_code}\n' http://localhost:8642/health
"
```

Expected: `dashboard: 302`, `gateway: 200`

- [ ] **Step 5: 마이그레이션 실행 (파괴적 — 사용자 승인 필수)**

```bash
ssh -o ProxyJump=ubuntu@$LT_IP ubuntu@$BRLA_IP "
export GITHUB_HERMES_TOKEN=\$(sudo cat /data/hermes/data/.env | grep GITHUB_HERMES_TOKEN | cut -d= -f2)
sudo -E bash /tmp/migrate-hermes-backup.sh
"
```

(스크립트를 brla로 복사 후 실행. 사용자 승인 전에 확인)

Expected: archive tag push, .git 재초기화, force push 성공, `.git` 크기 축소

- [ ] **Step 6: 백업 수동 실행 + 검증**

```bash
ssh -o ProxyJump=ubuntu@$LT_IP ubuntu@$BRLA_IP "
echo '=== backup 수동 실행 ==='
docker exec hermes /opt/data/backup.sh
echo '=== owner 확인 (전부 10000) ==='
sudo find /data/hermes/data -maxdepth 2 -newer /data/hermes/data/.git -exec ls -la {} \; | head
echo '=== .git/config token 잔존 확인 ==='
sudo grep access-token /data/hermes/data/.git/config || echo 'token 잔존 없음 (OK)'
echo '=== GitHub repo 최신 commit 확인 ==='
sudo git -C /data/hermes/data log --oneline -3
"
```

Expected: backup 성공, owner=10000, `.git/config`에 token 없음, GitHub에 새 commit push

- [ ] **Step 7: cron 일 1회 등록 확인**

```bash
ssh -o ProxyJump=ubuntu@$LT_IP ubuntu@$BRLA_IP "sudo crontab -l | grep hermes-backup"
```

Expected: `10 3 * * * flock -n /data/hermes/backup.lock docker exec hermes /opt/data/backup.sh >> /data/hermes/backup.log 2>&1`

- [ ] **Step 8: 최종 commit + CLAUDE.md 갱신**

`CLAUDE.md`의 Hermes 백업 관련 섹션 갱신:
- 백업 실행: 호스트 cron(docker exec) → 컨테이너 내부
- UID 10000, SSH `/data/hermes/ssh`
- 백업 빈도: 일 1회 (03:10)
- 백업 포맷: `sql/*.sql.gz` (gzip -9n)

```bash
git add CLAUDE.md
git commit -m "docs: CLAUDE.md hermes 백업 정책 갱신 (컨테이너 실행, UID 10000, 일1회, gzip)"
```

---

## Self-Review 체크

**Spec coverage (design v2 대조):**
- B1 경로 충돌 → Task 5 (backup.sh `/data/hermes/data/backup.sh`)
- B2 복원 import → Task 6 (gunzip + sqlite3 import)
- B3 SSH 권한 → Task 2 (마운트) + Task 4 (UID 10000 폴더)
- B4 git identity → Task 3 (`-c user.name/email` + export)
- B5 clean remote → Task 6 (clean URL + transient token)
- B6 flock → Task 5 (cron flock)
- Risk gzip -9n → Task 3
- Risk 100MB guard → Task 3
- Risk SQLite backup API → Task 3
- Risk force push 안전장치 → Task 7 (archive tag + .git.backup)
- 마이그레이션 → Task 7
- 검증 체크리스트 → Task 8

**Placeholder scan:** 없음 (모든 step에 실제 코드/명령 포함)

**Type consistency:** `GITHUB_HERMES_TOKEN`, `HERMES_BACKUP_REPO`, `/data/hermes/ssh`, `/data/hermes/backup.lock` 전 task 일관
