output "builtin_catalog" {
  description = "The curated catalog of built in baseline definition ids the module exposes."
  value       = module.machine_configuration.builtin_catalog
}

output "guest_configuration_extension_ids" {
  description = "Map of extension key to { name, id } for the onboarded VM."
  value       = module.machine_configuration.guest_configuration_extension_ids_zipmap
}

output "policy_assignments" {
  description = "The scoped baseline assignment(s) created over the resource group."
  value       = module.machine_configuration.policy_assignments
}
