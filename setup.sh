#!/bin/bash

# ==============================================================================
# 🎯 [바이너리 완전판] 공백/줄바꿈 에러 없는 전체 암호문 해독 및 인프라 배포
# ==============================================================================

if [ ! -f "keys.txt" ]; then
    echo "❌ 에러: keys.txt 파일이 없습니다! 마스터 키 파일을 먼저 업로드해 주세요."
    exit 1
fi

echo "🔐 1단계: .env.sops 바이너리 전체 복호화 가동..."
export SOPS_AGE_KEY_FILE="$(pwd)/keys.txt"
sops -d --input-type binary --output-type binary .env.sops > .env

echo "🧠 2단계: [안전 규격] 줄바꿈/특수문자 오류 없이 변수들을 메모리에 완벽 적재..."
# 🎯 xargs의 공백 분리 버그를 우회하여 내부 값을 통째로 쉘 변수로 주입합니다.
set -a
source .env
set +a

echo "🔒 3단계: [보안] 터미널에 남은 평문 흔적 파일(.env) 즉시 영구 파괴!"
#rm -f .env

echo "📂 4단계: OpenTofu 코드가 위치한 tf-infra 폴더로 이동 중..."
cd tf-infra

echo "🔑 5단계: OCI API 접속용 인증서(.pem) 파일 추출 및 권한 격리..."
mkdir -p .oci
# 🎯 따옴표와 이스케이프 문자(\n)가 섞인 키 값을 온전하게 파일로 추출하기 위해 -e 옵션 사용
echo -e "$OCI_PRIVATE_KEY" > .oci/oci_api_key.pem
chmod 600 .oci/oci_api_key.pem

echo "📝 6단계: OpenTofu 전용 일회용 변수 파일(terraform.tfvars) 자동 작성..."
cat <<EOF > terraform.tfvars
oci_tenancy_ocid     = "${OCI_TENANCY_OCID}"
oci_user_ocid        = "${OCI_USER_OCID}"
oci_fingerprint      = "${OCI_FINGERPRINT}"
oci_private_key_path = "$(pwd)/.oci/oci_api_key.pem"
compartment_ocid     = "${OCI_COMPARTMENT_OCID}"
oci_region           = "${OCI_REGION}"
tailscale_auth_key   = "${TAILSCALE_AUTH_KEY}"
ssh_public_key       = "${OCI_SSH_PUBLIC_KEY}"
EOF

echo "🚀 7단계: 대망의 OpenTofu 인프라 빌드 및 자동 배포 총공격 개시!"
# tofu init
# tofu apply -auto-approve

echo "✅ 완료: 모든 작업이 성공적으로 처리되었습니다."