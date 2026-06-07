---
name: tailscale-serve-sync
description: Ansible tailscale role에 정의된 Serve 항목과 brla 실제 상태를 비교하여 동기화
disable-model-invocation: true
---

# Tailscale Serve 동기화

Ansible tailscale role에 정의된 Serve 라우팅과 brla 서버의 실제 `tailscale serve status`를 비교하여 누락 항목을 등록.

## 사전 조건

- `ansible/inventory/hosts.ini`가 존재해야 함
- brla SSH 접속 가능

## 실행

### 1. 현재 상태 조회

```bash
ansible -i ansible/inventory/hosts.ini brla -m shell -a "tailscale serve status" --become
```

### 2. 기대 항목 (CLAUDE.md 기준)

| 경로 | 백엔드 | 비고 |
| :--- | :--- | :--- |
| `/` | `http://127.0.0.1:3000` | Homepage |
| `:8080` | `http://localhost:8080` | code-server |
| `:8088` | `http://localhost:8088` | Gatus |
| `:8090` | `http://localhost:8090` | Beszel |
| `:9119` | `http://localhost:9119` | Hermes Dashboard |

### 3. 누락 항목 등록

누락된 항목을 발견하면 `sudo`로 등록:

```bash
# 루트 경로
ansible -i ansible/inventory/hosts.ini brla -m command -a "tailscale serve --bg 3000" --become

# 포트 경로
ansible -i ansible/inventory/hosts.ini brla -m command -a "tailscale serve --bg --https=<port> http://localhost:<port>" --become
```

### 4. 제거 항목 정리

더 이상 사용하지 않는 Serve 항목 제거:

```bash
ansible -i ansible/inventory/hosts.ini brla -m command -a "tailscale serve --https=<port> off" --become
```

### 5. Ansible 자동화 확인

`ansible/roles/tailscale/tasks/main.yml`의 Serve 설정 task와 실제 서버 상태가 일치하는지 확인. 누락된 항목은 task도 추가해야 함.

## 주의사항

- Tailscale Serve 명령은 root 권한 필요 (`--become` 또는 `sudo`)
- `tailscale serve --bg`는 멱등성이 있어 이미 등록된 항목은 무시됨
- 서비스 포트 변경 시 Homepage `HOMEPAGE_ALLOWED_HOSTS`도 함께 업데이트 필요
