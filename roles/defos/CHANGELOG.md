# Changelog

All notable changes to this role will be documented in this file.

Format: https://keepachangelog.com/en/1.0.0/

## [Unreleased]

### Added
- PowerShell Module Logging
- Process Creation Logging
- PowerShell Script Logging
- Firewall rules for RDP
- Firewall rules for remoteadmin base
- Firewall rules for SSH

## [1.0.5] - 2026-02-24
### Updated
- `roles/defos/tasks/07-packages.yml` to install .NET 4.8 on Server 2019 prior to installing chocolatey packages
- `roles/defos/tasks/08-ssh.yml` Updated to ensure the service is started and set to automatic, and configured a jinja2 template that is applied to the host to configure the SSHD service
## [1.0.4] - 2026-02-16
### Updated
- If `## [Unreleased]` didn't exist, the script will prepend a normalized Unreleased header and proceed.
- If `Unreleased` had content, that content is moved into the new version block and `Unreleased` becomes a clean stub ready for future notes.
- If `Unreleased` was empty (or only whitespace), the script creates a stub and writes `- N/A` under `### Added` (so releases have non-empty notes).

The script still updates roles/defos/meta/main.yml, commits, tags, and pushes.
## [1.0.2] - 2026-02-16
### Added
- CHANGELOG.md to track changes

### Changed
- N/A

### Fixed
- N/A

## [1.0.1] - 2026-02-16
## [1.0.0] - 2026-02-16
### Added
- Initial release of the `defos` role: ensures a Windows event source exists. See `meta/main.yml` for author and platform metadata. (Initial import)
