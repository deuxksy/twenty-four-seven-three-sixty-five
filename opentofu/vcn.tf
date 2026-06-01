# opentofu/vcn.tf

# VCN
resource "oci_core_vcn" "main" {
  compartment_id = var.compartment_ocid
  cidr_blocks    = [var.vcn_cidr]
  display_name   = "twenty-four-seven-three-sixty-five-vcn"
  dns_label      = "tfss365"
}

# Internet Gateway
resource "oci_core_internet_gateway" "igw" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "public-igw"
  enabled        = true
}

# Service Gateway
data "oci_core_services" "oci_services" {
  filter {
    name   = "name"
    values = ["All .* Services In Oracle Services Network"]
    regex  = true
  }
}

resource "oci_core_service_gateway" "sgw" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "sgw"
  services {
    service_id = data.oci_core_services.oci_services.services[0].id
  }
}

# Route Table - Public (Internet Gateway)
resource "oci_core_route_table" "public" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "public-rt"
  route_rules {
    destination       = "0.0.0.0/0"
    network_entity_id = oci_core_internet_gateway.igw.id
  }
}

# Route Table - Service Gateway
resource "oci_core_route_table" "service" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "service-rt"
  route_rules {
    destination       = data.oci_core_services.oci_services.services[0].cidr_block
    destination_type  = "SERVICE_CIDR_BLOCK"
    network_entity_id = oci_core_service_gateway.sgw.id
    description       = "OCI services via Service Gateway"
  }
}

# Security List - lt (SSH + Tailscale 공용 허용)
resource "oci_core_security_list" "lt" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "lt-sl"

  ingress_security_rules {
    protocol  = "6"
    source    = "0.0.0.0/0"
    stateless = false
    tcp_options {
      min = 22
      max = 22
    }
  }

  ingress_security_rules {
    protocol  = "17"
    source    = "0.0.0.0/0"
    stateless = false
    udp_options {
      min = 41641
      max = 41641
    }
  }

  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
    stateless   = false
  }
}

# Security List - brla (Tailscale만 공용, SSH는 VCN 내부만)
resource "oci_core_security_list" "brla" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "brla-sl"

  # Tailscale만 공용 허용
  ingress_security_rules {
    protocol  = "17"
    source    = "0.0.0.0/0"
    stateless = false
    udp_options {
      min = 41641
      max = 41641
    }
  }

  # SSH는 VCN 내부(lt)에서만
  ingress_security_rules {
    protocol  = "6"
    source    = var.vcn_cidr
    stateless = false
    tcp_options {
      min = 22
      max = 22
    }
  }

  # VCN 내부 통신
  ingress_security_rules {
    protocol  = "all"
    source    = var.vcn_cidr
    stateless = false
  }

  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
    stateless   = false
  }
}

# Subnet - lt 전용
resource "oci_core_subnet" "lt" {
  compartment_id    = var.compartment_ocid
  vcn_id            = oci_core_vcn.main.id
  cidr_block        = "10.210.0.0/24"
  display_name      = "lt-subnet"
  dns_label         = "lt"
  route_table_id    = oci_core_route_table.public.id
  security_list_ids = [oci_core_security_list.lt.id]
}

# Subnet - brla 전용
resource "oci_core_subnet" "brla" {
  compartment_id    = var.compartment_ocid
  vcn_id            = oci_core_vcn.main.id
  cidr_block        = "10.210.1.0/24"
  display_name      = "brla-subnet"
  dns_label         = "brla"
  route_table_id    = oci_core_route_table.public.id
  security_list_ids = [oci_core_security_list.brla.id]
}
