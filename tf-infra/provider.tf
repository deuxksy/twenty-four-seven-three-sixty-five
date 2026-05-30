# tf-infra/provider.tf
provider "oci" {
  tenancy_ocid     = var.oci_tenancy_ocid
  user_ocid        = var.oci_user_ocid
  fingerprint      = var.oci_fingerprint
  private_key_path = var.oci_private_key_path
  region           = var.oci_region
}

variable "oci_tenancy_ocid" {}
variable "oci_user_ocid" {}
variable "oci_fingerprint" {}
variable "oci_region" { default = "ap-chuncheon-1" } # 예시: 춘천 리전 기본값
variable "oci_private_key_path" { default = "/workspace/.oci/oci_api_key.pem" }
variable "compartment_ocid" {}