# Plan-time tests for the module. The azurerm provider is mocked, so no credentials and no cloud
# calls are needed:
#   terraform init -backend=false && terraform test

mock_provider "azurerm" {}

run "onboards_and_assigns_windows_and_linux" {
  command = plan

  variables {
    guest_configuration_extensions = {
      AzurePolicyforWindows = {
        virtual_machine_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ldo-uks-tst-mc/providers/Microsoft.Compute/virtualMachines/vm-win"
        os_type            = "Windows"
      }
      AzurePolicyforLinux = {
        virtual_machine_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ldo-uks-tst-mc/providers/Microsoft.Compute/virtualMachines/vm-lnx"
        os_type            = "Linux"
      }
    }

    machine_configuration_assignments = {
      win_baseline = {
        name               = "AzureWindowsBaseline"
        virtual_machine_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ldo-uks-tst-mc/providers/Microsoft.Compute/virtualMachines/vm-win"
        location           = "uksouth"
        assignment_type    = "Audit"
        version            = "1.*"
      }
      iis_custom = {
        name               = "IISHardening"
        virtual_machine_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ldo-uks-tst-mc/providers/Microsoft.Compute/virtualMachines/vm-win"
        location           = "uksouth"
        assignment_type    = "ApplyAndAutoCorrect"
        content_uri        = "https://ldopkgs.blob.core.windows.net/packages/iis-hardening_1.0.0.zip"
        content_hash       = "ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789"
        parameters         = { "Minimum TLS Version;ExpectedValue" = "1.2" }
      }
    }

    policy_assignments = {
      linux_cis = {
        display_name = "Linux CIS baseline"
        scope_type   = "resource_group"
        scope_id     = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ldo-uks-tst-mc"
        location     = "uksouth"
        builtin      = "linux_cis"
      }
    }
  }

  assert {
    condition     = azurerm_virtual_machine_extension.guest_config["AzurePolicyforWindows"].publisher == "Microsoft.GuestConfiguration"
    error_message = "Windows onboarding extension should use the Microsoft.GuestConfiguration publisher."
  }

  assert {
    condition     = azurerm_virtual_machine_extension.guest_config["AzurePolicyforWindows"].type == "ConfigurationforWindows"
    error_message = "Windows onboarding extension type should be ConfigurationforWindows."
  }

  assert {
    condition     = azurerm_virtual_machine_extension.guest_config["AzurePolicyforLinux"].type == "ConfigurationForLinux"
    error_message = "Linux onboarding extension type should be ConfigurationForLinux."
  }

  assert {
    condition     = azurerm_virtual_machine_extension.guest_config["AzurePolicyforWindows"].type_handler_version == "1.29"
    error_message = "Windows extension should default to the 1.29 type handler version."
  }

  assert {
    condition     = length(azurerm_policy_virtual_machine_configuration_assignment.this) == 2
    error_message = "Two per machine assignments should be created."
  }

  assert {
    condition     = azurerm_policy_virtual_machine_configuration_assignment.this["iis_custom"].configuration[0].assignment_type == "ApplyAndAutoCorrect"
    error_message = "The custom IIS assignment should enforce with ApplyAndAutoCorrect."
  }

  assert {
    condition     = azurerm_policy_virtual_machine_configuration_assignment.this["iis_custom"].configuration[0].content_uri != null
    error_message = "The custom IIS assignment should carry a content_uri."
  }

  assert {
    condition     = azurerm_policy_virtual_machine_configuration_assignment.this["iis_custom"].configuration[0].version == "1.0.0"
    error_message = "A custom package assignment without an explicit version should default to 1.0.0 (the service rejects custom assignments with a null version)."
  }

  assert {
    condition     = azurerm_resource_group_policy_assignment.this["linux_cis"].policy_definition_id == "/providers/Microsoft.Authorization/policyDefinitions/a3be3bae-0be0-4903-a924-edb7375c1d2e"
    error_message = "The linux_cis builtin key should resolve to the verified CIS Linux definition id."
  }

  assert {
    condition     = azurerm_resource_group_policy_assignment.this["linux_cis"].enforce == true
    error_message = "Default enforcement_mode should map to enforce = true."
  }

  assert {
    condition     = azurerm_resource_group_policy_assignment.this["linux_cis"].parameters == jsonencode({ BaselineSettings = { value = "" } })
    error_message = "The linux_cis builtin should default the required BaselineSettings parameter to the stock baseline (empty string), or the service rejects the assignment with MissingPolicyParameter."
  }
}

run "report_only_maps_to_enforce_false" {
  command = plan

  variables {
    policy_assignments = {
      linux_audit = {
        display_name     = "Linux baseline, report only"
        scope_type       = "subscription"
        scope_id         = "/subscriptions/00000000-0000-0000-0000-000000000000"
        location         = "uksouth"
        builtin          = "linux_compute_baseline"
        enforcement_mode = "DoNotEnforce"
      }
    }
  }

  assert {
    condition     = azurerm_subscription_policy_assignment.this["linux_audit"].enforce == false
    error_message = "DoNotEnforce should map to enforce = false (report only)."
  }
}

run "rejects_lowercase_content_hash" {
  command = plan

  variables {
    machine_configuration_assignments = {
      bad_hash = {
        name               = "Broken"
        virtual_machine_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ldo-uks-tst-mc/providers/Microsoft.Compute/virtualMachines/vm-win"
        location           = "uksouth"
        content_uri        = "https://ldopkgs.blob.core.windows.net/packages/x_1.0.0.zip"
        content_hash       = "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789"
      }
    }
  }

  expect_failures = [var.machine_configuration_assignments]
}
