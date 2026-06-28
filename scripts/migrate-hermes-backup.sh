#!/bin/bash
# Hermes 백업 repo 마이그레이션 — 기존 .git(944MB) 재초기화 + force push
# brla에서 수동 실행 (일회성, 파괴적)
# 사용법: sudo GITHUB_HERMES_TOKEN=xxx bash scripts/migrate-hermes-backup.sh
# 사전 조건: GITHUB_HERMES_TOKEN 환경변수, backup.sh 신규 버전 배포 완료

set -euo pipefail

DATA_DIR=/data/hermes/data
REPO="deuxksy/ai-brla"
DATE=$(date +%Y%m%d)
TOKEN="${GITHUB_HERMES_TOKEN:?GITHUB_HERMES_TOKEN 환경변수 필요}"

cd "$DATA_DIR"

echo "=== 1. remote history 보존 (archive tag) ==="
git tag "archive/pre-redesign-$DATE" || true
git push "https://x-access-token:${TOKEN}@github.com/${REPO}.git" "archive/pre-redesign-$DATE"

echo "=== 2. .git 로컬 백업 (안전망) ==="
cp -a .git "/data/hermes/.git.backup-$DATE"
echo "백업: /data/hermes/.git.backup-$DATE ($(du -sh "/data/hermes/.git.backup-$DATE" | cut -f1))"

echo "=== 3. 기존 raw dump 제거 ==="
rm -f sql/*.sql

echo "=== 4. .git 재초기화 (clean URL) ==="
rm -rf .git
git init -b main
git remote add origin "https://github.com/${REPO}.git"
git config user.name "Crong"
git config user.email "deuxksy@gmail.com"

echo "=== 5. 신규 backup.sh 실행 (gzip dump + 첫 commit) ==="
docker exec hermes /opt/data/backup.sh

echo "=== 6. force push (archive tag로 rollback 가능) ==="
git push --force-with-lease "https://x-access-token:${TOKEN}@github.com/${REPO}.git" main

echo "=== 7. owner 복구 + 검증 ==="
chown -R 10000:10000 "$DATA_DIR/.git" "$DATA_DIR/sql"
echo ".git/config token 잔존: $(grep -c 'access-token' .git/config 2>/dev/null || echo 0)"
echo ".git 크기: $(du -sh .git | cut -f1)"

echo ""
echo "마이그레이션 완료."
echo "rollback 필요 시: /data/hermes/.git.backup-$DATE 또는 archive/pre-redesign-$DATE tag"
