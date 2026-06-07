---
name: update-service
description: 단일 서비스 설정 파일을 수정하고 Ansible로 brla에 배포 후 재시작
disable-model-invocation: true
---

# 단일 서비스 업데이트

단일 서비스의 설정 파일을 brla에 배포하고 컨테이너를 재시작.

## 인자

- `service`: homepage, gatus, beszel, hermes 중 하나
- `config_file`: (선택) 특정 설정 파일만 지정. 미지정 시 전체 config 디렉토리 복사

## 사전 조건

- `ansible/inventory/hosts.ini`가 존재해야 함
- brla SSH 접속 가능 (ProxyJump 경유)

## 실행

### 1. 설정 파일 복사

```bash
# 전체 config 디렉토리 복사
ansible -i ansible/inventory/hosts.ini brla -m copy -a "src={{ project_root }}/ansible/roles/{{ service }}/files/config/ dest=/data/{{ service }}/config/ owner=ubuntu group=ubuntu mode=0644"

# 또는 특정 파일만 복사
ansible -i ansible/inventory/hosts.ini brla -m copy -a "src={{ project_root }}/ansible/roles/{{ service }}/files/config/{{ config_file }} dest=/data/{{ service }}/config/{{ config_file }} owner=ubuntu group=ubuntu mode=0644"
```

### 2. 컨테이너 재시작

```bash
ansible -i ansible/inventory/hosts.ini brla -m command -a "docker restart {{ service }}"
```

### 3. Health Check

| 서비스 | 검증 |
| :--- | :--- |
| homepage | `curl -s -o /dev/null -w '%{http_code}' http://localhost:3000` |
| gatus | `curl -s -o /dev/null -w '%{http_code}' http://localhost:8088` |
| beszel | `curl -s -o /dev/null -w '%{http_code}' http://localhost:8090` |
| hermes | `curl -s -o /dev/null -w '%{http_code}' http://localhost:8642/health` |

```bash
ansible -i ansible/inventory/hosts.ini brla -m command -a "curl -s -o /dev/null -w '%{http_code}' http://localhost:{{ port }}{{ path }}"
```

### 4. (필요시) docker-compose 템플릿 재생성

`templates/docker-compose.yml.j2` 변경 시 템플릿 렌더링 후 `docker compose up -d` 필요:

```bash
ansible-playbook -i ansible/inventory/hosts.ini ansible/playbook-brla.yml --tags {{ service }}
```

## 주의사항

- Hermes는 `network_mode: host` → 포트 매핑 없이 호스트 직접 접근
- Homepage `HOMEPAGE_ALLOWED_HOSTS` 변경 시 컨테이너 재생성 필요 (`docker compose up -d`)
- Ansible ad-hoc 명령에 반드시 `-i ansible/inventory/hosts.ini` 포함
