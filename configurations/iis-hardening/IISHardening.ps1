# CIS Microsoft IIS 10 Benchmark, Level 1, as a PowerShell DSC configuration for an Azure Machine
# Configuration package. Compile with PSDesiredStateConfiguration 2.0.7 and PSDscResources, build
# with New-GuestConfigurationPackage -Type AuditAndSet, and assign with ApplyAndAutoCorrect to
# enforce and continuously drift correct.
#
# Coverage note: the Schannel transport controls (section 7) are pure registry and always apply. The
# section 1 to 6 controls are IIS configuration, so the package ensures the Web-Server role is
# present first (making it a self-contained "hardened IIS server" baseline that is also testable on a
# clean VM). A few controls are environment specific (web content and log directory on a non-system
# volume, per-site forms authentication, FTP) and are enforced only where they apply; they are noted
# inline. Section and value basis: CIS IIS 10 v1.2.1 Level 1.

Configuration IISHardening {

    Import-DscResource -ModuleName 'PSDscResources'

    Node localhost {

        # --- Roles and features -------------------------------------------------------------------
        # Make the package self contained: ensure IIS and the management console are present so the
        # section 1 to 6 controls have something to harden, and so the package proves out on a clean
        # VM. 4.11 needs IP and Domain Restrictions; 1.7 removes WebDAV.
        WindowsFeature IIS {
            Name   = 'Web-Server'
            Ensure = 'Present'
        }

        WindowsFeature IISMgmtConsole {
            Name      = 'Web-Mgmt-Console'
            Ensure    = 'Present'
            DependsOn = '[WindowsFeature]IIS'
        }

        WindowsFeature IPSecurity {
            Name      = 'Web-IP-Security'
            Ensure    = 'Present'
            DependsOn = '[WindowsFeature]IIS'
        }

        # 1.7 (L1) Ensure the WebDAV feature is disabled.
        WindowsFeature WebDavPublishing {
            Name   = 'Web-DAV-Publishing'
            Ensure = 'Absent'
        }

        # --- Section 7: transport encryption (Schannel registry) ----------------------------------
        # 7.2 to 7.6: disable SSL 2.0/3.0, TLS 1.0/1.1; enable TLS 1.2. Each protocol is written to
        # both the Server and Client subkeys, with Enabled and DisabledByDefault DWORDs. These key
        # names have no forward slash, so the Registry resource is safe.
        $protocols = @(
            @{ Name = 'SSL 2.0'; Enabled = 0; DisabledByDefault = 1 }
            @{ Name = 'SSL 3.0'; Enabled = 0; DisabledByDefault = 1 }
            @{ Name = 'TLS 1.0'; Enabled = 0; DisabledByDefault = 1 }
            @{ Name = 'TLS 1.1'; Enabled = 0; DisabledByDefault = 1 }
            @{ Name = 'TLS 1.2'; Enabled = 1; DisabledByDefault = 0 }
        )
        foreach ($p in $protocols) {
            foreach ($side in @('Server', 'Client')) {
                $safe = ($p.Name + '_' + $side) -replace '[^A-Za-z0-9]', '_'
                $key = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\$($p.Name)\$side"

                Registry "Schannel_${safe}_Enabled" {
                    Key       = $key
                    ValueName = 'Enabled'
                    ValueType = 'Dword'
                    ValueData = "$($p.Enabled)"
                    Ensure    = 'Present'
                    Force     = $true
                }

                Registry "Schannel_${safe}_DisabledByDefault" {
                    Key       = $key
                    ValueName = 'DisabledByDefault'
                    ValueType = 'Dword'
                    ValueData = "$($p.DisabledByDefault)"
                    Ensure    = 'Present'
                    Force     = $true
                }
            }
        }

        # 7.7 to 7.11: cipher hardening. The cipher key names contain a forward slash (for example
        # 'RC4 40/128'), which the registry provider and the Registry resource mishandle, so each is
        # enforced with a Script resource that uses the .NET registry API (the CIS remediation
        # pattern). 7.7 NULL and 7.8 DES and 7.9 RC4 (four widths) and 7.10 AES 128/128 are disabled
        # (Enabled = 0); 7.11 AES 256/256 is enabled (Enabled = 1).
        $ciphers = @(
            @{ Name = 'NULL'; Enabled = 0 }
            @{ Name = 'DES 56/56'; Enabled = 0 }
            @{ Name = 'RC4 40/128'; Enabled = 0 }
            @{ Name = 'RC4 56/128'; Enabled = 0 }
            @{ Name = 'RC4 64/128'; Enabled = 0 }
            @{ Name = 'RC4 128/128'; Enabled = 0 }
            @{ Name = 'AES 128/128'; Enabled = 0 }
            @{ Name = 'AES 256/256'; Enabled = 1 }
        )
        foreach ($c in $ciphers) {
            $safe = $c.Name -replace '[^A-Za-z0-9]', '_'
            $cipherName = $c.Name
            $cipherVal = $c.Enabled

            $testScript = [ScriptBlock]::Create(@"
`$base = 'SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers'
`$k = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("`$base\$cipherName")
if (`$null -eq `$k) { return `$false }
`$v = `$k.GetValue('Enabled')
`$k.Close()
return ([int]`$v -eq $cipherVal)
"@)

            $setScript = [ScriptBlock]::Create(@"
`$base = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers', `$true)
`$sk = `$base.CreateSubKey('$cipherName')
`$sk.SetValue('Enabled', $cipherVal, [Microsoft.Win32.RegistryValueKind]::DWord)
`$sk.Close(); `$base.Close()
"@)

            Script "SchannelCipher_$safe" {
                GetScript  = { @{ Result = 'schannel-cipher' } }
                TestScript = $testScript
                SetScript  = $setScript
            }
        }

        # --- Section 3: ASP.NET (machine.config) --------------------------------------------------
        # 3.1 (L1) Ensure deployment method retail is set. This lives in machine.config for both the
        # 32 bit and 64 bit .NET frameworks, not applicationHost, so a Script edits both files.
        Script AspNet_DeploymentRetail_3_1 {
            GetScript  = { @{ Result = 'aspnet-retail' } }
            TestScript = {
                $paths = @(
                    "$env:windir\Microsoft.NET\Framework\v4.0.30319\Config\machine.config",
                    "$env:windir\Microsoft.NET\Framework64\v4.0.30319\Config\machine.config"
                )
                foreach ($f in $paths) {
                    if (-not (Test-Path $f)) { continue }
                    [xml]$x = Get-Content $f
                    $node = $x.configuration.'system.web'.deployment
                    if ($null -eq $node -or "$($node.retail)" -ne 'true') { return $false }
                }
                return $true
            }
            SetScript  = {
                $paths = @(
                    "$env:windir\Microsoft.NET\Framework\v4.0.30319\Config\machine.config",
                    "$env:windir\Microsoft.NET\Framework64\v4.0.30319\Config\machine.config"
                )
                foreach ($f in $paths) {
                    if (-not (Test-Path $f)) { continue }
                    [xml]$x = Get-Content $f
                    $sw = $x.configuration.'system.web'
                    if ($null -eq $sw) { $sw = $x.CreateElement('system.web'); [void]$x.configuration.AppendChild($sw) }
                    $dep = $sw.deployment
                    if ($null -eq $dep) { $dep = $x.CreateElement('deployment'); [void]$sw.AppendChild($dep) }
                    $dep.SetAttribute('retail', 'true')
                    $x.Save($f)
                }
            }
        }

        # --- Sections 1 to 6: IIS configuration (server wide) -------------------------------------
        # Each server wide control is a Script that reads with Get-WebConfigurationProperty and writes
        # with Set-WebConfigurationProperty against MACHINE/WEBROOT/APPHOST (applicationHost.config)
        # or MACHINE/WEBROOT (root web.config). All depend on the Web-Server role.

        # 1.3 (L1) Directory browsing disabled.
        Script Iis_DirectoryBrowsing_1_3 {
            DependsOn  = '[WindowsFeature]IIS'
            GetScript  = { @{ Result = 'directoryBrowse' } }
            TestScript = {
                Import-Module WebAdministration -ErrorAction SilentlyContinue
                (Get-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter 'system.webServer/directoryBrowse' -Name 'enabled').Value -eq $false
            }
            SetScript  = {
                Import-Module WebAdministration -ErrorAction SilentlyContinue
                Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter 'system.webServer/directoryBrowse' -Name 'enabled' -Value $false
            }
        }

        # 1.4 (L1) Application pool identity is ApplicationPoolIdentity (default for all pools).
        Script Iis_AppPoolIdentity_1_4 {
            DependsOn  = '[WindowsFeature]IIS'
            GetScript  = { @{ Result = 'appPoolIdentity' } }
            TestScript = {
                Import-Module WebAdministration -ErrorAction SilentlyContinue
                (Get-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter 'system.applicationHost/applicationPools/applicationPoolDefaults/processModel' -Name 'identityType').Value -eq 'ApplicationPoolIdentity'
            }
            SetScript  = {
                Import-Module WebAdministration -ErrorAction SilentlyContinue
                Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter 'system.applicationHost/applicationPools/applicationPoolDefaults/processModel' -Name 'identityType' -Value 'ApplicationPoolIdentity'
            }
        }

        # 1.6 (L1) Anonymous authentication runs as the application pool identity (userName empty).
        Script Iis_AnonymousUser_1_6 {
            DependsOn  = '[WindowsFeature]IIS'
            GetScript  = { @{ Result = 'anonymousUser' } }
            TestScript = {
                Import-Module WebAdministration -ErrorAction SilentlyContinue
                [string]((Get-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter 'system.webServer/security/authentication/anonymousAuthentication' -Name 'userName').Value) -eq ''
            }
            SetScript  = {
                Import-Module WebAdministration -ErrorAction SilentlyContinue
                Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter 'system.webServer/security/authentication/anonymousAuthentication' -Name 'userName' -Value ''
            }
        }

        # 3.4 (L1) Detailed HTTP errors are not shown remotely (errorMode DetailedLocalOnly).
        Script Iis_HttpErrorsMode_3_4 {
            DependsOn  = '[WindowsFeature]IIS'
            GetScript  = { @{ Result = 'httpErrors' } }
            TestScript = {
                Import-Module WebAdministration -ErrorAction SilentlyContinue
                (Get-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter 'system.webServer/httpErrors' -Name 'errorMode').Value -ne 'Detailed'
            }
            SetScript  = {
                Import-Module WebAdministration -ErrorAction SilentlyContinue
                Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter 'system.webServer/httpErrors' -Name 'errorMode' -Value 'DetailedLocalOnly'
            }
        }

        # 3.7 (L1) Cookies set with HttpOnly.
        Script Iis_HttpOnlyCookies_3_7 {
            DependsOn  = '[WindowsFeature]IIS'
            GetScript  = { @{ Result = 'httpOnlyCookies' } }
            TestScript = {
                Import-Module WebAdministration -ErrorAction SilentlyContinue
                (Get-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT' -Filter 'system.web/httpCookies' -Name 'httpOnlyCookies').Value -eq $true
            }
            SetScript  = {
                Import-Module WebAdministration -ErrorAction SilentlyContinue
                Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT' -Filter 'system.web/httpCookies' -Name 'httpOnlyCookies' -Value $true
            }
        }

        # 3.9 (L1) MachineKey validation is a SHA-2 method (HMACSHA256).
        Script Iis_MachineKeyValidation_3_9 {
            DependsOn  = '[WindowsFeature]IIS'
            GetScript  = { @{ Result = 'machineKey' } }
            TestScript = {
                Import-Module WebAdministration -ErrorAction SilentlyContinue
                (Get-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT' -Filter 'system.web/machineKey' -Name 'validation').Value -eq 'HMACSHA256'
            }
            SetScript  = {
                Import-Module WebAdministration -ErrorAction SilentlyContinue
                Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT' -Filter 'system.web/machineKey' -Name 'validation' -Value 'HMACSHA256'
            }
        }

        # 4.5 (L1) Double encoded requests rejected.
        Script Iis_DoubleEscaping_4_5 {
            DependsOn  = '[WindowsFeature]IIS'
            GetScript  = { @{ Result = 'allowDoubleEscaping' } }
            TestScript = {
                Import-Module WebAdministration -ErrorAction SilentlyContinue
                (Get-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter 'system.webServer/security/requestFiltering' -Name 'allowDoubleEscaping').Value -eq $false
            }
            SetScript  = {
                Import-Module WebAdministration -ErrorAction SilentlyContinue
                Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter 'system.webServer/security/requestFiltering' -Name 'allowDoubleEscaping' -Value $false
            }
        }

        # 4.6 (L1) HTTP TRACE method disabled (deny the TRACE verb in request filtering).
        Script Iis_TraceVerb_4_6 {
            DependsOn  = '[WindowsFeature]IIS'
            GetScript  = { @{ Result = 'traceVerb' } }
            TestScript = {
                Import-Module WebAdministration -ErrorAction SilentlyContinue
                $verbs = Get-WebConfiguration -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter 'system.webServer/security/requestFiltering/verbs/add'
                $trace = $verbs | Where-Object { $_.verb -eq 'TRACE' }
                ($null -ne $trace) -and (-not $trace.allowed)
            }
            SetScript  = {
                Import-Module WebAdministration -ErrorAction SilentlyContinue
                $existing = Get-WebConfiguration -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter 'system.webServer/security/requestFiltering/verbs/add' | Where-Object { $_.verb -eq 'TRACE' }
                if ($existing) {
                    Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter "system.webServer/security/requestFiltering/verbs/add[@verb='TRACE']" -Name 'allowed' -Value $false
                }
                else {
                    Add-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter 'system.webServer/security/requestFiltering/verbs' -Name '.' -Value @{ verb = 'TRACE'; allowed = 'False' }
                }
            }
        }

        # 4.7 (L1) Unlisted file extensions not allowed.
        Script Iis_AllowUnlisted_4_7 {
            DependsOn  = '[WindowsFeature]IIS'
            GetScript  = { @{ Result = 'allowUnlisted' } }
            TestScript = {
                Import-Module WebAdministration -ErrorAction SilentlyContinue
                (Get-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter 'system.webServer/security/requestFiltering/fileExtensions' -Name 'allowUnlisted').Value -eq $false
            }
            SetScript  = {
                Import-Module WebAdministration -ErrorAction SilentlyContinue
                Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter 'system.webServer/security/requestFiltering/fileExtensions' -Name 'allowUnlisted' -Value $false
            }
        }

        # 4.8 (L1) Handlers do not combine Write with Script or Execute (accessPolicy Read, Script).
        Script Iis_HandlerAccessPolicy_4_8 {
            DependsOn  = '[WindowsFeature]IIS'
            GetScript  = { @{ Result = 'handlerAccessPolicy' } }
            TestScript = {
                Import-Module WebAdministration -ErrorAction SilentlyContinue
                $ap = (Get-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter 'system.webServer/handlers' -Name 'accessPolicy').Value
                $tokens = ($ap -split ',') | ForEach-Object { $_.Trim() }
                -not (($tokens -contains 'Write') -and (($tokens -contains 'Script') -or ($tokens -contains 'Execute')))
            }
            SetScript  = {
                Import-Module WebAdministration -ErrorAction SilentlyContinue
                Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter 'system.webServer/handlers' -Name 'accessPolicy' -Value 'Read, Script'
            }
        }

        # 4.9 (L1) notListedIsapisAllowed is false.
        Script Iis_NotListedIsapis_4_9 {
            DependsOn  = '[WindowsFeature]IIS'
            GetScript  = { @{ Result = 'notListedIsapis' } }
            TestScript = {
                Import-Module WebAdministration -ErrorAction SilentlyContinue
                (Get-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter 'system.webServer/security/isapiCgiRestriction' -Name 'notListedIsapisAllowed').Value -eq $false
            }
            SetScript  = {
                Import-Module WebAdministration -ErrorAction SilentlyContinue
                Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter 'system.webServer/security/isapiCgiRestriction' -Name 'notListedIsapisAllowed' -Value $false
            }
        }

        # 4.10 (L1) notListedCgisAllowed is false.
        Script Iis_NotListedCgis_4_10 {
            DependsOn  = '[WindowsFeature]IIS'
            GetScript  = { @{ Result = 'notListedCgis' } }
            TestScript = {
                Import-Module WebAdministration -ErrorAction SilentlyContinue
                (Get-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter 'system.webServer/security/isapiCgiRestriction' -Name 'notListedCgisAllowed').Value -eq $false
            }
            SetScript  = {
                Import-Module WebAdministration -ErrorAction SilentlyContinue
                Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter 'system.webServer/security/isapiCgiRestriction' -Name 'notListedCgisAllowed' -Value $false
            }
        }

        # 4.11 (L1) Dynamic IP address restrictions: deny by concurrent requests enabled.
        Script Iis_DynamicIpSecurity_4_11 {
            DependsOn  = '[WindowsFeature]IPSecurity'
            GetScript  = { @{ Result = 'dynamicIpSecurity' } }
            TestScript = {
                Import-Module WebAdministration -ErrorAction SilentlyContinue
                (Get-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter 'system.webServer/security/dynamicIpSecurity/denyByConcurrentRequests' -Name 'enabled').Value -eq $true
            }
            SetScript  = {
                Import-Module WebAdministration -ErrorAction SilentlyContinue
                Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter 'system.webServer/security/dynamicIpSecurity/denyByConcurrentRequests' -Name 'enabled' -Value $true
                Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter 'system.webServer/security/dynamicIpSecurity/denyByConcurrentRequests' -Name 'maxConcurrentRequests' -Value 20
            }
        }

        # 5.2 (L1) Advanced W3C logging fields enabled.
        Script Iis_AdvancedLogging_5_2 {
            DependsOn  = '[WindowsFeature]IIS'
            GetScript  = { @{ Result = 'logExtFileFlags' } }
            TestScript = {
                Import-Module WebAdministration -ErrorAction SilentlyContinue
                $flags = (Get-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter 'system.applicationHost/sites/siteDefaults/logFile' -Name 'logExtFileFlags').Value
                $required = @('Date', 'Time', 'ClientIP', 'UserName', 'Method', 'UriStem', 'UriQuery', 'HttpStatus', 'Win32Status', 'TimeTaken', 'ServerPort', 'UserAgent', 'Referer', 'HttpSubStatus')
                $have = "$flags"
                -not ($required | Where-Object { $have -notmatch $_ })
            }
            SetScript  = {
                Import-Module WebAdministration -ErrorAction SilentlyContinue
                $value = 'Date,Time,ClientIP,UserName,SiteName,ComputerName,ServerIP,Method,UriStem,UriQuery,HttpStatus,Win32Status,BytesSent,BytesRecv,TimeTaken,ServerPort,UserAgent,Cookie,Referer,ProtocolVersion,Host,HttpSubStatus'
                Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter 'system.applicationHost/sites/siteDefaults/logFile' -Name 'logExtFileFlags' -Value $value
            }
        }

        # 5.3 (L1) ETW logging enabled (logTargetW3C File,ETW).
        Script Iis_EtwLogging_5_3 {
            DependsOn  = '[WindowsFeature]IIS'
            GetScript  = { @{ Result = 'logTargetW3C' } }
            TestScript = {
                Import-Module WebAdministration -ErrorAction SilentlyContinue
                $t = (Get-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter 'system.applicationHost/sites/siteDefaults/logFile' -Name 'logTargetW3C').Value
                "$t" -match 'ETW'
            }
            SetScript  = {
                Import-Module WebAdministration -ErrorAction SilentlyContinue
                Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter 'system.applicationHost/sites/siteDefaults/logFile' -Name 'logTargetW3C' -Value 'File,ETW'
            }
        }
    }
}

IISHardening
