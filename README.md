# Fedora 44 security baseline + nightly ClamAV CIFS scans (Ansible)

## Inventory / configuration

1. Edit `inventory/hosts.ini` with your Fedora 44 machines and SSH users.
2. Edit `group_vars/all.yml` for site defaults; use `host_vars/<host>.yml` for host-specific scan shares and overrides.
3. Confirm you have sudo access and an existing working SSH management path.

## Secrets and local setup

This project uses Ansible Vault for the sudo password so the real secret is not stored in Git.

1. Install Ansible:

```bash
sudo dnf install ansible-core
```

2. Create the local inventory, vault password, and encrypted secret file from the examples:

```bash
cp inventory/hosts.ini.example inventory/hosts.ini
cp .vault_pass.example .vault_pass
chmod 600 .vault_pass
cp group_vars/secrets.yml.example group_vars/secrets.yml
```

3. Edit the local files and replace the example values with your real data:

- `inventory/hosts.ini` should list the real Fedora 44 hosts or localhost configuration.
- `.vault_pass` should contain the vault password for unlocking the encrypted secret file.
- `group_vars/secrets.yml` should contain the actual sudo password:

```yaml
vault_ansible_become_pass: "YourSudoPasswordHere"
```

4. Encrypt the secret file before you share or commit any work:

```bash
ansible-vault encrypt group_vars/secrets.yml
```

5. Keep the following local-only files out of Git; the project already ignores them in `.gitignore`:

- `inventory/hosts.ini`
- `.vault_pass`
- `group_vars/secrets.yml`

> Do not put the real sudo password in `group_vars/all.yml` or any tracked file. The playbook references `ansible_become_pass: "{{ vault_ansible_become_pass }}"`, and the value is supplied from the encrypted vault file.

## Run

```bash
ansible-playbook --syntax-check site.yml
ansible-playbook site.yml --check --diff
ansible-playbook site.yml --limit fedora1
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
