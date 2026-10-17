import Foundation
import SwiftUI

@Observable
@MainActor
final class DeviceAdminService {

    // MARK: - Read-only Storage Inventory

    var storageInventoryCache: [UUID: StorageInventory] = [:]
    var isLoadingStorage: [UUID: Bool] = [:]
    var storageError: [UUID: String] = [:]

    func fetchStorage(for deviceId: UUID, sshService: SSHService) async {
        guard isLoadingStorage[deviceId] != true else { return }
        isLoadingStorage[deviceId] = true
        storageError[deviceId] = nil
        defer { isLoadingStorage[deviceId] = false }
        do {
            let platform = try await sshService.platform(for: deviceId)
            guard let command = platform.inventoryCommand else { throw InventoryError.unsupported }
            let output = try await sshService.executeCommand(command, on: deviceId)
            storageInventoryCache[deviceId] = try platform.parseInventory(output)
        } catch let error as InventoryError {
            storageError[deviceId] = error.localizedDescription
        } catch {
            storageError[deviceId] = "Could not refresh storage. Check the SSH connection and the account’s read permissions, then try again."
        }
    }

    // MARK: - Port/Process State

    var portCache: [UUID: [PortInfo]] = [:]
    var isLoadingPorts: [UUID: Bool] = [:]
    var portError: [UUID: String] = [:]

    // MARK: - System Info State

    var systemInfoCache: [UUID: DeviceSystemInfo] = [:]
    var isLoadingSystemInfo: [UUID: Bool] = [:]
    var systemInfoError: [UUID: String] = [:]

    // MARK: - Process Manager State

    var processCache: [UUID: [SystemProcess]] = [:]
    var isLoadingProcesses: [UUID: Bool] = [:]
    var processError: [UUID: String] = [:]

    // MARK: - Cache Cleanup State

    var isCleaningCache: [UUID: Bool] = [:]
    var cacheCleanResult: [UUID: String] = [:]
    var cacheCleanError: [UUID: String] = [:]

    // MARK: - Docker State

    var dockerAvailability: [UUID: DockerAvailability] = [:]
    var containerCache: [UUID: [DockerContainer]] = [:]
    var isLoadingContainers: [UUID: Bool] = [:]
    var dockerError: [UUID: String] = [:]
    var containerLogs: [String: String] = [:]
    var isLoadingLogs: [String: Bool] = [:]
    var actionInProgress: [String: Bool] = [:]

    // MARK: - Port/Process Methods

    func fetchPorts(for deviceId: UUID, sshService: SSHService) async {
        guard isLoadingPorts[deviceId] != true else { return }
        isLoadingPorts[deviceId] = true
        portError[deviceId] = nil
        defer { isLoadingPorts[deviceId] = false }
        do {
            let platform = try await sshService.platform(for: deviceId)
            guard platform.supportsInventory else { throw InventoryError.unsupported }
            let output = try await sshService.executeCommand(platform == .windows ? Self.windowsPortsScript : Self.portsScript, on: deviceId)
            portCache[deviceId] = platform == .windows ? parseWindowsPorts(output) : parsePorts(output)
        } catch {
            portError[deviceId] = "Listening ports are unavailable. Check OS support and permissions for lsof, ss/netstat or Get-NetTCPConnection."
        }
    }

    func killProcess(pid: Int, deviceId: UUID, sshService: SSHService, useSudo: Bool = false) async throws {
        let command = useSudo ? "sudo kill -9 \(pid)" : "kill -9 \(pid)"
        _ = try await sshService.executeCommand(command, on: deviceId)
        await fetchPorts(for: deviceId, sshService: sshService)
    }

    // MARK: - Docker Methods

