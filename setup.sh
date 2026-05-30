# 1. GitHub Secret에서 주입된 Private Key를 불변 컨테이너 내부 경로에 쓰기
mkdir -p /workspace/.oci
echo "$OCI_PRIVATE_KEY" > /workspace/.oci/oci_api_key.pem
chmod 600 /workspace/.oci/oci_api_key.pem

# 2. 뼈대 생성 (OpenTofu 레이어)
cd tf-infra
tofu init && tofu apply -auto-approve

# 3. 사설망 및 애플리케이션 스택 구성 (Ansible 레이어)
cd ../ansible-config
ansible-playbook -i inventory.ini site.yml \
  --extra-vars "vault_tailscale_ephemeral_key=$TAILSCALE_AUTH_KEY"