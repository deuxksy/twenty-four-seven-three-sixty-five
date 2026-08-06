---
name: docker-maintenance
description: brla Docker 운영 — 디스크 점유 분석, 미사용 이미지 회수, containerd image store gotcha, 컨테이너 복구 smoke test
disable-model-invocation: true
---

# Docker 운영 관리 (brla)

brla(ARM A1) Docker 운영 작업. 모든 명령은 ansible ad-hoc으로 실행.

## ansible ad-hoc 기본 형태

```bash
ansible -i ansible/inventory/hosts.ini brla -b -m shell -a '...'
```

**주의**: `-m shell -a` 인자에 `{{...}}` 포함 금지. Jinja2 파싱 실패 (`unexpected '.'`). `docker ps --format '{{.Names}}'` 등은 `--format` 제거 또는 `command` 모듈 + escape.

## 1. 디스크 점유 분석 (읽기 전용)

```bash
# 루트/데이터 사용률
ansible -i ansible/inventory/hosts.ini brla -b -m shell -a 'df -h / /data'

# Docker 용량 (이미지/컨테이너/볼륨/캐시)
ansible -i ansible/inventory/hosts.ini brla -b -m shell -a 'docker system df'

# 활성 데이터 위치 (Docker data-root + containerd root)
ansible -i ansible/inventory/hosts.ini brla -b -m shell -a 'du -sh /data/docker /data/containerd'

# Docker Root Dir + storage driver 확인
ansible -i ansible/inventory/hosts.ini brla -b -m shell -a 'docker info 2>/dev/null | egrep "Docker Root Dir|Storage Driver|driver-type"'
```

## 2. 미사용 이미지 회수

루트/데이터 부족 시. 실행 중인 컨테이너 이미지는 보호됨.

```bash
ansible -i ansible/inventory/hosts.ini brla -b -m shell -a 'docker image prune -a -f'
```

실적: reclaimable 22GB 중 7.16GB 회수 (레이어 공유로 예상보다 적음), 루트 87% → 22%.

## 3. containerd image store gotcha (Docker 29+)

**핵심**: Docker 29+ default는 이미지/레이어 데이터를 `/var/lib/docker`가 아닌 **`/data/containerd`** 에 저장.

- 확인: `docker info`의 `driver-type: io.containerd.snapshotter.v1`
- `data-root`만 `/data/docker`로 바꾸면 이미지 누락 → containerd root도 `/data/containerd`로 함께 이동 필수
- 상세: CLAUDE.md Gotchas + docker role(tasks/main.yml) 참조

## 4. data-root 마이그레이션

이미 `/data/docker` + `/data/containerd`로 이동 완료. 재마이그레이션 필요 시:
1. docker compose stop → systemctl stop docker docker.socket containerd
2. install -d -o root -g root -m 0711 /data/docker /data/containerd
3. rsync -aHAX --numeric-ids /var/lib/{docker,containerd}/ → /data/{docker,containerd}/
4. daemon.json(data-root) + containerd config.toml(root) 배포
5. systemctl start containerd → docker
6. smoke test

절차 상세 + Codex 검증 결과: git log `5d8efb8` 참조.

## 5. smoke test (컨테이너 복구 후)

```bash
ansible -i ansible/inventory/hosts.ini brla -b -m shell -a '
curl -s -o /dev/null -w "homepage:%{http_code}\n" http://127.0.0.1:3000
curl -s -o /dev/null -w "code-server:%{http_code}\n" http://127.0.0.1:8080
curl -s -o /dev/null -w "gatus:%{http_code}\n" http://127.0.0.1:8088
curl -s -o /dev/null -w "beszel:%{http_code}\n" http://127.0.0.1:8090
curl -s -o /dev/null -w "hermes-dashboard:%{http_code}\n" http://127.0.0.1:9120
curl -s -o /dev/null -w "hermes-gateway:%{http_code}\n" http://127.0.0.1:8642/health
'
```

예상: homepage 200, code-server 302, gatus 200, beszel 200, hermes-dashboard 302, hermes-gateway 200.

## 롤백

data-root 마이그레이션 실패 시: daemon.json `data-root` 제거 + containerd config root 원복 → `/var/lib/{docker,containerd}` 복귀. checkpoint tag `checkpoint-pre-docker-dataroot-role` 참조.
