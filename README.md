<!--
  This is the template for every Libre DevOps Terraform module. When you create a module from it:
    - replace the title, tagline, and the CI workflow / repo name in the badge URLs
    - replace the resources in main.tf, and the variables, outputs, and examples to match
    - run `just docs` (or Sort-LdoTerraform.ps1) to regenerate the section between the markers
-->
<!--
  Keep the title and badges OUTSIDE the centered <div>: the Terraform Registry's markdown renderer
  does not parse markdown inside an HTML block, so a # heading or [![badge]] in the div renders as
  literal text on the registry. Only the logo (HTML) goes in the div.
-->
<div align="center">
  <a href="https://libredevops.org">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="https://libredevops.org/assets/libre-devops-white.png">
      <img alt="Libre DevOps" src="https://libredevops.org/assets/libre-devops-black.png" width="300">
    </picture>
  </a>
</div>

# Terraform Azure Machine Configuration

Onboard machines to Azure Machine Configuration (the modern, cross platform successor to Azure
Automation State Configuration, which retires on 2027-09-30) and audit or enforce PowerShell DSC in
guest state. Assign the built in compute security and CIS baselines across a scope, and apply custom
DSC packages to individual Windows and Linux VMs with continuous drift correction
(`ApplyAndAutoCorrect`). Windows uses PSDSC v2, Linux uses PSDSC v3, and the same model covers Azure
and Arc enabled servers.

