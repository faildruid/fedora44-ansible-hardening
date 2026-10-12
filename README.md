# Fedora 44 security baseline + nightly ClamAV CIFS scans (Ansible)

## Inventory / configuration

1. For the current localhost-only workflow, keep `inventory/hosts.ini` pointed at the local Fedora 44 host.
2. Put host-specific values in `host_vars/localhost.yml`; use `group_vars/all.yml` for shared defaults that apply to all hosts.
3. Confirm you have sudo access and an existing working SSH management path.

Example local inventory:

```ini
[fedora_servers]
localhost ansible_connection=local ansible_user=root
```

## Secrets and local setup

This project is currently intended for a local test host, so the password is kept in `host_vars/localhost.yml` and Ansible auto-loads it for the localhost host.

1. Install Ansible:

```bash
sudo dnf install ansible-core
```

2. Create the local inventory and host vars files from the examples:

```bash
cp inventory/hosts.ini.example inventory/hosts.ini
mkdir -p host_vars
cp host_vars/localhost.yml.example host_vars/localhost.yml
cp .vault_pass.example .vault_pass
chmod 600 .vault_pass
```

3. Edit the local files and replace the example values with your real data:

- `inventory/hosts.ini` should point at the localhost or other target host, as needed.
- `.vault_pass` should contain the vault password for unlocking an encrypted secret file.
- `host_vars/localhost.yml` should contain the actual sudo password:

```yaml
vault_ansible_become_pass: "YourSudoPasswordHere"
ansible_become_pass: "{{ vault_ansible_become_pass }}"
```

4. If you want to encrypt the host-specific vars file before sharing or committing any work:

```bash
ansible-vault encrypt host_vars/localhost.yml
```

5. Keep the following local-only files out of Git; the project already ignores them in `.gitignore`:

- `inventory/hosts.ini`
- `.vault_pass`
- `host_vars/localhost.yml`

> For the localhost-only workflow, Ansible auto-loads `host_vars/localhost.yml`. Do not rely on `group_vars/secrets.yml` unless you explicitly inject it with `-e @group_vars/secrets.yml`.

## Run

```bash
ansible-playbook --syntax-check site.yml
ansible-playbook site.yml --check --diff
ansible-playbook site.yml --limit localhost
ansible-playbook site.yml
```

For tags / selective execution:

```bash
ansible-playbook site.yml --tags clamav
ansible-playbook site.yml --tags validation
```

Use `--ask-become-pass` if necessary. In check mode, dependent unit checks may fail on brand-new hosts where packages/units have not yet been installed; run a staged deployment.

## Defaults

- Installs `clamav`, `clamav-freshclam`, `firewalld`, and SELinux support tooling.
- Enables `clamav-freshclam.service` and a daily `02:00` local-time `clamav-cifs-scan.timer`.
- Scans six example CIFS mount paths listed in `group_vars/all.yml`, **only if each is an actual CIFS mount**. Fails without scanning local fallback directories.
- Scanning is **detection only**: no remove/move/quarantine. Journal logging via `journalctl -u clamav-cifs-scan.service`.
- Enables firewalld but **does not modify** existing rules/zones or open/close SSH/Samba ports.
- Does **not** manage CIFS credentials/fstab, SSH hardening, runtime SELinux enforcement, system upgrades, scheduled DNF automatic updates, or trigger an initial scan unless explicitly enabled.

## Opt-in switches

Edit `group_vars/all.yml` or set host vars:

```yaml
ssh_hardening_enabled: false     # dangerous if key auth not tested
selinux_enforcing: false         # review current policies first
package_upgrade_enabled: false  # avoid surprise restarts
install_dnf_automatic: false     # package only; no auto timer
run_initial_scan: false         # begins full scan asynchronously
```

**SSH caution:** The drop-in can lock you out. Review the effective `sshd -T` config and SSH `Include` ordering; have console/out-of-band access. Test key auth separately before enabling.

**SELinux caution:** Never blindly disable SELinux to fix scanner permissions. Inspect AVC denials.

**Scan caution:** `findmnt` confirms a mountpoint, not server reachability; hung CIFS reads can still stall. `TimeoutStartSec=infinity` follows the runbook and requires external health monitoring. Ensure signatures are successfully downloaded before relying on scan results.

**Credentials:** Keep secrets in Ansible Vault or another secret store, not Git/Gists. The playbook intentionally does not provision CIFS passwords.

## Verification on hosts

```bash
systemctl status clamav-freshclam.service
systemctl list-timers --all clamav-cifs-scan.timer
findmnt -t cifs -o TARGET,SOURCE,FSTYPE
journalctl -u clamav-cifs-scan.service -n 100 --no-pager
getenforce
firewall-cmd --list-all
sshd -T | grep -E '^(permitrootlogin|passwordauthentication|kbdinteractiveauthentication) '
```

## Notes

- Fedora 44 only, controlled by assertion.
- Existing mount definitions and remote SMB ACLs remain untouched; configure separate read-only credentials at SMB server if feasible.
- No automated malware alert destination is configured. Integrate failed-service checks and `DETECTION` logs with your monitoring stack.
- Test in a nonproduction environment / one host first; idempotent deployment is intended, but changes to enabled services and SSH still carry operational risk.
