# opentofu/variables.tf

# OCI 인증
variable "oci_tenancy_ocid" {}
variable "oci_user_ocid" {}
variable "oci_fingerprint" {}
variable "oci_region" {
  default = "ap-chuncheon-1"
}
variable "oci_private_key_path" {
  default = "/workspace/.oci/oci_api_key.pem"
}
variable "compartment_ocid" {}

# SSH
variable "ssh_public_key" {}

# Tailscale
variable "tailscale_auth_key" {}

# 네트워크
variable "vcn_cidr" {
  default = "10.210.0.0/16"
}
variable "public_subnet_cidr" {
  default = "10.210.0.0/24"
}
variable "private_subnet_cidr" {
  default = "10.210.1.0/24"
}

# 호스트명
variable "amd_hostname" {
  default = "lt"
}
variable "arm_hostname" {
  default = "brla"
}
