resource "azurerm_virtual_network" "lab" {
  for_each = local.regions

  name                = "vnet-${each.key}"
  location            = each.value.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = [each.value.address_space]
  dns_servers         = var.vnet_dns_servers
  tags                = var.tags
}

resource "azurerm_subnet" "workload" {
  for_each = local.regions

  name                 = "snet-${each.key}-workload"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.lab[each.key].name
  address_prefixes     = [each.value.subnet_prefix]
}

resource "azurerm_subnet" "nva" {
  name                 = "snet-${local.hub_key}-nva"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.lab[local.hub_key].name
  address_prefixes     = [local.nva_subnet_prefix]
}

# Network security groups

resource "azurerm_network_security_group" "workload" {
  for_each = local.regions

  name                = "nsg-${each.key}-workload"
  location            = each.value.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags

  security_rule {
    name                       = "Allow-RDP-from-admin-IP"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = var.admin_source_cidr
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-RDP-from-Mac"
    priority                   = 210
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = var.mac_source_cidr
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "workload" {
  for_each = local.regions

  subnet_id                 = azurerm_subnet.workload[each.key].id
  network_security_group_id = azurerm_network_security_group.workload[each.key].id
}

resource "azurerm_network_security_group" "nva" {
  name                = "nsg-${local.hub_key}-nva"
  location            = local.hub.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags

  security_rule {
    name                       = "Allow-SSH-from-admin-IP"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.admin_source_cidr
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-SSH-from-Mac"
    priority                   = 210
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.mac_source_cidr
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "nva" {
  subnet_id                 = azurerm_subnet.nva.id
  network_security_group_id = azurerm_network_security_group.nva.id
}

# Hub-and-spoke peering

resource "azurerm_virtual_network_peering" "lab" {
  for_each = local.peerings

  name                      = "peer-${each.key}"
  resource_group_name       = azurerm_resource_group.main.name
  virtual_network_name      = azurerm_virtual_network.lab[each.value.local].name
  remote_virtual_network_id = azurerm_virtual_network.lab[each.value.remote].id

  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = false
}

# Route tables: every other region is reached through the Ubuntu router.
# The NVA subnet has no route table.

resource "azurerm_route_table" "workload" {
  for_each = local.regions

  name                = "rt-${each.key}-workload"
  location            = each.value.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
}

resource "azurerm_route" "via_nva" {
  for_each = local.inter_region_routes

  name                   = "to-${each.value.destination}"
  resource_group_name    = azurerm_resource_group.main.name
  route_table_name       = azurerm_route_table.workload[each.value.source].name
  address_prefix         = each.value.address_prefix
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = local.nva_private_ip
}

resource "azurerm_subnet_route_table_association" "workload" {
  for_each = local.regions

  subnet_id      = azurerm_subnet.workload[each.key].id
  route_table_id = azurerm_route_table.workload[each.key].id
}

# Renames from the earlier spoke-only routing. Safe to delete after one apply.

moved {
  from = azurerm_route_table.spoke["swiss"]
  to   = azurerm_route_table.workload["swiss"]
}

moved {
  from = azurerm_route_table.spoke["germany"]
  to   = azurerm_route_table.workload["germany"]
}

moved {
  from = azurerm_subnet_route_table_association.spoke["swiss"]
  to   = azurerm_subnet_route_table_association.workload["swiss"]
}

moved {
  from = azurerm_subnet_route_table_association.spoke["germany"]
  to   = azurerm_subnet_route_table_association.workload["germany"]
}

moved {
  from = azurerm_route.spoke_via_nva["swiss-to-germany"]
  to   = azurerm_route.via_nva["swiss-to-germany"]
}

moved {
  from = azurerm_route.spoke_via_nva["germany-to-swiss"]
  to   = azurerm_route.via_nva["germany-to-swiss"]
}
