# A managed image can only be deployed in its own region (Poland Central).
# Publish it to an Azure Compute Gallery and replicate it to every lab region.

resource "azurerm_shared_image_gallery" "lab" {
  name                = "gal_sysvol_lab"
  location            = local.hub.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
}

resource "azurerm_shared_image" "windows" {
  name                = "win-winrm"
  gallery_name        = azurerm_shared_image_gallery.lab.name
  resource_group_name = azurerm_resource_group.main.name
  location            = local.hub.location
  os_type             = "Windows"
  hyper_v_generation  = "V2"
  tags                = var.tags

  identifier {
    publisher = "sysvol-lab"
    offer     = "windows-server"
    sku       = "win-winrm"
  }
}

resource "azurerm_shared_image_version" "windows" {
  name                = var.windows_image_version
  gallery_name        = azurerm_shared_image_gallery.lab.name
  image_name          = azurerm_shared_image.windows.name
  resource_group_name = azurerm_resource_group.main.name
  location            = local.hub.location
  managed_image_id    = var.windows_source_image_id
  tags                = var.tags

  dynamic "target_region" {
    for_each = local.regions

    content {
      name                   = target_region.value.location
      regional_replica_count = 1
      storage_account_type   = "Standard_LRS"
    }
  }
}

# Windows VMs, one per region

resource "azurerm_public_ip" "windows" {
  for_each = local.regions

  name                = "pip-${lower(each.value.windows_vm)}"
  location            = each.value.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_network_interface" "windows" {
  for_each = local.regions

  name                = "nic-${lower(each.value.windows_vm)}"
  location            = each.value.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.workload[each.key].id
    private_ip_address_allocation = "Static"
    private_ip_address            = each.value.windows_ip
    public_ip_address_id          = azurerm_public_ip.windows[each.key].id
  }
}

resource "azurerm_windows_virtual_machine" "windows" {
  for_each = local.regions

  name                  = each.value.windows_vm
  computer_name         = each.value.windows_vm
  location              = each.value.location
  resource_group_name   = azurerm_resource_group.main.name
  size                  = var.windows_vm_size
  priority              = "Spot"
  eviction_policy       = "Deallocate"
  max_bid_price         = -1
  admin_username        = var.admin_username
  admin_password        = var.admin_password
  source_image_id       = azurerm_shared_image_version.windows.id
  network_interface_ids = [azurerm_network_interface.windows[each.key].id]
  tags                  = var.tags

  os_disk {
    name                 = "osdisk-${lower(each.value.windows_vm)}"
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }
}

# Ubuntu router (NVA) in the Poland hub

resource "azurerm_public_ip" "nva" {
  name                = "pip-nva01"
  location            = local.hub.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_network_interface" "nva" {
  name                  = "nic-nva01"
  location              = local.hub.location
  resource_group_name   = azurerm_resource_group.main.name
  ip_forwarding_enabled = true
  tags                  = var.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.nva.id
    private_ip_address_allocation = "Static"
    private_ip_address            = local.nva_private_ip
    public_ip_address_id          = azurerm_public_ip.nva.id
  }
}

resource "azurerm_linux_virtual_machine" "nva" {
  name                            = "NVA01"
  computer_name                   = "nva01"
  location                        = local.hub.location
  resource_group_name             = azurerm_resource_group.main.name
  size                            = var.ubuntu_vm_size
  priority                        = "Spot"
  eviction_policy                 = "Deallocate"
  max_bid_price                   = -1
  admin_username                  = var.admin_username
  admin_password                  = var.admin_password
  disable_password_authentication = false
  network_interface_ids           = [azurerm_network_interface.nva.id]
  custom_data                     = base64encode(file("${path.module}/nva-cloud-init.yaml"))
  tags                            = var.tags

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  os_disk {
    name                 = "osdisk-nva01"
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }
}
