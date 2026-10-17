import Foundation

/// Read-only, no sudo, no temporary files, no disk changes and no installation.
/// Explicit util-linux columns and JSON keep spaces and mount paths intact.
enum LinuxInventoryProbe {
    static let networkCountersAWK = #"""
        NR>2 {
          line=$0; sub(/^[[:space:]]+/, "", line)
          split(line, fields, /[[:space:]:]+/)
          if(fields[1]!="lo"){rx+=fields[2];tx+=fields[10]}
        }
        END {printf "METRIC_NET=%.0f:%.0f\n",rx,tx}
        """#

    static let script = #"""
        export LC_ALL=C
        printf 'ADMIN_INVENTORY_V1\n'
        if [ "$(uname -s 2>/dev/null)" != Linux ]; then
          printf 'ADMIN_UNSUPPORTED\nADMIN_INVENTORY_END\n'
          exit 0
        fi
        printf 'ADMIN_BLOCKS_BEGIN\n'
        BLOCKS=$(lsblk --json --bytes --paths --output NAME,PKNAME,MAJ:MIN,TYPE,SIZE,ROTA,RO,TRAN,MODEL,FSTYPE,LABEL,MOUNTPOINTS 2>/dev/null) ||
          BLOCKS=$(lsblk --json --bytes --paths --output NAME,PKNAME,MAJ:MIN,TYPE,SIZE,ROTA,RO,TRAN,MODEL,FSTYPE,LABEL,MOUNTPOINT 2>/dev/null) ||
          BLOCKS=$(lsblk --json --bytes --paths --output NAME,TYPE,SIZE,ROTA,MODEL,MOUNTPOINT 2>/dev/null) || BLOCKS=''
        printf '%s\n' "$BLOCKS"
        printf 'ADMIN_BLOCKS_END\nADMIN_VOLUMES_BEGIN\n'
        VOLUMES=$(findmnt --json --bytes --df --list --output SOURCE,TARGET,FSTYPE,MAJ:MIN,SIZE,USED,AVAIL,OPTIONS 2>/dev/null) || VOLUMES=''
        printf '%s\n' "$VOLUMES"
        printf 'ADMIN_VOLUMES_END\nADMIN_RESOURCES_BEGIN\n'
        printf 'CPU_MODEL=%s\n' "$(awk -F ': *' '/^model name|^Hardware|^Model/{print $2;exit}' /proc/cpuinfo 2>/dev/null)"
        printf 'CPU_CORES=%s\n' "$(getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null)"
        awk '
          /^MemTotal:/ {total=$2*1024}
          /^MemAvailable:/ {available=$2*1024;hasavailable=1}
          /^MemFree:/ {free=$2*1024}
          /^Buffers:/ {buffers=$2*1024}
          /^Cached:/ {cached=$2*1024}
          /^SwapTotal:/ {swaptotal=$2*1024;hasswap=1}
          /^SwapFree:/ {swapfree=$2*1024}
          END {
            if(total>0){printf "MEM_TOTAL=%.0f\nMEM_AVAILABLE=%.0f\n",total,hasavailable?available:free+buffers+cached}
            if(hasswap){printf "SWAP_TOTAL=%.0f\nSWAP_FREE=%.0f\n",swaptotal,swapfree}
          }' /proc/meminfo 2>/dev/null
        awk '{printf "UPTIME=%s\n",$1}' /proc/uptime 2>/dev/null
        awk '{printf "LOAD=%s %s %s\n",$1,$2,$3}' /proc/loadavg 2>/dev/null
        printf 'ADMIN_RESOURCES_END\nADMIN_INVENTORY_END\n'
        """#
}

/// Linux /proc/stat counters sampled since the previous refresh (not since boot).
struct LinuxCPUSample: Sendable {
    let total: UInt64
    let idle: UInt64
    init?(counters: String) {
        let fields = counters.split(whereSeparator: \.isWhitespace)
        let parsed = fields.prefix(8).map { UInt64($0) }
        guard parsed.count >= 4, parsed.allSatisfy({ $0 != nil }) else { return nil }
        let numbers = parsed.compactMap { $0 }
        var total: UInt64 = 0
        for number in numbers {
            let (value, overflow) = total.addingReportingOverflow(number)
            guard !overflow else { return nil }
            total = value
        }
        let (idle, overflow) = numbers[3].addingReportingOverflow(numbers.count > 4 ? numbers[4] : 0)
        guard !overflow, idle <= total else { return nil }
        self.total = total
        self.idle = idle
    }
    func usage(since previous: LinuxCPUSample) -> Double? {
        guard total > previous.total, idle >= previous.idle else { return nil }
        let elapsed = total - previous.total
        let idleElapsed = idle - previous.idle
        guard idleElapsed <= elapsed else { return nil }
        return min(100, max(0, 100 * (1 - Double(idleElapsed) / Double(elapsed))))
    }
}
