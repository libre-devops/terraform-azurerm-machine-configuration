output "guest_configuration_extensions" {
  description = "The Guest Configuration extensions installed on the Windows and Linux VMs."
  value       = module.machine_configuration.guest_configuration_extensions
}

output "machine_configuration_assignments" {
  description = "The per machine (custom package) assignments, when the package coordinates were supplied."
  value       = module.machine_configuration.machine_configuration_assignments
}

output "package_blobs" {
  description = "Map of package key to the blob name CI should upload the built .zip as."
  value = {
    iis   = local.iis_blob
    nginx = local.nginx_blob
  }
}

output "package_container_name" {
  description = "Container holding the DSC packages."
  value       = azurerm_storage_container.packages.name
}

output "package_resource_group_name" {
  description = "Resource group of the package storage account (for the CI upload IP dance)."
  value       = local.rg_name
}

# Consumed by the CI self-test to upload the built .zip packages after apply (through the storage
# firewall dance, since the account is private) to the blobs the assignments reference.
output "package_storage_account_name" {
  description = "Name of the private storage account hosting the DSC packages."
  value       = one(module.package_storage.names)
}

output "policy_assignments" {
  description = "The scoped CIS baseline assignments created over the resource group."
  value       = module.machine_configuration.policy_assignments
}
