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
