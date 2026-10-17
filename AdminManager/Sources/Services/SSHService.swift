import Foundation
import SwiftUI

@Observable
@MainActor
final class SSHService {
    var devices: [Device] = []
    var connectedDevices: Set<UUID> = []
    var config: SSHConfig = SSHConfig()
    var isLoading = false
    var error: String?

    private var linuxCPUSamples: [UUID: LinuxCPUSample] = [:]
    private(set) var remotePlatforms: [UUID: RemotePlatform] = [:]

    private let storageKey = "admin_manager_devices"
    private let configKey = "admin_manager_ssh_config"

    /// Directory for SSH ControlMaster sockets (kept short to avoid path length limits).
    private let controlDir: String = {
        let dir = "/tmp/adminmanager-ssh-\(NSUserName())"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return dir
    }()

    init() {
        loadDevices()
        loadConfig()
    }

    // MARK: - SSH Environment

    private static let sshEnvironment: [String: String] = {
        var env: [String: String] = [
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin",
            "HOME": NSHomeDirectory(),
            "LANG": "en_US.UTF-8",
            "TERM": "xterm-256color"
        ]
        if let sock = ProcessInfo.processInfo.environment["SSH_AUTH_SOCK"] {
            env["SSH_AUTH_SOCK"] = sock
        }
        return env
    }()

    private func controlPath(for device: Device) -> String {
        "\(controlDir)/\(device.username)@\(device.hostname):\(device.port)"
    }

    // MARK: - Device Management

    /// Returns `true` if a device with the same hostname and port already exists.
    func hasDevice(hostname: String, port: Int) -> Bool {
        devices.contains { $0.hostname == hostname && $0.port == port }
    }

    /// Adds a device. Returns `false` if a device with the same hostname:port already exists.
    @discardableResult
    func addDevice(_ device: Device) -> Bool {
        if hasDevice(hostname: device.hostname, port: device.port) {
            return false
        }
        devices.append(device)
        saveDevices()
        return true
    }

    func updateDevice(_ device: Device) {
        if let index = devices.firstIndex(where: { $0.id == device.id }) {
            devices[index] = device
            saveDevices()
        }
    }

    func deleteDevice(_ device: Device) {
        let id = device.id
        KeychainHelper.deletePassword(for: device)
        // Disconnect before removing from array so disconnect can still find the device
        Task {
            await disconnect(from: id)
            devices.removeAll { $0.id == id }
            connectedDevices.remove(id)
            saveDevices()
        }
    }

    func deviceById(_ id: UUID) -> Device? {
        devices.first { $0.id == id }
    }

    // MARK: - SSH Connection

    func connect(to device: Device, password: String? = nil) async throws {
        isLoading = true
        error = nil
        defer { isLoading = false }

        // Localhost: no SSH needed, just mark connected and auto-detect category
        if device.isLocalhost {
            markConnected(device)
            await detectDeviceCategory(for: device.id)
            return
        }

        // Reuse existing ControlMaster if still alive
        if await checkControlSocket(for: device) {
            markConnected(device)
            await detectDeviceCategory(for: device.id)
            return
        }

        let ctrlPath = controlPath(for: device)

        // Capture @MainActor properties before entering background queue
        let timeout = self.config.connectionTimeout
        let keepAlive = self.config.keepAliveInterval

        let sshEnvironment = Self.sshEnvironment

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                var askpassHelper: PrivateAskpassFile?

                do {
                    var env = sshEnvironment

                    // For password auth, create a temporary askpass helper
                    if device.authMethod == .password, let pwd = password, !pwd.isEmpty {
                        let helper = try PrivateAskpassFile(password: pwd)
                        askpassHelper = helper
                        env["SSH_ASKPASS"] = helper.url.path
                        env["SSH_ASKPASS_REQUIRE"] = "force"
                        env["DISPLAY"] = ":0"
                    }

                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
                    process.environment = env
                    process.standardInput = FileHandle.nullDevice

                    process.arguments = [
                        "-o", "ControlMaster=yes",
                        "-o", "ControlPath=\(ctrlPath)",
                        "-o", "ControlPersist=yes",
                        "-o", "StrictHostKeyChecking=accept-new",
                        "-o", "ConnectTimeout=\(timeout)",
                        "-o", "ServerAliveInterval=\(keepAlive)",
                        "-p", "\(device.port)",
                        "-N",
                        "-f",
                        "\(device.username)@\(device.hostname)"
                    ]

                    let errorPipe = Pipe()
                    let stdoutPipe = Pipe()
                    process.standardOutput = stdoutPipe
                    process.standardError = errorPipe

                    defer {
                        askpassHelper?.remove()
                    }

                    try process.run()

                    // Read pipes before waitUntilExit to avoid deadlock
                    var errorData = Data()
                    let group = DispatchGroup()
                    group.enter()
                    DispatchQueue.global(qos: .utility).async {
                        let _ = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                        group.leave()
                    }
                    group.enter()
                    DispatchQueue.global(qos: .utility).async {
                        errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                        group.leave()
                    }
                    group.wait()
                    process.waitUntilExit()

                    if process.terminationStatus == 0 {
                        continuation.resume()
                    } else {
                        let errStr = String(data: errorData, encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Connection failed"
                        continuation.resume(throwing: SSHError.connectionFailed(errStr))
                    }
                } catch {
                    askpassHelper?.remove()
                    continuation.resume(throwing: error)
                }
            }
        }

