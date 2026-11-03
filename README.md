# Azure SYSVOL replication lab

Terraform deploys three Windows Spot VMs from the custom `win-winrm-image`
(DC01 in Poland Central, DC02 in Switzerland North, and DC03 in Germany West
Central), plus an Ubuntu Spot router (`NVA01`) in Poland Central. Everything
is in the `sysvol-lab` resource group.

Each region has its own VNet. Poland is the hub and is peered with both
spokes. All traffic between regions is routed through `NVA01` using UDRs.

The Ansible playbooks in [`config-manager/`](./config-manager) configure the
domain, and [`powershell-scripts/`](./powershell-scripts) contains SYSVOL
repair tooling.

See [`Infrastructure/README.md`](./Infrastructure/README.md) for the address
plan, routing, credentials, and deploy and destroy steps.
