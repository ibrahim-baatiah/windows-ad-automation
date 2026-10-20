# Azure Windows Lab

Terraform infrastructure and Ansible configuration for a small Azure lab
containing Windows Server virtual machines and a Linux VM. Terraform creates
the infrastructure; Ansible configures the Windows machines as an Active
Directory forest with one primary domain controller and two additional domain
controllers.

> **Current status:** The previous Azure deployment was destroyed. The
> Terraform and Ansible files remain as configuration; follow the deployment
> steps below to recreate the lab.

## Repository layout

| Path | Purpose |
| --- | --- |
| [`Infrastructure/`](./Infrastructure/) | Terraform for the resource group, VNet, subnet, NSG, public IPs, and four VMs |
| [`config-manager/`](./config-manager/) | Ansible inventory and playbook for Windows Active Directory setup |

Detailed infrastructure parameters and Terraform operations are documented in
[`Infrastructure/README.md`](./Infrastructure/README.md).

## Architecture

Terraform is configured to create:

- **Windows:** three Windows VMs using a generalized Windows Gen2 managed
  image configured in Terraform.
- **Linux:** one VM using Ubuntu Server 22.04 LTS Gen2.
- **Networking:** one resource group, one virtual network, and one subnet
  shared by all VMs.
- **Connectivity:** one static Standard public IPv4 address per VM and one
  subnet-level NSG. The NSG permits SSH (TCP 22) and RDP (TCP 3389) from the
  public IPv4 address Terraform detects at plan/apply time.
- **VM sizing:** `Standard_D2s_v5` by default. All VMs are regular, non-Spot
  instances.

The Windows image is a dependency: the deploying identity must be able to use
it, and it must remain available for future VM replacements. Terraform does
not manage or delete that source image. Its resource ID is configured in the
Terraform file and is intentionally not repeated in this README.

### Ansible configuration

[`config-manager/ansible-windows.yml`](./config-manager/ansible-windows.yml)
uses the `win` inventory group to:

1. Install Active Directory Domain Services on all three Windows servers.
2. Create the configured Active Directory forest and DNS on the `dc_primary`
   host.
3. Promote the hosts in `dc_additional` to additional domain controllers,
   serially, after setting their DNS to the primary DC.

The inventory uses private addresses in the Terraform subnet. Ansible
must therefore run from a system with network access to that VNet, such as a
VM in the VNet or a connected VPN/peered network. The current Terraform NSG
allows only SSH and RDP from the detected public address; it does **not**
currently allow WinRM/PSRP TCP 5985. Configure private connectivity and an
appropriate narrowly scoped NSG rule before expecting Ansible to connect.

The inventory's current private addresses are examples and are not guaranteed
allocations: Terraform assigns private addresses dynamically. After
deployment, update the inventory with the actual Windows private IPs from
Terraform's `windows_private_ip_addresses` output.

## Prerequisites

- An Azure subscription with permission to create resource groups, networking
  resources, public IPs, and virtual machines.
- Permission to read and use the custom Windows managed image in resource
  group `test`.
- Terraform 1.5 or later.
- Azure CLI authenticated to the subscription, or another supported AzureRM
  authentication method.
- An internet connection for Terraform's public-IP detection request to
  `https://api4.ipify.org`.
- For Ansible: a supported Ansible controller, `pypsrp`, and the
  `ansible.windows` and `microsoft.ad` collections.

## Deploy the Azure infrastructure

From the repository root:

```sh
az login
az account set --subscription "<subscription-id>"
az account show --output table

cd Infrastructure
terraform init
terraform fmt -check
terraform validate
terraform plan
```

Review the plan, including the image ID, detected admin IP, resource count, and
estimated charges. Supply the sensitive `admin_password` variable through an
ignored local `terraform.tfvars` file or `TF_VAR_admin_password`, then apply:

```sh
terraform apply
```

Terraform marks the password variable sensitive for CLI display, but the value
can still be present in Terraform state. Protect state and backups; use a
secured remote backend for shared use. Do not commit real passwords,
`terraform.tfvars`, or state files.

Terraform outputs include the Windows and Linux private/public IP addresses,
the resource group and VNet IDs, and `allowed_admin_public_ip`. Use the private
Windows IP output to update the Ansible inventory.

## Configure the Windows domain controllers

From a machine that can reach the VNet over the necessary WinRM/PSRP port:

1. Update [`config-manager/inventory.ini`](./config-manager/inventory.ini)
   with the current private IP addresses.
2. Install the Ansible collection and Python requirements:

   ```sh
   ansible-galaxy collection install ansible.windows microsoft.ad
   python -m pip install pypsrp
   ```

3. Replace the inventory's placeholder passwords with secure values supplied
   through Ansible Vault or another secrets manager. Do not commit plaintext
   credentials. The domain Safe Mode password should be stored as a secret too.
4. Check connectivity and review the playbook, then run:

   ```sh
   ansible win -i config-manager/inventory.ini -m ansible.windows.win_ping
   ansible-playbook -i config-manager/inventory.ini config-manager/ansible-windows.yml
   ```

The inventory currently specifies PowerShell Remoting over HTTP on port 5985
with NTLM. Use it only on a trusted/private network, and ensure the Windows
image has WinRM configured to accept the connection. For less trusted
networks, configure encrypted WinRM/HTTPS and appropriate authentication
instead.

The Ansible playbook configures the three Windows hosts; it does not currently
configure the Ubuntu VM.

## Security and cost notes

- Keep inbound rules scoped to a trusted source address. Terraform detects a
  public IPv4 address during planning/applying; VPNs, proxies, NAT, and changing
  ISP addresses can affect the detected value.
- Public IPs make the VMs internet-addressable. The NSG limits the currently
  configured inbound ports, but private access such as VPN or Azure Bastion is
  preferable for production.
- Use unique, strong administrator and domain passwords. Rotate any password
  that has been exposed or reused.
- These VMs are regular, non-Spot instances. Compute is billed while allocated;
  disks and public IP resources may continue to incur charges after VM
  deallocation.
- This lab configuration does not provide backups, high availability,
  monitoring, or a remote Terraform state backend by default.

## Tear down

Review what Terraform will remove:

```sh
cd Infrastructure
terraform plan -destroy
```

If the plan contains only resources intended for removal:

```sh
terraform destroy
```

This removes the Terraform-managed lab resource group and its resources. The
Windows managed source image in resource group `test` is outside that group
and is not deleted.
