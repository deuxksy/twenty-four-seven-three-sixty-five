# OCI Free-Tier 인프라 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** OpenTofu로 OCI VNC/인스턴스/스토리지를 프로비저닝하고, Ansible로 Tailscale/Docker/code-server/Hermes를 설정

**Architecture:** OpenTofu가 cloud-init으로 Tailscale만 최소 설치한 후, Ansible이 Tailscale 네트워크를 통해 전체 설정. AMD Micro(lt)는 Public Subnet에 jumphost/exit node, ARM A1(brla)는 Private Subnet에 Docker Compose로 서비스 구동.

**Tech Stack:** OpenTofu, OCI Provider, Ansible, Tailscale, Docker Compose, code-server

**Spec:** `docs/superpowers/specs/2026-06-02-oci-free-tier-infra-design.md`

---

## File Structure

```
opentofu/
├── backend.tf              # 기존, 수정 없음
├── provider.tf             # 기존, provider만 남기고 변수 제거
├── variables.tf            # 신규, 모든 변수 선언
├── data.tf                 # 신규, Ubuntu 24.04 이미지 조회
├── vcn.tf                  # 신규, VCN + Subnet + Security + Gateway
├── compute.tf              # 신규, AMD Micro + ARM A1
├── storage.tf              # 신규, Block Volume + Attachment
├── cloud-init-lt.yaml      # 신규, AMD용 cloud-init
├── cloud-init-brla.yaml    # 신규, ARM용 cloud-init
└── outputs.tf              # 신규, Ansible inventory 출력

ansible/
├── ansible.cfg             # 신규, 기본 설정
├── inventory/
│   └── hosts.ini           # 자동 생성 (gitignore)
├── playbook-lt.yml         # 신규, AMD: exit node 설정
├── playbook-brla.yml       # 신규, ARM: Docker + 서비스 배포
└── roles/
    ├── tailscale/          # Tailscale 공통 + exit node
    ├── docker/             # Docker + Compose 설치
    ├── code-server/        # code-server 컨테이너
    └── hermes/             # Hermes 컨테이너
```

---

### Task 1: tf-infra → opentofu 디렉토리명 변경

**Files:**
- Rename: `tf-infra/` → `opentofu/`
- Modify: `setup.sh`
- Modify: `CLAUDE.md`
- Modify: `.gitignore`

- [ ] **Step 1: 디렉토리 이름 변경**

```bash
cd /Users/crong/git/twenty-four-seven-three-sixty-five
git mv tf-infra opentofu
```

- [ ] **Step 2: setup.sh에서 tf-infra 참조를 opentofu로 변경**

`setup.sh`의 `cd tf-infra` → `cd opentofu`로 변경:

```bash
sed -i '' 's|cd tf-infra|cd opentofu|' setup.sh
```

- [ ] **Step 3: CLAUDE.md에서 tf-infra 참조를 opentofu로 변경**

```bash
sed -i '' 's|tf-infra/|opentofu/|g' CLAUDE.md
sed -i '' 's|tf-infra/|opentofu/|g' README.md
```

- [ ] **Step 4: 커밋**

```bash
git add -A && git commit -m "refactor: tf-infra 디렉토리명을 opentofu로 변경"
```

---

### Task 2: OpenTofu 변수 분리 (variables.tf + provider.tf 정리)

**Files:**
- Create: `opentofu/variables.tf`
- Modify: `opentofu/provider.tf`

- [ ] **Step 1: variables.tf 생성**

기존 `provider.tf`에 있던 변수 + 스펙에 필요한 추가 변수를 모두 이동:

```hcl
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
```

- [ ] **Step 2: provider.tf에서 변수 제거, provider만 남김**

```hcl
# opentofu/provider.tf

provider "oci" {
  tenancy_ocid     = var.oci_tenancy_ocid
  user_ocid        = var.oci_user_ocid
  fingerprint      = var.oci_fingerprint
  private_key_path = var.oci_private_key_path
  region           = var.oci_region
}
```

- [ ] **Step 3: setup.sh의 terraform.tfvars에 새 변수 추가**

`setup.sh`의 cat heredoc에 `ssh_public_key`와 `tailscale_auth_key` 추가. 기존 `setup.sh`의 tfvars 생성 부분을 다음으로 교체:

