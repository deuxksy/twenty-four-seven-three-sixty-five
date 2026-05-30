#!/bin/bash

# ==============================================================================
# 🎯 [통합 파이프라인] SOPS 해독 -> 환경변수 적재 -> (검증용: OpenTofu 주석처리)
# ==============================================================================

# [안전장치] keys.txt 파일이 없으면 에러를 내고 중단합니다.
if [ ! -f "keys.txt" ]; then
    echo "❌ 에러: keys.txt 파일이 없습니다! 개인키 파일을 먼저 업로드해 주세요."
    exit 1
fi

echo "🔐 1단계: SOPS 복호화 환경 구동 및 암호문 해독 중..."
export SOPS_AGE_KEY_FILE="$(pwd)/keys.txt"
sops -d --input-type raw --output-type raw .env.sops > .env

echo "🧠 2단계: 해독된 평문 변수들을 시스템 메모리(RAM)에 적재 중..."
export $(cat .env | xargs)

echo "🔒 3단계: [보안] 터미널에 남은 평문 흔적 파일(.env) 즉시 영구 파괴!"
rm -f .env

echo "🔑 4단계: OCI API 접속용 인증서(.pem) 파일 추출 및 권한 격리..."
mkdir -p .oci
echo "$OCI_PRIVATE_KEY" > .oci/oci_api_key.pem
chmod 600 .oci/oci_api_key.pem

echo "📝 5단계: OpenTofu 전용 일회용 변수 파일(terraform.tfvars) 자동 작성..."
cat <<EOF > terraform.tfvars
tenancy_ocid       = "$OCI_TENANCY_OCID"
user_ocid          = "$OCI_USER_OCID"
fingerprint        = "$OCI_FINGERPRINT"
private_key_path   = "/workspace/.oci/oci_api_key.pem"
compartment_ocid   = "$OCI_COMPARTMENT_OCID"
region             = "$OCI_REGION"
tailscale_auth_key = "$TAILSCALE_AUTH_KEY"
ssh_public_key     = "$OCI_SSH_PUBLIC_KEY"
EOF

echo "⚠️  6단계: OpenTofu 빌드 및 자동 배포 단계는 주석 처리되어 실행되지 않습니다."
# tofu init
# tofu apply -auto-approve

echo "✅ 검증 완료: 1~5단계가 성공적으로 완료되었으며 terraform.tfvars 파일이 준비되었습니다!"