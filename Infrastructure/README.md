# Azure VM infrastructure

Terraform in this directory provisions four regular (non-Spot) virtual
machines in Azure: three Windows VMs from a custom managed image and one
Ubuntu Linux VM. It also creates the resource group, network, public IP
addresses, and subnet-level network security group (NSG).

> **Deployment status:** The previous deployment was destroyed. The Azure
> deployment resource group and its resources were confirmed removed. Run
> `terraform apply` to create the infrastructure again.

## What gets created

| Resource | Configuration |
| --- | --- |
| Resource group | Configurable name and Azure region |
| Virtual network | One VNet with a private IPv4 address space |
| Subnet | One subnet shared by all four VMs |
| Windows VMs | Three regular, non-Spot VMs |
| Windows image | Generalized Windows Gen2 managed image, described below |
| Linux VM | Ubuntu Server 22.04 LTS Gen2; regular, non-Spot |
| VM sizes | `Standard_D2s_v5` for Windows and Linux by default |
| Network interfaces | One per VM, with a dynamic private IPv4 address |
| Public IPs | One Standard SKU, static IPv4 address per VM |
| Network security | One NSG associated with the shared subnet |
| New OS disks | Standard SSD LRS; the managed image's original source disk uses Premium LRS |

All four VMs are in the same subnet. Each receives a public IP; inbound access
is restricted by the subnet NSG.

## Windows managed image

The Windows VMs use a generalized Windows Gen2 Azure managed image. Its
resource ID is configured in `main.tf` and is intentionally omitted from this
README. Keep the source image available, and ensure the deploying identity can
read and use it, for as long as Terraform may need to create or replace the
Windows VMs. The image must also be available in a region compatible with the
VM deployment.

Terraform's `source_image_id` uses the managed image directly. The VM
configuration does not explicitly enable Trusted Launch for this image.
Successful provisioning still depends on the source image having been
correctly prepared and generalized for Azure VM deployment, including a
working Azure VM Agent.

## Network access and security

The NSG is associated with the subnet and contains these inbound allow rules:

| Protocol | Port | Source |
| --- | ---: | --- |
| TCP | 22 (SSH) | Current public IPv4 address detected by Terraform, as a `/32` |
| TCP | 3389 (RDP) | Current public IPv4 address detected by Terraform, as a `/32` |

The current public IPv4 address is fetched from `https://api4.ipify.org` by
the Terraform HTTP provider during planning/applying. An internet connection
is required. The detected address is the egress address visible to that
service; VPNs, proxies, NAT gateways, or changing ISP addresses can affect
which address you need. Check the `allowed_admin_public_ip` output before
applying. If your public IP changes, run Terraform again to update the NSG.

The NSG is subnet-scoped: it allows both ports to all interfaces in the
subnet, subject to the guest OS service listening on the port. Use a stable
trusted source IP; do not replace the source with `*` or a broad range. For
production access, consider private connectivity such as VPN or Azure Bastion
instead of exposing VM public IPs.

## Authentication and password handling

The same Terraform variable, `admin_password`, is used for the Windows local
administrator and Linux account password. It is marked `sensitive` in
Terraform, which hides it in many CLI displays, but Terraform state can still
contain the secret in plaintext. Protect state files and state backups, restrict
access to them, and use a secured remote backend for shared or production
deployments.

Do not commit real passwords or `terraform.tfvars`. Use a strong, unique
password that satisfies Windows and Linux password requirements. If the
password previously used for this deployment was shared or reused, rotate it
before deploying.

Supply the password using either a local ignored `terraform.tfvars` file:

```hcl
admin_password = "REPLACE_WITH_A_STRONG_UNIQUE_PASSWORD"
```

or an environment variable. In a shell, set it without placing the secret in
Terraform source code:

```sh
export TF_VAR_admin_password='REPLACE_WITH_A_STRONG_UNIQUE_PASSWORD'
```

Unset the environment variable when finished:

```sh
unset TF_VAR_admin_password
```

Other settings can be supplied in `terraform.tfvars`, for example:

```hcl
resource_group_name    = "your-resource-group"
location               = "your-azure-region"
windows_vm_size        = "Standard_D2s_v5"
linux_vm_size          = "Standard_D2s_v5"
windows_admin_username = "azureadmin"
linux_admin_username   = "azureuser"
```

The repository currently does not include a `terraform.tfvars.example` file.
Create a local `terraform.tfvars` if you want to override defaults, and ensure
that it is excluded from source control.

## Requirements

- Terraform 1.5 or later
- Azure CLI installed and signed in (`az login`), or another supported AzureRM
  provider authentication method
- Azure permissions to create resource groups, networking resources, public
  IPs, and virtual machines in the selected subscription
- Permission to use the Windows managed image in the `test` resource group
- Internet access for the public-IP detection request

Terraform uses the AzureRM provider (`>= 4.2.0, < 5.0.0`) and HTTP provider
(`>= 3.4.0, < 4.0.0`). The lock file records the selected provider builds.

## Deploy

From this directory, authenticate and choose the intended subscription:

```sh
az login
az account set --subscription "<subscription-id>"
az account show --output table
```

Set the sensitive password as described above, then initialize, validate, and
review the plan:

```sh
terraform init
terraform fmt -check
terraform validate
terraform plan
```

Review the complete plan, especially the resource group, image ID, detected
source IP, VM count, and estimated charges. Create resources only after
reviewing the plan:

```sh
terraform apply
```

Terraform may ask for confirmation. Use `-auto-approve` only when you have
already reviewed the plan and intentionally want to skip that confirmation.

## Outputs

After a successful apply, Terraform provides:

- `resource_group_name`: resource group name
- `virtual_network_id`: VNet resource ID
- `windows_private_ip_addresses`: private IPs keyed by Windows VM name
- `linux_private_ip_address`: Linux private IP
- `windows_public_ip_addresses`: public IPs keyed by Windows VM name
- `linux_public_ip_address`: Linux public IP
- `allowed_admin_public_ip`: detected source address permitted by the NSG

Use the Windows public IPs for RDP and the Linux public IP for SSH. The
administrator usernames are `windows_admin_username` and
`linux_admin_username`, respectively.

## Destroy

To delete the Terraform-managed deployment, first inspect the destroy plan:

```sh
terraform plan -destroy
```

If it lists only resources you intend to remove, run:

```sh
terraform destroy
```

This removes the Terraform-managed resource group and its resources. It does
not delete the source managed image in resource group `test`. Detached disks,
manually created objects, or other untracked resources may not be removed by a
Terraform destroy; inspect the target resource group in Azure after
destruction.

## Cost and operational notes

These are regular, non-Spot VMs, so compute is billed while the VMs are
allocated, including when stopped from inside the guest OS. Deallocating a VM
stops compute billing, but managed disks and some networking resources can
continue to incur charges. Standard static public IPs and OS disks can also
incur charges. Check Azure pricing and your subscription's quotas before
deployment.

This configuration does not create backups, monitoring, a remote Terraform
state backend, or high availability. Treat the VMs as interruptible only if
you separately change their priority to Spot; the current configuration
creates regular VMs.
