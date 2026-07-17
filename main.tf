# Curated catalog of built in Guest Configuration policy definitions and initiatives, verified live
# against the Azure Policy service. policy_assignments[*].builtin selects one of these keys so a
# caller assigns a security baseline without hand pasting a GUID. Update these here in one place.
locals {
  builtin_catalog = {
    # Guest Configuration policy DEFINITIONS (AuditIfNotExists security baselines).
    windows_compute_baseline = "/providers/Microsoft.Authorization/policyDefinitions/72650e9f-97bc-4b2a-ab5f-9781a9fcecbc"
    linux_compute_baseline   = "/providers/Microsoft.Authorization/policyDefinitions/fc9b3da7-8347-4380-8e70-0a0361d8dedd"
    windows_cis              = "/providers/Microsoft.Authorization/policyDefinitions/6dcfa239-b481-4de9-a03f-980f24f3b0bb"
    linux_cis                = "/providers/Microsoft.Authorization/policyDefinitions/a3be3bae-0be0-4903-a924-edb7375c1d2e"

    # Onboarding prerequisite INITIATIVES: install the extension and identity across a scope.
    prereq_system_assigned = "/providers/Microsoft.Authorization/policySetDefinitions/12794019-7a00-42cf-95c2-882eed337cc8"
    prereq_user_assigned   = "/providers/Microsoft.Authorization/policySetDefinitions/2b0ce52e-301c-4221-ab38-1601e2b4cee3"
  }
  builtin_catalog_keys = keys(local.builtin_catalog)

  # Default Guest Configuration extension shape per OS. type_handler_version is Required by the
  # provider, so it always resolves (caller override, else the per OS default here).
  gc_extension_defaults = {
    Windows = { publisher = "Microsoft.GuestConfiguration", type = "ConfigurationforWindows", version = "1.29" }
    Linux   = { publisher = "Microsoft.GuestConfiguration", type = "ConfigurationForLinux", version = "1.26" }
  }

  # Catalog entries whose definition declares REQUIRED parameters the service will not default,
  # verified live: linux_cis (2.1.0) declares BaselineSettings with no defaultValue and rejects an
  # assignment without it (MissingPolicyParameter). An empty string selects the stock CIS baseline
  # (the windows_cis definition declares exactly that as its default); "{}" is the one poisonous
  # value (it can never satisfy the definition's existence condition). Caller parameters win per key.
  builtin_default_parameters = {
    linux_cis = { BaselineSettings = { value = "" } }
  }

  policy_assignment_parameters = {
    for k, a in var.policy_assignments : k => merge(
      a.builtin != null ? lookup(local.builtin_default_parameters, a.builtin, {}) : {},
      a.parameters != null ? a.parameters : {},
    )
  }

  # Resolve each scoped assignment to a concrete definition (or set) id: catalog key wins, then an
  # explicit definition id, then an explicit set (initiative) id. The provider assignment argument
  # policy_definition_id accepts either a definition or a set, so no further discrimination is needed.
  policy_assignments_resolved = {
    for k, a in var.policy_assignments : k => merge(a, {
      resolved_definition_id = coalesce(
        a.builtin != null ? local.builtin_catalog[a.builtin] : null,
        a.policy_definition_id,
        a.policy_set_definition_id,
      )
      resolved_parameters = length(local.policy_assignment_parameters[k]) > 0 ? local.policy_assignment_parameters[k] : null
    })
  }

  rg_assignments  = { for k, a in local.policy_assignments_resolved : k => a if a.scope_type == "resource_group" }
  sub_assignments = { for k, a in local.policy_assignments_resolved : k => a if a.scope_type == "subscription" }
  mg_assignments  = { for k, a in local.policy_assignments_resolved : k => a if a.scope_type == "management_group" }

  # Remediation role grants for assignment identities (DeployIfNotExists baselines): flatten each
  # assignment to a plan known (assignment key, role definition id) keyed map so the grant set is
  # stable regardless of the computed principal id.
  remediation_grants = merge([
    for k, a in var.policy_assignments : {
      for rid in a.remediation_role_definition_ids :
      "${k}:${rid}" => {
        assignment_key     = k
        role_definition_id = rid
        scope              = coalesce(a.remediation_role_scope, a.scope_id)
      }
    }
  ]...)
}

# --- Onboarding: install the Guest Configuration extension so per machine assignments execute -----
resource "azurerm_virtual_machine_extension" "guest_config" {
  for_each = var.guest_configuration_extensions

  virtual_machine_id         = each.value.virtual_machine_id
  name                       = each.key
  publisher                  = local.gc_extension_defaults[each.value.os_type].publisher
  type                       = local.gc_extension_defaults[each.value.os_type].type
  type_handler_version       = coalesce(each.value.type_handler_version, local.gc_extension_defaults[each.value.os_type].version)
  auto_upgrade_minor_version = each.value.auto_upgrade_minor_version
  automatic_upgrade_enabled  = each.value.automatic_upgrade_enabled
  settings                   = each.value.settings
  protected_settings         = each.value.protected_settings
  tags                       = each.value.tags
}