```bash
# setup.sh의 6단계 tfvars 생성 부분
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
```

- [ ] **Step 4: validate로 검증**

```bash
cd opentofu && tofu validate
```

Expected: `Success! The configuration is valid.` (기존 변수가 그대로 작동하는지 확인)

- [ ] **Step 5: 커밋**

```bash
git add opentofu/variables.tf opentofu/provider.tf setup.sh
git commit -m "refactor: variables.tf 분리, provider.tf 정리, tfvars에 ssh/tailscale 키 추가"
```

---

### Task 3: Ubuntu 이미지 조회 데이터 소스 (data.tf)

**Files:**
- Create: `opentofu/data.tf`

- [ ] **Step 1: data.tf 생성**

OCI에서 최신 Ubuntu 24.04 이미지 OCID를 동적으로 조회:

```hcl
# opentofu/data.tf

# AMD용 Ubuntu 24.04 LTS 이미지
data "oci_core_images" "ubuntu_amd" {
  compartment_id           = var.compartment_ocid
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "24.04"
  shape                    = "VM.Standard.E2.1.Micro"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

# ARM용 Ubuntu 24.04 LTS 이미지
data "oci_core_images" "ubuntu_arm" {
  compartment_id           = var.compartment_ocid
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "24.04"
  shape                    = "VM.Standard.A1.Flex"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}
```

- [ ] **Step 2: validate**

```bash
cd opentofu && tofu validate
```

Expected: `Success!`

- [ ] **Step 3: 커밋**

```bash
git add opentofu/data.tf
git commit -m "feat: Ubuntu 24.04 이미지 조회 데이터 소스 추가"
```

---

### Task 4: VCN 네트워킹 (vcn.tf)

**Files:**
- Create: `opentofu/vcn.tf`

- [ ] **Step 1: vcn.tf 생성**

```hcl
# opentofu/vcn.tf

# VCN
resource "oci_core_vcn" "main" {
  compartment_id = var.compartment_ocid
  cidr_blocks    = [var.vcn_cidr]
  display_name   = "twenty-four-seven-three-sixty-five-vcn"
  dns_label      = "tfss365"
}

# Internet Gateway (Public Subnet용)
resource "oci_core_internet_gateway" "igw" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "public-igw"
  enabled        = true
}

# Service Gateway (Private Subnet용 - OCI 서비스 접근)
resource "oci_core_service_gateway" "sgw" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "private-sgw"
  services {
    service_id = data.oci_core_services.oci_services.services[0].id
  }
}

# OCI 서비스 목록 조회 (Service Gateway용)
data "oci_core_services" "oci_services" {
  filter {
    name   = "name"
    values = ["All .* Services In Oracle Services Network"]
    regex  = true
  }
}

# Public Subnet
resource "oci_core_subnet" "public" {
  compartment_id    = var.compartment_ocid
  vcn_id            = oci_core_vcn.main.id
  cidr_block        = var.public_subnet_cidr
  display_name      = "public-subnet"
  dns_label         = "public"
  route_table_id    = oci_core_route_table.public.id
  security_list_ids = [oci_core_security_list.public.id]
}

# Private Subnet
resource "oci_core_subnet" "private" {
  compartment_id    = var.compartment_ocid
  vcn_id            = oci_core_vcn.main.id
  cidr_block        = var.private_subnet_cidr
  display_name      = "private-subnet"
  dns_label         = "private"
  route_table_id    = oci_core_route_table.private.id
  security_list_ids = [oci_core_security_list.private.id]

  # ARM 인스턴스는 공용 IP 없음
  prohibit_public_ip_on_vnic = true
}

# Route Table - Public (Internet Gateway로 라우팅)
resource "oci_core_route_table" "public" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "public-rt"
  route_rules {
    destination       = "0.0.0.0/0"
    network_entity_id = oci_core_internet_gateway.igw.id
  }
}

# Route Table - Private (기본 라우트 없음, Tailscale이 처리)
resource "oci_core_route_table" "private" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "private-rt"
  route_rules {
    destination       = data.oci_core_services.oci_services.services[0].cidr_block
    network_entity_id = oci_core_service_gateway.sgw.id
    description       = "OCI services via Service Gateway"
  }
}

# Security List - Public (SSH + Tailscale)
resource "oci_core_security_list" "public" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "public-sl"

  # SSH 인바운드
  ingress_security_rules {
    protocol  = "6" # TCP
    source    = "0.0.0.0/0"
    stateless = false
    tcp_options {
      min = 22
      max = 22
    }
  }

  # Tailscale 인바운드 (WireGuard UDP)
  ingress_security_rules {
    protocol  = "17" # UDP
    source    = "0.0.0.0/0"
    stateless = false
    udp_options {
      min = 41641
      max = 41641
    }
  }

  # 모든 아웃바운드 허용
  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
    stateless   = false
  }
}

# Security List - Private (AMD에서만 접근 허용)
resource "oci_core_security_list" "private" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "private-sl"

  # VCN 내부 통신 허용
  ingress_security_rules {
    protocol  = "all"
    source    = var.vcn_cidr
    stateless = false
  }

  # 모든 아웃바운드 허용
  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
    stateless   = false
  }
}
```

