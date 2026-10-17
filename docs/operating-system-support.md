# Operating-system support

The macOS UI owns presentation; `SSHService` owns the existing local/SSH transport
and a per-connection `RemotePlatform` cache. Detection first reads `uname -s`, then
uses a fixed noninteractive Windows PowerShell probe when necessary. FreeBSD is
recognized explicitly. Unknown probes are retryable and never treated as macOS.
Disconnect clears the platform and CPU sample caches.

`DeviceAdminService` selects a fixed inventory command through `RemotePlatform`,
then the platform parser produces the shared `StorageInventory`/`SystemResources`
model. No remote-provided path or volume label is evaluated as shell code. Existing
saved device records do not change and no migration is required.

- Linux keeps the versioned lsblk/findmnt/proc collector and older lsblk fallback.
- macOS uses versioned sections containing diskutil property lists. Physical disk
  classification comes from `diskutil list -plist physical`. Synthesized APFS
  containers link to all reported physical stores. Volume usage and shared
  container availability remain distinct. Available RAM is an estimate of free,
  inactive and speculative pages, rather than Linux MemAvailable semantics.
- Windows uses a UTF-16LE encoded fixed PowerShell command, with profiles disabled
  and noninteractive execution. A version-1 JSON allowlist includes only disk,
  partition, volume and resource fields; serial numbers and storage unique IDs
  are not returned. Storage Spaces, iSCSI, VHD and RAID-presented disks are logical
  for capacity accounting. CIM fallback reports limitations explicitly.

Missing data is optional. Truncated/version-mismatched or malformed responses fail
with a generic error rather than an empty successful inventory. A failed refresh
retains the prior in-memory snapshot and labels it as previous data. Read-only mounts remain neutral even when full. Mac battery current handles signed
and unsigned IOKit representations; charge/discharge power is labelled separately
from package power. Core metrics
must contain the expected platform and valid CPU/RAM values before entering history.
Unsupported platforms cannot invoke a storage adapter or synthesize healthy metrics.

Storage never requests elevation, changes execution policy, installs tools, starts
SSH services or changes partitions/mounts. Existing administration features retain
their own confirmation and platform limitations; this change expands read paths.
Terminal commands still use the remote user's configured shell. SMART, ZFS pool
accounting, vendor NAS APIs and underlying hardware RAID members remain out of scope.

Validation includes synthetic Linux/macOS/Windows parser contracts, APFS physical
relationships/shared capacity, unmounted disks, virtual-disk exclusion, large byte
counts, mount paths with spaces, unknown values and invalid responses. The macOS
collector is exercised locally. The Windows script is exercised in official
PowerShell with synthetic Storage/CIM responses; it still needs a real Windows
OpenSSH host for end-to-end certification. Linux/ZimaOS had a real read-only check
in the preceding storage change. UI review uses an isolated app profile.

References: the installed Apple `diskutil(8)`, `plutil(1)`, `vm_stat(1)` and
`sysctl(8)` manuals; Microsoft [Get-Disk](https://learn.microsoft.com/en-us/powershell/module/storage/get-disk),
[Get-Partition](https://learn.microsoft.com/en-us/powershell/module/storage/get-partition),
[Get-Volume](https://learn.microsoft.com/en-us/powershell/module/storage/get-volume),
and [PowerShell.exe encoding](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_powershell_exe).
