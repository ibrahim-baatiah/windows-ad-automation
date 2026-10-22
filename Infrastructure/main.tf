terraform {
  required_version = ">= 1.5.0"

  backend "azurerm" {
    storage_account_name = "tfblobcontainer"
    container_name       = "win-terraform"
    key                  = "windows-ad-automation.tfstate"
    use_azuread_auth     = true
    use_cli              = true
  }

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.2.0, < 5.0.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.6.0, < 4.0.0"
    }
  }
}

provider "azurerm" {
  features {}
}

locals {
  vnet_prefixes = {
    DC01   = "10.30.0.0/16"
    CA01   = "10.31.0.0/16"
    CA02   = "10.32.0.0/16"
    SRV1   = "10.33.0.0/16"
    POLAND = "172.16.0.0/16"
  }

  windows_vms = {
    DC01 = {
      location      = "switzerlandnorth"
      address_space = "10.30.0.0/16"
      subnet_prefix = "10.30.1.0/24"
    }
    CA01 = {
      location      = "germanywestcentral"
      address_space = "10.31.0.0/16"
      subnet_prefix = "10.31.1.0/24"
    }
    CA02 = {
      location      = "francecentral"
      address_space = "10.32.0.0/16"
      subnet_prefix = "10.32.1.0/24"
    }
    SRV1 = {
      location      = "northeurope"
      address_space = "10.33.0.0/16"
      subnet_prefix = "10.33.1.0/24"
    }
  }

  peering_pairs = {
    dc01_to_ca01 = { local = "DC01", remote = "CA01" }
    ca01_to_dc01 = { local = "CA01", remote = "DC01" }
    dc01_to_ca02 = { local = "DC01", remote = "CA02" }
    ca02_to_dc01 = { local = "CA02", remote = "DC01" }
    dc01_to_srv1 = { local = "DC01", remote = "SRV1" }
    srv1_to_dc01 = { local = "SRV1", remote = "DC01" }
  }

  route_table_subnets = {
    DC01 = {
      location            = local.windows_vms.DC01.location
      subnet_id           = azurerm_subnet.windows["DC01"].id
      resource_group_name = var.resource_group_name
    }
    CA01 = {
      location            = local.windows_vms.CA01.location
      subnet_id           = azurerm_subnet.windows["CA01"].id
      resource_group_name = var.resource_group_name
    }
    CA02 = {
      location            = local.windows_vms.CA02.location
      subnet_id           = azurerm_subnet.windows["CA02"].id
      resource_group_name = var.resource_group_name
    }
    SRV1 = {
      location            = local.windows_vms.SRV1.location
      subnet_id           = azurerm_subnet.windows["SRV1"].id
      resource_group_name = var.resource_group_name
    }
    POLAND = {
      location            = data.azurerm_virtual_network.poland.location
      subnet_id           = data.azurerm_subnet.poland.id
      resource_group_name = var.resource_group_name
    }
  }

  route_entries = {
    for route in flatten([
      for source_name, source in local.route_table_subnets : [
        for destination_name, address_prefix in local.vnet_prefixes : {
          key            = "${source_name}-to-${destination_name}"
          source_name    = source_name
          destination    = destination_name
          address_prefix = address_prefix
          resource_group = source.resource_group_name
        } if destination_name != source_name
      ]
    ]) : route.key => route
  }
}

data "azurerm_virtual_network" "poland" {
  name                = "vnet-polandcentral-1"
  resource_group_name = "test"
}

data "azurerm_subnet" "poland" {
  name                 = "snet-polandcentral-1"
  virtual_network_name = data.azurerm_virtual_network.poland.name
  resource_group_name  = "test"
}

resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

resource "azurerm_virtual_network" "windows" {
  for_each = local.windows_vms

  name                = "${lower(each.key)}-vnet"
  address_space       = [each.value.address_space]
  location            = each.value.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
}

resource "azurerm_subnet" "windows" {
  for_each = local.windows_vms

  name                 = "${lower(each.key)}-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.windows[each.key].name
  address_prefixes     = [each.value.subnet_prefix]
}