- [ ] **Step 2: validate**

```bash
cd opentofu && tofu validate
```

Expected: `Success!`

- [ ] **Step 3: 커밋**

```bash
git add opentofu/vcn.tf
git commit -m "feat: VCN 네트워킹 리소스 추가 (Subnet, Gateway, Security List, Route Table)"
```

---

### Task 5: cloud-init 템플릿

**Files:**
- Create: `opentofu/cloud-init-lt.yaml`
- Create: `opentofu/cloud-init-brla.yaml`

- [ ] **Step 1: AMD Micro(lt)용 cloud-init 생성**

```yaml
# opentofu/cloud-init-lt.yaml
#cloud-config
hostname: lt
manage_etc_hosts: true

package_update: true
packages:
  - curl

runcmd:
  # Tailscale 설치
  - curl -fsSL https://tailscale.com/install.sh | sh
  # Tailscale 인증 (exit node + subnet router 활성화)
  - tailscale up --authkey=${tailscale_auth_key} --hostname=lt --advertise-exit-node --advertise-routes=${private_subnet_cidr}
  # 방화벽 포워딩 활성화 (exit node + subnet router에 필요)
  - echo 'net.ipv4.ip_forward = 1' | tee -a /etc/sysctl.d/99-tailscale.conf
  - echo 'net.ipv6.conf.all.forwarding = 1' | tee -a /etc/sysctl.d/99-tailscale.conf
  - sysctl -p /etc/sysctl.d/99-tailscale.conf
```

- [ ] **Step 2: ARM A1(brla)용 cloud-init 생성**

```yaml
# opentofu/cloud-init-brla.yaml
#cloud-config
hostname: brla
manage_etc_hosts: true

package_update: true
packages:
  - curl

runcmd:
  # Tailscale 설치
  - curl -fsSL https://tailscale.com/install.sh | sh
  # Tailscale 인증
  - tailscale up --authkey=${tailscale_auth_key} --hostname=brla
```

- [ ] **Step 3: 커밋**

```bash
git add opentofu/cloud-init-lt.yaml opentofu/cloud-init-brla.yaml
git commit -m "feat: cloud-init 템플릿 추가 (lt: exit node, brla: Tailscale)"
```

---

### Task 6: 컴퓨트 인스턴스 (compute.tf)

**Files:**
- Create: `opentofu/compute.tf`

- [ ] **Step 1: compute.tf 생성**

cloud-init 템플릿에서 변수 치환을 위해 `template_file` 대신 `template_cloudinit_config` 사용:

```hcl
# opentofu/compute.tf

# AMD Micro (lt) - Jumphost / Tailscale Exit Node
resource "oci_core_instance" "lt" {
  compartment_id      = var.compartment_ocid
  display_name        = "lt"
  hostname_label      = "lt"
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  shape               = "VM.Standard.E2.1.Micro"

  shape_config {
    ocpus         = 0.12 # 1/8 OCPU
    memory_in_gbs = 1
  }

  source_details {
    source_type             = "image"
    source_id               = data.oci_core_images.ubuntu_amd.images[0].id
    boot_volume_size_in_gbs = 47
  }

  create_vnic_details {
    subnet_id                 = oci_core_subnet.public.id
    assign_public_ip          = true
    hostname_label            = "lt"
    skip_source_dest_check    = true # Exit node에 필요
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data           = base64encode(templatefile("${path.module}/cloud-init-lt.yaml", {
      tailscale_auth_key    = var.tailscale_auth_key
      private_subnet_cidr   = var.private_subnet_cidr
    }))
  }

  # jumphost이므로 삭제 보호 해제 (비용 절약)
  preserve_boot_volume = false
}

# ARM A1 (brla) - Docker Compose Server
resource "oci_core_instance" "brla" {
  compartment_id      = var.compartment_ocid
  display_name        = "brla"
  hostname_label      = "brla"
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
    subnet_id                 = oci_core_subnet.private.id
    assign_public_ip          = false
    hostname_label            = "brla"
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data           = base64encode(templatefile("${path.module}/cloud-init-brla.yaml", {
      tailscale_auth_key = var.tailscale_auth_key
    }))
  }

  preserve_boot_volume = false
}

# Availability Domains 조회
data "oci_identity_availability_domains" "ads" {
  compartment_id = var.compartment_ocid
}
```

