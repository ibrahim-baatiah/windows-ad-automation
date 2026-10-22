# Azure Windows PKI lab

Terraform deploys four raw Windows Server 2022 Datacenter Gen2 Spot VMs. It
does not install or configure Active Directory, DNS, Certificate Services,
or IIS; those roles are configured separately after deployment.

| VM | Intended role | Region |
| --- | --- | --- |
| `DC01` | Domain controller and DNS | Switzerland North |
| `CA01` | Standalone offline Root CA | Germany West Central |
| `CA02` | Enterprise Issuing CA | France Central |
| `SRV1` | HTTP CDP/AIA web server | North Europe |

The VMs share a resource group located in Poland Central. Each VM has its own
regional VNet and subnet. DC01 is the hub, bidirectionally peered with CA01,
CA02, SRV1, and the existing Poland Central VNet. A private-only, one-vCPU
Ubuntu router in a dedicated DC01 subnet forwards inter-VNet traffic using
UDRs attached to all five workload subnets. The spokes are not peered with one
another.

Each Windows VM has a public IP, with inbound RDP limited to
`91.150.218.97/32` by default. The Linux router has no public IP and is
administered with Azure Run Command. Existing Windows NSGs are unchanged and
retain Azure's default allow rule for traffic from connected VNet address
spaces, in addition to the explicit RDP rule from the admin IP.

> **CA01 note:** Because CA01 is peered and has a public IP with RDP access,
> it is not an offline Root CA. Remove its peering and public IP before
> treating it as offline.

The Poland route table is attached to the existing `172.16.0.0/24` subnet in
resource group `test`, which contains VM `test23`. Terraform manages the route
table and subnet association, not the Poland VNet or VM. The Linux router is
regular (non-Spot) to avoid eviction interrupting routing; the four Windows
VMs remain Spot instances.

All VMs use Spot priority and can be evicted by Azure without notice. This
can interrupt domain-controller or certificate-authority services. Global
VNet peering and public IPs may incur additional charges.

## Deploy

See [`Infrastructure/README.md`](./Infrastructure/README.md) for requirements,
credential handling, Terraform commands, network details, outputs, and destroy
instructions.

From the repository root:

```powershell
az login
az account set --subscription "<subscription-id>"
Set-Location Infrastructure
terraform init
terraform fmt -check
terraform validate
terraform plan
terraform apply
```

Set a strong, unique `admin_password` in the ignored local
`Infrastructure/terraform.tfvars` file or through `TF_VAR_admin_password`.
Never commit credentials or Terraform state.
