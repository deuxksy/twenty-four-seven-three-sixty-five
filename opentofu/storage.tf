# opentofu/storage.tf

# Block Volume (64GB) - ARM A1(brla) 데이터 볼륨
resource "oci_core_volume" "brla_data" {
  compartment_id      = var.compartment_ocid
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  display_name        = "brla-data"
  size_in_gbs         = 64
  vpus_per_gb         = 0
}

# Block Volume을 ARM A1(brla)에 Attach (Paravirtualized)
resource "oci_core_volume_attachment" "brla_data_attach" {
  attachment_type = "paravirtualized"
  compartment_id  = var.compartment_ocid
  instance_id     = oci_core_instance.brla.id
  volume_id       = oci_core_volume.brla_data.id
  display_name    = "brla-data-attach"
  device          = "/dev/oracleoci/oraclevdb"
}
