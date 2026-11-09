# Contributing

Issues and pull requests are welcome. Open an issue first for anything large, so we can agree the approach before you write it.

## Set up

You need [uv](https://docs.astral.sh/uv/) and [just](https://github.com/casey/just). Then:

```bash
just deps      # pinned Python tools, roles and collections
just lint      # yamllint, ansible-lint (production profile), zizmor
just syntax    # every stage playbook against the example inventory
```

## Rules

- Playbooks never hold site values. Everything site-specific is a variable, documented in the README and set in `inventory/example` with made-up values.
- Work that belongs in a role goes in the role, not in a playbook.
- Use fully qualified module names, name every task, and keep `ansible-lint` on the production profile clean.
- Every stage must be safe to run again.
- Never commit an inventory other than `inventory/example`, credentials, packages, real host names or real organisation, product or repository names.
- Docs and comments are in British English.

## Commits and versions

Write commit subjects in the imperative, wrapped at 72 characters. Add an entry under Unreleased in `CHANGELOG.md`. Maintainers tag versions with `just tag 1.2.3`.