- [ ] **Step 2: cloud-init YAML에 변수 플레이스홀더 확인**

`cloud-init-lt.yaml`의 `${tailscale_auth_key}`와 `${private_subnet_cidr}`가 `templatefile()`로 치환됨. YAML을 수정:

```yaml
# opentofu/cloud-init-lt.yaml (변수 치환용)
#cloud-config
hostname: lt
manage_etc_hosts: true

package_update: true
packages:
  - curl

runcmd:
  - curl -fsSL https://tailscale.com/install.sh | sh
  - tailscale up --authkey=${tailscale_auth_key} --hostname=lt --advertise-exit-node --advertise-routes=${private_subnet_cidr}
  - echo 'net.ipv4.ip_forward = 1' | tee -a /etc/sysctl.d/99-tailscale.conf
  - echo 'net.ipv6.conf.all.forwarding = 1' | tee -a /etc/sysctl.d/99-tailscale.conf
  - sysctl -p /etc/sysctl.d/99-tailscale.conf
```

```yaml
# opentofu/cloud-init-brla.yaml (변수 치환용)
#cloud-config
hostname: brla
manage_etc_hosts: true

package_update: true
packages:
  - curl

runcmd:
  - curl -fsSL https://tailscale.com/install.sh | sh
  - tailscale up --authkey=${tailscale_auth_key} --hostname=brla
```

- [ ] **Step 3: validate**

```bash
cd opentofu && tofu validate
```

Expected: `Success!`

- [ ] **Step 4: 커밋**

```bash
git add opentofu/compute.tf opentofu/cloud-init-lt.yaml opentofu/cloud-init-brla.yaml
git commit -m "feat: AMD Micro(lt) + ARM A1(brla) 컴퓨트 인스턴스 추가"
```

---

### Task 7: 블록 볼륨 스토리지 (storage.tf)

**Files:**
- Create: `opentofu/storage.tf`

- [ ] **Step 1: storage.tf 생성**

```hcl
# opentofu/storage.tf

# Block Volume (64GB) - ARM A1(brla) 데이터 볼륨
resource "oci_core_volume" "brla_data" {
  compartment_id      = var.compartment_ocid
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  display_name        = "brla-data"
  size_in_gbs         = 64

  # Free-Tier: VPUs = 0 (성능 낮음, 비용 무료)
  vpus_per_gb = 0
}

# Block Volume을 ARM A1(brla)에 Attach (Paravirtualized)
resource "oci_core_volume_attachment" "brla_data_attach" {
  attachment_type = "paravirtualized"
  compartment_id  = var.compartment_ocid
  instance_id     = oci_core_instance.brla.id
  volume_id       = oci_core_volume.brla_data.id
  display_name    = "brla-data-attach"

  # /home/ubuntu에 마운트 예정
  device = "/dev/oracleoci/oraclevdb"
}
```

- [ ] **Step 2: validate**

```bash
cd opentofu && tofu validate
```

Expected: `Success!`

- [ ] **Step 3: 커밋**

```bash
git add opentofu/storage.tf
git commit -m "feat: ARM A1(brla)에 64GB Block Volume 추가"
```

---

### Task 8: 출력값 — Ansible 인벤토리 (outputs.tf)

**Files:**
- Create: `opentofu/outputs.tf`

- [ ] **Step 1: outputs.tf 생성**

