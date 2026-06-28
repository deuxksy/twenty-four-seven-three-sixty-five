# Hermes 백업 재설계 — Design Spec

> **Date**: 2026-06-28
> **Status**: Draft
> **Topic**: Hermes Git 백업의 컨테이너 내부 실행 전환 + 권한 일관성 확보

## 목차

- [TL;DR](#tldr)
- [문제 정의](#문제-정의)
- [목표](#목표)
- [설계 결정사항](#설계-결정사항)
- [아키텍처](#아키텍처)
- [컴포넌트 변경](#컴포넌트-변경)
- [데이터 흐름](#데이터-흐름)
- [에러 핸들링](#에러-핸들링)
- [마이그레이션 계획](#마이그레이션-계획)
- [검증 체크리스트](#검증-체크리스트)
- [결합점](#결합점-동기화-필수)

## TL;DR

Hermes 데이터 Git 백업을 **호스트 직접 실행에서 Hermes 컨테이너 내부 실행으로 전환**. 컨테이너 UID를 hermes(10000)로 고정해 파일 owner 변질을 근본 차단하고, gzip 압축으로 GitHub 100MB 제약을 회피한다.

## 문제 정의

### 1. 백업 push 실패

- `state.db.sql` = **123 MB** → GitHub 100 MB 한도 초과, pre-receive hook 거부
- 로컬이 origin/main보다 **17 커밋 ahead** (최근 4-5일치 백업 누락)
- `.git` = **899 MB** (100 MB+ blob 다수 적재)

### 2. 파일 owner 변질

```
Hermes 컨테이너 실행 UID:  root (0)      ← docker-compose user 지정 없음
/data/hermes/data 소유권:  hermes (10000), mode 0700
```

- Linux는 파일 생성/수정 프로세스의 effective UID를 파일 owner로 기록
- Hermes 컨테이너(root)가 `/opt/data` 파일 조작 → root(0) 소유로 덮어씀
- Ansible이 `owner: 10000`으로 배포해도 컨테이너 실행 후 변질
- 디렉토리 권한도 0755(Ansible 의도) → 0700(컨테이너 변경)으로 드리프트

### 3. 보안

- remote URL에 **GitHub PAT 평문 노출** (`github_pat_...`)

## 목표

1. 백업 push 정상화 (객체 100 MB 이하)
2. 파일 owner 일관성 (항상 hermes/10000, 변질 없음)
3. 호스트 의존성 최소화 (git/python3/gzip 직접 설치 제거)
4. 자원 효율 (sidecar 없이 기존 컨테이너 활용)

## 설계 결정사항

| 항목 | 결정 | 근거 |
| :--- | :--- | :--- |
| 백업 실행 위치 | Hermes 컨테이너 내부 | git/python3/gzip 내장, 호스트 의존성 제거 |
| 컨테이너 UID | `user: "10000:10000"` | 호스트 hermes 계정과 일치 → owner 변질 차단 |
| 스케줄러 | 호스트 root crontab | 가벼움, hermes nologin/docker-그룹-아님 무관 |
| 백업 빈도 | 일 1회 (03:10) | `.git` 증가 억제 (gzip은 delta 압축 안 됨) |
| 압축 | gzip -9 (`state.db.sql.gz` ≈ 38 MB) | 100 MB 이하, GitHub 제약 회피 |
| LFS | 제외 | 38 MB로 불필요, GitHub LFS bandwidth 한도(1 GB/월) 초과 리스크 |
| Token | docker-compose env 주입, push 시점 사용 | remote URL 평문 PAT 제거 |
| 마이그레이션 | `.git` 재초기화 + force push | 899 MB 히스토리 단절, 백업 repo는 최신 스냅샷이 중요 |

## 아키텍처

```mermaid
graph TD
    A[호스트 root crontab 03:10 일1회] --> B[docker exec hermes]
    B --> C[컨테이너 /opt/data/backup.sh UID 10000]
    C --> D[python3 sqlite3 dump]
    D --> E[gzip -9 압축 sql/*.sql.gz]
    E --> F[git add -A]
    F --> G[git commit]
    G --> H[git push - GITHUB_HERMES_TOKEN env]
    H --> I[GitHub deuxksy/ai-brla]
    C -.stdout/stderr.-> J[호스트 /data/hermes/backup.log]
```

**권한 모델**:

```
호스트: hermes 계정 (UID 10000, nologin, docker 그룹 아님)
  └─ root cron (docker 소켓 접근 가능)
       └─ docker exec hermes → 컨테이너 UID 10000으로 실행
            └─ 파일 조작 → 항상 hermes(10000) 소유 (변질 없음)
```

## 컴포넌트 변경

### 1. `templates/docker-compose.yml.j2`

- `user: "10000:10000"` 추가 (Hermes 컨테이너를 hermes UID로 실행)
- `GITHUB_HERMES_TOKEN` 환경변수 추가

### 2. `templates/backup.sh.j2` (gzip 추가 완료, 보강 필요)

- gzip -9 압축 적용 완료
- **push 시점에 token 주입** (remote URL 하드코딩 제거):
  ```bash
  git push "https://x-access-token:${GITHUB_HERMES_TOKEN}@github.com/${HERMES_BACKUP_REPO:-deuxksy/ai-brla}.git" HEAD:main
  ```
- 배포 경로: `/data/hermes/data/backup.sh` (컨테이너 `/opt/data/backup.sh`)

### 3. `files/gitignore` (완료)

- `sql/*.sql` 무시 (.sql.gz만 추적)

### 4. `files/gitattributes` — **삭제** (LFS 제외 확정)

### 5. `tasks/main.yml`

- backup.sh 배포 경로: `/data/hermes/data/backup.sh` (owner 10000)
- cron 재구성: `docker exec hermes /opt/data/backup.sh`, 일 1회 (`10 3 * * *`)
- 기존 호스트 git_config(restore 포함) 로직 중 **복원(최초 clone)은 유지** — 인스턴스 재구축 시에만 동작하는 일회성 프로비저닝. token만 env 주입으로 개선
- 정기 백업 관련 호스트 git 의존성 제거 (컨테이너가 담당)
- 마이그레이션은 **Ansible에 넣지 않고 brla에서 SSH 수동 실행** (일회성 파괴 작업, 멱등성 복잡도 회피)

## 데이터 흐름

1. **매일 03:10**: 호스트 root cron이 `docker exec hermes /opt/data/backup.sh` 실행
2. **컨테이너 (UID 10000)**:
   - `state.db` / `response_store.db` / `kanban.db` → python3 sqlite3 dump
   - gzip -9 압축 → `sql/*.sql.gz` (원본 `.sql`은 gitignore 제외)
   - `git add -A` → `git commit` → `git push` (env token)
3. **로그**: stdout/stderr → 호스트 `/data/hermes/backup.log` (cron 리다이렉트)

## 에러 핸들링

| 실패 지점 | 동작 | 복구 |
| :--- | :--- | :--- |
| sqlite3 dump (python3) | `set -euo pipefail` 중단 | backup.log 기록, 다음 cron 재시도 |
| gzip 압축 | nonzero exit 중단 | 동상 |
| git push (네트워크/인증) | commit은 로컬 유지 | 다음 cron 실행 시 재시도 |
| 컨테이너 정지 | docker exec 실패 | Hermes restart 정책(unless-stopped) + 백업 누락은 로그로 감지 |

## 마이그레이션 계획

기존 `.git`(899 MB, 100 MB+ blob 다수) 재초기화 — 일회성, brla에서 수동 실행:

1. `.git` 백업: `cp -a .git .git.backup-$(date +%Y%m%d)` (안전망)
2. 기존 raw dump 삭제: `rm -f sql/*.sql`
3. `.git` 삭제 후 재초기화: `git init` + `git lfs` 없이
4. remote 재등록 (token 없는 clean URL)
5. backup.sh 신규 실행 → gzip dump + 첫 commit
6. `git push -f origin main` (origin 기존 히스토리 덮어쓰기)

> **파괴적 작성**: force push로 origin 히스토리 단절. 백업 repo는 최신 스냅샷이 목적이므로 감수. `.git.backup`으로 안전망 확보.

## 검증 체크리스트

- [ ] docker-compose `user: 10000` 적용 후 Hermes 정상 기동 (dashboard 9120 → 302, gateway 8642 → 200)
- [ ] 컨테이너 내 git/python3/gzip 접근 (UID 10000)
- [ ] backup.sh 수동 실행 → `sql/*.sql.gz` 생성, push 성공
- [ ] GitHub repo에 `.sql.gz` 커밋 반영 확인
- [ ] 파일 owner = hermes(10000) 확인 (root 소유 파일 없음)
- [ ] cron 일 1회 실행 확인 (`10 3 * * *`)
- [ ] `.git` 크기 축소 확인 (899 MB → 수십 MB)

## 결합점 (동기화 필수)

다중 파일/환경에서 참조하는 값. 변경 시 동기화 필수:

| 값 | 참조 위치 |
| :--- | :--- |
| UID `10000` | docker-compose(`user`), 호스트 hermes 계정, `/data/hermes/data` 소유권, backup.sh 파일 소유권 |
| 백업 경로 `/data/hermes/data` | docker-compose volume(`/opt/data`), backup.sh, cron |
| 백업 빈도 `10 3 * * *` | cron, CLAUDE.md |
| 백업 repo `deuxksy/ai-brla` | backup.sh push URL, 복원 로직, CLAUDE.md |
| Token env `GITHUB_HERMES_TOKEN` | docker-compose env, backup.sh, SOPS(`.env.sops`) |
| 백업 포맷 `sql/*.sql.gz` | backup.sh, gitignore, gitattributes(삭제) |
