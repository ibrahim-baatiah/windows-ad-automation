# Windows 10 client (Spot) in the Germany workload subnet, to be joined to the
# domain with config-manager/join-domain.yml.

locals {
  client = {
    region     = "germany"
    name       = "CLIENT01"
    private_ip = "10.30.1.5"
  }

  # Marketplace images have no WinRM listener. Enable it for Ansible (run from
  # NVA01), reachable only from the lab VNets, and let local admins use it.
  client_winrm_script = <<-EOT
    $ErrorActionPreference = 'Stop'
    Get-NetConnectionProfile | Set-NetConnectionProfile -NetworkCategory Private
    Enable-PSRemoting -Force -SkipNetworkProfileCheck
    New-NetFirewallRule -Name 'WinRM-HTTP-Lab' -DisplayName 'WinRM HTTP from lab VNets' -Direction Inbound -Protocol TCP -LocalPort 5985 -RemoteAddress ${join(",", [for region in local.regions : region.address_space])} -Action Allow
    New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name LocalAccountTokenFilterPolicy -Value 1 -PropertyType DWord -Force
  EOT
}

resource "azurerm_public_ip" "client" {
  name                = "pip-${lower(local.client.name)}"
  location            = local.regions[local.client.region].location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_network_interface" "client" {
  name                = "nic-${lower(local.client.name)}"
  location            = local.regions[local.client.region].location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.workload[local.client.region].id
    private_ip_address_allocation = "Static"
    private_ip_address            = local.client.private_ip
    public_ip_address_id          = azurerm_public_ip.client.id
  }
}

resource "azurerm_windows_virtual_machine" "client" {
  name                  = local.client.name
  computer_name         = local.client.name
  location              = local.regions[local.client.region].location
  resource_group_name   = azurerm_resource_group.main.name
  size                  = var.client_vm_size
  priority              = "Spot"
  eviction_policy       = "Deallocate"
  max_bid_price         = -1
  license_type          = "Windows_Client"
  admin_username        = var.admin_username
  admin_password        = var.admin_password
  network_interface_ids = [azurerm_network_interface.client.id]
  tags                  = var.tags

  source_image_reference {
    publisher = "MicrosoftWindowsDesktop"
    offer     = "Windows-10"
    sku       = "win10-22h2-pro"
    version   = "latest"
  }

  os_disk {
    name                 = "osdisk-${lower(local.client.name)}"
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }
}

resource "azurerm_virtual_machine_extension" "client_winrm" {
  name                 = "enable-winrm"
  virtual_machine_id   = azurerm_windows_virtual_machine.client.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"
  tags                 = var.tags

  protected_settings = jsonencode({
    commandToExecute = "powershell.exe -NoProfile -ExecutionPolicy Bypass -EncodedCommand ${textencodebase64(local.client_winrm_script, "UTF-16LE")}"
  })
}