```hcl
# opentofu/outputs.tf

# AMD Micro (lt)
output "lt_public_ip" {
  description = "AMD Micro(lt) 공용 IP"
  value       = oci_core_instance.lt.public_ip
}

output "lt_tailscale_ip" {
  description = "AMD Micro(lt) Tailscale IP (cloud-init 완료 후 확인 필요)"
  value       = "Tailscale Admin Console에서 확인: https://login.tailscale.com/admin/machines"
}

# ARM A1 (brla)
output "brla_private_ip" {
  description = "ARM A1(brla) 사설 IP"
  value       = oci_core_instance.brla.private_ip
}

output "brla_tailscale_ip" {
  description = "ARM A1(brla) Tailscale IP (cloud-init 완료 후 확인 필요)"
  value       = "Tailscale Admin Console에서 확인: https://login.tailscale.com/admin/machines"
}

# Ansible inventory 생성용
output "ansible_inventory_ini" {
  description = "Ansible inventory (hosts.ini) 내용"
  value = <<-EOT
    [lt]
    lt ansible_host=${oci_core_instance.lt.public_ip} ansible_user=ubuntu

    [brla]
    brla ansible_host=${oci_core_instance.brla.private_ip} ansible_user=ubuntu ansible_proxy_jump=lt

    [all:children]
    lt
    brla

    [all:vars]
    ansible_python_interpreter=/usr/bin/python3
    ansible_ssh_common_args=-o StrictHostKeyChecking=no
  EOT
}

# Block Volume device path
output "brla_volume_device" {
  description = "Block Volume device path (Ansible에서 마운트용)"
  value       = "/dev/oracleoci/oraclevdb"
}
```

- [ ] **Step 2: validate**

```bash
cd opentofu && tofu validate
```

Expected: `Success!`

- [ ] **Step 3: 커밋**

```bash
git add opentofu/outputs.tf
git commit -m "feat: Ansible inventory 출력값 추가"
```

---

### Task 9: OpenTofu 전체 plan 검증

**Files:**
- Modify: `opentofu/terraform.tfvars` (수동 생성, .gitignore에 이미 등록됨)

- [ ] **Step 1: .env에서 환경변수 로드**

```bash
cd /Users/crong/git/twenty-four-seven-three-sixty-five
source .env.local
dec
load
```

- [ ] **Step 2: terraform.tfvars 수동 생성 (setup.sh가 아직 구버전이므로)**

```bash
cd opentofu
cat <<EOF > terraform.tfvars
oci_tenancy_ocid     = "$OCI_TENANCY_OCID"
oci_user_ocid        = "$OCI_USER_OCID"
oci_fingerprint      = "$OCI_FINGERPRINT"
oci_private_key_path = "$(cd .. && pwd)/opentofu/.oci/oci_api_key.pem"
compartment_ocid     = "$OCI_COMPARTMENT_OCID"
oci_region           = "$OCI_REGION"
tailscale_auth_key   = "$TAILSCALE_AUTH_KEY"
ssh_public_key       = "$OCI_SSH_PUBLIC_KEY"
EOF
```

- [ ] **Step 3: tofu init 재실행**

```bash
cd opentofu && tofu init
```

Expected: `OpenTofu has been successfully initialized!`

- [ ] **Step 4: tofu plan 실행**

```bash
cd opentofu && tofu plan -var-file=terraform.tfvars
```

Expected: `Plan: X to add, 0 to change, 0 to destroy.` — 리소스 수 확인:
- VCN (1) + IGW (1) + SGW (1) + Subnet (2) + Route Table (2) + Security List (2) = 9
- Instance (2) + Volume (1) + Volume Attachment (1) = 4
- **총 13개 리소스 추가 예상**

- [ ] **Step 5: plan 출력 리뷰 후 커밋 (변경사항 없으면 스킵)**

```bash
git add -A && git status
# plan 결과에 만족하면 다음 Task로 진행
```

---

### Task 10: Ansible 기본 구조

**Files:**
- Create: `ansible/ansible.cfg`
- Create: `ansible/inventory/.gitkeep`

- [ ] **Step 1: 디렉토리 생성**

```bash
mkdir -p ansible/inventory ansible/roles/{tailscale,docker,code-server,hermes}/{tasks,handlers,templates,defaults,vars}
```

- [ ] **Step 2: ansible.cfg 생성**

