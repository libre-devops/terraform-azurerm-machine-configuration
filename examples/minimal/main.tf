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
      virtual_machine_id = module.linux_vm.ids[local.vm_name]
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
