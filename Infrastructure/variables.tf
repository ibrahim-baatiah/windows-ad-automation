variable "subscription_id" {
  description = "Azure subscription to deploy into."
  type        = string
  default     = "9248b49a-6e5f-4ce1-b906-cd5b6baf80cf"
}

variable "resource_group_name" {
  description = "Resource group that holds every lab resource."
  type        = string
  default     = "sysvol-lab"
}

variable "windows_source_image_id" {
  description = "Managed image (Poland Central) used for the three Windows VMs."
  type        = string
  default     = "/subscriptions/9248b49a-6e5f-4ce1-b906-cd5b6baf80cf/resourceGroups/test/providers/Microsoft.Compute/images/win-winrm-image"
}

variable "windows_image_version" {
  description = "Compute Gallery image version created from the managed image."
  type        = string
  default     = "1.0.0"
}

variable "windows_vm_size" {
  description = "Size of the Windows Spot VMs (2 vCPU)."
  type        = string
  default     = "Standard_D2s_v5"
}

variable "ubuntu_vm_size" {
  description = "Size of the Ubuntu router Spot VM (1 vCPU)."
  type        = string
  default     = "Standard_F1s"
}

variable "client_vm_size" {
  description = "Size of the Windows 10 client Spot VM (1 vCPU, Gen1)."
  type        = string
  default     = "Standard_A1_v2"
}

variable "admin_username" {
  description = "Local administrator username for all VMs."
  type        = string
  default     = "azureadmin"
}

variable "admin_password" {
  description = "Administrator password for all VMs, used for RDP and SSH (12-72 characters)."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.admin_password) >= 12 && length(var.admin_password) <= 72
    error_message = "admin_password must be between 12 and 72 characters."
  }
}

variable "admin_source_cidr" {
  description = "Public IPv4 CIDR allowed to RDP to the Windows VMs and SSH to the Ubuntu router."
  type        = string
  default     = "91.150.218.97/32"

  validation {
    condition     = can(cidrnetmask(var.admin_source_cidr))
    error_message = "admin_source_cidr must be a valid IPv4 CIDR."
  }
}

variable "mac_source_cidr" {
  description = "Public IPv4 CIDR of the Mac, allowed to RDP to the Windows VMs and SSH to the Ubuntu router."
  type        = string
  default     = "91.150.213.3/32"

  validation {
    condition     = can(cidrnetmask(var.mac_source_cidr))
    error_message = "mac_source_cidr must be a valid IPv4 CIDR."
  }
}

variable "vnet_dns_servers" {
  description = "Custom DNS servers for all VNets (for example the DC IPs once AD is installed). Empty uses Azure DNS."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags applied to supported resources."
  type        = map(string)
  default     = {}
}