```ini
# ansible/ansible.cfg
[defaults]
inventory = inventory/hosts.ini
host_key_checking = False
retry_files_enabled = False
stdout_callback = yaml
timeout = 30

[privilege_escalation]
become = True
become_method = sudo
```

- [ ] **Step 3: inventory/.gitkeep 생성**

```bash
touch ansible/inventory/.gitkeep
```

- [ ] **Step 4: ansible/inventory/hosts.ini를 .gitignore에 추가**

```bash
echo "ansible/inventory/hosts.ini" >> .gitignore
```

- [ ] **Step 5: 커밋**

```bash
git add ansible/ .gitignore
git commit -m "feat: Ansible 기본 구조 생성 (ansible.cfg, roles 디렉토리)"
```

---

### Task 11: Ansible tailscale role

**Files:**
- Create: `ansible/roles/tailscale/tasks/main.yml`
- Create: `ansible/roles/tailscale/defaults/main.yml`

- [ ] **Step 1: defaults/main.yml 생성**

```yaml
# ansible/roles/tailscale/defaults/main.yml
tailscale_exit_node: false
tailscale_advertise_routes: ""
tailscale_hostname: "{{ inventory_hostname }}"
```

- [ ] **Step 2: tasks/main.yml 생성**

```yaml
# ansible/roles/tailscale/tasks/main.yml

# Tailscale 인증 상태 확인
- name: Tailscale 인증 상태 확인
  command: tailscale status --json
  register: ts_status
  changed_when: false
  failed_when: false

# cloud-init이 이미 설치+인증했으므로, 설정만 검증
- name: Tailscale 실행 중 확인
  command: tailscale status
  register: ts_check
  changed_when: false

- name: Tailscale IP 출력
  debug:
    msg: "{{ inventory_hostname }} Tailscale IP: {{ ts_check.stdout_lines[0] | default('확인 중') }}"

# Exit node 설정 (AMD만)
- name: Exit node + subnet router 활성화
  command: >
    tailscale up
    --hostname={{ tailscale_hostname }}
    --advertise-exit-node
    --advertise-routes={{ tailscale_advertise_routes }}
  when: tailscale_exit_node | bool
  notify: restart tailscale

# IP 포워딩 (exit node에 필요)
- name: IP 포워딩 활성화
  sysctl:
    name: "{{ item }}"
    value: '1'
    sysctl_set: yes
  loop:
    - net.ipv4.ip_forward
    - net.ipv6.conf.all.forwarding
  when: tailscale_exit_node | bool

# Tailscale HTTPS 인증서 발급
- name: Tailscale 인증서 발급
  command: tailscale cert {{ tailscale_hostname }}.bun-bull.ts.net
  args:
    creates: "/etc/tailscale/{{ tailscale_hostname }}.bun-bull.ts.net.crt"
  when: not tailscale_exit_node | bool
```

- [ ] **Step 3: handlers/main.yml 생성**

```yaml
# ansible/roles/tailscale/handlers/main.yml
- name: restart tailscale
  service:
    name: tailscaled
    state: restarted
```

- [ ] **Step 4: 커밋**

```bash
git add ansible/roles/tailscale/
git commit -m "feat: Ansible tailscale role 추가 (exit node, 인증서 발급)"
```

---

### Task 12: Ansible docker role

**Files:**
- Create: `ansible/roles/docker/tasks/main.yml`

- [ ] **Step 1: tasks/main.yml 생성**

```yaml
# ansible/roles/docker/tasks/main.yml

# Docker 공식 GPG 키 추가
- name: Docker GPG 키 추가
  apt_key:
    url: https://download.docker.com/linux/ubuntu/gpg
    state: present

- name: Docker APT 리포지토리 추가
  apt_repository:
    repo: "deb [arch=arm64] https://download.docker.com/linux/ubuntu {{ ansible_distribution_release }} stable"
    state: present
    update_cache: yes

# Docker 설치
- name: Docker Engine + Compose 플러그인 설치
  apt:
    name:
      - docker-ce
      - docker-ce-cli
      - containerd.io
      - docker-compose-plugin
    state: present

- name: ubuntu 유저를 docker 그룹에 추가
  user:
    name: ubuntu
    groups: docker
    append: yes

- name: Docker 서비스 활성화
  service:
    name: docker
    state: started
    enabled: yes

# Block Volume 마운트
- name: Block Volume 파일시스템 생성
  filesystem:
    fstype: ext4
    dev: /dev/oracleoci/oraclevdb

- name: Block Volume /home/ubuntu에 마운트
  mount:
    path: /home/ubuntu
    src: /dev/oracleoci/oraclevdb
    fstype: ext4
    state: mounted
```

