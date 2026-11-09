# Changelog

Notable changes to these playbooks. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## Unreleased

### Added

- First version.
- Stage playbooks with a `just` recipe each: download, stage, provision, bootstrap, test, release, teardown and status.
- A manifest in `artifacts/` that carries the release between stages, and a test report the release stage requires.
- Release by upload to a separate production Satellite, or by promotion on one Satellite.
- Refusals: no new release over an unfinished one, no release without a passing test for every RHEL version, and no release without typing the version.
- An example inventory with made-up values, copied to a git-ignored `inventory/local` by `just init`.
- A test stage that installs from Satellite, onboards to a test tenant, runs the Defender checks (security intelligence, engine, real-time protection, quick scan, EICAR, health issues) and always offboards, with a hook for your own checks.
- Markdown test and release reports for change records, and the test summary in the production content view version's description.
- Defaults in an internal `release` role, so inventory values always win.
