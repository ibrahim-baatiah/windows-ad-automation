# Azure Spot VM infrastructure

This configuration creates a new resource group, one virtual network and subnet,
three regular (non-Spot) Windows VMs from the generalized Windows Gen2 managed
image `win-winrm-image`, and one regular (non-Spot) Ubuntu 22.04 LTS VM. All
four VMs share the subnet and each has a Standard static public IPv4 address.
Network security groups allow RDP to the Windows VMs and SSH to the Linux VM
only from the public IPv4 address detected when Terraform runs. One NSG is
associated with the shared subnet, so these inbound rules apply to all four
VMs.

## Requirements

- Terraform 1.5 or later
- An internet connection so Terraform can detect the current public IPv4
  address through `https://api4.ipify.org`
- Azure CLI authenticated to the intended subscription (`az login`), or another
  supported AzureRM provider authentication method
- A strong shared administrator password for all four VMs

## Configure and deploy

From this directory:

1. Copy `terraform.tfvars.example` to `terraform.tfvars` and set the shared
   `admin_password`, or supply it through the `TF_VAR_admin_password`
   environment variable. The password variable is marked sensitive. Do not
   commit real credentials; the local tfvars file is excluded from Git.
2. Change `location` if needed. VM size and image availability vary by region.
3. Run:

   ```sh
   terraform init
   terraform fmt -check
   terraform validate
   terraform plan
   ```

4. Review the plan, including the detected address in the
   `allowed_admin_public_ip` output, then run `terraform apply` to create the
   resources.

## Existing Windows VM recovery

The previous deployment left `win-01`, `win-02`, and `win-03` in Azure in a
deallocated state, but they are not tracked in the current Terraform state.
Import them before planning so Terraform can detect and replace them with the
managed-image versions instead of trying to create VMs with names that already
exist:

```sh
terraform import 'azurerm_windows_virtual_machine.main["win-01"]' '/subscriptions/9248b49a-6e5f-4ce1-b906-cd5b6baf80cf/resourceGroups/rg-spot-vms/providers/Microsoft.Compute/virtualMachines/win-01'
terraform import 'azurerm_windows_virtual_machine.main["win-02"]' '/subscriptions/9248b49a-6e5f-4ce1-b906-cd5b6baf80cf/resourceGroups/rg-spot-vms/providers/Microsoft.Compute/virtualMachines/win-02'
terraform import 'azurerm_windows_virtual_machine.main["win-03"]' '/subscriptions/9248b49a-6e5f-4ce1-b906-cd5b6baf80cf/resourceGroups/rg-spot-vms/providers/Microsoft.Compute/virtualMachines/win-03'
```

Then run `terraform plan` and confirm the Windows VMs are replaced before
applying. The new OS disks use distinct names so the detached disks from the
previous deployment won't conflict. Those old disks may continue to incur
storage charges until removed.

The detected address is the public IPv4 address visible to the IP-check
service. If you connect through a VPN, proxy, or changing ISP address, confirm
this is the address from which you will connect. Rerun `terraform apply` after
your public IP changes to update the NSG rules. Terraform contacts the IP-check
service during planning and applying. The public IP resources may incur Azure
charges.

Connect to Windows VMs over RDP (TCP 3389) and the Linux VM over SSH (TCP 22)
using their public IP outputs. The same sensitive `admin_password` variable
configures password-based administrator access on all four VMs. Terraform
stores sensitive values in state, so protect the state file and use a secure
remote backend for shared or production use.
