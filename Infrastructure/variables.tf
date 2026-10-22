variable "resource_group_name" {
  description = "Name of the shared resource group for the Windows VM deployment."
  type        = string
  default     = "rg-spot-vms"
}

variable "location" {
  description = "Azure region for the shared resource group."
  type        = string
  default     = "polandcentral"
}

variable "windows_vm_size" {
  description = "Azure VM size shared by all four Windows Spot VMs."
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

variable "rdp_source_cidr" {
  description = "Single public IPv4 CIDR allowed to access the VMs over RDP."
  type        = string
  default     = "91.150.218.97/32"

  validation {
    condition     = can(cidrnetmask(var.rdp_source_cidr)) && can(regex("/32$", var.rdp_source_cidr))
    error_message = "rdp_source_cidr must be a single IPv4 address with a /32 mask."
  }
}

variable "tags" {
  description = "Tags applied to supported resources."
  type        = map(string)
  default     = {}
}
