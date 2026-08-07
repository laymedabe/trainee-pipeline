# Output the IP addresses of the provisioned VMs
output "node_ips" {
  value = {
    for idx, domain in libvirt_domain.pa_node : domain.name => domain.network_interface[0].addresses[0]
  }
  description = "The IP addresses of the deployed nodes"
}

# Generate Ansible dynamic inventory
resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/templates/inventory.tpl", {
    nodes = {
      for idx, domain in libvirt_domain.pa_node : domain.name => domain.network_interface[0].addresses[0]
    }
  })
  filename = "${path.module}/../ansible/inventory/hosts.ini"
}
