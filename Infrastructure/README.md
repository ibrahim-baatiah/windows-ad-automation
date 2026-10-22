# Azure Windows PKI lab infrastructure

Terraform provisions four raw Windows Server 2022 Datacenter Gen2 Spot VMs.
It does not install Active Directory, DNS, Certificate Services, or a web
server role; configure those inside the VMs after deployment.

| VM | Purpose | Azure region | Network |
| --- | --- | --- | --- |
| `DC01` | Domain controller / DNS | Switzerland North (`switzerlandnorth`) | Peered |
| `CA01` | Standalone offline root CA | Germany West Central (`germanywestcentral`) | Isolated, not peered |
| `CA02` | Enterprise issuing CA | France Central (`francecentral`) | Peered |
| `SRV1` | HTTP CDP/AIA web server | North Europe (`northeurope`) | Peered |

All resources are in the same resource group, whose location defaults to
Poland Central. Azure VNets are regional, so each VM has a separate VNet and
subnet in its own region. DC01 is the hub and has bidirectional global VNet
peering with each spoke: CA01, CA02, and SRV1. The spokes are not peered with
one another. The existing Poland Central VNet in resource group `test` is
included as a spoke.

## VM and network settings

- All VMs use `Standard_D2s_v5` by default, Spot priority, and deallocate on
  eviction. Spot capacity is not guaranteed; Azure can evict any VM, including
  the domain controller and certificate authorities.
- All VMs use the same Marketplace image reference:
  `MicrosoftWindowsServer / WindowsServer / 2022-datacenter-g2 / latest`.
- Each VM has a Standard static public IP and a Standard SSD LRS OS disk.
- Each subnet NSG allows inbound RDP (TCP 3389) only from
  `91.150.218.97/32` by default. No SSH or other inbound Internet access is
  configured on the Windows VMs. Update `rdp_source_cidr` if your public
  address changes.
- The existing `test23` VM is in `vnet-polandcentral-1` (`172.16.0.0/16`),
  resource group `test`. Terraform attaches a route table to its existing
  subnet, `172.16.0.0/24`.
- Global VNet peering can incur data-transfer charges.

## DC01 routing appliance

Terraform also creates a private-only Ubuntu 22.04 router VM (`dc01-router`)
in Switzerland North, in a dedicated `10.30.2.0/24` subnet of `dc01-vnet`.
It uses the one-vCPU `Standard_F1s` size, a static private address of
`10.30.2.4`, and regular (non-Spot) priority to avoid Spot eviction taking
down inter-VNet routing. Its NIC has Azure IP forwarding enabled. Cloud-init
enables Linux IPv4 forwarding and loose reverse-path filtering at boot.
Administration is through Azure Run Command; the VM has no public IP.

Route tables are created and associated with the workload subnet in each of
the five VNets. Each of the other VNet address prefixes is routed through
`10.30.2.4`, including the routes for traffic originating in DC01's workload
subnet. The router subnet itself has no UDR, so it can forward packets using
Azure's routes to the peered VNets. Peering permits forwarded traffic.

The existing NSGs are unchanged. In addition to the explicit RDP rule, the
Windows NSGs retain Azure's default `AllowVnetInBound` rule, which allows
traffic from the connected VNet address spaces; the route tables direct that
inter-VNet traffic through the router. The Poland subnet currently has no NSG.

CA01 is peered and has a public IP with an RDP rule, so it is not an offline
or network-isolated Root CA. Before using CA01 as an offline Root CA, remove
its public IP and VNet peering, and only bring it online for controlled
administration and certificate transfers. The Windows VMs are Spot instances
and may be evicted, so they are not suitable for reliable production
certificate authorities.

## Credentials and state

The same `admin_password` is set on all four VMs. Set a strong, unique
Windows-compatible password through an ignored local `terraform.tfvars` file
or `TF_VAR_admin_password`. Do not put it in source control. Terraform state
contains sensitive values. The Azure Storage backend stores state at
`tfblobcontainer/win-terraform/windows-ad-automation.tfstate` and authenticates
using the signed-in Azure CLI identity. Grant that identity the **Storage Blob
Data Contributor** role on the container (or a broader suitable scope). Enable
storage-account blob versioning and soft delete to support state recovery.
The router's Linux admin password is generated randomly and stored only in
the remote Terraform state; use Azure Run Command rather than SSH to administer
the private-only VM.

Example local `terraform.tfvars`:

```hcl
admin_password = "REPLACE_WITH_A_STRONG_UNIQUE_PASSWORD"
```

## Deploy

From this directory, authenticate to the intended subscription and initialize
the remote backend. On first initialization Terraform migrates any local state
to the configured blob:

```powershell
az login
az account set --subscription "<subscription-id>"
terraform init
terraform fmt -check
terraform validate
terraform plan
```

Confirm the VM regions, Spot settings, image, RDP source CIDR, and estimated
charges in the plan before applying. Use a newly rotated password; never reuse
a password that has been shared in chat or stored in a previously exposed
configuration:

```powershell
terraform apply
```

Outputs include each VM's private and public IP, each VNet ID, and the
permitted RDP source CIDR.

## Destroy

Inspect the destroy plan before removing the deployment:

```powershell
terraform plan -destroy
terraform destroy
```

This removes the Terraform-managed resource group and its resources, as well
as the route-table association Terraform manages on the existing Poland
subnet. The Poland VNet and VM are not Terraform-managed and are not deleted.
