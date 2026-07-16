# Nginx hardening (CIS NGINX Benchmark, Level 1)

`NginxHardening.ps1` is a PowerShell DSC configuration (Linux, PSDSC v3, `nxtools`) mapping the CIS
NGINX Benchmark **v2.1.0 Level 1** to enforceable resources. Build it into a machine configuration
package with `New-LdoMachineConfigPackage -Type AuditAndSet` and assign it per machine with
`ApplyAndAutoCorrect`.

The package ensures nginx is installed (self contained on a clean Ubuntu VM), then enforces:

- **http context directives**, as one managed include `/etc/nginx/conf.d/cis-l1-hardening.conf`:
  autoindex off, server_tokens off, tightened timeouts (keepalive, send, client header and body, all
  10s), bounded `client_max_body_size` and `large_client_header_buffers`, error logging at info,
  modern `ssl_protocols` and strong `ssl_ciphers` with server preference, custom DH parameters, HSTS,
  and the X-Frame-Options and X-Content-Type-Options response headers. One managed file keeps the
  directives in the right context and idempotent (re-runs never stack duplicates).
- **Filesystem, account and rotation controls** as `nxScript` check-and-set resources: the service
  account is locked with an invalid shell, `/etc/nginx` is owned root and access restricted, the PID
  file is secured, default pages do not reference nginx, logs rotate weekly keeping 13, TLS private
  keys are mode 400, and custom Diffie-Hellman parameters are generated once.

Server and location scoped controls (HTTP to HTTPS redirect, reject unknown host, approved methods)
ship as a ready to include snippet at `/etc/nginx/snippets/cis-l1-server.conf` and are audited rather
than force injected, so an existing site's `nginx -t` is never broken. Every config-touching change
finishes with `nginx -t`.

Compile with the `PSDesiredStateConfiguration` 3.0.0 prerelease and `nxtools`. The `GuestConfiguration`
build module runs on Ubuntu 18+.
