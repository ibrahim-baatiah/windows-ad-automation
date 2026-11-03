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
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

locals {
  hub_key = "poland"

  # One VNet per region. Poland is the hub; the others are spokes.
  regions = {
    poland = {
      location      = "polandcentral"
      address_space = "10.10.0.0/16"
      subnet_prefix = "10.10.1.0/24"
      windows_vm    = "DC01"
      windows_ip    = "10.10.1.4"
    }
    swiss = {
      location      = "switzerlandnorth"
      address_space = "10.20.0.0/16"
      subnet_prefix = "10.20.1.0/24"
      windows_vm    = "DC02"
      windows_ip    = "10.20.1.4"
    }
    germany = {
      location      = "germanywestcentral"
      address_space = "10.30.0.0/16"
      subnet_prefix = "10.30.1.0/24"
      windows_vm    = "DC03"
      windows_ip    = "10.30.1.4"
    }
  }

  spokes = { for key, region in local.regions : key => region if key != local.hub_key }
  hub    = local.regions[local.hub_key]

  # The Ubuntu router lives in its own hub subnet, which has no UDR.
  nva_subnet_prefix = "10.10.2.0/24"
  nva_private_ip    = "10.10.2.4"

  # Hub <-> spoke peerings, both directions.
  peerings = merge(
    { for key, _ in local.spokes : "${local.hub_key}-to-${key}" => { local = local.hub_key, remote = key } },
    { for key, _ in local.spokes : "${key}-to-${local.hub_key}" => { local = key, remote = local.hub_key } },
  )

  # All traffic between regions is sent through the Ubuntu router.
  inter_region_routes = {
    for route in flatten([
      for source, _ in local.regions : [
        for destination, dest_region in local.regions : {
          key            = "${source}-to-${destination}"
          source         = source
          destination    = destination
          address_prefix = dest_region.address_space
        } if destination != source
      ]
    ]) : route.key => route
  }
}

resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = local.hub.location
  tags     = var.tags
}