# --- Per machine assignment: onboard a specific VM to a built in baseline or a custom DSC package --
resource "azurerm_policy_virtual_machine_configuration_assignment" "this" {
  for_each = var.machine_configuration_assignments

  location           = each.value.location
  virtual_machine_id = each.value.virtual_machine_id
  name               = each.value.name

  configuration {
    assignment_type = each.value.assignment_type
    content_uri     = each.value.content_uri
    content_hash    = each.value.content_hash
    # The service REJECTS a custom package assignment (content_uri set) whose version is null,
    # empty, or whitespace (caught live: 400 "guestConfiguration properties version"); built in
    # baselines accept a null version (latest). Default custom packages to 1.0.0.
    version = each.value.content_uri != null ? coalesce(each.value.version, "1.0.0") : each.value.version

    dynamic "parameter" {
      for_each = each.value.parameters
      content {
        name  = parameter.key
        value = parameter.value
      }
    }
  }

  # Assignments do not run until the extension is present; order all extensions before all
  # assignments so a single apply onboards then assigns.
  depends_on = [azurerm_virtual_machine_extension.guest_config]
}

# --- Scoped assignment: audit or enforce a baseline across a resource group ------------------------
resource "azurerm_resource_group_policy_assignment" "this" {
  for_each = local.rg_assignments

  resource_group_id    = each.value.scope_id
  location             = each.value.location
  name                 = each.key
  policy_definition_id = each.value.resolved_definition_id
  display_name         = each.value.display_name
  description          = each.value.description
  enforce              = each.value.enforcement_mode == "Default"
  not_scopes           = each.value.not_scopes
  parameters           = each.value.resolved_parameters != null ? jsonencode(each.value.resolved_parameters) : null

  dynamic "identity" {
    for_each = each.value.identity_type == "None" ? [] : [1]
    content {
      type         = each.value.identity_type
      identity_ids = each.value.identity_type == "UserAssigned" ? each.value.identity_ids : null
    }
  }
}

# --- Scoped assignment: audit or enforce a baseline across a subscription --------------------------
resource "azurerm_subscription_policy_assignment" "this" {
  for_each = local.sub_assignments

  subscription_id      = each.value.scope_id
  location             = each.value.location
  name                 = each.key
  policy_definition_id = each.value.resolved_definition_id
  display_name         = each.value.display_name
  description          = each.value.description
  enforce              = each.value.enforcement_mode == "Default"
  not_scopes           = each.value.not_scopes
  parameters           = each.value.resolved_parameters != null ? jsonencode(each.value.resolved_parameters) : null

  dynamic "identity" {
    for_each = each.value.identity_type == "None" ? [] : [1]
    content {
      type         = each.value.identity_type
      identity_ids = each.value.identity_type == "UserAssigned" ? each.value.identity_ids : null
    }
  }
}

# --- Scoped assignment: audit or enforce a baseline across a management group ----------------------
resource "azurerm_management_group_policy_assignment" "this" {
  for_each = local.mg_assignments

  management_group_id  = each.value.scope_id
  location             = each.value.location
  name                 = each.key
  policy_definition_id = each.value.resolved_definition_id
  display_name         = each.value.display_name
  description          = each.value.description
  enforce              = each.value.enforcement_mode == "Default"
  not_scopes           = each.value.not_scopes
  parameters           = each.value.resolved_parameters != null ? jsonencode(each.value.resolved_parameters) : null

  dynamic "identity" {
    for_each = each.value.identity_type == "None" ? [] : [1]
    content {
      type         = each.value.identity_type
      identity_ids = each.value.identity_type == "UserAssigned" ? each.value.identity_ids : null
    }
  }
}

# --- Remediation grants: give each assignment identity the roles it needs to deploy ---------------
locals {
  assignment_identity_principal_ids = merge(
    { for k, r in azurerm_resource_group_policy_assignment.this : k => try(r.identity[0].principal_id, null) },
    { for k, r in azurerm_subscription_policy_assignment.this : k => try(r.identity[0].principal_id, null) },
    { for k, r in azurerm_management_group_policy_assignment.this : k => try(r.identity[0].principal_id, null) },
  )
}

resource "azurerm_role_assignment" "remediation" {
  for_each = local.remediation_grants

  scope              = each.value.scope
  role_definition_id = each.value.role_definition_id
  principal_id       = local.assignment_identity_principal_ids[each.value.assignment_key]
}
