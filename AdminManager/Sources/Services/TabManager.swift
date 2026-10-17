import Foundation
import SwiftUI

@Observable
@MainActor
final class TabManager {
    var tabs: [SSHTab] = []
    var activeTabId: UUID?

    var activeTab: SSHTab? {
        guard let id = activeTabId else { return nil }
        return tabs.first { $0.id == id }
    }

    var activeTabIndex: Int? {
        guard let id = activeTabId else { return nil }
        return tabs.firstIndex { $0.id == id }
    }

    init() {
        setupNotifications()
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            forName: .newTab,
            object: nil,
            queue: .main
        ) { _ in
            // Will be handled by view with device selection
        }

        NotificationCenter.default.addObserver(
            forName: .closeTab,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                if let activeId = self?.activeTabId {
                    self?.closeTab(id: activeId)
                }
            }
        }
    }

    // MARK: - Tab Management

    func createTab(for device: Device) -> SSHTab {
        let tab = SSHTab(
            deviceId: device.id,
            title: device.displayName,
            isConnected: false,
            terminalOutput: [
                TerminalLine(
                    content: "Connecting to \(device.connectionString)...",
                    type: .system
                )
            ]
        )
        tabs.append(tab)
        activeTabId = tab.id
        return tab
    }

    func closeTab(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs.remove(at: index)

        if activeTabId == id {
            if let newTab = tabs.last {
                activeTabId = newTab.id
            } else {
                activeTabId = nil
            }
        }
    }

    func selectTab(id: UUID) {
        if tabs.contains(where: { $0.id == id }) {
            activeTabId = id
        }
    }

    func selectNextTab() {
        guard let currentIndex = activeTabIndex, !tabs.isEmpty else { return }
        let nextIndex = (currentIndex + 1) % tabs.count
        activeTabId = tabs[nextIndex].id
    }

    func selectPreviousTab() {
        guard let currentIndex = activeTabIndex, !tabs.isEmpty else { return }
        let prevIndex = currentIndex > 0 ? currentIndex - 1 : tabs.count - 1
        activeTabId = tabs[prevIndex].id
    }

    // MARK: - Tab Content Updates

    func updateTabConnection(id: UUID, isConnected: Bool) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].isConnected = isConnected

        let message = isConnected ? "Connected successfully" : "Disconnected"
        appendOutput(to: id, line: TerminalLine(content: message, type: .system))
    }

    func appendOutput(to tabId: UUID, line: TerminalLine) {
        guard let index = tabs.firstIndex(where: { $0.id == tabId }) else { return }
        tabs[index].terminalOutput.append(line)

        // Keep terminal output manageable
        if tabs[index].terminalOutput.count > 1000 {
            tabs[index].terminalOutput.removeFirst(tabs[index].terminalOutput.count - 1000)
        }
    }

    func appendCommand(to tabId: UUID, command: String) {
        appendOutput(to: tabId, line: TerminalLine(content: "$ \(command)", type: .command))
    }

    func appendResponse(to tabId: UUID, output: String, isError: Bool = false) {
        let lines = output.components(separatedBy: "\n")
        for line in lines where !line.isEmpty {
            appendOutput(
                to: tabId,
                line: TerminalLine(content: line, type: isError ? .error : .output)
            )
        }
    }

    func clearTerminal(for tabId: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == tabId }) else { return }
        tabs[index].terminalOutput = [
            TerminalLine(content: "Terminal cleared", type: .system)
        ]
    }

    func updateCurrentCommand(for tabId: UUID, command: String) {
        guard let index = tabs.firstIndex(where: { $0.id == tabId }) else { return }
        tabs[index].currentCommand = command
    }

    // MARK: - Tab Reordering

    func moveTab(from source: IndexSet, to destination: Int) {
        tabs.move(fromOffsets: source, toOffset: destination)
    }

    func getTabsForDevice(_ deviceId: UUID) -> [SSHTab] {
        tabs.filter { $0.deviceId == deviceId }
    }

    func closeAllTabsForDevice(_ deviceId: UUID) {
        let tabIds = tabs.filter { $0.deviceId == deviceId }.map { $0.id }
        for id in tabIds {
            closeTab(id: id)
        }
    }
}
