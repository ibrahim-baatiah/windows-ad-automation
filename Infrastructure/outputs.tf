output "resource_group_name" {
  description = "Name of the resource group containing the deployment."
  value       = azurerm_resource_group.main.name
}

output "virtual_network_ids" {
  description = "Virtual network IDs keyed by VM name."
  value = {
    for name, network in azurerm_virtual_network.windows :
    name => network.id
  }
}

output "windows_private_ip_addresses" {
  description = "Private IP addresses keyed by VM name."
  value = {
    for name, nic in azurerm_network_interface.windows :
    name => nic.private_ip_address
  }
}

output "windows_public_ip_addresses" {
  description = "Public IP addresses keyed by VM name."
  value = {
    for name, ip in azurerm_public_ip.windows :
    name => ip.ip_address
  }
}

output "allowed_rdp_source_cidr" {
  description = "Public IPv4 CIDR allowed to connect to the VMs over RDP."
  value       = var.rdp_source_cidr
}

output "dc01_router_private_ip_address" {
  description = "Private IP address of the DC01 VNet router."
  value       = azurerm_network_interface.router.private_ip_address
}

output "router_route_table_ids" {
  description = "Route table IDs applied to each VM subnet, including the Poland VNet subnet."
  value = {
    for name, route_table in azurerm_route_table.spokes :
    name => route_table.id
  }
}
