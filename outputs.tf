# --- Curated built in catalog ---------------------------------------------------------------------
output "builtin_catalog" {
  description = "Curated map of friendly key to built in Guest Configuration definition/initiative id. Reference a key via policy_assignments[*].builtin, or read the id directly."
  value       = local.builtin_catalog
}

output "builtin_catalog_keys" {
  description = "The valid keys of builtin_catalog (the accepted values for policy_assignments[*].builtin)."
  value       = local.builtin_catalog_keys
}

output "guest_configuration_extension_ids_zipmap" {
  description = "Map of extension key to { name, id } for easy composition."
  value       = { for k, e in azurerm_virtual_machine_extension.guest_config : k => { name = e.name, id = e.id } }
}

# --- Onboarding extensions ------------------------------------------------------------------------
output "guest_configuration_extensions" {
  description = "Map of extension key to the installed Guest Configuration extension (id, name, type, virtual_machine_id)."
  value = {
    for k, e in azurerm_virtual_machine_extension.guest_config : k => {
      id                 = e.id
      name               = e.name
      type               = e.type
      virtual_machine_id = e.virtual_machine_id
    }
  }
}

output "machine_configuration_assignment_ids_zipmap" {
  description = "Map of assignment key to { name, id } for easy composition."
  value       = { for k, a in azurerm_policy_virtual_machine_configuration_assignment.this : k => { name = a.name, id = a.id } }
}

# --- Per machine assignments ----------------------------------------------------------------------
output "machine_configuration_assignments" {
  description = "Map of assignment key to the per machine Guest Configuration assignment (id, name, virtual_machine_id)."
  value = {
    for k, a in azurerm_policy_virtual_machine_configuration_assignment.this : k => {
      id                 = a.id
      name               = a.name
      virtual_machine_id = a.virtual_machine_id
    }
  }
}

output "policy_assignment_ids_zipmap" {
  description = "Map of assignment key to { name, id } across every scope, for easy composition."
  value = merge(
    { for k, r in azurerm_resource_group_policy_assignment.this : k => { name = r.name, id = r.id } },
    { for k, r in azurerm_subscription_policy_assignment.this : k => { name = r.name, id = r.id } },
    { for k, r in azurerm_management_group_policy_assignment.this : k => { name = r.name, id = r.id } },
  )
}

output "policy_assignment_principal_ids" {
  description = "Map of assignment key to its system assigned identity principal id (null when identity is None)."
  value       = local.assignment_identity_principal_ids
}

# --- Scoped policy assignments (all scopes merged) -------------------------------------------------
output "policy_assignments" {
  description = "Map of assignment key to the scoped policy assignment (id, name, scope_type, principal_id of its identity)."
  value = merge(
    { for k, r in azurerm_resource_group_policy_assignment.this : k => { id = r.id, name = r.name, scope_type = "resource_group", principal_id = try(r.identity[0].principal_id, null) } },
    { for k, r in azurerm_subscription_policy_assignment.this : k => { id = r.id, name = r.name, scope_type = "subscription", principal_id = try(r.identity[0].principal_id, null) } },
    { for k, r in azurerm_management_group_policy_assignment.this : k => { id = r.id, name = r.name, scope_type = "management_group", principal_id = try(r.identity[0].principal_id, null) } },
  )
}

# --- Remediation role grants ----------------------------------------------------------------------
output "remediation_role_assignment_ids" {
  description = "Map of '<assignment key>:<role definition id>' to the created role assignment id."
  value       = { for k, r in azurerm_role_assignment.remediation : k => r.id }
}
