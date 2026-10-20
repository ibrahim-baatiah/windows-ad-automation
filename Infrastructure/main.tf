terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.2.0, < 5.0.0"
    }
  }
}

provider "azurerm" {
  features {}
}

locals {
  windows_vm_names = ["win-01", "win-02", "win-03"]
}

resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

resource "azurerm_virtual_network" "main" {
  name                = "${var.resource_group_name}-vnet"
  address_space       = ["10.20.0.0/16"]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
}

resource "azurerm_subnet" "main" {
  name                 = "workload"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.20.1.0/24"]
}

resource "azurerm_network_interface" "windows" {
  for_each = toset(local.windows_vm_names)

  name                = "${each.key}-nic"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.main.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_network_interface" "linux" {
  name                = "linux-01-nic"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.main.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_windows_virtual_machine" "main" {
  for_each = toset(local.windows_vm_names)

  name                = each.key
  computer_name       = each.key
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  size                = var.windows_vm_size
  admin_username      = var.windows_admin_username
  admin_password      = var.admin_password
  network_interface_ids = [
    azurerm_network_interface.windows[each.key].id
  ]

  priority        = "Spot"
  eviction_policy = var.spot_eviction_policy
  max_bid_price   = var.spot_max_bid_price

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter"
    version   = "latest"
  }

  os_disk {
    name                 = "${each.key}-osdisk"
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  tags = var.tags
}

resource "azurerm_linux_virtual_machine" "main" {
  name                = "linux-01"
  computer_name       = "linux-01"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  size                = var.linux_vm_size
  admin_username      = var.linux_admin_username
  network_interface_ids = [
    azurerm_network_interface.linux.id
  ]

  disable_password_authentication = false
  admin_password                  = var.admin_password
  priority                        = "Spot"
  eviction_policy                 = var.spot_eviction_policy
  max_bid_price                   = var.spot_max_bid_price

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  os_disk {
    name                 = "linux-01-osdisk"
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  tags = var.tags
}