- [ ] **Step 2: 커밋**

```bash
git add ansible/roles/docker/
git commit -m "feat: Ansible docker role 추가 (Docker Engine, Compose, Block Volume 마운트)"
```

---

### Task 13: Ansible code-server role

**Files:**
- Create: `ansible/roles/code-server/tasks/main.yml`
- Create: `ansible/roles/code-server/templates/docker-compose.yml.j2`

- [ ] **Step 1: templates/docker-compose.yml.j2 생성**

```yaml
# ansible/roles/code-server/templates/docker-compose.yml.j2
services:
  code-server:
    image: codercom/code-server:latest
    container_name: code-server
    restart: unless-stopped
    ports:
      - "8080:8080"
    volumes:
      - /home/ubuntu:/home/coder
    environment:
      - PASSWORD={{ code_server_password | default('changeme') }}
      - TZ=Asia/Seoul
    labels:
      - "com.centurylinklabs.watchtower.enable=true"
```

- [ ] **Step 2: tasks/main.yml 생성**

```yaml
# ansible/roles/code-server/tasks/main.yml

- name: code-server Docker Compose 파일 생성
  template:
    src: docker-compose.yml.j2
    dest: /home/ubuntu/code-server/docker-compose.yml
    owner: ubuntu
    group: ubuntu
  become: yes

- name: code-server 디렉토리 생성
  file:
    path: /home/ubuntu/code-server
    state: directory
    owner: ubuntu
    group: ubuntu

- name: code-server 컨테이너 시작
  community.docker.docker_compose_v2:
    project_src: /home/ubuntu/code-server
    state: present
  become: yes
  become_user: ubuntu
```

- [ ] **Step 3: 커밋**

```bash
git add ansible/roles/code-server/
git commit -m "feat: Ansible code-server role 추가"
```

---

### Task 14: Ansible hermes role

**Files:**
- Create: `ansible/roles/hermes/tasks/main.yml`
- Create: `ansible/roles/hermes/templates/docker-compose.yml.j2`

- [ ] **Step 1: templates/docker-compose.yml.j2 생성**

```yaml
# ansible/roles/hermes/templates/docker-compose.yml.j2
services:
  hermes:
    image: {{ hermes_image | default('hermes:latest') }}
    container_name: hermes
    restart: unless-stopped
    ports:
      - "3000:3000"
    volumes:
      - /home/ubuntu/hermes/data:/app/data
      - /home/ubuntu/hermes/config:/app/config
    environment:
      - TZ=Asia/Seoul
    labels:
      - "com.centurylinklabs.watchtower.enable=true"
```

- [ ] **Step 2: tasks/main.yml 생성**

```yaml
# ansible/roles/hermes/tasks/main.yml

- name: Hermes 디렉토리 생성
  file:
    path: "{{ item }}"
    state: directory
    owner: ubuntu
    group: ubuntu
  loop:
    - /home/ubuntu/hermes
    - /home/ubuntu/hermes/data
    - /home/ubuntu/hermes/config

- name: Hermes Docker Compose 파일 생성
  template:
    src: docker-compose.yml.j2
    dest: /home/ubuntu/hermes/docker-compose.yml
    owner: ubuntu
    group: ubuntu

- name: Hermes 컨테이너 시작
  community.docker.docker_compose_v2:
    project_src: /home/ubuntu/hermes
    state: present
  become: yes
  become_user: ubuntu
```

- [ ] **Step 3: 커밋**

```bash
git add ansible/roles/hermes/
git commit -m "feat: Ansible hermes role 추가"
```

---

### Task 15: Ansible Playbook 작성

**Files:**
- Create: `ansible/playbook-lt.yml`
- Create: `ansible/playbook-brla.yml`

- [ ] **Step 1: playbook-lt.yml 생성 (AMD Micro)**

```yaml
# ansible/playbook-lt.yml
---
- name: AMD Micro (lt) - Tailscale Exit Node 설정
  hosts: lt
  become: yes
  roles:
    - role: tailscale
      vars:
        tailscale_exit_node: true
        tailscale_advertise_routes: "10.210.1.0/24"
        tailscale_hostname: "lt"
```