    func checkDocker(for deviceId: UUID, sshService: SSHService) async {
        dockerAvailability[deviceId] = .unknown

        // Try without shell redirect (works on both Unix and Windows SSH)
        do {
            let output = try await sshService.executeCommand("docker --version", on: deviceId)
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && (trimmed.lowercased().contains("docker") || trimmed.lowercased().contains("version")) {
                dockerAvailability[deviceId] = .installed(version: trimmed)
                return
            }
        } catch {}

        // Try with 'where docker' for Windows
        do {
            let output = try await sshService.executeCommand("where docker 2>NUL || which docker 2>/dev/null", on: deviceId)
            if !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                dockerAvailability[deviceId] = .installed(version: "Docker")
                return
            }
        } catch {}

        dockerAvailability[deviceId] = .notInstalled
    }

    func fetchContainers(for deviceId: UUID, sshService: SSHService) async {
        isLoadingContainers[deviceId] = true
        dockerError[deviceId] = nil

        let command = "docker ps -a --format \"{{.ID}}\\t{{.Names}}\\t{{.Image}}\\t{{.Status}}\\t{{.Ports}}\\t{{.State}}\""

        do {
            let output = try await sshService.executeCommand(command, on: deviceId)
            containerCache[deviceId] = parseContainers(output)
        } catch {
            // Try with sudo
            do {
                let output = try await sshService.executeCommand("sudo \(command)", on: deviceId)
                containerCache[deviceId] = parseContainers(output)
            } catch {
                dockerError[deviceId] = "Failed to list containers: \(error.localizedDescription)"
            }
        }

        isLoadingContainers[deviceId] = false
    }

    /// Validates a Docker container ID or name to prevent shell injection.
    private static func sanitizeContainerId(_ id: String) -> String {
        // Docker IDs are hex; names match [a-zA-Z0-9][a-zA-Z0-9_.-]*
        id.filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." || $0 == "-" }
    }

    /// Validates Docker action to an allowed set.
    private static let allowedDockerActions: Set<String> = [
        "start", "stop", "restart", "pause", "unpause", "rm", "rm -f"
    ]

    func containerAction(_ action: String, containerId: String, deviceId: UUID, sshService: SSHService) async throws {
        let safeId = Self.sanitizeContainerId(containerId)
        guard Self.allowedDockerActions.contains(action) else {
            throw SSHError.commandFailed("Invalid Docker action: \(action)")
        }
        let key = "\(deviceId):\(safeId):\(action)"
        actionInProgress[key] = true
        defer { Task { @MainActor in actionInProgress[key] = false } }

        let command = "docker \(action) \(safeId)"
        _ = try await sshService.executeCommand(command, on: deviceId)
        await fetchContainers(for: deviceId, sshService: sshService)
    }

    func fetchLogs(containerId: String, deviceId: UUID, sshService: SSHService, tail: Int = 100) async throws -> String {
        let safeId = Self.sanitizeContainerId(containerId)
        let key = safeId
        isLoadingLogs[key] = true
        defer { Task { @MainActor in isLoadingLogs[key] = false } }

        let command = "docker logs --tail \(tail) \(safeId) 2>&1"
        let output = try await sshService.executeCommand(command, on: deviceId)
        containerLogs[key] = output
        return output
    }

    func isActionInProgress(_ action: String, containerId: String, deviceId: UUID) -> Bool {
        actionInProgress["\(deviceId):\(containerId):\(action)"] ?? false
    }

    // MARK: - System Info Methods

    func fetchSystemInfo(for deviceId: UUID, sshService: SSHService) async {
        guard isLoadingSystemInfo[deviceId] != true else { return }
        isLoadingSystemInfo[deviceId] = true
        systemInfoError[deviceId] = nil
        defer { isLoadingSystemInfo[deviceId] = false }
        do {
            let platform = try await sshService.platform(for: deviceId)
            guard platform != .unsupported else { throw InventoryError.unsupported }
            let command = platform == .windows ? Self.windowsSystemInfoScript : Self.systemInfoScript
            let output = try await sshService.executeCommand(command, on: deviceId)
            guard let info = parseSystemInfo(output) else { throw InventoryError.malformed }
            systemInfoCache[deviceId] = info
        } catch {
            systemInfoError[deviceId] = "System information is unavailable. Check the detected operating system and the account’s read permissions."
        }
    }

    private static let systemInfoScript = """
    echo "SYSINFO_HOSTNAME=$(hostname 2>/dev/null)"
    OS=$(uname -s 2>/dev/null)
    if [ "$OS" = "Darwin" ]; then
      echo "SYSINFO_OS=$(sw_vers -productName 2>/dev/null) $(sw_vers -productVersion 2>/dev/null)"
      echo "SYSINFO_KERNEL=$(uname -r 2>/dev/null)"
      echo "SYSINFO_ARCH=$(uname -m 2>/dev/null)"
      echo "SYSINFO_CPU=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "Apple Silicon")"
      echo "SYSINFO_CORES=$(sysctl -n hw.ncpu 2>/dev/null)"
      MEM=$(sysctl -n hw.memsize 2>/dev/null)
      echo "SYSINFO_MEM_TOTAL=$(echo "$MEM" | awk '{printf "%.1f GB", $1/1073741824}')"
      echo "SYSINFO_DISK_TOTAL=$(df -H / 2>/dev/null | awk 'NR==2{print $2}')"
      echo "SYSINFO_DISK_USED=$(df -H / 2>/dev/null | awk 'NR==2{print $3}')"
      BOOT=$(sysctl kern.boottime 2>/dev/null | awk -F'[= ,]+' '{for(i=1;i<=NF;i++){if($i=="sec"){print $(i+1);exit}}}')
      NOW=$(date +%s)
      SECS=$((NOW-${BOOT:-NOW}))
      DAYS=$((SECS/86400)); HRS=$(( (SECS%86400)/3600 )); MINS=$(( (SECS%3600)/60 ))
      echo "SYSINFO_UPTIME=${DAYS}d ${HRS}h ${MINS}m"
      echo "SYSINFO_SHELL=$($SHELL --version 2>/dev/null | head -1)"
      echo "SYSINFO_IPS=$(ifconfig 2>/dev/null | awk '/inet /{if($2!="127.0.0.1") printf "%s,",$2}')"
    elif [ "$OS" = "Linux" ]; then
      if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "SYSINFO_OS=$PRETTY_NAME"
      else
        echo "SYSINFO_OS=Linux $(uname -r 2>/dev/null)"
      fi
      echo "SYSINFO_KERNEL=$(uname -r 2>/dev/null)"
      echo "SYSINFO_ARCH=$(uname -m 2>/dev/null)"
      echo "SYSINFO_CPU=$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs || echo "$(uname -m)")"
      echo "SYSINFO_CORES=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null)"
      echo "SYSINFO_MEM_TOTAL=$(free -h 2>/dev/null | awk '/^Mem:/{print $2}')"
      echo "SYSINFO_DISK_TOTAL=$(df -H / 2>/dev/null | awk 'NR==2{print $2}')"
      echo "SYSINFO_DISK_USED=$(df -H / 2>/dev/null | awk 'NR==2{print $3}')"
      UP=$(cat /proc/uptime 2>/dev/null | awk '{print int($1)}')
      DAYS=$((UP/86400)); HRS=$(( (UP%86400)/3600 )); MINS=$(( (UP%3600)/60 ))
      echo "SYSINFO_UPTIME=${DAYS}d ${HRS}h ${MINS}m"
      echo "SYSINFO_SHELL=$($SHELL --version 2>/dev/null | head -1)"
      echo "SYSINFO_IPS=$(hostname -I 2>/dev/null | tr ' ' ',')"
    else
      echo "SYSINFO_OS=$(uname -s 2>/dev/null) $(uname -r 2>/dev/null)"
      echo "SYSINFO_KERNEL=$(uname -r 2>/dev/null)"
      echo "SYSINFO_ARCH=$(uname -m 2>/dev/null)"
      echo "SYSINFO_CPU=Unknown"
      echo "SYSINFO_CORES=0"
      echo "SYSINFO_MEM_TOTAL=Unknown"
      echo "SYSINFO_DISK_TOTAL=Unknown"
      echo "SYSINFO_DISK_USED=Unknown"
      echo "SYSINFO_UPTIME=Unknown"
      echo "SYSINFO_SHELL=Unknown"
      echo "SYSINFO_IPS="
    fi
    """

    /// PowerShell script for Windows system info via SSH.
    private static var windowsSystemInfoScript: String = {
        let ps = """
        $ErrorActionPreference='SilentlyContinue'
        Write-Output "SYSINFO_HOSTNAME=$env:COMPUTERNAME"
        $os=Get-CimInstance Win32_OperatingSystem
        Write-Output "SYSINFO_OS=$($os.Caption)"
        Write-Output "SYSINFO_KERNEL=$($os.Version)"
        Write-Output "SYSINFO_ARCH=$($os.OSArchitecture)"
        $cpu=Get-CimInstance Win32_Processor|Select-Object -First 1
        Write-Output "SYSINFO_CPU=$($cpu.Name)"
        Write-Output "SYSINFO_CORES=$($cpu.NumberOfLogicalProcessors)"
        $memGB=[math]::Round($os.TotalVisibleMemorySize/1048576,1)
        Write-Output "SYSINFO_MEM_TOTAL=$($memGB) GB"
        $d=Get-CimInstance Win32_LogicalDisk -Filter ("DeviceID='{0}'" -f $os.SystemDrive)
        $dtGB=[math]::Round($d.Size/1073741824,1)
        $duGB=[math]::Round(($d.Size-$d.FreeSpace)/1073741824,1)
        Write-Output "SYSINFO_DISK_TOTAL=$($dtGB)G"
        Write-Output "SYSINFO_DISK_USED=$($duGB)G"
        $up=(Get-Date)-$os.LastBootUpTime
        Write-Output "SYSINFO_UPTIME=$([int]$up.TotalDays)d $([int]$up.Hours)h $([int]$up.Minutes)m"
        Write-Output "SYSINFO_SHELL=PowerShell $($PSVersionTable.PSVersion)"
        $ips=(Get-NetIPAddress -AddressFamily IPv4|Where-Object{$_.IPAddress -ne '127.0.0.1'}|ForEach-Object{$_.IPAddress}) -join ','
        Write-Output "SYSINFO_IPS=$ips"
        """
        return PowerShellCommand.encode(ps)
    }()

    private func parseSystemInfo(_ output: String) -> DeviceSystemInfo? {
        var values: [String: String] = [:]
        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let eqIdx = trimmed.firstIndex(of: "="), trimmed.hasPrefix("SYSINFO_") else { continue }
            let key = String(trimmed[trimmed.startIndex..<eqIdx])
            let val = String(trimmed[trimmed.index(after: eqIdx)...])
            values[key] = val
        }

        guard let os = values["SYSINFO_OS"], !os.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let ips = (values["SYSINFO_IPS"] ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        return DeviceSystemInfo(
            hostname: values["SYSINFO_HOSTNAME"] ?? "Unknown",
            osName: values["SYSINFO_OS"] ?? "Unknown",
            osVersion: "",
            kernelVersion: values["SYSINFO_KERNEL"] ?? "Unknown",
            architecture: values["SYSINFO_ARCH"] ?? "Unknown",
            cpuModel: values["SYSINFO_CPU"] ?? "Unknown",
            cpuCores: Int(values["SYSINFO_CORES"] ?? "0") ?? 0,
            memoryTotal: values["SYSINFO_MEM_TOTAL"] ?? "Unknown",
            diskTotal: values["SYSINFO_DISK_TOTAL"] ?? "Unknown",
            diskUsed: values["SYSINFO_DISK_USED"] ?? "Unknown",
            uptimeFormatted: values["SYSINFO_UPTIME"] ?? "Unknown",
            shellVersion: values["SYSINFO_SHELL"] ?? "Unknown",
            ipAddresses: ips
        )
    }

    // MARK: - Cache Cleanup Methods

    func cleanCache(for deviceId: UUID, sshService: SSHService) async {
        isCleaningCache[deviceId] = true
        cacheCleanResult[deviceId] = nil
        cacheCleanError[deviceId] = nil

        // Get the device-specific command profile
        let device = sshService.devices.first(where: { $0.id == deviceId })
        let profile = device.map { DeviceCommandProfileStore.effectiveProfile(for: $0) }
        let cacheScript = profile?.cleanCache ?? Self.cleanCacheScript

        do {
            let output = try await sshService.executeCommand(cacheScript, on: deviceId)
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.contains("CACHE_FREED=") {
                let result = parseCleanCacheResult(trimmed)
                cacheCleanResult[deviceId] = result
            } else {
                // Try Windows fallback
                let winOutput = try await sshService.executeCommand(Self.windowsCleanCacheScript, on: deviceId)
                let winTrimmed = winOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                if winTrimmed.contains("CACHE_FREED=") {
                    cacheCleanResult[deviceId] = parseCleanCacheResult(winTrimmed)
                } else {
                    cacheCleanResult[deviceId] = "Cache cleaned"
                }
            }
        } catch {
            // Try Windows fallback
            do {
                let winOutput = try await sshService.executeCommand(Self.windowsCleanCacheScript, on: deviceId)
                let winTrimmed = winOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                if winTrimmed.contains("CACHE_FREED=") {
                    cacheCleanResult[deviceId] = parseCleanCacheResult(winTrimmed)
                } else {
                    cacheCleanResult[deviceId] = "Cache cleaned"
                }
            } catch {
                cacheCleanError[deviceId] = "Failed to clean cache: \(error.localizedDescription)"
            }
        }

        isCleaningCache[deviceId] = false
    }

    private static let cleanCacheScript = """
    OS=$(uname -s 2>/dev/null)
    if [ "$OS" = "Darwin" ]; then
      FREE_BEFORE=$(vm_stat 2>/dev/null | awk '/Pages free/{gsub(/\\./, "", $3); print $3}')
      sudo purge 2>/dev/null
      FREE_AFTER=$(vm_stat 2>/dev/null | awk '/Pages free/{gsub(/\\./, "", $3); print $3}')
      PAGE_SIZE=$(sysctl -n hw.pagesize 2>/dev/null || echo 4096)
      if [ -n "$FREE_BEFORE" ] && [ -n "$FREE_AFTER" ]; then
        FREED=$(( (FREE_AFTER - FREE_BEFORE) * PAGE_SIZE / 1048576 ))
        echo "CACHE_FREED=${FREED}MB"
      else
        echo "CACHE_FREED=0MB"
      fi
      echo "CACHE_OS=Darwin"
    elif [ "$OS" = "Linux" ]; then
      FREE_BEFORE=$(free -m 2>/dev/null | awk '/^Mem:/{print $4}')
      sync
      sudo sh -c 'echo 3 > /proc/sys/vm/drop_caches' 2>/dev/null
      FREE_AFTER=$(free -m 2>/dev/null | awk '/^Mem:/{print $4}')
      if [ -n "$FREE_BEFORE" ] && [ -n "$FREE_AFTER" ]; then
        FREED=$((FREE_AFTER - FREE_BEFORE))
        echo "CACHE_FREED=${FREED}MB"
      else
        echo "CACHE_FREED=0MB"
      fi
      echo "CACHE_OS=Linux"
    else
      echo "CACHE_FREED=0MB"
      echo "CACHE_OS=Unknown"
    fi
    """

    private static var windowsCleanCacheScript: String = {
        let ps = """
        $ErrorActionPreference='SilentlyContinue'
        $os=Get-CimInstance Win32_OperatingSystem
        $freeBefore=[math]::Round($os.FreePhysicalMemory/1024,0)
        Clear-DnsClientCache
        Get-Process | Where-Object {$_.WorkingSet64 -gt 50MB} | ForEach-Object {
            [void][System.Runtime.InteropServices.Marshal]::SetProcessWorkingSetSize($_.Handle, [IntPtr]::new(-1), [IntPtr]::new(-1))
        }
        $os2=Get-CimInstance Win32_OperatingSystem
        $freeAfter=[math]::Round($os2.FreePhysicalMemory/1024,0)
        $freed=$freeAfter-$freeBefore
        Write-Output "CACHE_FREED=${freed}MB"
        Write-Output "CACHE_OS=Windows"
        """
        return PowerShellCommand.encode(ps)
    }()

    private func parseCleanCacheResult(_ output: String) -> String {
        var freedMB = 0
        var os = ""
        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("CACHE_FREED=") {
                let val = trimmed.dropFirst("CACHE_FREED=".count)
                    .replacingOccurrences(of: "MB", with: "")
                freedMB = Int(val) ?? 0
            } else if trimmed.hasPrefix("CACHE_OS=") {
                os = String(trimmed.dropFirst("CACHE_OS=".count))
            }
        }
        if freedMB > 0 {
            return "Freed \(freedMB) MB of RAM"
        } else if !os.isEmpty {
            return "Cache cleaned successfully"
        }
        return "Cache cleaned"
    }

    // MARK: - Process Manager Methods

    func fetchProcesses(for deviceId: UUID, sshService: SSHService) async {
        guard isLoadingProcesses[deviceId] != true else { return }
        isLoadingProcesses[deviceId] = true
        processError[deviceId] = nil
        defer { isLoadingProcesses[deviceId] = false }
        do {
            let platform = try await sshService.platform(for: deviceId)
            guard platform.supportsInventory else { throw InventoryError.unsupported }
            let output = try await sshService.executeCommand(platform == .windows ? Self.windowsProcessScript : Self.processScript, on: deviceId)
            processCache[deviceId] = platform == .windows ? parseWindowsProcesses(output) : parseProcesses(output)
        } catch {
            processError[deviceId] = "Processes are unavailable. Check OS support and permissions for ps or Get-Process."
        }
    }

    func killProcessByPid(pid: Int, deviceId: UUID, sshService: SSHService, signal: KillSignal = .term, useSudo: Bool = false) async throws {
        let cmd = useSudo ? "sudo kill -\(signal.rawValue) \(pid)" : "kill -\(signal.rawValue) \(pid)"
        _ = try await sshService.executeCommand(cmd, on: deviceId)
        await fetchProcesses(for: deviceId, sshService: sshService)
    }

    /// Cross-platform script: lists top 50 processes sorted by memory usage.
    private static let processScript = """
    OS=$(uname -s 2>/dev/null)
    if [ "$OS" = "Linux" ]; then
      echo "PROC_OS=Linux"
      ps aux --sort=-%mem 2>/dev/null | head -51
    elif [ "$OS" = "Darwin" ]; then
      echo "PROC_OS=Darwin"
      ps aux -m 2>/dev/null | head -51
    else
      echo "PROC_OS=Linux"
      ps aux --sort=-%mem 2>/dev/null | head -51
    fi
    """

    private static let windowsProcessScript: String = {
        let ps = """
        Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 50 | ForEach-Object {
            "$($_.Id)`t$($_.UserName)`t$([math]::Round($_.CPU,1))`t$([math]::Round($_.WorkingSet64/1MB,1))`t$($_.ProcessName)"
        }
        """
        return PowerShellCommand.encode(ps)
    }()

    // MARK: - Process Parsing

    private func parseProcesses(_ output: String) -> [SystemProcess] {
        let lines = output.components(separatedBy: .newlines)
        var processes: [SystemProcess] = []
        var skippedHeader = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("PROC_OS=") { continue }

            // Skip the ps header line (USER PID %CPU %MEM ...)
            if !skippedHeader && (trimmed.hasPrefix("USER") || trimmed.contains("%CPU") || trimmed.contains("%MEM")) {
                skippedHeader = true
                continue
            }

            if let proc = parsePsAuxLine(trimmed) {
                processes.append(proc)
            }
        }

        return processes
    }

    /// Parses a `ps aux` line. Columns: USER PID %CPU %MEM VSZ RSS TTY STAT START TIME COMMAND
    /// COMMAND (column 11+) can contain spaces.
    private func parsePsAuxLine(_ line: String) -> SystemProcess? {
        let parts = line.split(separator: " ", maxSplits: 10, omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 11 else { return nil }

        let user = parts[0]
        guard let pid = Int(parts[1]) else { return nil }
        let cpuPercent = Double(parts[2]) ?? 0
        let memPercent = Double(parts[3]) ?? 0
        let rssKB = Double(parts[5]) ?? 0
        let memMB = rssKB / 1024.0
        let state = parts[7]
        let command = parts[10]

        return SystemProcess(
            pid: pid,
            user: user,
            cpuPercent: cpuPercent,
            memPercent: memPercent,
            memMB: memMB,
            command: command,
            state: state
        )
    }

    private func parseWindowsProcesses(_ output: String) -> [SystemProcess] {
        let lines = output.components(separatedBy: .newlines)
        var processes: [SystemProcess] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            let parts = trimmed.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 5 else { continue }

            let pid = Int(parts[0]) ?? 0
            let user = parts[1].isEmpty ? "-" : parts[1]
            let cpu = Double(parts[2]) ?? 0
            let memMB = Double(parts[3]) ?? 0
            let command = parts[4]

            guard pid > 0 else { continue }

            processes.append(SystemProcess(
                pid: pid,
                user: user,
                cpuPercent: cpu,
                memPercent: 0,
                memMB: memMB,
                command: command
            ))
        }

        return processes
    }

    // MARK: - Port Parsing

    /// Combined script: detects OS and lists listening ports.
    private static let portsScript = """
    OS=$(uname -s 2>/dev/null)
    if [ "$OS" = "Linux" ]; then
        echo "PORT_OS=Linux"
        ss -tulnp 2>/dev/null || netstat -tulnp 2>/dev/null
    elif [ "$OS" = "Darwin" ]; then
        echo "PORT_OS=Darwin"
        lsof -i -P -n 2>/dev/null | grep LISTEN
    else
        echo "PORT_OS=Unknown"
        ss -tulnp 2>/dev/null || netstat -tulnp 2>/dev/null
    fi
    """

    private static let windowsPortsScript: String = {
        let ps = """
        Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | ForEach-Object {
            $proc = Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue
            "$($_.LocalPort)`t$($_.OwningProcess)`t$($_.State)`t$($proc.ProcessName)`t$($_.LocalAddress)"
        }
        """
        return PowerShellCommand.encode(ps)
    }()

    private func parsePorts(_ output: String) -> [PortInfo] {
        let lines = output.components(separatedBy: .newlines)
        var os = "Linux"
        var ports: [PortInfo] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("PORT_OS=") {
                os = String(trimmed.dropFirst(8))
                continue
            }
            if trimmed.isEmpty { continue }

            if os == "Darwin" {
                if let port = parseLsofLine(trimmed) {
                    ports.append(port)
                }
            } else {
                if let port = parseSsLine(trimmed) {
                    ports.append(port)
                }
            }
        }

        return ports.sorted { $0.port < $1.port }
    }

    /// Parses a line from `ss -tulnp`, e.g.:
    /// `tcp   LISTEN  0  128  0.0.0.0:22  0.0.0.0:*  users:(("sshd",pid=1234,fd=3))`
    private func parseSsLine(_ line: String) -> PortInfo? {
        let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 5 else { return nil }

        let protoStr = parts[0].lowercased()
        guard protoStr.hasPrefix("tcp") || protoStr.hasPrefix("udp") else { return nil }

        let proto: PortProtocol
        switch protoStr {
        case "tcp": proto = .tcp
        case "tcp6": proto = .tcp6
        case "udp": proto = .udp
        case "udp6": proto = .udp6
        default: proto = .tcp
        }

        let state = parts[1]
        // Skip header line
        guard state != "State" else { return nil }

        // Local address:port is at index 4
        let localAddr = parts[4]
        let (address, port) = splitAddressPort(localAddr)
        guard let portNum = port else { return nil }

        // Parse process info from users:(("name",pid=N,...))
        var pid = 0
        var processName = "-"
        if let usersField = parts.last, usersField.contains("pid=") {
            if let pidRange = usersField.range(of: "pid=") {
                let afterPid = usersField[pidRange.upperBound...]
                let pidStr = afterPid.prefix(while: { $0.isNumber })
                pid = Int(pidStr) ?? 0
            }
            if let nameStart = usersField.range(of: "((\""),
               let nameEnd = usersField.range(of: "\"", range: nameStart.upperBound..<usersField.endIndex) {
                processName = String(usersField[nameStart.upperBound..<nameEnd.lowerBound])
            }
        }

        return PortInfo(port: portNum, proto: proto, pid: pid, processName: processName, state: state, localAddress: address)
    }

    /// Parses a line from `lsof -i -P -n | grep LISTEN`, e.g.:
    /// `sshd    1234  root  3u  IPv4  12345  0t0  TCP *:22 (LISTEN)`
    private func parseLsofLine(_ line: String) -> PortInfo? {
        let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 9 else { return nil }

        let processName = parts[0]
        let pid = Int(parts[1]) ?? 0

        // Find the TCP/UDP field and address:port
        var proto: PortProtocol = .tcp
        var address = "*"
        var portNum = 0

        for (i, part) in parts.enumerated() {
            if part.hasPrefix("TCP") || part.hasPrefix("UDP") {
                proto = part.hasPrefix("TCP") ? .tcp : .udp
                // Next part should be address:port
                if i + 1 < parts.count {
                    let addrPort = parts[i + 1]
                    let (addr, port) = splitAddressPort(addrPort)
                    address = addr
                    portNum = port ?? 0
                }
                break
            }
        }

        guard portNum > 0 else { return nil }

        return PortInfo(port: portNum, proto: proto, pid: pid, processName: processName, state: "LISTEN", localAddress: address)
    }

    private func parseWindowsPorts(_ output: String) -> [PortInfo] {
        let lines = output.components(separatedBy: .newlines)
        var ports: [PortInfo] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            let parts = trimmed.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 4 else { continue }

            let port = Int(parts[0]) ?? 0
            let pid = Int(parts[1]) ?? 0
            let state = parts[2]
            let processName = parts[3].isEmpty ? "-" : parts[3]
            let address = parts.count > 4 ? parts[4] : "0.0.0.0"

            guard port > 0 else { continue }

            ports.append(PortInfo(port: port, proto: .tcp, pid: pid, processName: processName, state: state, localAddress: address))
        }

        return ports.sorted { $0.port < $1.port }
    }

    // MARK: - Docker Parsing

    private func parseContainers(_ output: String) -> [DockerContainer] {
        let lines = output.components(separatedBy: .newlines)
        var containers: [DockerContainer] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let parts = trimmed.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 6 else { continue }

            let containerId = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let name = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            let image = parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
            let status = parts[3].trimmingCharacters(in: .whitespacesAndNewlines)
            let ports = parts[4].trimmingCharacters(in: .whitespacesAndNewlines)
            let stateStr = parts[5]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
                .lowercased()

            let state = DockerContainerState(rawValue: stateStr) ?? .unknown

            containers.append(DockerContainer(
                containerId: containerId,
                name: name,
                image: image,
                status: status,
                state: state,
                ports: ports
            ))
        }

        return containers
    }

    // MARK: - Helpers

    private func splitAddressPort(_ addrPort: String) -> (String, Int?) {
        // Handle IPv6 [::]:port and IPv4 addr:port
        if let lastColon = addrPort.lastIndex(of: ":") {
            let address = String(addrPort[addrPort.startIndex..<lastColon])
            let portStr = String(addrPort[addrPort.index(after: lastColon)...])
            return (address, Int(portStr))
        }
        return (addrPort, nil)
    }
}
