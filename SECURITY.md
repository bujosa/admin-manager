# Security and local data

Do not commit credentials, connection URLs, local preferences, device inventories,
or screenshots containing private data. Report vulnerabilities privately through
GitHub private vulnerability reporting; never include live secrets in public issues.

## Credential storage

Credentials entered in the app are stored in the macOS login Keychain using
non-synchronizing, device-only items. Existing credentials in UserDefaults are
migrated on launch. Plaintext preferences are removed only after a successful
Keychain write and read-back verification. If Keychain is unavailable, migration
keeps the previous value and reports an error; unlock Keychain and reopen the app.

A locally installed app's preferences and Keychain items are separate from the
source checkout and must never be included in a release. A database password or
API key previously committed to any repository must be revoked by its owner;
removing it from the current source does not revoke it or remove older copies.

## AdminManager boundaries

SSH passwords continue to use macOS Keychain. Device addresses, usernames and
command preferences stay in local app preferences. SSH password authentication
uses a short-lived helper in an owner-only temporary directory; it is removed
after the connection attempt. Prefer SSH agent/key authentication where possible.
SSH host keys use OpenSSH's accept-new behavior: verify a new server's identity
out of band. Remote terminals and administration commands act with the selected
SSH account's permissions. AI prompts may include selected device information;
use only providers you intend to receive that context. AI-generated commands
always require review and an explicit Run action; the model cannot authorize
automatic shell execution.

## Read-only system inventory

Storage reads block-device metadata, mount points, filesystem capacity and system
resource counters through the existing SSH connection (or the explicit localhost
device). Linux uses util-linux/proc, macOS uses diskutil property lists and sysctl,
and Windows uses fixed PowerShell Storage/CIM queries. Inventory requires no sudo
or disk modification. Windows probes do not change execution policy or profiles.
Results stay in memory. Disk labels and mount paths may identify
private shares: redact them before sharing diagnostics or screenshots. If a
refresh fails, the previous snapshot is labelled as previous data. Missing tools
produce warnings; missing usage measurements remain unavailable. SMART health
is not inferred from mount state.
