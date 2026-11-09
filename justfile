# Release Microsoft Defender for Endpoint (mdatp) through Red Hat Satellite, one stage at a
# time. Run `just` to list the recipes, `just status` to see where the current release is.
#
# You need uv (https://docs.astral.sh/uv/). Install just with `uv tool install rust-just` or
# `brew install just`. Every stage recipe passes extra arguments to ansible-playbook, for
# example: just test --ask-vault-pass --limit el9-test.example.com

set shell := ["bash", "-euo", "pipefail", "-c"]

playbook := "uv run ansible-playbook"

# List the recipes.
default:
    @just --list

# Install the pinned Python tools, and the roles and collections the playbooks use.
deps:
    uv sync --locked
    uv run ansible-galaxy install -r requirements.yml -p .ansible/roles --force
    uv run ansible-galaxy collection install -r requirements.yml -p .ansible/collections

# Copy the example inventory to inventory/local (git-ignored) for you to edit.
init:
    [[ -e inventory/local ]] && { echo "inventory/local already exists" >&2; exit 1; } || cp -r inventory/example inventory/local
    cp inventory/local/group_vars/all/vault.yml.example inventory/local/group_vars/all/vault.yml
    @echo "Edit inventory/local, then encrypt inventory/local/group_vars/all/vault.yml with ansible-vault encrypt."

# Show where the current release is and what to run next.
status *args:
    {{ playbook }} playbooks/status.yml {{ args }}

# 1. Download and verify the release from packages.microsoft.com.
download *args:
    {{ playbook }} playbooks/01-download.yml {{ args }}

# 2. Upload it to the test Satellite and publish to the test environment.
stage *args:
    {{ playbook }} playbooks/02-stage.yml {{ args }}

# 3. Optional: build the test VMs in Aria Automation and write them to the inventory.
provision *args:
    {{ playbook }} playbooks/03-provision.yml {{ args }}

# 4. Add your SSH key to the test VMs (first run uses the build password from vault).
bootstrap *args:
    {{ playbook }} playbooks/04-bootstrap.yml {{ args }}

# 5. Install the release on the test VMs and check it.
test *args:
    {{ playbook }} playbooks/05-test.yml {{ args }}

# 6. Release to production, after a passing test and your confirmation.
release *args:
    {{ playbook }} playbooks/06-release.yml {{ args }}

# 7. Optional: delete the test VMs built by the provision stage.
teardown *args:
    {{ playbook }} playbooks/07-teardown.yml {{ args }}

# Lint the YAML, the playbooks (ansible-lint, production profile) and the workflows (zizmor).
lint: deps
    uv run yamllint .
    uv run ansible-lint
    uv run zizmor --offline .github/workflows

# Syntax-check every playbook against the example inventory.
syntax: deps
    {{ playbook }} -i inventory/example --syntax-check playbooks/0*.yml playbooks/status.yml

# Scan the full git history for secrets (needs gitleaks on PATH).
secrets:
    gitleaks git --redact --verbose .

# Tag a version of the playbooks and push the tag: just tag 1.0.0
tag version:
    [[ '{{ version }}' =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "version must be semver, for example 1.0.0" >&2; exit 1; }
    git tag -a '{{ version }}' -m 'Release {{ version }}'
    git push origin '{{ version }}'