- [ ] **Step 2: playbook-brla.yml 생성 (ARM A1)**

```yaml
# ansible/playbook-brla.yml
---
- name: ARM A1 (brla) - Docker + 서비스 배포
  hosts: brla
  become: yes
  roles:
    - role: tailscale
      vars:
        tailscale_exit_node: false
        tailscale_hostname: "brla"
    - role: docker
    - role: code-server
    - role: hermes
```

- [ ] **Step 3: 커밋**

```bash
git add ansible/playbook-lt.yml ansible/playbook-brla.yml
git commit -m "feat: Ansible playbook 추가 (lt: exit node, brla: Docker + 서비스)"
```

---

### Task 16: 문서 업데이트

**Files:**
- Modify: `CLAUDE.md`
- Modify: `README.md`

- [ ] **Step 1: CLAUDE.md에 Ansible 명령어 및 새 디렉토리 구조 반영**

CLAUDE.md의 Commands 섹션에 추가:

```markdown
## Commands

```bash
# SOPS 시크릿 관리 (keys.txt 필요)
source .env.local          # enc/dec/load alias 로드
dec                        # .env.sops → .env 복호화
enc                        # .env → .env.sops 암호화
load                       # .env 변수를 쉘 환경에 주입

# OpenTofu (opentofu/ 디렉토리에서 실행)
cd opentofu
tofu init                  # Cloudflare R2 backend로 초기화
tofu plan -var-file=terraform.tfvars
tofu apply -auto-approve -var-file=terraform.tfvars

# Ansible (Tailscale 연결 후 실행)
cd ansible
# 인벤토리 생성 (tofu apply 후)
tofu output -raw ansible_inventory_ini > ansible/inventory/hosts.ini
# AMD Micro (lt) 설정
ansible-playbook playbook-lt.yml
# ARM A1 (brla) 설정
ansible-playbook playbook-brla.yml

# 전체 배포 (setup.sh)
# keys.txt가 프로젝트 루트에 있어야 함
bash setup.sh
```
```

- [ ] **Step 2: README.md에 Ansible 정보 추가**

README.md의 구조 섹션에 `ansible/` 추가.

- [ ] **Step 3: 커밋**

```bash
git add CLAUDE.md README.md
git commit -m "docs: Ansible 명령어 및 opentofu 디렉토리 반영"
```

---

## Self-Review

### 1. Spec Coverage

| 스펙 요구사항 | Task |
| :--- | :--- |
| VCN 10.210.0.0/16 | Task 4 |
| Public Subnet 10.210.0.0/24 | Task 4 |
| Private Subnet 10.210.1.0/24 | Task 4 |
| Internet Gateway | Task 4 |
| Service Gateway | Task 4 |
| Route Tables (Public/Private) | Task 4 |
| Security Lists (Public/Private) | Task 4 |
| AMD Micro (lt) VM.Standard.E2.1.Micro | Task 6 |
| ARM A1 (brla) VM.Standard.A1.Flex 4/24 | Task 6 |
| Ubuntu 24.04 LTS | Task 3 + Task 6 |
| Block Volume 64GB → /home/ubuntu | Task 7 + Task 12 |
| cloud-init Tailscale | Task 5 + Task 6 |
| Tailscale exit node (AMD) | Task 5 + Task 11 |
| Docker Compose (ARM) | Task 12 |
| code-server 컨테이너 | Task 13 |
| Hermes 컨테이너 | Task 14 |
| Ansible playbook | Task 15 |
| Tailscale HTTPS (bun-bull.ts.net) | Task 11 |
| tf-infra → opentofu | Task 1 |
| outputs → Ansible inventory | Task 8 |

### 2. Placeholder Scan

- TBD/TODO 없음 ✅
- "Add appropriate error handling" 없음 ✅
- 모든 코드 블록에 실제 내용 포함 ✅

### 3. Type Consistency

- 변수명 `tailscale_auth_key`, `private_subnet_cidr`, `ssh_public_key` 모든 파일에서 일관 ✅
- 호스트명 `lt`, `brla` 일관 ✅
- 디바이스 경로 `/dev/oracleoci/oraclevdb` 일관 ✅
