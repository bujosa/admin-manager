import Foundation
import SwiftUI

@Observable
@MainActor
final class DeviceMonitorService {
    var metricsCache: [UUID: SystemMetrics] = [:]
    var metricsHistory: [UUID: [SystemMetrics]] = [:]
    var metricsError: [UUID: String] = [:]
    var isMonitoring = false
    var refreshInterval: TimeInterval = 30

    private var monitoringTask: Task<Void, Never>?
    private let maxHistorySize = 60

    func startMonitoring(sshService: SSHService) {
        guard !isMonitoring else { return }
        isMonitoring = true

        monitoringTask = Task {
            while !Task.isCancelled && isMonitoring {
                await refreshAllMetrics(sshService: sshService)
                try? await Task.sleep(for: .seconds(refreshInterval))
            }
        }
    }

    func stopMonitoring() {
        isMonitoring = false
        monitoringTask?.cancel()
        monitoringTask = nil
    }

    func refreshAllMetrics(sshService: SSHService) async {
        for deviceId in sshService.activeSessions.keys {
            await refreshMetrics(for: deviceId, sshService: sshService)
        }
    }

    func refreshMetrics(for deviceId: UUID, sshService: SSHService) async {
        do {
            let metrics = try await sshService.getSystemMetrics(for: deviceId)
            metricsCache[deviceId] = metrics
            metricsError[deviceId] = nil

            var history = metricsHistory[deviceId] ?? []
            history.append(metrics)
            if history.count > maxHistorySize {
                history.removeFirst(history.count - maxHistorySize)
            }
            metricsHistory[deviceId] = history
        } catch {
            metricsError[deviceId] = "Metrics unavailable. Linux, macOS and Windows require their native read-only system tools. Check SSH permissions and refresh."
        }
    }

    func getLatestMetrics(for deviceId: UUID) -> SystemMetrics? {
        metricsCache[deviceId]
    }

    func getMetricsHistory(for deviceId: UUID) -> [SystemMetrics] {
        metricsHistory[deviceId] ?? []
    }

    func clearHistory(for deviceId: UUID) {
        metricsHistory.removeValue(forKey: deviceId)
        metricsCache.removeValue(forKey: deviceId)
        metricsError.removeValue(forKey: deviceId)
    }

    func clearAllHistory() {
        metricsHistory.removeAll()
        metricsCache.removeAll()
        metricsError.removeAll()
    }

    // MARK: - Aggregate Statistics

    var totalDevicesMonitored: Int {
        metricsCache.count
    }

    var averageCpuUsage: Double {
        guard !metricsCache.isEmpty else { return 0 }
        let total = metricsCache.values.reduce(0) { $0 + $1.cpuUsage }
        return total / Double(metricsCache.count)
    }

    var averageMemoryUsage: Double {
        guard !metricsCache.isEmpty else { return 0 }
        let total = metricsCache.values.reduce(0) { $0 + $1.memoryUsagePercent }
        return total / Double(metricsCache.count)
    }

    var healthySystems: Int {
        metricsCache.values.filter { $0.healthStatus == .healthy }.count
    }

    var warningSystems: Int {
        metricsCache.values.filter { $0.healthStatus == .warning }.count
    }

    var criticalSystems: Int {
        metricsCache.values.filter { $0.healthStatus == .critical }.count
    }
}
