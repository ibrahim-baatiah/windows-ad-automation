# Azure Spot VM infrastructure

This configuration creates a new resource group, one virtual network and subnet,
three regular (non-Spot) Windows Server 2022 VMs, and one regular (non-Spot)
Ubuntu 22.04 LTS VM. All four VMs share the subnet. The VMs have private IP
addresses only; no public IPs or inbound internet access are created.

## Requirements

- Terraform 1.5 or later
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

4. Review the plan, then run `terraform apply` to create the resources.

Because the VMs have no public IP addresses, connect from a network with access
to this VNet (for example, through VPN or peering). The same sensitive
`admin_password` variable configures password-based administrator access on
the Linux VM and local administrator access on the Windows VMs. Terraform
stores sensitive values in state, so protect the state file and use a secure
remote backend for shared or production use.
