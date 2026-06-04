---
name: verify-infra
description: lt/brla SSH 접속 후 Tailscale, Docker, code-server, Hermes, Git 백업 상태 종합 검증
---

# 인프라 상태 검증

lt(AMD Micro)과 brla(ARM A1)의 전체 서비스 상태를 SSH로 확인.

## 사전 조건

- `source .env.local` 완료 (또는 `.env` 복호화)

## IP 주소 획득

검증 전 `ansible/inventory/hosts.ini`에서 IP를 파싱:

```bash
LT_IP=$(grep 'ansible_host=' ansible/inventory/hosts.ini | head -1 | sed 's/.*ansible_host=\([^ ]*\).*/\1/')
BRLA_IP=$(grep 'ansible_host=' ansible/inventory/hosts.ini | tail -1 | sed 's/.*ansible_host=\([^ ]*\).*/\1/')
```

파싱 실패 시 `tofu output`으로 대체:

```bash
cd opentofu && tofu output -raw lt_public_ip
tofu output -raw brla_private_ip
```

## 검증 항목

### 1. lt 접속 및 Tailscale 확인

```bash
ssh -o ConnectTimeout=5 ubuntu@$LT_IP "tailscale status | head -5"
```

예상: `lt ... idle; offers exit node`, `brla ... linux` 확인.

### 2. brla Docker 컨테이너 (ProxyJump 경유)

```bash
ssh -o ConnectTimeout=5 -o ProxyJump=ubuntu@$LT_IP ubuntu@$BRLA_IP "docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'"
```

예상: `code-server Up`, `hermes Up`.

### 3. 서비스 HTTP 검증 (brla에서)

```bash
ssh -o ConnectTimeout=5 -o ProxyJump=ubuntu@$LT_IP ubuntu@$BRLA_IP "
  echo -n 'code-server: ' && curl -s -o /dev/null -w '%{http_code}' http://localhost:8080
  echo ''
  echo -n 'hermes-dashboard: ' && curl -s -o /dev/null -w '%{http_code}' http://localhost:9119
  echo ''
"
```

예상: `code-server: 302`, `hermes-dashboard: 200`.

### 4. /data 마운트 확인

```bash
ssh -o ConnectTimeout=5 -o ProxyJump=ubuntu@$LT_IP ubuntu@$BRLA_IP "df -h /data"
```

예상: 63GB Block Volume.

### 5. Docker 로그 로테이션 확인 (brla)

```bash
ssh -o ConnectTimeout=5 -o ProxyJump=ubuntu@$LT_IP ubuntu@$BRLA_IP "cat /etc/docker/daemon.json"
```

예상: `{"log-opts": {"max-size": "10m", "max-file": "3"}}`. 기존 컨테이너는 `docker compose down && up` 필요.

### 6. Hermes Git 백업 확인 (brla)

```bash
ssh -o ConnectTimeout=5 -o ProxyJump=ubuntu@$LT_IP ubuntu@$BRLA_IP "
  echo '--- cron ---' && sudo crontab -l | grep backup
  echo '--- last backup ---' && cat /data/hermes/backup.log
"
```

예상: cron `03:10, 09:10, 15:10, 21:10` 4회/일. `backup.log`에 커밋 해시와 push 결과 표시. `deuxksy/ai-brla` repo에 push.

### 대안: Ansible health check

```bash
cd ansible
ansible-playbook playbook-ops.yml --tags health
```

uptime, load average, disk usage를 lt/brla 양쪽에서 한 번에 확인.

## 결과 포맷

| 항목 | 상태 | 비고 |
| :--- | :--- | :--- |
| lt SSH | ✅/❌ | |
| lt Tailscale | ✅/❌ | |
| brla Tailscale | ✅/❌ | |
| code-server | ✅/❌ | HTTP 상태코드 |
| Hermes dashboard | ✅/❌ | HTTP 상태코드 |
| /data 마운트 | ✅/❌ | 용량 |
| Docker 로그 로테이션 | ✅/❌ | daemon.json |
| Hermes Git 백업 | ✅/❌ | cron + 최근 백업 |
