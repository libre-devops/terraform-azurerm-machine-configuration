<div align="center">
  <a href="https://libredevops.org">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="https://libredevops.org/assets/libre-devops-white.png">
      <img alt="Libre DevOps" src="https://libredevops.org/assets/libre-devops-black.png" width="200">
    </picture>
  </a>
</div>

# Machine Configuration package catalog

PowerShell DSC source for the custom Azure Machine Configuration packages this module can apply.
Each package is authored here, built into a `.zip` by the `LibreDevOpsHelpers` Machine Configuration
helpers (which wrap the `GuestConfiguration` PowerShell module), uploaded to a storage blob, and then
referenced from a per machine assignment by `content_uri` plus the UPPERCASE SHA256 `content_hash`.

The Terraform module never builds these packages: packaging is imperative (compile a MOF, zip it,
hash it) and stays in the helpers. The module stays declarative and consumes the built coordinates.

## Catalog

| Package | Platform | Standard | DSC building blocks |
|---------|----------|----------|---------------------|
| [`iis-hardening`](./iis-hardening) | Windows | CIS Microsoft IIS 10 Benchmark, Level 1 | `Registry` (Schannel TLS/ciphers) and `Script` (IIS config) from `PSDscResources` |
| [`nginx-hardening`](./nginx-hardening) | Linux | CIS NGINX Benchmark, Level 1 | `nxFile` / `nxFileLine` / `nxScript` / `nxFileSystemObject` from `nxtools` |

## Building a package (what the helper does)

1. Author `Configuration <Name> { Import-DscResource ...; <resources> }` in `<name>/<Name>.ps1`.
2. Dot source and invoke the script to compile `localhost.mof`, then rename it to `<Name>.mof`.
3. `New-GuestConfigurationPackage -Name <Name> -Configuration <Name>.mof -Type AuditAndSet -Force`.
   `AuditAndSet` is required so an assignment can enforce with `ApplyAndAutoCorrect`; use `Audit` for
   audit only packages.
4. `Test-GuestConfigurationPackage` to validate, then upload the `.zip` and compute the UPPERCASE
   SHA256 (`(Get-FileHash -Algorithm SHA256 <zip>).Hash`, already upper case).
5. Feed `content_uri` and `content_hash` into `machine_configuration_assignments`.

## Authoring notes

- **Windows** uses PSDSC v2: compile with `PSDesiredStateConfiguration` 2.0.7 and
  `PSDscResources`. The `GuestConfiguration` module only builds on Ubuntu 18+, but the package it
  produces runs on any supported OS.
- **Linux** uses PSDSC v3 and the `nxtools` resources (the older `nx*` providers are not used by
  machine configuration). File content, single directives, permissions, and arbitrary check and set
  logic are all expressible with `nxFile`, `nxFileLine`, `nxFileSystemObject`, and `nxScript`.
- Keep the uncompressed package under 100 MB. Never put secrets in a package.