resource "azurerm_network_security_group" "windows" {
  for_each = local.windows_vms

  name                = "${lower(each.key)}-nsg"
  location            = each.value.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags

  security_rule {
    name                       = "Allow-RDP-from-admin-IP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = var.rdp_source_cidr
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "windows" {
  for_each = local.windows_vms

  subnet_id                 = azurerm_subnet.windows[each.key].id
  network_security_group_id = azurerm_network_security_group.windows[each.key].id
}

resource "azurerm_virtual_network_peering" "windows" {
  for_each = local.peering_pairs

  name                      = "${lower(each.value.local)}-to-${lower(each.value.remote)}"
  resource_group_name       = azurerm_resource_group.main.name
  virtual_network_name      = azurerm_virtual_network.windows[each.value.local].name
  remote_virtual_network_id = azurerm_virtual_network.windows[each.value.remote].id

  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = false
}

resource "azurerm_subnet" "router" {
  name                 = "dc01-router-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.windows["DC01"].name
  address_prefixes     = ["10.30.2.0/24"]
}

resource "random_password" "router_admin" {
  length           = 32
  special          = true
  override_special = "_%@-"
}

resource "azurerm_network_interface" "router" {
  name                  = "dc01-router-nic"
  location              = local.windows_vms.DC01.location
  resource_group_name   = azurerm_resource_group.main.name
  ip_forwarding_enabled = true
  tags                  = var.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.router.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.30.2.4"
  }
}

resource "azurerm_linux_virtual_machine" "router" {
  name                            = "dc01-router"
  computer_name                   = "dc01-router"
  resource_group_name             = azurerm_resource_group.main.name
  location                        = local.windows_vms.DC01.location
  size                            = "Standard_F1s"
  priority                        = "Spot"
  eviction_policy                 = "Deallocate"
  max_bid_price                   = -1
  admin_username                  = "routeradmin"
  admin_password                  = random_password.router_admin.result
  disable_password_authentication = false
  network_interface_ids           = [azurerm_network_interface.router.id]
  custom_data                     = base64encode(file("${path.module}/router-cloud-init.yaml"))
  tags                            = var.tags

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  os_disk {
    name                 = "dc01-router-osdisk"
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }
}

resource "azurerm_route_table" "spokes" {
  for_each = local.route_table_subnets

  name                = "${lower(each.key)}-router-rt"
  location            = each.value.location
  resource_group_name = each.value.resource_group_name
  tags                = var.tags
}

resource "azurerm_route" "through_dc01_router" {
  for_each = local.route_entries

  name                   = "${lower(each.value.source_name)}-to-${lower(each.value.destination)}"
  resource_group_name    = local.route_table_subnets[each.value.source_name].resource_group_name
  route_table_name       = azurerm_route_table.spokes[each.value.source_name].name
  address_prefix         = each.value.address_prefix
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = azurerm_network_interface.router.private_ip_address
}

resource "azurerm_subnet_route_table_association" "through_dc01_router" {
  for_each = local.route_table_subnets

  subnet_id      = each.value.subnet_id
  route_table_id = azurerm_route_table.spokes[each.key].id
}

resource "azurerm_public_ip" "windows" {
  for_each = local.windows_vms

  name                = "${lower(each.key)}-pip"
  resource_group_name = azurerm_resource_group.main.name
  location            = each.value.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_network_interface" "windows" {
  for_each = local.windows_vms

  name                = "${lower(each.key)}-nic"
  location            = each.value.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.windows[each.key].id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.windows[each.key].id
  }
}

resource "azurerm_windows_virtual_machine" "windows" {
  for_each = local.windows_vms

  name                = each.key
  computer_name       = each.key
  resource_group_name = azurerm_resource_group.main.name
  location            = each.value.location
  size                = var.windows_vm_size
  priority            = "Spot"
  eviction_policy     = "Deallocate"
  max_bid_price       = -1
  admin_username      = var.windows_admin_username
  admin_password      = var.admin_password
  network_interface_ids = [
    azurerm_network_interface.windows[each.key].id
  ]

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter-g2"
    version   = "latest"
  }

  os_disk {
    name                 = "${lower(each.key)}-osdisk"
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  tags = var.tags
}
