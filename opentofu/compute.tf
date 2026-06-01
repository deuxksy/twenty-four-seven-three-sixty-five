# opentofu/compute.tf

# Availability Domains 조회
data "oci_identity_availability_domains" "ads" {
  compartment_id = var.compartment_ocid
}

# AMD Micro (lt) - Jumphost / Tailscale Exit Node
resource "oci_core_instance" "lt" {
  compartment_id      = var.compartment_ocid
  display_name        = "lt"
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  shape               = "VM.Standard.E2.1.Micro"

  shape_config {
    ocpus         = 0.12
    memory_in_gbs = 1
  }

  source_details {
    source_type             = "image"
    source_id               = data.oci_core_images.ubuntu_amd.images[0].id
    boot_volume_size_in_gbs = 47
  }

  create_vnic_details {
    subnet_id              = oci_core_subnet.public.id
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
    boot_volume_size_in_gbs = 47
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.private.id
    assign_public_ip = false
    hostname_label   = "brla"
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data           = base64encode(templatefile("${path.module}/cloud-init-brla.yaml", {
      tailscale_auth_key = var.tailscale_auth_key
    }))
  }

  preserve_boot_volume = false
}
