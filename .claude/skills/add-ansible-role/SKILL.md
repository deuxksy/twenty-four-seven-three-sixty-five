---
name: add-ansible-role
description: brla에 새 도구/서비스 추가 — 설치 방식(apt/binary/서비스)에 따라 packages/binary/개별 role에 배치하고 playbook-brla.yml과 CLAUDE.md를 동기화
disable-model-invocation: true
---

# Ansible role 추가

brla에 새 도구를 추가할 때, **설치 방식** 기준으로 role을 배치하고 관련 파일을 동기화.

## 사전 조건

- 추가할 도구의 설치 방식 파악 (apt / GitHub release 바이너리 / 설정+서비스)
- ansible 디렉토리 구조 이해 (CLAUDE.md Directory Structure 참조)

## 1단계: 설치 방식별 role 배치

### A. apt로 설치 가능 → `packages` role

`ansible/roles/packages/tasks/main.yml`의 `name` 리스트에 패키지 추가:

```yaml
- name: apt 패키지 설치
  apt:
    name:
      - age
      - <새 패키지>      # ← 추가
    state: present
```

### B. GitHub release 바이너리 → `binary` role

`ansible/roles/binary/tasks/main.yml`에 태스크 블록 추가:

```yaml
# <도구명>: <설명> (ARM64)
- name: <도구> 최신 release 조회 (GitHub API)
  uri:
    url: https://api.github.com/repos/<org>/<repo>/releases/latest
    return_content: yes
    body_format: json
  register: <도구>_release
  changed_when: false

- name: <도구> 바이너리 설치 (ARM64)
  get_url:
    url: "https://github.com/<org>/<repo>/releases/download/{{ <도구>_release.json.tag_name }}/<파일명 패턴>.linux.arm64"
    dest: /usr/local/bin/<도구>
    mode: "0755"
    force: "{{ <도구>_force | default(false) }}"
```

### C. 설정/서비스/복합 → 신규 개별 role

`ansible/roles/<name>/tasks/main.yml` 생성 (docker, hermes, mise 등 패턴 참조).

## 2단계: playbook-brla.yml 등록

`ansible/playbook-brla.yml`에 role 추가. 순서 원칙 — 시스템 기반 → 패키지 → 셸 → 사용자 도구 → 서비스:

```yaml
roles:
  - role: tailscale        # 네트워크 기반
  - role: docker           # 시스템 서비스
  - role: packages         # apt 패키지
  - role: binary           # 바이너리 도구
  - role: zsh              # 셸 환경
  - role: mise             # 사용자 개발 도구
  - role: claude-code      # 사용자 CLI
  - role: code-server      # 서비스
  - role: hermes           # 서비스
```

개별 role(C)은 성격에 따라 적절한 위치에 삽입.

## 3단계: 멱등성 확보

- `creates:` 파일 기반 (`creates: /path/to/file`)
- `changed_when: false` 명령이 no-op일 때 (mise install 등)
- `become_user: ubuntu` 사용자 범위 도구 (~/.local/bin)

## 4단계: non-login shell 대응

Ansible은 non-login shell이라 `.bashrc`/mise activate 미동작:

- mise 등은 **절대 경로** 호출: `/home/ubuntu/.local/bin/mise install ...`
- corepack 등 node 환경 필요 명령은 `mise exec nodejs@24 --`로 환경 명시
- interactive shell용 활성화는 `.bashrc`/`.zshrc`에 lineinfile으로 별도 추가

## 5단계: CLAUDE.md 동기화

- **Directory Structure**: role 추가/수정 내역 반영
- **Gotchas**: non-obvious 동작, 경로, 인증 방식 등

## 6단계: 구문 검증

```bash
ansible-playbook --syntax-check ansible/playbook-brla.yml -i ansible/inventory/hosts.ini
```

## 주의사항

- 사용자 범위 도구(mise, oh-my-zsh, claude-code)는 `become_user: ubuntu`, 시스템은 `become: yes`(루트, playbook 기본)
- oh-my-zsh installer: `RUNZSH=no CHSH=no` (non-interactive)
- Claude Code 인증은 대화형 OAuth → ansible 범위 밖, 사용자 직접 수행
- 인프라 변경 후 스펙과 실제 코드 동기화 필수
