# Forwarded into the tags module for the DeployedBranch / DeployedRepo tags. The terraform-azure
# action fills these in CI via TF_VAR_deployed_branch / TF_VAR_deployed_repo; empty when run locally.
variable "deployed_branch" {
  description = "Git branch the deployment came from. Auto-filled in CI from TF_VAR_deployed_branch."
  type        = string
  default     = ""
}

variable "deployed_repo" {
  description = "Repository URL the deployment came from. Auto-filled in CI from TF_VAR_deployed_repo."
  type        = string
  default     = ""
}

# Custom Guest Configuration package hashes. CI builds each package with the helper, computes the
# UPPERCASE SHA256, and passes it via TF_VAR_*; it then uploads the .zip to the deterministic blob
# (the content URI is derived from the package storage account created in this example, so only the
# hash needs to be injected). Empty locally, which gates the custom ApplyAndAutoCorrect assignments
# off so validate and plan succeed without the packages existing.
variable "iis_package_hash" {
  description = "UPPERCASE SHA256 of the IIS hardening package .zip. Empty disables the IIS assignment."
  type        = string
  default     = ""
}

variable "loc" {
  description = "Outfix: short Azure region code used in resource names (for example uks)."
  type        = string
  default     = "uks"
}

variable "nginx_package_hash" {
  description = "UPPERCASE SHA256 of the Nginx hardening package .zip. Empty disables the Nginx assignment."
  type        = string
  default     = ""
}

variable "regions" {
  description = "Map of short region codes to Azure region slugs."
  type        = map(string)
  default = {
    uks = "uksouth"
    ukw = "ukwest"
    eus = "eastus"
    euw = "westeurope"
  }
}

variable "short" {
  description = "Infix: short product code used in resource names."
  type        = string
  default     = "ldo"
}
