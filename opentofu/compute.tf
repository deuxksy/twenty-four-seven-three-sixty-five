# opentofu/compute.tf

# Availability Domains 조회
data "oci_identity_availability_domains" "ads" {
  compartment_id = var.compartment_ocid
}

# AMD Micro (lt) - Jumphost / Tailscale Exit Node
# VM.Standard.E2.1.Micro는 고정 사양 (1/8 OCPU, 1GB RAM) — shape_config 불필요
resource "oci_core_instance" "lt" {
  compartment_id      = var.compartment_ocid
  display_name        = "lt"
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  shape               = "VM.Standard.E2.1.Micro"

  source_details {
    source_type             = "image"
    source_id               = data.oci_core_images.ubuntu_amd.images[0].id
    boot_volume_size_in_gbs = 50
  }

  create_vnic_details {
    subnet_id              = oci_core_subnet.lt.id
    assign_public_ip       = true
    hostname_label         = "lt"
    skip_source_dest_check = true
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data           = base64encode(templatefile("${path.module}/cloud-init-lt.yaml", {
      tailscale_auth_key  = var.tailscale_auth_key
      private_subnet_cidr = var.private_subnet_cidr
    }))
  }

  # 인스턴스 destroy 시 Tailscale에서 기존 노드 자동 삭제 (재생성 시 hostname 중복 방지)
  provisioner "local-exec" {
    when = destroy
    command = <<-EOT
      DEVICE_ID=$(curl -sf "https://api.tailscale.com/api/v2/tailnet/${var.tailscale_tailnet}/devices" \
        -u "${var.tailscale_api_key}:" \
        | jq -r '.devices[] | select(.hostname=="lt") | .id // empty' | head -1)
      if [ -n "$DEVICE_ID" ]; then
        echo "Deleting Tailscale node lt ($DEVICE_ID)"
        curl -sf -X DELETE "https://api.tailscale.com/api/v2/device/$DEVICE_ID" \
          -u "${var.tailscale_api_key}:"
      fi
    EOT
  }

  preserve_boot_volume = false
}

# ARM A1 (brla) - Docker Compose Server
resource "oci_core_instance" "brla" {
  compartment_id      = var.compartment_ocid
  display_name        = "brla"
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  shape               = "VM.Standard.A1.Flex"

  shape_config {
    ocpus         = 4
    memory_in_gbs = 24
  }

  source_details {
    source_type             = "image"
    source_id               = data.oci_core_images.ubuntu_arm.images[0].id
    boot_volume_size_in_gbs = 50
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.lt.id
    assign_public_ip = true
    hostname_label   = "brla"
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data           = base64encode(templatefile("${path.module}/cloud-init-brla.yaml", {
      tailscale_auth_key = var.tailscale_auth_key
    }))
  }

  # 인스턴스 destroy 시 Tailscale에서 기존 노드 자동 삭제 (재생성 시 hostname 중복 방지)
  provisioner "local-exec" {
    when = destroy
    command = <<-EOT
      DEVICE_ID=$(curl -sf "https://api.tailscale.com/api/v2/tailnet/${var.tailscale_tailnet}/devices" \
        -u "${var.tailscale_api_key}:" \
        | jq -r '.devices[] | select(.hostname=="brla") | .id // empty' | head -1)
      if [ -n "$DEVICE_ID" ]; then
        echo "Deleting Tailscale node brla ($DEVICE_ID)"
        curl -sf -X DELETE "https://api.tailscale.com/api/v2/device/$DEVICE_ID" \
          -u "${var.tailscale_api_key}:"
      fi
    EOT
  }

  preserve_boot_volume = false
}
