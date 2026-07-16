<!--
  Header for the minimal example README. Edit this file, then run `just docs`
  (or ./Sort-LdoTerraform.ps1 -IncludeExamples) to regenerate the section between the markers.
  The example's main.tf is embedded into the README automatically (see .terraform-docs.yml).
-->
<div align="center">
  <a href="https://libredevops.org">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="https://libredevops.org/assets/libre-devops-white.png">
      <img alt="Libre DevOps" src="https://libredevops.org/assets/libre-devops-black.png" width="200">
    </picture>
  </a>
</div>

# Minimal example

The smallest valid call to this module: required inputs only. The environment comes from the
Terraform workspace (`terraform.workspace`), not a variable. Run it with `just e2e minimal`, which
applies the stack then always destroys it.

[![Terraform Registry](https://img.shields.io/badge/registry-libre--devops-7B42BC?logo=terraform&logoColor=white)](https://registry.terraform.io/namespaces/libre-devops)

<!-- BEGIN_TF_DOCS -->
## Example configuration

```hcl
# Minimal call: onboard one Linux VM to Azure Machine Configuration and audit it against the built
# in Azure compute security baseline. rg -> vnet -> a hardened Linux VM (SSH only, system identity,
# Trusted Launch) -> the Guest Configuration extension (onboarding) -> a resource group scoped audit
# assignment of the Linux compute security baseline. Audit only, so nothing in guest is changed.
locals {
  location  = lookup(var.regions, var.loc, "uksouth")
  rg_name   = "rg-${var.short}-${var.loc}-${terraform.workspace}-mc-min"
  vnet_name = "vnet-${var.short}-${var.loc}-${terraform.workspace}-mc-min"
  vm_name   = "vm-lnx-${var.short}-${var.loc}-${terraform.workspace}-min"
}

module "tags" {
  source  = "libre-devops/tags/azurerm"
  version = "~> 4.0"

  cost_centre     = "1888/67"
  owner           = "platform@example.com"
  deployed_branch = var.deployed_branch
  deployed_repo   = var.deployed_repo
  additional_tags = { Application = "terraform-azurerm-machine-configuration" }
}

module "rg" {
  source  = "libre-devops/rg/azurerm"
  version = "~> 4.0"

  resource_groups = [{ name = local.rg_name, location = local.location, tags = module.tags.tags }]
}

module "network" {
  source  = "libre-devops/network/azurerm"
  version = "~> 4.0"

  resource_group_id = module.rg.ids[local.rg_name]
  location          = local.location
  tags              = module.tags.tags

  vnet_name     = local.vnet_name
  address_space = ["10.0.0.0/16"]
  subnets = {
    # default_outbound_access_enabled is required here: the Guest Configuration agent needs outbound
    # to Azure (443) to install the extension and report compliance. A real estate would front this
    # with a NAT gateway or private link instead of default outbound.
    "snet-app-${local.vnet_name}" = { address_prefixes = ["10.0.1.0/24"], default_outbound_access_enabled = true }
  }
}

# One hardened Linux VM with the secure defaults (SSH only, Trusted Launch, a system assigned
# identity, managed boot diagnostics). The system identity is what Guest Configuration reports with;
# the throwaway public key keeps the example self contained.
module "linux_vm" {
  source  = "libre-devops/linux-vm/azurerm"
  version = "~> 4.0"

  resource_group_id = module.rg.ids[local.rg_name]
  location          = local.location
  tags              = module.tags.tags

  linux_virtual_machines = {
    (local.vm_name) = {
      size                = "Standard_D2lds_v6"
      admin_username      = "azureuser"
      source_image_simple = "Ubuntu2404"
      subnet_id           = module.network.subnet_ids["snet-app-${local.vnet_name}"]
      admin_ssh_keys = [{
        public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCtbmPhzCR+ZpI/Y4H1IvPEI+tvGT4R5ReLtj5QZVcRXJiRdIbYsb6sjaYu8JcR6vzSHAlJcx0zmcSP4SR7HqtuXbODv+OvVpBCoil9LWbCfOgOQ6XZ3oSFYe8lFllbFLiM7I+ok+s7Cygnu58fil7pDdBFrS7DZRjvT87RrOX0dp2LDNNN7LYFy5nwHvkBv9z36q9RFGcP4e0XDNtU0+LGnolz4oDWkJt/0POaHIxnJJX7ge0r0bReZq/t1XRr/RrhPYk6gkWsSkfbwwxGPA2UdxFRDVn2aMx6Hz8gQfcHRS2kEvKRMIgQfBOmB6OInLCLaUZRWm5YdEBZXwtdREor example"
      }]
    }
  }
}

# The module under test: onboard the VM (install the Guest Configuration extension) and audit it
# against the Linux compute security baseline across the resource group.
module "machine_configuration" {
  source = "../../"

  guest_configuration_extensions = {
    AzurePolicyforLinux = {
      virtual_machine_id = module.linux_vm.virtual_machine_ids[local.vm_name]
      os_type            = "Linux"
    }
  }

  policy_assignments = {
    "mc-linux-baseline-min" = {
      display_name = "Linux compute security baseline (audit)"
      scope_type   = "resource_group"
      scope_id     = module.rg.ids[local.rg_name]
      location     = local.location
      builtin      = "linux_compute_baseline"
    }
  }
}
```

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9.0, < 2.0.0 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | >= 4.0.0, < 5.0.0 |

## Providers

No providers.

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_linux_vm"></a> [linux\_vm](#module\_linux\_vm) | libre-devops/linux-vm/azurerm | ~> 4.0 |
| <a name="module_machine_configuration"></a> [machine\_configuration](#module\_machine\_configuration) | ../../ | n/a |
| <a name="module_network"></a> [network](#module\_network) | libre-devops/network/azurerm | ~> 4.0 |
| <a name="module_rg"></a> [rg](#module\_rg) | libre-devops/rg/azurerm | ~> 4.0 |
| <a name="module_tags"></a> [tags](#module\_tags) | libre-devops/tags/azurerm | ~> 4.0 |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_deployed_branch"></a> [deployed\_branch](#input\_deployed\_branch) | Git branch the deployment came from. Auto-filled in CI from TF\_VAR\_deployed\_branch. | `string` | `""` | no |
| <a name="input_deployed_repo"></a> [deployed\_repo](#input\_deployed\_repo) | Repository URL the deployment came from. Auto-filled in CI from TF\_VAR\_deployed\_repo. | `string` | `""` | no |
| <a name="input_loc"></a> [loc](#input\_loc) | Outfix: short Azure region code used in resource names (for example uks). | `string` | `"uks"` | no |
| <a name="input_regions"></a> [regions](#input\_regions) | Map of short region codes to Azure region slugs. | `map(string)` | <pre>{<br/>  "eus": "eastus",<br/>  "euw": "westeurope",<br/>  "uks": "uksouth",<br/>  "ukw": "ukwest"<br/>}</pre> | no |
| <a name="input_short"></a> [short](#input\_short) | Infix: short product code used in resource names. | `string` | `"ldo"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_builtin_catalog"></a> [builtin\_catalog](#output\_builtin\_catalog) | The curated catalog of built in baseline definition ids the module exposes. |
| <a name="output_guest_configuration_extension_ids"></a> [guest\_configuration\_extension\_ids](#output\_guest\_configuration\_extension\_ids) | Map of extension key to { name, id } for the onboarded VM. |
| <a name="output_policy_assignments"></a> [policy\_assignments](#output\_policy\_assignments) | The scoped baseline assignment(s) created over the resource group. |
<!-- END_TF_DOCS -->
