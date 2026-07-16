# IIS hardening (CIS Microsoft IIS 10, Level 1)

`IISHardening.ps1` is a PowerShell DSC configuration mapping the CIS Microsoft IIS 10 Benchmark
**v1.2.1 Level 1** to enforceable resources. Build it into a machine configuration package with
`New-LdoMachineConfigPackage -Type AuditAndSet` and assign it per machine with `ApplyAndAutoCorrect`.

The package ensures the Web-Server role is present (so it is self contained and provable on a clean
Windows VM), then enforces:

- **Transport (section 7):** disable SSL 2.0/3.0 and TLS 1.0/1.1, enable TLS 1.2 (Schannel protocol
  registry keys, Server and Client); disable NULL, DES, RC4 (all widths) and AES 128/128 ciphers and
  enable AES 256/256 (cipher keys carry a forward slash, so they are written with the .NET registry
  API inside a `Script` resource).
- **IIS configuration (sections 1 to 6):** directory browsing off, application pool identity,
  anonymous user as the pool identity, detailed errors local only, HttpOnly cookies, SHA-2 machineKey
  validation, reject double encoded requests, deny the TRACE verb, disallow unlisted extensions,
  handler access policy, ISAPI/CGI restrictions, dynamic IP restrictions, advanced W3C and ETW
  logging, and the ASP.NET deployment retail flag in machine.config.

Environment specific controls (web content and logs on a non-system volume, per-site forms
authentication, FTP) are noted in the source and left to the deploying environment.

Compile with `PSDesiredStateConfiguration` 2.0.7 and `PSDscResources`.
