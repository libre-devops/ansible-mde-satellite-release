# Security policy

## Reporting a vulnerability

Report vulnerabilities in these playbooks privately, through [GitHub's private vulnerability reporting](https://github.com/libre-devops/ansible-mde-satellite-release/security/advisories/new). Do not open a public issue.

## Keeping your details private

- Your inventory (`inventory/local`) holds your server names, Satellite organisation, products and credentials. Git ignores it. Keep it in a private repository or on the machine you run the stages from, never in a public one.
- Put every password, token and onboarding package in Ansible Vault (`vault.yml` files), and delete the test VMs' build password once the bootstrap stage has added your key.
- The provision stage never writes passwords or tokens to the inventory file it creates.
- `artifacts/` holds the downloaded RPMs, the manifest and the test report. Git ignores it.

## What the stages check

The download stage verifies Microsoft's signature on the repository metadata and each RPM's checksum. The release stage needs a passing test for every RHEL version and your confirmation. See [Safety checks](./README.md#safety-checks).
