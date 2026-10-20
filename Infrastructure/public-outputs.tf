output "windows_public_ip_addresses" {
  description = "Public IP addresses of the three Windows VMs."
  value = {
    for name, ip in azurerm_public_ip.windows :
    name => ip.ip_address
  }
}

output "linux_public_ip_address" {
  description = "Public IP address of the Linux VM."
  value       = azurerm_public_ip.linux.ip_address
}

output "allowed_admin_public_ip" {
  description = "Public IPv4 address allowed to connect to SSH and RDP."
  value       = trimspace(data.http.current_public_ip.response_body)
}
