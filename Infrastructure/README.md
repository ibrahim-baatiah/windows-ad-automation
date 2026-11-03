# sysvol-lab infrastructure

Terraform deploys a four-VM Spot lab into a single resource group,
`sysvol-lab` (Poland Central), across three regional VNets in a hub-and-spoke
topology.

| VM | OS / image | Size | Region | VNet | Private IP |
| --- | --- | --- | --- | --- | --- |
| `DC01` | `win-winrm-image` | `Standard_D2s_v5` (2 vCPU) | Poland Central | `vnet-poland` (hub) `10.10.0.0/16` | `10.10.1.4` |
| `DC02` | `win-winrm-image` | `Standard_D2s_v5` (2 vCPU) | Switzerland North | `vnet-swiss` (spoke) `10.20.0.0/16` | `10.20.1.4` |
| `DC03` | `win-winrm-image` | `Standard_D2s_v5` (2 vCPU) | Germany West Central | `vnet-germany` (spoke) `10.30.0.0/16` | `10.30.1.4` |
| `NVA01` | Ubuntu 24.04 LTS | `Standard_F1s` (1 vCPU) | Poland Central | `vnet-poland`, `snet-poland-nva` | `10.10.2.4` |

All four VMs are Spot (`max_bid_price = -1`, evict to deallocate). Each
region's Spot vCPU quota is 3, so Poland Central (2 + 1 vCPU) is at its limit.

## Windows image

The source managed image lives in Poland Central, and a managed image can only
be deployed in its own region. Terraform publishes it to the Azure Compute
Gallery `gal_sysvol_lab` as version `1.0.0` of `win-winrm`, replicated to all
three regions, and builds the Windows VMs from that version. Replication
makes the first apply take noticeably longer.

## Routing

- Swiss and Germany are each peered with Poland in both directions, with
  forwarded traffic allowed. They are not peered with each other.
- All traffic between regions goes through `NVA01`. Each workload subnet,
  including Poland's, has a route table that sends every other region's
  address space to `10.10.2.4`. The NVA subnet has no route table.
- IP forwarding is on in two places: on the NVA's NIC in Azure, and in Linux
  (`net.ipv4.ip_forward=1` through cloud-init, `nva-cloud-init.yaml`).

If `NVA01` is evicted, all traffic between regions stops until it is started
again.

## Security

- Traffic between regions is allowed by the default `AllowVnetInBound` rule.
  The `VirtualNetwork` tag covers both peered VNets and UDR prefixes.
- RDP (3389) to the Windows VMs and SSH (22) to `NVA01` are allowed only from
  `admin_source_cidr` (default `91.150.218.97/32`) and `mac_source_cidr`
  (default `91.150.213.3/32`). WinRM is reachable only from inside the lab
  VNets.
- The Windows image's firewall blocks ICMP echo, so ping fails even though
  routing works. Test with TCP (`Test-NetConnection <ip> -Port 3389`).
- `NVA01` uses SSH password authentication with `admin_username` and
  `admin_password`, the same credentials as the Windows VMs.

## DNS for Active Directory

The VNets start on Azure DNS. After promoting the domain controllers, point
all VNets at them and re-apply:

```hcl
vnet_dns_servers = ["10.10.1.4", "10.20.1.4", "10.30.1.4"]
```

The VMs receive the new DNS servers after a restart (or `ipconfig /renew`).

## Credentials and state

Put secrets in an ignored `terraform.tfvars`, or use `TF_VAR_*` variables:

```hcl
admin_password = "REPLACE_WITH_A_STRONG_UNIQUE_PASSWORD"
```

State is stored in the `tfblobcontainer/win-terraform` container under the
key `windows-ad-automation.tfstate`, using the signed-in Azure CLI identity
(this requires **Storage Blob Data Contributor**).

## Deploy

```bash
az login
az account set --subscription 9248b49a-6e5f-4ce1-b906-cd5b6baf80cf
terraform init
terraform plan
terraform apply
```

## Destroy

```bash
terraform destroy
```

This deletes the `sysvol-lab` resource group, including the gallery. The
source image in resource group `test` is not managed by Terraform and is left
in place.
