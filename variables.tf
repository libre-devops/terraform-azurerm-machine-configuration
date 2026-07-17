variable "guest_configuration_extensions" {
  description = <<-EOT
    Guest Configuration VM extensions to install, keyed by a stable name. Installing the
    extension is the onboarding step: a per machine configuration assignment will not execute
    until the extension is present on the virtual machine, and the virtual machine must carry a
    system assigned identity so the platform can report and remediate. Set os_type to Windows or
    Linux; the module picks the correct publisher and type per OS when they are not overridden.
  EOT
  type = map(object({
    virtual_machine_id         = string
    os_type                    = string
    type_handler_version       = optional(string)
    auto_upgrade_minor_version = optional(bool, true)
    automatic_upgrade_enabled  = optional(bool, true)
    settings                   = optional(string)
    protected_settings         = optional(string)
    tags                       = optional(map(string))
  }))
  default = {}

  validation {
    condition     = alltrue([for e in values(var.guest_configuration_extensions) : contains(["Windows", "Linux"], e.os_type)])
    error_message = "Each guest_configuration_extensions[*].os_type must be either \"Windows\" or \"Linux\"."
  }

  validation {
    condition = alltrue([
      for e in values(var.guest_configuration_extensions) :
      can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Compute/virtualMachines/[^/]+$", e.virtual_machine_id))
    ])
    error_message = "Each guest_configuration_extensions[*].virtual_machine_id must be the full virtual machine RESOURCE id (/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Compute/virtualMachines/<name>). Beware the azurerm VM resource's virtual_machine_id attribute (the LDO vm modules' virtual_machine_ids output): that is the compute fabric GUID and will not parse. Pass the VM resource id (the vm modules' ids output) instead."
  }
}

variable "machine_configuration_assignments" {
  description = <<-EOT
    Per machine (guest configuration) assignments, keyed by a stable name. Onboard a specific
    virtual machine to a built in baseline (for example AzureWindowsBaseline or AzureLinuxBaseline,
    leaving content_uri and content_hash unset) or to a custom DSC package (both content_uri and
    content_hash required; content_hash is the UPPERCASE SHA256 of the .zip). assignment_type
    defaults to Audit (the safe default); ApplyAndAutoCorrect enforces continuously. The referenced
    virtual machine must already carry the Guest Configuration extension (see
    guest_configuration_extensions) and a system assigned identity.
  EOT
  type = map(object({
    name               = string
    virtual_machine_id = string
    location           = string
    assignment_type    = optional(string, "Audit")
    version            = optional(string)
    content_uri        = optional(string)
    content_hash       = optional(string)
    parameters         = optional(map(string), {})
  }))
  default = {}

  validation {
    condition = alltrue([
      for a in values(var.machine_configuration_assignments) :
      contains(["Audit", "ApplyAndMonitor", "ApplyAndAutoCorrect", "DeployAndAutoCorrect"], a.assignment_type)
    ])
    error_message = "Each machine_configuration_assignments[*].assignment_type must be one of Audit, ApplyAndMonitor, ApplyAndAutoCorrect or DeployAndAutoCorrect."
  }

  validation {
    condition = alltrue([
      for a in values(var.machine_configuration_assignments) :
      (a.content_uri == null) == (a.content_hash == null)
    ])
    error_message = "content_uri and content_hash must be set together (custom package) or both left unset (built in package)."
  }

  validation {
    condition = alltrue([
      for a in values(var.machine_configuration_assignments) :
      a.content_hash == null ? true : can(regex("^[A-F0-9]{64}$", a.content_hash))
    ])
    error_message = "content_hash must be an UPPERCASE 64 character hex SHA256 (the SH256SUM of the .zip in upper case)."
  }

  validation {
    condition = alltrue([
      for a in values(var.machine_configuration_assignments) :
      can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Compute/virtualMachines/[^/]+$", a.virtual_machine_id))
    ])
    error_message = "Each machine_configuration_assignments[*].virtual_machine_id must be the full virtual machine RESOURCE id (/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Compute/virtualMachines/<name>). Beware the azurerm VM resource's virtual_machine_id attribute (the LDO vm modules' virtual_machine_ids output): that is the compute fabric GUID and will not parse. Pass the VM resource id (the vm modules' ids output) instead."
  }
}

variable "policy_assignments" {
  description = <<-EOT
    Scoped Guest Configuration policy assignments, keyed by a stable name: the fleet wide way to
    audit or enforce baselines across every machine in a resource group, subscription or management
    group. Point each entry at the curated built in catalog with builtin (for example linux_cis,
    windows_cis, linux_compute_baseline, windows_compute_baseline, prereq_system_assigned), or set
    policy_definition_id / policy_set_definition_id explicitly. enforcement_mode defaults to Default;
    set it to DoNotEnforce for report only. A system assigned identity plus remediation role grants
    are wired for definitions that deploy (DeployIfNotExists).
  EOT
  type = map(object({
    display_name             = string
    description              = optional(string)
    scope_type               = string
    scope_id                 = string
    location                 = string
    builtin                  = optional(string)
    policy_definition_id     = optional(string)
    policy_set_definition_id = optional(string)
    parameters               = optional(any)
    enforcement_mode         = optional(string, "Default")
    not_scopes               = optional(list(string), [])
    identity_type            = optional(string, "SystemAssigned")
    identity_ids             = optional(list(string), [])

    remediation_role_definition_ids = optional(list(string), [])
    remediation_role_scope          = optional(string)
  }))
  default = {}

  validation {
    condition = alltrue([
      for a in values(var.policy_assignments) :
      contains(["resource_group", "subscription", "management_group"], a.scope_type)
    ])
    error_message = "Each policy_assignments[*].scope_type must be one of resource_group, subscription or management_group."
  }

  validation {
    condition = alltrue([
      for a in values(var.policy_assignments) :
      length(compact([a.builtin, a.policy_definition_id, a.policy_set_definition_id])) == 1
    ])
    error_message = "Each policy_assignments[*] must set exactly one of builtin, policy_definition_id or policy_set_definition_id."
  }

  validation {
    condition = alltrue([
      for a in values(var.policy_assignments) :
      a.builtin == null ? true : contains(local.builtin_catalog_keys, a.builtin)
    ])
    error_message = "policy_assignments[*].builtin must be a key of the built in catalog (see the builtin_catalog output for the valid keys)."
  }

  validation {
    condition = alltrue([
      for a in values(var.policy_assignments) :
      contains(["Default", "DoNotEnforce"], a.enforcement_mode)
    ])
    error_message = "Each policy_assignments[*].enforcement_mode must be Default or DoNotEnforce."
  }

  validation {
    condition = alltrue([
      for a in values(var.policy_assignments) :
      contains(["SystemAssigned", "UserAssigned", "None"], a.identity_type)
    ])
    error_message = "Each policy_assignments[*].identity_type must be SystemAssigned, UserAssigned or None."
  }
}
