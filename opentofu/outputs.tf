# opentofu/outputs.tf

# AMD Micro (lt)
output "lt_public_ip" {
  description = "AMD Micro(lt) 공용 IP"
  value       = oci_core_instance.lt.public_ip
}

# ARM A1 (brla)
output "brla_private_ip" {
  description = "ARM A1(brla) 사설 IP"
  value       = oci_core_instance.brla.private_ip
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
  value       = "/data"
}
