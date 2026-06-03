#!/bin/bash

# ==============================================================================
# 🎯 전체 암호문 해독 및 인프라 배포
# ==============================================================================

if [ ! -f "keys.txt" ]; then
    echo "❌ 에러: keys.txt 파일이 없습니다! 마스터 키 파일을 먼저 업로드해 주세요."
    exit 1
fi

# .env.local에서 SOPS 함수 로드
source .env.local

echo "🔐 1단계: .env.sops 복호화..."
sops-dec

echo "🧠 2단계: 변수 로드..."
sops-load

# 부모 셸에서 상속된 OCI_PRIVATE_KEY 제거 (PEM은 secrets/에서 별도 관리)
unset OCI_PRIVATE_KEY

echo "🔒 3단계: 평문 .env 제거..."
#rm -f .env

echo "📂 4단계: OpenTofu 디렉토리로 이동..."
cd opentofu

echo "🔑 5단계: OCI API 키 복호화..."
mkdir -p .oci
sops -d ../secrets/oci_api_key.pem.sops > .oci/oci_api_key.pem
chmod 600 .oci/oci_api_key.pem

echo "📝 6단계: terraform.tfvars 자동 생성..."
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

echo "🚀 7단계: OpenTofu 인프라 배포..."
tofu init
tofu plan
tofu apply -auto-approve

echo "📋 8단계: Ansible inventory 생성..."
tofu output -raw ansible_inventory_ini > ../ansible/inventory/hosts.ini

echo "✅ 완료: 인프라 프로비저닝 + inventory 생성 완료"
echo "👉 다음: cd ../ansible && ansible-playbook playbook-lt.yml && ansible-playbook playbook-brla.yml"
