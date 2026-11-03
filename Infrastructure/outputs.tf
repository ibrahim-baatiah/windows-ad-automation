output "resource_group_name" {
  description = "Resource group holding the lab."
  value       = azurerm_resource_group.main.name
}

output "windows_vms" {
  description = "Windows VMs keyed by name, with region and IP addresses."
  value = {
    for key, region in local.regions : region.windows_vm => {
      location   = region.location
      private_ip = azurerm_network_interface.windows[key].private_ip_address
      public_ip  = azurerm_public_ip.windows[key].ip_address
    }
  }
}

output "nva" {
  description = "Ubuntu router in the Poland hub."
  value = {
    private_ip = azurerm_network_interface.nva.private_ip_address
    public_ip  = azurerm_public_ip.nva.ip_address
  }
}

output "vnet_address_spaces" {
  description = "VNet address space keyed by region."
  value       = { for key, region in local.regions : key => region.address_space }
}

output "windows_image_version_id" {
  description = "Compute Gallery image version used by the Windows VMs."
  value       = azurerm_shared_image_version.windows.id
}

output "client_vm" {
  description = "Windows 10 client VM, to be joined to the domain."
  value = {
    name       = azurerm_windows_virtual_machine.client.name
    location   = azurerm_windows_virtual_machine.client.location
    private_ip = azurerm_network_interface.client.private_ip_address
    public_ip  = azurerm_public_ip.client.ip_address
  }
}