[![CI](https://github.com/libre-devops/terraform-azurerm-machine-configuration/actions/workflows/ci.yml/badge.svg)](https://github.com/libre-devops/terraform-azurerm-machine-configuration/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/libre-devops/terraform-azurerm-machine-configuration?sort=semver&label=release)](https://github.com/libre-devops/terraform-azurerm-machine-configuration/releases/latest)
[![Terraform Registry](https://img.shields.io/badge/registry-libre--devops-7B42BC?logo=terraform&logoColor=white)](https://registry.terraform.io/namespaces/libre-devops)
[![License](https://img.shields.io/github/license/libre-devops/terraform-azurerm-machine-configuration)](./LICENSE)

---

## What it does

- **Onboarding.** Installs the Guest Configuration extension (`AzurePolicyforWindows` /
  `AzurePolicyforLinux`) on the VMs you name, so per machine assignments actually execute. The VM
  must carry a system assigned identity (the Libre DevOps VM modules set one by default).
- **Built in baselines at scale.** A curated `builtin` catalog (verified live) resolves friendly
  keys (`windows_cis`, `linux_cis`, `windows_compute_baseline`, `linux_compute_baseline`,
  `prereq_system_assigned`) to the right built in definition or initiative, assigned across a
  resource group, subscription, or management group. Audit by default; enforce is opt in.
- **Custom DSC packages per machine.** Point a machine at a custom package (`content_uri` plus the
  UPPERCASE SHA256 `content_hash`) and choose `Audit`, `ApplyAndMonitor`, or `ApplyAndAutoCorrect`.
  Build the packages with the `LibreDevOpsHelpers` Machine Configuration helpers (which wrap the
  `GuestConfiguration` PowerShell module), as the `complete` example and CI do.
- **Remediation wiring.** Assignments that deploy (`DeployIfNotExists`) get a system assigned
  identity and the role grants they need.

## Usage

```hcl
module "machine_configuration" {
  source = "libre-devops/machine-configuration/azurerm"

  # Onboard a VM (install the Guest Configuration extension).
  guest_configuration_extensions = {
    AzurePolicyforLinux = {
      virtual_machine_id = module.linux_vm.virtual_machine_ids["vm-lnx-ldo-uks-dev-01"]
      os_type            = "Linux"
    }
  }

  # Audit the Linux CIS baseline across the resource group.
  policy_assignments = {
    "mc-linux-cis" = {
      display_name = "Linux CIS baseline (audit)"
      scope_type   = "resource_group"
      scope_id     = module.rg.ids["rg-ldo-uks-dev-01"]
      location     = "uksouth"
      builtin      = "linux_cis"
    }
  }
}
```

## Examples

- [`examples/minimal`](./examples/minimal) - the smallest valid call (required inputs only).
- [`examples/complete`](./examples/complete) - every supported input exercised.

## Developing

Local work needs **PowerShell 7+** and **[`just`](https://github.com/casey/just)**, because the recipes
wrap the [LibreDevOpsHelpers](https://www.powershellgallery.com/packages/LibreDevOpsHelpers)
PowerShell module (the same engine the `libre-devops/terraform-azure` action runs in CI). Install
just with `brew install just`, or `uv tool add rust-just` then `uv run just <recipe>`.

Run `just` to list recipes: `just update-ldo-pwsh` (install or force-update LibreDevOpsHelpers from
PSGallery), `just validate`, `just scan` (Trivy only), `just pwsh-analyze` (PSScriptAnalyzer only),
`just plan`, `just apply`, `just destroy`, `just e2e`, `just test`, and `just docs` (the
plan/apply/destroy recipes mirror the action, including the storage firewall dance; `just e2e`
applies an example then always destroys it, defaulting to `minimal`, so nothing is left running).
Releasing is also `just`:
`just increment-release [patch|minor|major]` bumps, tags, and publishes a GitHub release, and the
Terraform Registry picks up the tag.

## Security scan exceptions

This module is scanned with [Trivy](https://github.com/aquasecurity/trivy); HIGH and CRITICAL
findings fail the build. Any waiver is a deliberate, reviewed decision, never a way to quiet a
finding that should be fixed. Waivers live in [`.trivyignore.yaml`](./.trivyignore.yaml) (the
machine-applied source of truth, passed to Trivy with `--ignorefile`) and are mirrored in the table
below so the reason is auditable.

| Trivy ID | Resource | Finding | Justification |
|----------|----------|---------|---------------|
| AVD-AZU-0013 | `examples/complete` key vault | Vault network ACL does not block by default | Disposable example vault, created + written + read + destroyed in one apply, so it cannot be IP allow-listed before it exists. Public network Allow lets the CI runner write the demo secrets without a per-run firewall dance (the Libre DevOps example convention, matching the linux-vm module). A real vault stays firewalled (module default) and uses the action's allow-list dance. The module creates no key vault. |

To add an exception: add an entry to `.trivyignore.yaml` (`id`, optional `paths` to scope it, and a
`statement` recording why), then add a matching row here. Where the finding is out of this module's
scope, point the justification at the Libre DevOps module that does address it (for example the
private-endpoint module). Both the file and this table are reviewed in the pull request.

## Reference

The Requirements, Providers, Inputs, Outputs, and Resources below are generated by `terraform-docs`.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9.0, < 2.0.0 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | >= 4.0.0, < 5.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | >= 4.0.0, < 5.0.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [azurerm_management_group_policy_assignment.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/management_group_policy_assignment) | resource |
| [azurerm_policy_virtual_machine_configuration_assignment.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/policy_virtual_machine_configuration_assignment) | resource |
| [azurerm_resource_group_policy_assignment.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/resource_group_policy_assignment) | resource |
| [azurerm_role_assignment.remediation](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_subscription_policy_assignment.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subscription_policy_assignment) | resource |
| [azurerm_virtual_machine_extension.guest_config](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/virtual_machine_extension) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_guest_configuration_extensions"></a> [guest\_configuration\_extensions](#input\_guest\_configuration\_extensions) | Guest Configuration VM extensions to install, keyed by a stable name. Installing the<br/>extension is the onboarding step: a per machine configuration assignment will not execute<br/>until the extension is present on the virtual machine, and the virtual machine must carry a<br/>system assigned identity so the platform can report and remediate. Set os\_type to Windows or<br/>Linux; the module picks the correct publisher and type per OS when they are not overridden. | <pre>map(object({<br/>    virtual_machine_id         = string<br/>    os_type                    = string<br/>    type_handler_version       = optional(string)<br/>    auto_upgrade_minor_version = optional(bool, true)<br/>    automatic_upgrade_enabled  = optional(bool, true)<br/>    settings                   = optional(string)<br/>    protected_settings         = optional(string)<br/>    tags                       = optional(map(string))<br/>  }))</pre> | `{}` | no |
| <a name="input_machine_configuration_assignments"></a> [machine\_configuration\_assignments](#input\_machine\_configuration\_assignments) | Per machine (guest configuration) assignments, keyed by a stable name. Onboard a specific<br/>virtual machine to a built in baseline (for example AzureWindowsBaseline or AzureLinuxBaseline,<br/>leaving content\_uri and content\_hash unset) or to a custom DSC package (both content\_uri and<br/>content\_hash required; content\_hash is the UPPERCASE SHA256 of the .zip; the service requires a<br/>version for custom packages, so the module defaults it to 1.0.0 when unset). assignment\_type<br/>defaults to Audit (the safe default); ApplyAndAutoCorrect enforces continuously. The referenced<br/>virtual machine must already carry the Guest Configuration extension (see<br/>guest\_configuration\_extensions) and a system assigned identity. | <pre>map(object({<br/>    name               = string<br/>    virtual_machine_id = string<br/>    location           = string<br/>    assignment_type    = optional(string, "Audit")<br/>    version            = optional(string)<br/>    content_uri        = optional(string)<br/>    content_hash       = optional(string)<br/>    parameters         = optional(map(string), {})<br/>  }))</pre> | `{}` | no |
| <a name="input_policy_assignments"></a> [policy\_assignments](#input\_policy\_assignments) | Scoped Guest Configuration policy assignments, keyed by a stable name: the fleet wide way to<br/>audit or enforce baselines across every machine in a resource group, subscription or management<br/>group. Point each entry at the curated built in catalog with builtin (for example linux\_cis,<br/>windows\_cis, linux\_compute\_baseline, windows\_compute\_baseline, prereq\_system\_assigned), or set<br/>policy\_definition\_id / policy\_set\_definition\_id explicitly. Catalog definitions with required<br/>parameters are defaulted by the module (linux\_cis: BaselineSettings, an empty string, the stock<br/>CIS baseline); anything in parameters overrides the default per key. enforcement\_mode defaults to Default;<br/>set it to DoNotEnforce for report only. A system assigned identity plus remediation role grants<br/>are wired for definitions that deploy (DeployIfNotExists). | <pre>map(object({<br/>    display_name             = string<br/>    description              = optional(string)<br/>    scope_type               = string<br/>    scope_id                 = string<br/>    location                 = string<br/>    builtin                  = optional(string)<br/>    policy_definition_id     = optional(string)<br/>    policy_set_definition_id = optional(string)<br/>    parameters               = optional(any)<br/>    enforcement_mode         = optional(string, "Default")<br/>    not_scopes               = optional(list(string), [])<br/>    identity_type            = optional(string, "SystemAssigned")<br/>    identity_ids             = optional(list(string), [])<br/><br/>    remediation_role_definition_ids = optional(list(string), [])<br/>    remediation_role_scope          = optional(string)<br/>  }))</pre> | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_builtin_catalog"></a> [builtin\_catalog](#output\_builtin\_catalog) | Curated map of friendly key to built in Guest Configuration definition/initiative id. Reference a key via policy\_assignments[*].builtin, or read the id directly. |
| <a name="output_builtin_catalog_keys"></a> [builtin\_catalog\_keys](#output\_builtin\_catalog\_keys) | The valid keys of builtin\_catalog (the accepted values for policy\_assignments[*].builtin). |
| <a name="output_guest_configuration_extension_ids_zipmap"></a> [guest\_configuration\_extension\_ids\_zipmap](#output\_guest\_configuration\_extension\_ids\_zipmap) | Map of extension key to { name, id } for easy composition. |
| <a name="output_guest_configuration_extensions"></a> [guest\_configuration\_extensions](#output\_guest\_configuration\_extensions) | Map of extension key to the installed Guest Configuration extension (id, name, type, virtual\_machine\_id). |
| <a name="output_machine_configuration_assignment_ids_zipmap"></a> [machine\_configuration\_assignment\_ids\_zipmap](#output\_machine\_configuration\_assignment\_ids\_zipmap) | Map of assignment key to { name, id } for easy composition. |
| <a name="output_machine_configuration_assignments"></a> [machine\_configuration\_assignments](#output\_machine\_configuration\_assignments) | Map of assignment key to the per machine Guest Configuration assignment (id, name, virtual\_machine\_id). |
| <a name="output_policy_assignment_ids_zipmap"></a> [policy\_assignment\_ids\_zipmap](#output\_policy\_assignment\_ids\_zipmap) | Map of assignment key to { name, id } across every scope, for easy composition. |
| <a name="output_policy_assignment_principal_ids"></a> [policy\_assignment\_principal\_ids](#output\_policy\_assignment\_principal\_ids) | Map of assignment key to its system assigned identity principal id (null when identity is None). |
| <a name="output_policy_assignments"></a> [policy\_assignments](#output\_policy\_assignments) | Map of assignment key to the scoped policy assignment (id, name, scope\_type, principal\_id of its identity). |
| <a name="output_remediation_role_assignment_ids"></a> [remediation\_role\_assignment\_ids](#output\_remediation\_role\_assignment\_ids) | Map of '<assignment key>:<role definition id>' to the created role assignment id. |
<!-- END_TF_DOCS -->
