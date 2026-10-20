variable "resource_group_name" {
  description = "Name of the new resource group."
  type        = string
  default     = "rg-spot-vms"
}

variable "location" {
  description = "Azure region for the resource group and virtual machines."
  type        = string
  default     = "eastus"
}

variable "windows_vm_size" {
  description = "Azure VM size for all three Windows Spot VMs."
  type        = string
  default     = "Standard_D2s_v5"
}

variable "linux_vm_size" {
  description = "Azure VM size for the Linux Spot VM."
  type        = string
  default     = "Standard_D2s_v5"
}

variable "windows_admin_username" {
  description = "Local administrator username for the Windows VMs."
  type        = string
  default     = "azureadmin"
}

variable "admin_password" {
  description = "Shared local administrator password for all four VMs (12-72 characters)."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.admin_password) >= 12 && length(var.admin_password) <= 72
    error_message = "The shared administrator password must be between 12 and 72 characters."
  }
}

variable "linux_admin_username" {
  description = "SSH administrator username for the Linux VM."
  type        = string
  default     = "azureuser"
}

variable "spot_eviction_policy" {
  description = "Whether an evicted Spot VM is deallocated (retaining its disks) or deleted."
  type        = string
  default     = "Deallocate"

  validation {
    condition     = contains(["Deallocate", "Delete"], var.spot_eviction_policy)
    error_message = "spot_eviction_policy must be Deallocate or Delete."
  }
}

variable "spot_max_bid_price" {
  description = "Maximum hourly Spot price in USD; -1 means up to the pay-as-you-go price."
  type        = number
  default     = -1

  validation {
    condition     = var.spot_max_bid_price == -1 || var.spot_max_bid_price >= 0
    error_message = "spot_max_bid_price must be -1 or a non-negative number."
  }
}

variable "tags" {
  description = "Tags applied to supported resources."
  type        = map(string)
  default     = {}
}
