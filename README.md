<div align="center">
  <a href="https://libredevops.org">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="https://libredevops.org/assets/libre-devops-white.png">
      <img alt="Libre DevOps" src="https://libredevops.org/assets/libre-devops-black.png" width="300">
    </picture>
  </a>
</div>

# MDE Satellite release

Ansible playbooks that release a new version of Microsoft Defender for Endpoint on Linux (`mdatp`) through Red Hat Satellite, one stage at a time: download and verify it from packages.microsoft.com, stage it on a test Satellite, test it on VMs registered to that Satellite, and release it to production once the tests pass and you confirm.

[![CI](https://github.com/libre-devops/ansible-mde-satellite-release/actions/workflows/ci.yml/badge.svg)](https://github.com/libre-devops/ansible-mde-satellite-release/actions/workflows/ci.yml)
[![Licence](https://img.shields.io/github/license/libre-devops/ansible-mde-satellite-release)](./LICENSE)

---

> **Status:** the download stage has run against packages.microsoft.com, and the test stage against a RHEL 9 container standing in for a test VM. Not yet run end to end against a real Satellite, Aria Automation or onboarded test VM.

## The stages

Each stage is a playbook with a `just` recipe. Run them in order, on whatever days suit: the manifest in `artifacts/manifest.json` carries the release from one stage to the next, so every stage works on exactly what the download stage fetched.

| Recipe | Playbook | Runs on | What it does |
|---|---|---|---|
| `just download` | [`01-download.yml`](./playbooks/01-download.yml) | control node | Picks the latest (or a pinned) version for each RHEL version, downloads it, verifies Microsoft's repository signature and each RPM's checksum, and starts a new manifest. |
| `just stage` | [`02-stage.yml`](./playbooks/02-stage.yml) | control node | Uploads the RPMs to the test Satellite, publishes the content views and promotes them to the test environment. |
| `just provision` | [`03-provision.yml`](./playbooks/03-provision.yml) | control node | Optional. Builds the test VMs from an Aria Automation catalog item and writes them to an inventory file. Skip it if you build VMs another way. |
| `just bootstrap` | [`04-bootstrap.yml`](./playbooks/04-bootstrap.yml) | test VMs | Adds your SSH key to the test VMs, using the build password once. |
| `just test` | [`05-test.yml`](./playbooks/05-test.yml) | test VMs | Checks Satellite offers exactly the manifest's version and installs it from Satellite. With a test tenant's packages, onboards each VM, runs the [Defender checks](#the-test-stage), and offboards it again whatever happened. Writes `artifacts/test-report.json` and `test-report.md`. |
| `just release` | [`06-release.yml`](./playbooks/06-release.yml) | control node | Refuses unless every RHEL version passed. Asks you to type the version. Then uploads the same files to the production Satellite (with the test summary in the content view version's description), or promotes the content views, depending on `release_mode`. Writes `artifacts/release-report.md`. |
| `just teardown` | [`07-teardown.yml`](./playbooks/07-teardown.yml) | control node | Optional. Deletes the test VMs the provision stage built. Run it any time after testing, before or after the release. |
| `just status` | [`status.yml`](./playbooks/status.yml) | control node | Shows the release in progress and what to run next. |

```text
download latest RPM ─► stage on the test Satellite ─► provision VMs ─► credentials into inventory and vault ─► bootstrap SSH
   ─► test: install from Satellite ─► onboard ─► Defender checks ─► offboard
   ─► teardown VMs ─► release: promote or upload to production ─► reports for the change record
```

`artifacts/manifest.json` records every stage, so each one works on exactly what the download stage fetched.

The playbooks use these roles, each usable on its own:

| Role | Used by |
|---|---|
| [`libre_devops.rpm_repo_download`](https://github.com/libre-devops/ansible-role-rpm-repo-download) | download |
| [`libre_devops.satellite_content_upload`](https://github.com/libre-devops/ansible-role-satellite-content-upload) | stage, release |
| [`libre_devops.aria_automation_deployment`](https://github.com/libre-devops/ansible-role-aria-automation-deployment) | provision, teardown |
| [`libre_devops.ssh_bootstrap`](https://github.com/libre-devops/ansible-role-ssh-bootstrap) | bootstrap |
| [`libre_devops.mde_linux`](https://github.com/libre-devops/ansible-role-mde-linux) | test |

## Contents

- [Requirements](#requirements)
- [Set up](#set-up)
- [A release, step by step](#a-release-step-by-step)
- [The test stage](#the-test-stage)
- [Reports](#reports)
- [Variables](#variables)
- [Safety checks](#safety-checks)
- [Troubleshooting](#troubleshooting)
- [Developing](#developing)

## Requirements

| What | Detail |
|---|---|
| Control node | Linux or WSL with [uv](https://docs.astral.sh/uv/), [just](https://github.com/casey/just), `git` and `gpg` (to verify Microsoft's signature). For the Satellite stages, the `rpm` command (`apt install rpm` on Ubuntu) or the `rpm` Python bindings. For a first SSH connection with a password, `sshpass`. |
| Network | HTTPS from the control node to packages.microsoft.com, the Satellites and (for provision) Aria Automation. SSH to the test VMs. |
| Satellite | On each Satellite, a product and repository per RHEL version, and content views that include them. The test VMs registered to the test Satellite's test lifecycle environment (or, with two Satellites, to the test Satellite). |
| Test VMs | One per RHEL version in the release, reachable over SSH, with a Python that your `ansible-core` supports. RHEL 7 ships Python 2.7 and 3.6, which `ansible-core` 2.17 and later cannot manage: test RHEL 7 with `ansible-core` 2.16, or leave it out of the test stage. |
| Optional | A test Defender tenant's onboarding and offboarding packages, to onboard, check and offboard the test VMs. An Aria Automation API token and catalog item, for the provision stage. |

## Set up

```bash
git clone https://github.com/libre-devops/ansible-mde-satellite-release.git
cd ansible-mde-satellite-release
just deps     # Python tools, roles and collections
just init     # copies inventory/example to inventory/local, which git ignores
```

Then edit `inventory/local`:

1. `group_vars/all/release.yml`: the package and the RHEL versions to release.
2. `group_vars/all/satellite.yml`: the test and production Satellites, their repositories per RHEL version, content views, and `release_mode`.
3. `group_vars/all/vault.yml`: the Satellite passwords or tokens, then `ansible-vault encrypt inventory/local/group_vars/all/vault.yml`.
4. `group_vars/release_test/`: how to reach the test VMs, which key to add, and the optional test onboarding package.

Keep `inventory/local` out of public repositories: it holds your server names and, encrypted, your credentials. A private copy of this repository, or a separate private repository holding only your inventory, both work.

## A release, step by step

```bash
just download                          # or: just download -e release_version=101.25092.0005
just stage --ask-vault-pass
just status
```

Build a test VM for each RHEL version, registered to the test Satellite. Either let `just provision --ask-vault-pass` build them in Aria Automation (see [Provisioning in Aria Automation](#provisioning-in-aria-automation)), or build them however you normally do. Then:

1. Put each VM in the `release_test` group in `inventory/local/hosts.yml` (provision writes them to `inventory/local/release-test-vms.yml` for you).
2. Put the build password in an encrypted `inventory/local/group_vars/release_test/vault.yml` as `ansible_password`.

```bash
just bootstrap --ask-vault-pass        # adds your SSH key
```

3. Delete `ansible_password` from that vault file: from now on Ansible uses your key.

```bash
just test --ask-vault-pass             # install, onboard, check, offboard; writes the test reports
just teardown --ask-vault-pass         # if provision built the VMs
just release --ask-vault-pass          # asks you to type the version; writes the release report
```

Attach `artifacts/test-report.md` and `artifacts/release-report.md` to the change record.

Run any stage again if it fails: each one is safe to repeat. A test run that fails on one RHEL version can be repeated for that VM alone with `--limit`.

### Provisioning in Aria Automation

The provision stage requests the catalog item once per entry in `release_aria_deployments` (reusing deployments that already exist), waits for the VMs, and writes them to `inventory/local/release-test-vms.yml` in the `release_test` group. It never writes passwords or tokens: you add the credentials yourself, as above. Teardown deletes the deployments and the file.

```yaml
# inventory/local/group_vars/all/aria.yml
release_aria_url: https://aria.example.com
release_aria_refresh_token: "{{ vault_release_aria_refresh_token }}"
release_aria_project: Release testing
release_aria_catalog_item: Linux server
release_aria_deployments:
  - name: mde-release-el8
    inputs: { image: rhel8, cpuCount: 2, memoryMb: 2048 }
  - name: mde-release-el9
    inputs: { image: rhel9, cpuCount: 2, memoryMb: 2048 }
# Only if the address to connect to is not in the machine's address property:
release_aria_host_vars:
  ansible_host: "{{ resource.properties.myAddressProperty }}"
```

The catalog item's inputs and properties are whatever your Aria Automation administrators defined: copy them from the catalog item's request form, or from an existing deployment's properties.

## The test stage

On each VM in `release_test`, `just test`:

1. Checks the VM's RHEL version is in the release, and that Satellite offers exactly the manifest's version (so the VM really is on the test ring).
2. Installs that version from Satellite, upgrading whatever was there, and checks it is installed and the `mdatp` service runs.
3. With `release_test_onboarding_file` and `release_test_offboarding_file` (a test tenant's packages, kept in vault): sets the enforcement level the test needs (`release_test_enforcement_level`, real time by default), onboards the VM, and checks it is licensed, healthy and connected.
4. Runs the Defender checks in `release_test_checks`, each recorded on its own so one failure does not hide the rest:

   | Check | Passes when |
   |---|---|
   | `definitions` | `mdatp definitions update` brings `definitions_status` to `up_to_date` |
   | `engine` | `engine_load_status` reports the engine loaded |
   | `real_time_protection` | `real_time_protection_enabled` and `real_time_protection_available` are both true |
   | `quick_scan` | `mdatp scan quick` completes |
   | `eicar` | Defender removes the EICAR test file within `release_test_retries` x `release_test_delay` seconds |
   | `health_issues` | `health_issues` is empty |

5. Runs your own checks, if `release_test_extra_tasks` names a tasks file.
6. Offboards the VM with the offboarding package, whatever happened above, so a deleted test VM never lingers in the tenant. A failed offboard fails the test and says so.

The EICAR check raises an EICAR alert in the test tenant: that is expected. The test string is put together on the VM from two halves, so no file in this repository holds it and no virus scanner quarantines your clone.

Microsoft's offboarding packages expire (the download carries a "valid until" date). Download a fresh one from the test tenant when it runs out.

### Policy and group membership

These playbooks do not put test VMs into Entra ID groups, and the built-in checks do not need them to: the enforcement level the checks need is set on the test VMs directly.

If you want group-scoped Defender policy on the test VMs as well, note that a VM only gets an Entra device object after it is onboarded, which happens inside the test stage, and that can take from minutes to a day. Two ways work with [`libre_devops.entra_device_groups`](https://github.com/libre-devops/ansible-role-entra-device-groups), which manages device group membership from a JSON list:

- Keep long-lived test VMs (a standing test ring) and their group membership in `exact` mode, so each release is tested on VMs that already have the policies.
- Or run the test stage once to onboard the VMs, run the Entra role once their device objects appear, wait for the policies to arrive, and run the test stage again.

## Reports

| File | Written by | Holds |
|---|---|---|
| `artifacts/test-report.json` | test | Every VM's result and checks. The release stage reads it. |
| `artifacts/test-report.md` | test | The same, as tables for a change record or wiki page. |
| `artifacts/release-report.md` | release | What was released, when, by whom and where, the files and checksums, and the test summary. |
| Content view version description | release (`upload`) | The release and its test summary, kept with the version in Satellite. |

## Variables

All of them live in the inventory, so the playbooks never need editing.

### Release (`group_vars/all/release.yml`)

| Variable | Example | Description |
|---|---|---|
| `release_package` | `mdatp` | Package to release. |
| `release_version` | `latest` | `latest`, or an exact version such as `101.25092.0005`. |
| `release_source_url` | `https://packages.microsoft.com` | Where to download from. |
| `release_repositories` | see example | One entry per RHEL version: `label` (`el8`) and `path` (`rhel/8/prod`). The label links the RPM to its Satellite repository and to the test VM running that version. |

### Satellites (`group_vars/all/satellite.yml`)

| Variable | Description |
|---|---|
| `release_mode` | `upload` (separate test and production Satellites: upload the tested files to production) or `promote` (one Satellite: promote the content views). |
| `release_test_satellite`, `release_prod_satellite` | `server_url`, `organization`, `username`, `password`, `validate_certs`, `ca_path`, `repositories` (a `product` and `repository` per label) and `content_views` (each with `name` and `lifecycle_environments`). |
| `release_promotions` | For `promote`: each with `content_view`, `from` and `to`. |

### Test VMs (`group_vars/release_test/`)

| Variable | Description |
|---|---|
| `ansible_user`, `ansible_ssh_private_key_file`, `ansible_ssh_common_args` | How to reach the VMs. `ansible_password` only for the first bootstrap, in vault. |
| `release_bootstrap_key_files` | Public keys the bootstrap stage adds for `ansible_user`. |
| `release_test_onboarding_file` | Path on the control node to a test tenant's `mdatp_onboard.json` (vaulted). Empty skips onboarding and the Defender checks. |
| `release_test_offboarding_file` | Path to the same tenant's `mdatp_offboard.json` (vaulted). Required with an onboarding file. |
| `release_test_enforcement_level` | Enforcement level set on the test VMs before onboarding (`real_time` by default). Empty leaves their policy alone. |
| `release_test_checks` | Defender checks to run: `definitions`, `engine`, `real_time_protection`, `quick_scan`, `eicar`, `health_issues`. |
| `release_test_verify_connectivity` | With onboarding, also run `mdatp connectivity test`. |
| `release_test_retries`, `release_test_delay` | How long to wait for definitions and the EICAR removal (30 x 10 seconds by default). |
| `release_test_command_timeout` | Longest a definitions update or quick scan may take, in seconds (1800). |
| `release_test_eicar_path` | Where the EICAR test file is written on the VM. |
| `release_test_extra_tasks` | A tasks file of your own checks, run on each VM after the built-in ones. |

Defaults for every variable are in [`playbooks/roles/release/defaults/main.yml`](./playbooks/roles/release/defaults/main.yml). They have the lowest precedence, so your inventory always wins.

### Aria Automation (optional, `group_vars/all/aria.yml`)

Defaults are in [`playbooks/roles/release/defaults/main.yml`](./playbooks/roles/release/defaults/main.yml).

| Variable | Default | Description |
|---|---|---|
| `release_aria_url` | none | Aria Automation URL. |
| `release_aria_refresh_token` | `""` | An API token (refresh token), from vault. Preferred. |
| `release_aria_username`, `release_aria_password`, `release_aria_domain` | `""` | On-premises sign-in instead of a token. |
| `release_aria_validate_certs` | `true` | Check Aria Automation's TLS certificate. |
| `release_aria_project` | `""` | Project, by name or ID. |
| `release_aria_catalog_item` | `""` | Catalog item, by name or ID, for every deployment that does not name its own. |
| `release_aria_deployments` | `[]` | One per test VM: `name`, `inputs`, and optionally its own `catalog_item`, `catalog_item_version`, `project` or `reason`. |
| `release_aria_reason` | `Test VM for an mdatp release` | Reason recorded with each request. |
| `release_aria_inventory_file` | `<inventory>/release-test-vms.yml` | Where provision writes the VMs. |
| `release_aria_host_name` | the machine's `resourceName` | Inventory name of each machine, as a template with `resource`. |
| `release_aria_host_vars` | `ansible_host` from the machine's `address` | Host variables for each machine, as templates with `resource`. Variables whose names look like passwords, secrets or tokens are never written to the file. |

The [`libre_devops.aria_automation_deployment`](https://github.com/libre-devops/ansible-role-aria-automation-deployment) README covers signing in, finding catalog item inputs and machine properties, and its troubleshooting.

## Safety checks

- **Verified downloads.** The download stage checks Microsoft's signature on the repository metadata against Microsoft's published keys, then each RPM's checksum against that metadata, before anything reaches Satellite.
- **One release at a time.** The download stage refuses to start a new release while the manifest holds one that has not reached production. `-e release_restart=true` starts again.
- **The tested file is the released file.** Stage and release both upload the files the manifest lists, and Satellite matches them by checksum. With `promote`, production gets the content view version that was tested.
- **No release without a pass.** The release stage needs a passing result in `artifacts/test-report.json` for every RHEL version, with the manifest's version. A VM that was unreachable counts as a failure.
- **A person confirms.** The release stage stops until you type the version. For a pipeline with its own approval, pass `-e release_confirm=<version>`.
- **Test VMs leave the tenant.** With onboarding, the test stage always offboards each VM after its checks, even when a check or the onboarding failed, and fails the test if offboarding fails.

## Troubleshooting

| Symptom | What to check |
|---|---|
| `... holds a release that has not reached production yet` | Finish that release, or start again with `-e release_restart=true`. |
| `The repositories on this VM do not offer ...` | The VM is not registered to the test Satellite or its test lifecycle environment, or the stage step has not run. On the VM: `subscription-manager identity` and `dnf repolist`. |
| `This VM runs el7, but the manifest only has ...` | Add that RHEL version to `release_repositories`, or take the VM out of `release_test`. |
| `No passing test for ...` | Run `just test` and fix the failures listed in `artifacts/test-report.json`. |
| SSH asks for a password, or `sshpass` is missing | For the first bootstrap only: install `sshpass` and put `ansible_password` in the group's vault file. |
| RHEL 7 test VM fails with a Python version error | See the RHEL 7 note in [Requirements](#requirements). |

Each role's README has its own troubleshooting table, for the download, Satellite, Aria Automation, SSH and Defender steps.

## Developing

| Recipe | What it does |
|---|---|
| `just deps` | Installs the pinned Python tools, and the roles and collections in `requirements.yml` into `.ansible/`. |
| `just lint` | `yamllint`, `ansible-lint` on the production profile, and `zizmor` on the workflows. |
| `just syntax` | Syntax-checks every stage playbook against the example inventory. |
| `just secrets` | Scans the git history with gitleaks. |
| `just tag 1.2.3` | Tags a version of the playbooks. The Release workflow creates a GitHub release. |

CI runs the secret scan, lint and syntax check. The stages run against real Satellites and VMs, so test changes with a real release (or a pinned older version) before relying on them.

## Licence

[MIT](./LICENSE).
