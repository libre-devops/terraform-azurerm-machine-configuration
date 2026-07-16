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