        // Save password to Keychain for auto-reconnect
        if device.authMethod == .password, let pwd = password, !pwd.isEmpty {
            KeychainHelper.save(password: pwd, for: device)
        }

        markConnected(device)
        await detectDeviceCategory(for: device.id)
    }

    func disconnect(from deviceId: UUID) async {
        remotePlatforms.removeValue(forKey: deviceId)
        guard let device = deviceById(deviceId) else {
            linuxCPUSamples.removeValue(forKey: deviceId)
            connectedDevices.remove(deviceId)
            return
        }

        // Localhost: just mark disconnected, no SSH session to close
        if device.isLocalhost {
            linuxCPUSamples.removeValue(forKey: deviceId)
            connectedDevices.remove(deviceId)
            if var dev = deviceById(deviceId) {
                dev.isOnline = false
                updateDevice(dev)
            }
            return
        }

        let ctrlPath = controlPath(for: device)
        let sshEnvironment = Self.sshEnvironment

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
                process.environment = sshEnvironment
                process.arguments = [
                    "-o", "ControlPath=\(ctrlPath)",
                    "-O", "exit",
                    "\(device.username)@\(device.hostname)"
                ]
                process.standardOutput = Pipe()
                process.standardError = Pipe()
                process.standardInput = FileHandle.nullDevice
                try? process.run()
                process.waitUntilExit()
                continuation.resume()
            }
        }

        linuxCPUSamples.removeValue(forKey: deviceId)
        remotePlatforms.removeValue(forKey: deviceId)
        connectedDevices.remove(deviceId)
        if var dev = deviceById(deviceId) {
            dev.isOnline = false
            updateDevice(dev)
        }
    }

    func executeCommand(_ command: String, on deviceId: UUID) async throws -> String {
        guard let device = deviceById(deviceId), connectedDevices.contains(deviceId) else {
            throw SSHError.notConnected
        }

        // Localhost: run command locally via /bin/sh
        if device.isLocalhost {
            return try await executeLocalCommand(command)
        }

        let ctrlPath = controlPath(for: device)
        let sshEnvironment = Self.sshEnvironment

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
                process.environment = sshEnvironment
                process.arguments = [
                    "-o", "ControlPath=\(ctrlPath)",
                    "-o", "ConnectTimeout=10",
                    "-p", "\(device.port)",
                    "\(device.username)@\(device.hostname)",
                    command
                ]

                let outputPipe = Pipe()
                let errorPipe = Pipe()
                process.standardOutput = outputPipe
                process.standardError = errorPipe
                process.standardInput = FileHandle.nullDevice

                do {
                    try process.run()

                    // Read both pipes concurrently BEFORE waitUntilExit to prevent pipe deadlock.
                    // If the process writes enough to fill the pipe buffer (~64KB), it blocks on write.
                    // Calling waitUntilExit() first would hang because the process can't finish.
                    var outputData = Data()
                    var errorData = Data()

                    let group = DispatchGroup()
                    group.enter()
                    DispatchQueue.global(qos: .userInitiated).async {
                        outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                        group.leave()
                    }
                    group.enter()
                    DispatchQueue.global(qos: .userInitiated).async {
                        errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                        group.leave()
                    }
                    group.wait()
                    process.waitUntilExit()

                    let output = String(data: outputData, encoding: .utf8) ?? ""

                    if process.terminationStatus != 0 && output.isEmpty {
                        let errStr = String(data: errorData, encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Command failed"
                        continuation.resume(throwing: SSHError.commandFailed(errStr))
                    } else {
                        continuation.resume(returning: output)
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Local Command Execution

    private func executeLocalCommand(_ command: String) async throws -> String {
        let sshEnvironment = Self.sshEnvironment

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/sh")
                process.arguments = ["-c", command]
                process.environment = sshEnvironment

                let outputPipe = Pipe()
                let errorPipe = Pipe()
                process.standardOutput = outputPipe
                process.standardError = errorPipe
                process.standardInput = FileHandle.nullDevice

                do {
                    try process.run()

                    var outputData = Data()
                    var errorData = Data()

                    let group = DispatchGroup()
                    group.enter()
                    DispatchQueue.global(qos: .userInitiated).async {
                        outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                        group.leave()
                    }
                    group.enter()
                    DispatchQueue.global(qos: .userInitiated).async {
                        errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                        group.leave()
                    }
                    group.wait()
                    process.waitUntilExit()

                    let output = String(data: outputData, encoding: .utf8) ?? ""

                    if process.terminationStatus != 0 && output.isEmpty {
                        let errStr = String(data: errorData, encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Command failed"
                        continuation.resume(throwing: SSHError.commandFailed(errStr))
                    } else {
                        continuation.resume(returning: output)
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func isConnected(deviceId: UUID) -> Bool {
        connectedDevices.contains(deviceId)
    }

    var activeSessions: [UUID: Bool] {
        Dictionary(uniqueKeysWithValues: connectedDevices.map { ($0, true) })
    }

    func platform(for deviceId: UUID) async throws -> RemotePlatform {
        guard connectedDevices.contains(deviceId) else { throw SSHError.notConnected }
        if let platform = remotePlatforms[deviceId] { return platform }
        var detected = RemotePlatform.unsupported
        if let output = try? await executeCommand("uname -s", on: deviceId) {
            detected = RemotePlatform.fromUname(output)
        }
        if detected == .unsupported {
            if let output = try? await executeCommand(RemotePlatform.windowsDetectionCommand, on: deviceId),
               output.components(separatedBy: .newlines).contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines) == "ADMIN_PLATFORM_WINDOWS" }) {
                detected = .windows
            }
        }
        // A failed connection/probe must be retryable, not cached as a platform.
        if detected != .unsupported, connectedDevices.contains(deviceId) { remotePlatforms[deviceId] = detected }
        return detected
    }

    // MARK: - Private Helpers

    private func markConnected(_ device: Device) {
        connectedDevices.insert(device.id)
        var updated = device
        updated.lastConnected = Date()
        updated.isOnline = true
        updateDevice(updated)
    }

    private func checkControlSocket(for device: Device) async -> Bool {
        let ctrlPath = controlPath(for: device)
        let sshEnvironment = Self.sshEnvironment
        guard FileManager.default.fileExists(atPath: ctrlPath) else { return false }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
                process.environment = sshEnvironment
                process.arguments = [
                    "-o", "ControlPath=\(ctrlPath)",
                    "-O", "check",
                    "\(device.username)@\(device.hostname)"
                ]
                process.standardOutput = Pipe()
                process.standardError = Pipe()
                process.standardInput = FileHandle.nullDevice
                try? process.run()
                process.waitUntilExit()
                continuation.resume(returning: process.terminationStatus == 0)
            }
        }
    }

    // MARK: - Real System Metrics

    /// Shell script for Linux and macOS metrics.
    /// Robust for Raspberry Pi (MemAvailable fallback, ARM thermal zones).
    private static let unixMetricsScript = """
    export LC_ALL=C
    OS=$(uname -s)
    echo "METRIC_OS=$OS"
    if [ "$OS" = "Linux" ]; then
      CPU_START=$(awk '/^cpu /{idle=$5+$6;total=0;for(i=2;i<=9 && i<=NF;i++)total+=$i;printf "%.0f %.0f",total,idle}' /proc/stat 2>/dev/null)
      sleep 0.2
      CPU_COUNTERS=$(awk '/^cpu /{for(i=2;i<=NF;i++)printf "%s ",$i}' /proc/stat 2>/dev/null)
      CPU_END=$(printf '%s\\n' "$CPU_COUNTERS" | awk '{total=0;for(i=1;i<=8 && i<=NF;i++)total+=$i;printf "%.0f %.0f",total,$4+$5}')
      CPU=$(printf '%s\\n%s\\n' "$CPU_START" "$CPU_END" | awk 'NR==1{total=$1;idle=$2}NR==2{dt=$1-total;di=$2-idle;if(dt>0 && di>=0 && di<=dt)printf "%.1f",100*(1-di/dt);else print "0"}')
      echo "METRIC_CPU=$CPU"
      echo "METRIC_CPU_COUNTERS=$CPU_COUNTERS"
      MEM_TOTAL=$(awk '/MemTotal/{printf "%.0f\\n",$2*1024}' /proc/meminfo 2>/dev/null || echo "0")
      MEM_AVAIL=$(awk '/MemAvailable/{printf "%.0f\\n",$2*1024}' /proc/meminfo 2>/dev/null)
      if [ -z "$MEM_AVAIL" ] || [ "$MEM_AVAIL" = "0" ]; then
        MF=$(awk '/^MemFree:/{printf "%.0f\\n",$2*1024}' /proc/meminfo 2>/dev/null || echo "0")
        BF=$(awk '/^Buffers:/{printf "%.0f\\n",$2*1024}' /proc/meminfo 2>/dev/null || echo "0")
        CA=$(awk '/^Cached:/{printf "%.0f\\n",$2*1024}' /proc/meminfo 2>/dev/null || echo "0")
        MEM_AVAIL=$((MF+BF+CA))
      fi
      echo "METRIC_MEM_TOTAL=$MEM_TOTAL"
      echo "METRIC_MEM_USED=$((MEM_TOTAL-MEM_AVAIL))"
      df -P -B1 / 2>/dev/null | awk 'NR==2{printf "METRIC_DISK_USED=%s\\nMETRIC_DISK_TOTAL=%s\\n",$3,$2}'
      ROOT_OPTIONS=$(findmnt -n -o OPTIONS --target / 2>/dev/null)
      case ",$ROOT_OPTIONS," in *,ro,*) echo "METRIC_ROOT_READONLY=1";; *) echo "METRIC_ROOT_READONLY=0";; esac
      TEMP=$(cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null | sort -rn | head -1)
      if [ -z "$TEMP" ]; then
        TEMP=$(vcgencmd measure_temp 2>/dev/null | grep -oE '[0-9.]+' | head -1 | awk '{printf "%d",$1*1000}')
      fi
      echo "METRIC_TEMP=$((${TEMP:-0}/1000))"
      echo "METRIC_UPTIME=$(awk '{printf "%.0f\\n",$1}' /proc/uptime 2>/dev/null || echo "0")"
      awk '{printf "METRIC_LOAD=%s:%s:%s\\n",$1,$2,$3}' /proc/loadavg 2>/dev/null
      echo "METRIC_PROCS=$(ls -1d /proc/[0-9]* 2>/dev/null | wc -l | tr -d ' ')"
      awk '\(LinuxInventoryProbe.networkCountersAWK)' /proc/net/dev 2>/dev/null
      # Fan speed (RPi 5 active cooler, or generic hwmon)
      FAN=""
      for f in /sys/devices/platform/cooling_fan/hwmon/hwmon*/fan1_input; do
        if [ -f "$f" ]; then FAN=$(cat "$f" 2>/dev/null); break; fi
      done
      if [ -z "$FAN" ]; then
        for f in /sys/class/hwmon/hwmon*/fan1_input; do
          if [ -f "$f" ]; then FAN=$(cat "$f" 2>/dev/null); break; fi
        done
      fi
      echo "METRIC_FAN=${FAN:-0}"
      # Power usage: RPi 5 PMIC > Jetson INA3221 > battery > Intel RAPL
      POWER=""
      # Raspberry Pi 5: vcgencmd pmic_read_adc (sum V*I per rail, apply correction)
      if command -v vcgencmd >/dev/null 2>&1; then
        PMIC=$(vcgencmd pmic_read_adc 2>/dev/null)
        if echo "$PMIC" | grep -q "current"; then
          POWER=$(echo "$PMIC" | awk -F'[=V A]' '
            /volt\\(/{gsub(/[^0-9.]/,"",$NF); v[substr($0,1,index($0," ")-1)]=$NF}
            /current\\(/{gsub(/[^0-9.]/,"",$NF); c[substr($0,1,index($0," ")-1)]=$NF}
            END{
              # Match rails by prefix (remove _V/_A suffix)
              split("3V7_WL_SW 3V3_SYS 1V8_SYS DDR_VDD2 DDR_VDDQ 1V1_SYS 0V8_SW VDD_CORE 3V3_DAC 3V3_ADC 0V8_AON HDMI",rails," ")
              p=0
              for(i in rails){
                r=rails[i]
                va=r"_V"; aa=r"_A"
                if(va in v && aa in c) p += v[va] * c[aa]
              }
              # Apply calibration correction (real = pmic * 1.1451 + 0.5879)
              if(p>0) printf "%.1f", p * 1.1451 + 0.5879
            }')
        fi
      fi
      # Jetson: INA3221 power sensor
      if [ -z "$POWER" ]; then
        for f in /sys/bus/i2c/drivers/ina3221x/*/iio:device*/in_power0_input; do
          if [ -f "$f" ]; then
            RAW=$(cat "$f" 2>/dev/null)
            if [ -n "$RAW" ]; then POWER=$((RAW/1000)); fi
            break
          fi
        done
      fi
      # Linux laptop battery
      if [ -z "$POWER" ] && [ -d /sys/class/power_supply/BAT0 ]; then
        V=$(cat /sys/class/power_supply/BAT0/voltage_now 2>/dev/null || echo "0")
        I=$(cat /sys/class/power_supply/BAT0/current_now 2>/dev/null || echo "0")
        if [ "$V" != "0" ] && [ "$I" != "0" ]; then
          POWER=$(awk "BEGIN{printf \"%.1f\",$V/1000000*$I/1000000}")
        fi
      fi
      # Intel RAPL (x86 servers/desktops)
      if [ -z "$POWER" ] && [ -d /sys/class/powercap/intel-rapl:0 ]; then
        E=$(cat /sys/class/powercap/intel-rapl:0/energy_uj 2>/dev/null || echo "0")
        sleep 1
        E2=$(cat /sys/class/powercap/intel-rapl:0/energy_uj 2>/dev/null || echo "0")
        POWER=$(awk "BEGIN{printf \"%.1f\",($E2-$E)/1000000}")
      fi
      echo "METRIC_POWER=${POWER:-0}"
      # GPU stats (NVIDIA)
      if command -v nvidia-smi >/dev/null 2>&1; then
        GPU_DATA=$(nvidia-smi --query-gpu=utilization.gpu,temperature.gpu,memory.used,memory.total,power.draw --format=csv,noheader,nounits 2>/dev/null | head -1)
        if [ -n "$GPU_DATA" ]; then
          echo "METRIC_GPU=$GPU_DATA"
        fi
      fi
    elif [ "$OS" = "Darwin" ]; then
      NCPU=$(sysctl -n hw.ncpu 2>/dev/null || echo "1")
      CPU=$(ps -A -o %cpu 2>/dev/null | awk -v n="$NCPU" '{s+=$1}END{printf "%.1f",s/n}')
      echo "METRIC_CPU=$CPU"
      MEM_TOTAL=$(sysctl -n hw.memsize 2>/dev/null || echo "0")
      echo "METRIC_MEM_TOTAL=$MEM_TOTAL"
      PG=$(sysctl -n hw.pagesize 2>/dev/null || echo "16384")
      ANON=$(vm_stat 2>/dev/null | awk '/Anonymous pages/{gsub(/\\./,"",$3);print $3}')
      WIRED=$(vm_stat 2>/dev/null | awk '/Pages wired/{gsub(/\\./,"",$4);print $4}')
      COMPRESSED=$(vm_stat 2>/dev/null | awk '/occupied by compressor/{gsub(/\\./,"",$5);print $5}')
      echo "METRIC_MEM_USED=$(( (${ANON:-0} + ${WIRED:-0} + ${COMPRESSED:-0}) * ${PG:-16384} ))"
      DF_VOL="/System/Volumes/Data"
      if ! df -P "$DF_VOL" >/dev/null 2>&1; then DF_VOL="/"; fi
      df -kP "$DF_VOL" 2>/dev/null | awk 'NR==2{printf "METRIC_DISK_USED=%.0f\\nMETRIC_DISK_TOTAL=%.0f\\n",$3*1024,$2*1024}'
      TEMP=""
      if command -v smctemp >/dev/null 2>&1; then
        TEMP=$(smctemp -c 2>/dev/null | awk '{printf "%.1f",$1}')
      elif [ -x /usr/local/bin/smctemp ]; then
        TEMP=$(/usr/local/bin/smctemp -c 2>/dev/null | awk '{printf "%.1f",$1}')
      fi
      if [ -z "$TEMP" ] || [ "$TEMP" = "0.0" ] || [ "$TEMP" = "0" ]; then
        TEMP=$(ioreg -r -c AppleSmartBattery -d1 2>/dev/null | awk -F'= ' '/"Temperature"/{gsub(/ /,"",$2);t=$2/100; if(t>0 && t<150) printf "%.1f",t}' | head -1)
      fi
      if [ -z "$TEMP" ] || [ "$TEMP" = "0.0" ] || [ "$TEMP" = "0" ]; then
        TEMP=$(ioreg -r -d2 -k temperature 2>/dev/null | awk '/"temperature" =/{t=$NF+0; if(t>10000)t=t/100; if(t>1000)t=t/10; if(t>0 && t<150) printf "%.1f",t}' | sort -rn | head -1)
      fi
      echo "METRIC_TEMP=${TEMP:-0}"
      BOOT=$(sysctl kern.boottime 2>/dev/null | awk -F'[= ,]+' '{for(i=1;i<=NF;i++){if($i=="sec"){print $(i+1);exit}}}')
      NOW=$(date +%s)
      echo "METRIC_UPTIME=$((NOW-${BOOT:-NOW}))"
      LOAD=$(sysctl -n vm.loadavg 2>/dev/null | awk '{print $2":"$3":"$4}')
      echo "METRIC_LOAD=$LOAD"
      echo "METRIC_PROCS=$(ps aux 2>/dev/null | wc -l | tr -d ' ')"
      netstat -ib 2>/dev/null | grep -v lo0 | awk '/Link/{rx+=$7;tx+=$10}END{printf "METRIC_NET=%.0f:%.0f\\n",rx,tx}'
      # macOS power usage: sudo powermetrics (real SoC power) > ioreg battery > fallback
      POWER=""
      GPU_POWER=""
      # Try sudo powermetrics first (works on all Macs with admin/sudo)
      PM_OUT=$(sudo -n powermetrics --samplers cpu_power,gpu_power -i 1000 -n 1 2>/dev/null)
      if [ -n "$PM_OUT" ]; then
        # CPU+package power (Combined Power / Package Power / CPU Power)
        PKG_W=$(echo "$PM_OUT" | awk '/Combined Power/{gsub(/[^0-9.]/,"",$NF);if($NF+0>0){printf "%.1f",$NF;exit}}')
        if [ -z "$PKG_W" ] || [ "$PKG_W" = "0.0" ]; then
          PKG_W=$(echo "$PM_OUT" | awk '/Package Power/{gsub(/[^0-9.]/,"",$NF);if($NF+0>0){printf "%.1f",$NF;exit}}')
        fi
        if [ -z "$PKG_W" ] || [ "$PKG_W" = "0.0" ]; then
          PKG_W=$(echo "$PM_OUT" | awk '/CPU Power/{gsub(/[^0-9.]/,"",$NF);if($NF+0>0){printf "%.1f",$NF;exit}}')
        fi
        if [ -n "$PKG_W" ] && [ "$PKG_W" != "0.0" ]; then
          POWER=$PKG_W
        fi
        # GPU power from powermetrics
        GPU_W=$(echo "$PM_OUT" | awk '/GPU Power/{gsub(/[^0-9.]/,"",$NF);if($NF+0>0){printf "%.1f",$NF;exit}}')
        if [ -n "$GPU_W" ] && [ "$GPU_W" != "0.0" ]; then
          GPU_POWER=$GPU_W
        fi
      fi
      # Fallback: ioreg battery (MacBooks)
      if [ -z "$POWER" ] || [ "$POWER" = "0.0" ]; then
        ioreg -r -c AppleSmartBattery -d1 2>/dev/null | awk -F'= ' '/"InstantAmperage"/{print "METRIC_BATTERY_CURRENT="$2} /"Voltage"/{print "METRIC_BATTERY_VOLTAGE="$2}'
      fi
      echo "METRIC_POWER=${POWER:-0}"
      if [ -n "$GPU_POWER" ]; then
        echo "METRIC_GPU_POWER=$GPU_POWER"
      fi
      # macOS GPU usage via ioreg
      GPU_UTIL=$(ioreg -r -d1 -c IOAccelerator 2>/dev/null | awk -F'"' '/"Device Utilization %"/{gsub(/ /,"",$0);split($0,a,"= ");if(a[2]+0>0)print a[2]}' | head -1)
      if [ -n "$GPU_UTIL" ]; then
        echo "METRIC_GPU_USAGE=$GPU_UTIL"
      fi
    fi
    """

    /// PowerShell script for Windows metrics via SSH.
    private static var windowsMetricsScript: String = {
        let ps = """
        $ErrorActionPreference='SilentlyContinue'
        Write-Output "METRIC_OS=Windows"
        $cpu=(Get-CimInstance Win32_Processor|Measure-Object LoadPercentage -Average).Average
        Write-Output "METRIC_CPU=$cpu"
        $os=Get-CimInstance Win32_OperatingSystem
        $mt=$os.TotalVisibleMemorySize*1024
        $mu=($os.TotalVisibleMemorySize-$os.FreePhysicalMemory)*1024
        Write-Output "METRIC_MEM_TOTAL=$mt"
        Write-Output "METRIC_MEM_USED=$mu"
        $d=Get-CimInstance Win32_LogicalDisk -Filter ("DeviceID='{0}'" -f $os.SystemDrive)
        Write-Output "METRIC_DISK_TOTAL=$($d.Size)"
        Write-Output "METRIC_DISK_USED=$($d.Size-$d.FreeSpace)"
        $tz=Get-CimInstance -Namespace root/WMI MSAcpi_ThermalZoneTemperature -EA SilentlyContinue
        if($tz){$t=[math]::Round(($tz.CurrentTemperature-2732)/10);Write-Output "METRIC_TEMP=$t"}else{Write-Output "METRIC_TEMP=0"}
        $bt=(Get-CimInstance Win32_OperatingSystem).LastBootUpTime
        $up=((Get-Date)-$bt).TotalSeconds
        Write-Output "METRIC_UPTIME=$([int]$up)"
        Write-Output "METRIC_PROCS=$(@(Get-Process).Count)"
        $na=Get-NetAdapterStatistics -EA SilentlyContinue
        $rx=($na|Measure-Object ReceivedBytes -Sum).Sum
        $tx=($na|Measure-Object SentBytes -Sum).Sum
        Write-Output "METRIC_NET=${rx}:${tx}"
        """
        return PowerShellCommand.encode(ps)
    }()

    func getSystemMetrics(for deviceId: UUID) async throws -> SystemMetrics {
        guard connectedDevices.contains(deviceId) else {
            throw SSHError.notConnected
        }

        let platform = try await platform(for: deviceId)
        guard platform.supportsInventory else { throw InventoryError.unsupported }
        let command = platform == .windows ? Self.windowsMetricsScript : Self.unixMetricsScript
        let output = try await executeCommand(command, on: deviceId)
        guard platform.hasValidMetrics(output) else {
            throw SSHError.commandFailed("System metrics are unavailable. Check the account’s read permissions and required system tools.")
        }
        return parseMetrics(output: output, deviceId: deviceId)
    }

    private func parseMetrics(output: String, deviceId: UUID) -> SystemMetrics {
        var values: [String: String] = [:]
        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("METRIC_") else { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            values[String(parts[0])] = String(parts[1])
        }

        func d(_ key: String) -> Double { Double(values[key] ?? "0") ?? 0 }
        func u(_ key: String) -> UInt64 { UInt64(values[key] ?? "0") ?? 0 }
        func i(_ key: String) -> Int { Int(values[key] ?? "0") ?? 0 }

        let loadParts = (values["METRIC_LOAD"] ?? "").split(separator: ":")
        let loadAvg = loadParts.compactMap { Double($0) }

        let netParts = (values["METRIC_NET"] ?? "0:0").split(separator: ":")
        let netIn = UInt64(netParts.first ?? "0") ?? 0
        let netOut = UInt64(netParts.last ?? "0") ?? 0

        let temp = d("METRIC_TEMP")
        var power = d("METRIC_POWER")
        var powerSource: String?
        if values["METRIC_OS"] == "Darwin", power <= 0,
           let current = values["METRIC_BATTERY_CURRENT"], let voltage = values["METRIC_BATTERY_VOLTAGE"],
           let batteryPower = MacBatteryPower.watts(amperage: current, millivolts: voltage) {
            power = batteryPower
            powerSource = "Battery charge/discharge"
        }

        // Parse GPU metrics (NVIDIA format: utilization, temp, mem_used, mem_total, power_draw)
        var gpuUsage: Double?
        var gpuTemp: Double?
        var gpuMemUsed: UInt64?
        var gpuMemTotal: UInt64?
        var gpuPower: Double?

        if let gpuData = values["METRIC_GPU"] {
            let gpuParts = gpuData.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            if gpuParts.count >= 5 {
                gpuUsage = Double(gpuParts[0])
                gpuTemp = Double(gpuParts[1])
                // nvidia-smi reports memory in MiB
                if let mu = Double(gpuParts[2]) { gpuMemUsed = UInt64(mu * 1_048_576) }
                if let mt = Double(gpuParts[3]) { gpuMemTotal = UInt64(mt * 1_048_576) }
                gpuPower = Double(gpuParts[4])
            }
        }

        // macOS GPU usage (simpler, no dedicated VRAM)
        if let gpuU = values["METRIC_GPU_USAGE"], let val = Double(gpuU) {
            gpuUsage = val
        }

        // macOS GPU power from powermetrics
        if let gpuPW = values["METRIC_GPU_POWER"], let val = Double(gpuPW), val > 0 {
            gpuPower = val
        }

        var cpuUsage = min(max(d("METRIC_CPU"), 0), 100)
        if values["METRIC_OS"] == "Linux", let counters = values["METRIC_CPU_COUNTERS"], let sample = LinuxCPUSample(counters: counters) {
            if let previous = linuxCPUSamples[deviceId], let recent = sample.usage(since: previous) { cpuUsage = recent }
            linuxCPUSamples[deviceId] = sample
        }

        return SystemMetrics(
            deviceId: deviceId,
            timestamp: Date(),
            cpuUsage: cpuUsage,
            memoryUsed: u("METRIC_MEM_USED"),
            memoryTotal: u("METRIC_MEM_TOTAL"),
            diskUsed: u("METRIC_DISK_USED"),
            diskTotal: u("METRIC_DISK_TOTAL"),
            rootVolumeReadOnly: values["METRIC_ROOT_READONLY"] == "1",
            temperature: temp > 0 ? temp : nil,
            fanSpeed: d("METRIC_FAN") > 0 ? Int(d("METRIC_FAN")) : nil,
            powerUsage: power > 0 ? power : nil,
            powerSource: powerSource,
            networkIn: netIn,
            networkOut: netOut,
            loadAverage: loadAvg,
            uptime: d("METRIC_UPTIME"),
            processes: i("METRIC_PROCS"),
            gpuUsage: gpuUsage,
            gpuTemperature: gpuTemp,
            gpuMemoryUsed: gpuMemUsed,
            gpuMemoryTotal: gpuMemTotal,
            gpuPowerDraw: gpuPower
        )
    }

    // MARK: - Device Category Auto-Detection

    private static let deviceDetectionScript = """
    OS=$(uname -s)
    if [ "$OS" = "Darwin" ]; then
      MODEL=$(system_profiler SPHardwareDataType 2>/dev/null | awk -F': ' '/Model Name/{gsub(/^[[:space:]]+/,"",$2);print $2}')
      echo "DETECT_MODEL=$MODEL"
    elif [ "$OS" = "Linux" ]; then
      MODEL=""
      if [ -f /proc/device-tree/model ]; then
        MODEL=$(cat /proc/device-tree/model 2>/dev/null | tr -d '\\0')
      fi
      if [ -z "$MODEL" ] && [ -f /sys/devices/soc0/machine ]; then
        MODEL=$(cat /sys/devices/soc0/machine 2>/dev/null)
      fi
      echo "DETECT_MODEL=$MODEL"
    fi
    """

    private static var windowsDetectionScript: String = {
        let ps = """
        $cs = Get-CimInstance Win32_ComputerSystem
        $mfr = $cs.Manufacturer
        $model = $cs.Model
        $chassis = (Get-CimInstance Win32_SystemEnclosure).ChassisTypes
        Write-Output "DETECT_MODEL=$mfr $model"
        Write-Output "DETECT_CHASSIS=$chassis"
        """
        guard let data = ps.data(using: .utf16LittleEndian) else { return "" }
        return "powershell -NoProfile -EncodedCommand \(data.base64EncodedString())"
    }()

    func detectDeviceCategory(for deviceId: UUID) async {
        guard let device = deviceById(deviceId) else { return }

        // Only auto-detect if current category is generic
        let genericCategories: [DeviceCategory] = [.server, .desktop, .laptop, .other, .miniPC]
        guard genericCategories.contains(device.category) else { return }

        // Try Unix detection first
        do {
            let output = try await executeCommand(Self.deviceDetectionScript, on: deviceId)
            if let model = Self.parseDetectModel(output), !model.isEmpty {
                if let newCategory = Self.mapModelToCategory(model) {
                    var updated = device
                    updated.category = newCategory
                    updateDevice(updated)
                }
                return
            }
        } catch {}

        // Fall back to Windows PowerShell detection
        do {
            let output = try await executeCommand(Self.windowsDetectionScript, on: deviceId)
            if let model = Self.parseDetectModel(output) {
                let newCategory = Self.mapModelToCategory(model) ?? Self.mapWindowsChassis(output)
                if let cat = newCategory {
                    var updated = device
                    updated.category = cat
                    updateDevice(updated)
                }
            }
        } catch {
            // Detection is best-effort, don't propagate errors
        }
    }

    private static func parseDetectModel(_ output: String) -> String? {
        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("DETECT_MODEL=") {
                return String(trimmed.dropFirst("DETECT_MODEL=".count))
            }
        }
        return nil
    }

    private static func mapWindowsChassis(_ output: String) -> DeviceCategory? {
        // WMI ChassisTypes: 3=Desktop, 9/10=Laptop, 35=MiniPC, 30=Tablet
        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("DETECT_CHASSIS=") {
                let chassisStr = String(trimmed.dropFirst("DETECT_CHASSIS=".count))
                // Parse individual numeric chassis values to avoid substring false positives
                let chassisValues = chassisStr.components(separatedBy: CharacterSet.decimalDigits.inverted)
                    .compactMap { Int($0) }
                for val in chassisValues {
                    switch val {
                    case 35: return .miniPC
                    case 9, 10, 14: return .laptop
                    case 3, 6, 7: return .desktop
                    default: continue
                    }
                }
            }
        }
        return nil
    }

    private static func mapModelToCategory(_ model: String) -> DeviceCategory? {
        let lower = model.lowercased()
        // Apple
        if lower.contains("mac mini") || lower.contains("macmini") { return .macMini }
        if lower.contains("mac studio") { return .macStudio }
        if lower.contains("macbook air") { return .macbookAir }
        if lower.contains("macbook pro") { return .macbookPro }
        if lower.contains("mac pro") { return .macPro }
        if lower.contains("imac") { return .iMac }
        // SBCs
        if lower.contains("raspberry pi") { return .raspberryPi }
        if lower.contains("jetson") && lower.contains("nano") { return .jetsonNano }
        if lower.contains("jetson") && lower.contains("thor") { return .jetsonThor }
        // Mini PCs (Beelink, Intel NUC, MinisForum, GMKtec, etc.)
        let miniPCBrands = ["beelink", "minisforum", "gmktec", "geekom", "chuwi", "acemagic", "trigkey", "nuc"]
        for brand in miniPCBrands {
            if lower.contains(brand) { return .miniPC }
        }
        if lower.contains("intel") && lower.contains("nuc") { return .miniPC }
        return nil
    }

    // MARK: - Auto-Connect

    func autoConnectDevices() async {
        for device in devices {
            // Localhost: always connect instantly (no SSH needed)
            if device.isLocalhost {
                markConnected(device)
                await detectDeviceCategory(for: device.id)
                continue
            }

            // Check for existing control socket first (works for all auth methods)
            if await checkControlSocket(for: device) {
                markConnected(device)
                await detectDeviceCategory(for: device.id)
                continue
            }

            if device.authMethod == .password {
                // Try stored Keychain password
                if let pwd = KeychainHelper.getPassword(for: device) {
                    do {
                        try await connect(to: device, password: pwd)
                        continue
                    } catch {
                        print("Auto-connect with saved password failed for \(device.displayName): \(error.localizedDescription)")
                    }
                }
                continue
            }

            // For key/agent auth, attempt full reconnection
            do {
                try await connect(to: device)
            } catch {
                print("Auto-connect failed for \(device.displayName): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Persistence

    private func saveDevices() {
        if let data = try? JSONEncoder().encode(devices) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func loadDevices() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([Device].self, from: data) {
            devices = decoded
        }
    }

    func saveConfig() {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: configKey)
        }
    }

    private func loadConfig() {
        if let data = UserDefaults.standard.data(forKey: configKey),
           let decoded = try? JSONDecoder().decode(SSHConfig.self, from: data) {
            config = decoded
        }
    }
}

// MARK: - SSH Errors

enum SSHError: LocalizedError {
    case notConnected
    case connectionFailed(String)
    case authenticationFailed
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to device"
        case .connectionFailed(let reason):
            return "Connection failed: \(reason)"
        case .authenticationFailed:
            return "Authentication failed"
        case .commandFailed(let reason):
            return "Command failed: \(reason)"
        }
    }
}
