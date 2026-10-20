output "resource_group_name" {
  description = "Name of the resource group containing the deployment."
  value       = azurerm_resource_group.main.name
}

output "virtual_network_id" {
  description = "ID of the shared virtual network."
  value       = azurerm_virtual_network.main.id
}

output "windows_private_ip_addresses" {
  description = "Private IP addresses of the three Windows Spot VMs."
  value = {
    for name, nic in azurerm_network_interface.windows :
    name => nic.private_ip_address
  }
}

output "linux_private_ip_address" {
  description = "Private IP address of the Linux Spot VM."
  value       = azurerm_network_interface.linux.private_ip_address
}
