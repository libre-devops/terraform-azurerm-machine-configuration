<!--
  Header for the complete example README. Edit this file, then run `just docs`
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

# Complete example

Exercises the fuller surface of this module. The environment comes from the Terraform workspace
(`terraform.workspace`), not a variable. Run it with `just e2e complete`, which applies the stack
then always destroys it.

[![Terraform Registry](https://img.shields.io/badge/registry-libre--devops-7B42BC?logo=terraform&logoColor=white)](https://registry.terraform.io/namespaces/libre-devops)

<!-- BEGIN_TF_DOCS -->
## Example configuration

```hcl
# Complete call: the full Machine Configuration surface across Windows and Linux. rg -> vnet -> a
# hardened Windows VM and a hardened Linux VM -> onboard both with the Guest Configuration extension
# -> assign the CIS security baselines (audit) across the resource group -> and, when the custom
# package hashes are supplied (built and uploaded by CI), enforce a custom IIS hardening package on
# Windows and a custom Nginx hardening package on Linux with ApplyAndAutoCorrect (continuous drift
# correction). The custom assignments are gated on the package hash variables so validate and plan
# work offline; CI fills them in for the live apply. Blocks are ordered by dependency, top to bottom.
locals {
  location  = lookup(var.regions, var.loc, "uksouth")
  rg_name   = "rg-${var.short}-${var.loc}-${terraform.workspace}-mc-cmp"
  vnet_name = "vnet-${var.short}-${var.loc}-${terraform.workspace}-mc-cmp"
  nsg_name  = "nsg-${var.short}-${var.loc}-${terraform.workspace}-mc-cmp"
  win_name  = "vm-win-${var.short}-${var.loc}-${terraform.workspace}-c"
  lnx_name  = "vm-lnx-${var.short}-${var.loc}-${terraform.workspace}-c"

  subnet_name     = "snet-app-${local.vnet_name}"
  kv_name         = "kv-${var.short}-${var.loc}-${terraform.workspace}-mccmp"
  ssh_key_name    = "ssh-${var.short}-${var.loc}-${terraform.workspace}-mccmp"
  win_secret_name = "${local.win_name}-admin-password"

  # Package coordinates. The package storage account and container are created below (private, from
  # the storage module); the content URI is the blob URL plus a read only container SAS generated
  # in-apply, so no public blob access is needed. CI only supplies the hash (computed when it builds
  # the .zip) and uploads the .zip to this blob after apply. Everything is torn down with the RG.
  package_container = "packages"
  iis_blob          = "iis-hardening.zip"
  nginx_blob        = "nginx-hardening.zip"
  pkg_sa_name       = "stldo${var.loc}mc${random_string.pkg.result}"
  pkg_blob_base     = "${module.package_storage.primary_blob_endpoints[local.pkg_sa_name]}${local.package_container}"
  iis_content_uri   = "${local.pkg_blob_base}/${local.iis_blob}${data.azurerm_storage_account_blob_container_sas.packages.sas}"
  nginx_content_uri = "${local.pkg_blob_base}/${local.nginx_blob}${data.azurerm_storage_account_blob_container_sas.packages.sas}"

  # Custom per machine assignments, gated on the package hash being supplied. Empty when the packages
  # have not been built (offline validate and local plan); populated by CI (which passes the built
  # hashes) to enforce with ApplyAndAutoCorrect.
  custom_assignments = merge(
    var.iis_package_hash != "" ? {
      iis_hardening = {
        name               = "IISHardening"
        virtual_machine_id = module.windows_vm.virtual_machine_ids[local.win_name]
        location           = local.location
        assignment_type    = "ApplyAndAutoCorrect"
        content_uri        = local.iis_content_uri
        content_hash       = var.iis_package_hash
        parameters         = {}
      }
    } : {},
    var.nginx_package_hash != "" ? {
      nginx_hardening = {
        name               = "NginxHardening"
        virtual_machine_id = module.linux_vm.virtual_machine_ids[local.lnx_name]
        location           = local.location
        assignment_type    = "ApplyAndAutoCorrect"
        content_uri        = local.nginx_content_uri
        content_hash       = var.nginx_package_hash
        parameters         = {}
      }
    } : {},
  )
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

data "azurerm_client_config" "current" {}

# Carve the VM subnet from the vnet address space with the subnet-calculator module (names it with the
# snet-<purpose>-<vnet> convention, so snet-app-<vnet> matches local.subnet_name).
module "subnet_calculator" {
  source  = "libre-devops/subnet-calculator/azurerm"
  version = "~> 4.0"

  base_cidr = "10.0.0.0/24"
  vnet_name = local.vnet_name

  subnets = [
    { purpose = "app", size = 26 },
  ]
}

module "network" {
  source  = "libre-devops/network/azurerm"
  version = "~> 4.0"

  resource_group_id = module.rg.ids[local.rg_name]
  location          = local.location
  tags              = module.tags.tags

  vnet_name     = local.vnet_name
  address_space = [module.subnet_calculator.base_cidr]
  subnets = {
    # Subnet CIDR carved by the subnet-calculator module. The Guest Configuration agent needs outbound
    # to Azure (443) to install the extension and report; the Microsoft.Storage service endpoint lets
    # it reach the private package storage account over the Azure backbone.
    (local.subnet_name) = {
      address_prefixes                = module.subnet_calculator.network_subnets[local.subnet_name].address_prefixes
      default_outbound_access_enabled = true
      service_endpoints               = ["Microsoft.Storage"]
    }
  }
}

# Secure-by-default NSG on the VM subnet (an explicit inbound deny plus curated outbound allows). No
# inbound is opened: Machine Configuration is agent driven and outbound only.
module "nsg" {
  source  = "libre-devops/nsg/azurerm"
  version = "~> 4.0"

  resource_group_id = module.rg.ids[local.rg_name]
  location          = local.location
  tags              = module.tags.tags

  name = local.nsg_name

  subnet_associations = {
    (local.subnet_name) = module.network.subnet_ids[local.subnet_name]
  }
}

# A vault for the generated Windows admin password and the SSH key pair. RBAC authorization (the
# module default); the applier is granted data-plane access below via the role-assignment module.
# Disposable example vault (public network Allow so the applier writes without an IP dance); a real
# vault stays firewalled and lets the action do the allow-list dance.
module "keyvault" {
  source  = "libre-devops/keyvault/azurerm"
  version = "~> 4.0"

  resource_group_id = module.rg.ids[local.rg_name]
  location          = local.location
  tags              = module.tags.tags

  key_vaults = {
    (local.kv_name) = {
      purge_protection_enabled = false
      network_acls             = { default_action = "Allow" }
    }
  }
}

# Grant the applier data-plane write access to the vault via the role-assignment module.
module "kv_rbac" {
  source  = "libre-devops/role-assignment/azurerm"
  version = "~> 4.0"

  role_assignments = {
    kv-secrets-officer = {
      scope                            = module.keyvault.ids[local.kv_name]
      principal_ids                    = [data.azurerm_client_config.current.object_id]
      role_names                       = ["Key Vault Secrets Officer"]
      skip_service_principal_aad_check = true
    }
  }
}

# KV data-plane RBAC is eventually consistent; wait before writing secrets so the first apply does not
# race a 403 while the assignment propagates.
resource "time_sleep" "kv_rbac_propagation" {
  create_duration = "120s"
  depends_on      = [module.kv_rbac]
}

# The Windows admin password: generated here (in state, since the VM needs it) and vaulted write-only
# via the keyvault-secret module (value_wo, so the value never lands in the secret resource's state).
resource "random_password" "win_admin" {
  length  = 24
  special = true
}

module "keyvault_secret" {
  source  = "libre-devops/keyvault-secret/azurerm"
  version = "~> 4.0"

  key_vault_id = module.keyvault.ids[local.kv_name]

  secrets = {
    (local.win_secret_name) = { content_type = "password" }
  }
  secret_values = {
    (local.win_secret_name) = random_password.win_admin.result
  }

  depends_on = [time_sleep.kv_rbac_propagation]
}

# Generate and vault the Linux SSH key pair (the private half is written to the vault, never surfaced).
module "ssh_key" {
  source  = "libre-devops/ssh-key/azurerm"
  version = "~> 4.0"

  resource_group_id = module.rg.ids[local.rg_name]
  location          = local.location
  tags              = module.tags.tags

  key_vault_id = module.keyvault.ids[local.kv_name]

  ssh_keys = {
    (local.ssh_key_name) = {}
  }

  depends_on = [time_sleep.kv_rbac_propagation]
}

# Private storage hosting the built DSC packages, composed from the storage module (secure defaults:
# deny by default network rules). The VM subnet reaches it over the Microsoft.Storage service endpoint
# (network), and a read only container SAS in the content URI authorises the download (authz); no
# public blob access. The per-VM assignment resource has no identity argument, so a SAS is the private
# option here (managed identity download is only wireable on the policy-definition path). The random
# suffix keeps the globally unique account name from colliding; CI uploads the .zips after apply
# through the storage firewall dance. Torn down with the resource group.
resource "random_string" "pkg" {
  length  = 8
  lower   = true
  upper   = false
  numeric = true
  special = false
}

module "package_storage" {
  source  = "libre-devops/storage-account/azurerm"
  version = "~> 4.0"

  resource_group_id = module.rg.ids[local.rg_name]
  location          = local.location
  tags              = module.tags.tags

  storage_accounts = {
    (local.pkg_sa_name) = {
      account_tier             = "Standard"
      account_replication_type = "LRS"
      network_rules = {
        default_action             = "Deny"
        bypass                     = ["AzureServices"]
        virtual_network_subnet_ids = [module.network.subnet_ids[local.subnet_name]]
      }
    }
  }
}

resource "azurerm_storage_container" "packages" {
  name                  = local.package_container
  storage_account_id    = module.package_storage.ids[local.pkg_sa_name]
  container_access_type = "private"
}

# A short lived, read only container SAS, generated in-apply locally from the account key (so it works
# even though the account is firewalled). It authorises the VMs' Guest Configuration agents to
# download the packages over the subnet service endpoint, with no public access.
data "azurerm_storage_account_blob_container_sas" "packages" {
  connection_string = module.package_storage.primary_connection_strings[local.pkg_sa_name]
  container_name    = azurerm_storage_container.packages.name
  https_only        = true

  start  = timestamp()
  expiry = timeadd(timestamp(), "24h")

  permissions {
    read   = true
    list   = true
    add    = false
    create = false
    write  = false
    delete = false
  }
}

# Hardened Windows VM (Trusted Launch, system identity, managed boot diagnostics). The admin password
# is generated and vaulted by the key-vault-secrets module.
module "windows_vm" {
  source  = "libre-devops/windows-vm/azurerm"
  version = "~> 4.0"

  resource_group_id = module.rg.ids[local.rg_name]
  location          = local.location
  tags              = module.tags.tags

  windows_virtual_machines = {
    (local.win_name) = {
      size                = "Standard_D2lds_v6"
      admin_username      = "azureadmin"
      admin_password      = random_password.win_admin.result
      source_image_simple = "WindowsServer2022AzureEdition"
      subnet_id           = module.network.subnet_ids[local.subnet_name]
    }
  }
}

# Hardened Linux VM (SSH only, Trusted Launch, system identity). The public key comes from the ssh-key
# module (its private half is vaulted, never surfaced here).
module "linux_vm" {
  source  = "libre-devops/linux-vm/azurerm"
  version = "~> 4.0"

  resource_group_id = module.rg.ids[local.rg_name]
  location          = local.location
  tags              = module.tags.tags

  linux_virtual_machines = {
    (local.lnx_name) = {
      size                = "Standard_D2lds_v6"
      admin_username      = "azureuser"
      source_image_simple = "Ubuntu2404"
      subnet_id           = module.network.subnet_ids[local.subnet_name]
      admin_ssh_keys = [{
        public_key = module.ssh_key.public_keys_openssh[local.ssh_key_name]
      }]
    }
  }
}

# The module under test: onboard both VMs, assign the Windows and Linux CIS baselines across the
# resource group (audit), and enforce the custom IIS and Nginx packages per VM when supplied.
module "machine_configuration" {
  source = "../../"

  guest_configuration_extensions = {
    AzurePolicyforWindows = {
      virtual_machine_id = module.windows_vm.virtual_machine_ids[local.win_name]
      os_type            = "Windows"
    }
    AzurePolicyforLinux = {
      virtual_machine_id = module.linux_vm.virtual_machine_ids[local.lnx_name]
      os_type            = "Linux"
    }
  }

  policy_assignments = {
    "mc-win-cis-cmp" = {
      display_name = "Windows CIS baseline (audit)"
      scope_type   = "resource_group"
      scope_id     = module.rg.ids[local.rg_name]
      location     = local.location
      builtin      = "windows_cis"
    }
    "mc-lnx-cis-cmp" = {
      display_name = "Linux CIS baseline (audit)"
      scope_type   = "resource_group"
      scope_id     = module.rg.ids[local.rg_name]
      location     = local.location
      builtin      = "linux_cis"
    }
  }

  machine_configuration_assignments = local.custom_assignments
}
```

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9.0, < 2.0.0 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | >= 4.0.0, < 5.0.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | >= 3.0.0, < 4.0.0 |
| <a name="requirement_time"></a> [time](#requirement\_time) | >= 0.9.0, < 1.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | >= 4.0.0, < 5.0.0 |
| <a name="provider_random"></a> [random](#provider\_random) | >= 3.0.0, < 4.0.0 |
| <a name="provider_time"></a> [time](#provider\_time) | >= 0.9.0, < 1.0.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_keyvault"></a> [keyvault](#module\_keyvault) | libre-devops/keyvault/azurerm | ~> 4.0 |
| <a name="module_keyvault_secret"></a> [keyvault\_secret](#module\_keyvault\_secret) | libre-devops/keyvault-secret/azurerm | ~> 4.0 |
| <a name="module_kv_rbac"></a> [kv\_rbac](#module\_kv\_rbac) | libre-devops/role-assignment/azurerm | ~> 4.0 |
| <a name="module_linux_vm"></a> [linux\_vm](#module\_linux\_vm) | libre-devops/linux-vm/azurerm | ~> 4.0 |
| <a name="module_machine_configuration"></a> [machine\_configuration](#module\_machine\_configuration) | ../../ | n/a |
| <a name="module_network"></a> [network](#module\_network) | libre-devops/network/azurerm | ~> 4.0 |
| <a name="module_nsg"></a> [nsg](#module\_nsg) | libre-devops/nsg/azurerm | ~> 4.0 |
| <a name="module_package_storage"></a> [package\_storage](#module\_package\_storage) | libre-devops/storage-account/azurerm | ~> 4.0 |
| <a name="module_rg"></a> [rg](#module\_rg) | libre-devops/rg/azurerm | ~> 4.0 |
| <a name="module_ssh_key"></a> [ssh\_key](#module\_ssh\_key) | libre-devops/ssh-key/azurerm | ~> 4.0 |
| <a name="module_subnet_calculator"></a> [subnet\_calculator](#module\_subnet\_calculator) | libre-devops/subnet-calculator/azurerm | ~> 4.0 |
| <a name="module_tags"></a> [tags](#module\_tags) | libre-devops/tags/azurerm | ~> 4.0 |
| <a name="module_windows_vm"></a> [windows\_vm](#module\_windows\_vm) | libre-devops/windows-vm/azurerm | ~> 4.0 |

## Resources

| Name | Type |
|------|------|
| [azurerm_storage_container.packages](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_container) | resource |
| [random_password.win_admin](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [random_string.pkg](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/string) | resource |
| [time_sleep.kv_rbac_propagation](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/sleep) | resource |
| [azurerm_client_config.current](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/client_config) | data source |
| [azurerm_storage_account_blob_container_sas.packages](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/storage_account_blob_container_sas) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_deployed_branch"></a> [deployed\_branch](#input\_deployed\_branch) | Git branch the deployment came from. Auto-filled in CI from TF\_VAR\_deployed\_branch. | `string` | `""` | no |
| <a name="input_deployed_repo"></a> [deployed\_repo](#input\_deployed\_repo) | Repository URL the deployment came from. Auto-filled in CI from TF\_VAR\_deployed\_repo. | `string` | `""` | no |
| <a name="input_iis_package_hash"></a> [iis\_package\_hash](#input\_iis\_package\_hash) | UPPERCASE SHA256 of the IIS hardening package .zip. Empty disables the IIS assignment. | `string` | `""` | no |
| <a name="input_loc"></a> [loc](#input\_loc) | Outfix: short Azure region code used in resource names (for example uks). | `string` | `"uks"` | no |
| <a name="input_nginx_package_hash"></a> [nginx\_package\_hash](#input\_nginx\_package\_hash) | UPPERCASE SHA256 of the Nginx hardening package .zip. Empty disables the Nginx assignment. | `string` | `""` | no |
| <a name="input_regions"></a> [regions](#input\_regions) | Map of short region codes to Azure region slugs. | `map(string)` | <pre>{<br/>  "eus": "eastus",<br/>  "euw": "westeurope",<br/>  "uks": "uksouth",<br/>  "ukw": "ukwest"<br/>}</pre> | no |
| <a name="input_short"></a> [short](#input\_short) | Infix: short product code used in resource names. | `string` | `"ldo"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_guest_configuration_extensions"></a> [guest\_configuration\_extensions](#output\_guest\_configuration\_extensions) | The Guest Configuration extensions installed on the Windows and Linux VMs. |
| <a name="output_machine_configuration_assignments"></a> [machine\_configuration\_assignments](#output\_machine\_configuration\_assignments) | The per machine (custom package) assignments, when the package coordinates were supplied. |
| <a name="output_package_blobs"></a> [package\_blobs](#output\_package\_blobs) | Map of package key to the blob name CI should upload the built .zip as. |
| <a name="output_package_container_name"></a> [package\_container\_name](#output\_package\_container\_name) | Container holding the DSC packages. |
| <a name="output_package_resource_group_name"></a> [package\_resource\_group\_name](#output\_package\_resource\_group\_name) | Resource group of the package storage account (for the CI upload IP dance). |
| <a name="output_package_storage_account_name"></a> [package\_storage\_account\_name](#output\_package\_storage\_account\_name) | Name of the private storage account hosting the DSC packages. |
| <a name="output_policy_assignments"></a> [policy\_assignments](#output\_policy\_assignments) | The scoped CIS baseline assignments created over the resource group. |
<!-- END_TF_DOCS -->
