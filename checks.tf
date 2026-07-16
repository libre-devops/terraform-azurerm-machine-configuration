# check blocks run after every plan and apply and warn (without blocking) when an invariant is
# violated. They catch the machine configuration mistakes that Terraform validation cannot: an
# assignment whose virtual machine was never onboarded with the extension, and a management group
# assignment name that will be rejected by the shorter management group limit.

# A per machine assignment does not execute until the Guest Configuration extension is present on
# the virtual machine. Warn when an assignment targets a VM that this module does not also onboard,
# in case onboarding was forgotten (a VM onboarded by another stack is a legitimate exception).
check "assigned_machines_are_onboarded" {
  assert {
    condition = alltrue([
      for a in values(var.machine_configuration_assignments) :
      contains([for e in values(var.guest_configuration_extensions) : e.virtual_machine_id], a.virtual_machine_id)
    ])
    error_message = "A machine_configuration_assignments entry targets a virtual machine that this module does not onboard with a guest_configuration_extensions entry; the assignment will not run until the Guest Configuration extension is installed on that VM."
  }
}

# Management group policy assignment names cannot exceed 24 characters (resource group and
# subscription assignments allow 64). Catch the over length name before Azure rejects it.
check "management_group_assignment_name_length" {
  assert {
    condition     = alltrue([for k in keys(local.mg_assignments) : length(k) <= 24])
    error_message = "A management_group scoped policy_assignments key exceeds 24 characters; management group assignment names are capped at 24."
  }
}
