import SwiftUI

struct NetworkMapView: View {
    @Environment(SSHService.self) private var sshService
    @Environment(DeviceMonitorService.self) private var monitor
    @Environment(NetworkScanService.self) private var networkService

    @State private var connectionSource: UUID?
    @State private var selectedConnectionId: UUID?
    @State private var connectionLabel = ""
    @State private var showLabelEditor = false
    @State private var pendingConnectionTarget: UUID?
    @State private var canvasSize: CGSize = .zero

    // Container states
    @State private var showContainerEditor = false
    @State private var newContainerLabel = ""
    @State private var newContainerColor = "blue"
    @State private var editingContainerId: UUID?
    @State private var editContainerLabel = ""
    @State private var showEditContainerSheet = false
    @State private var resizingContainerId: UUID?

    // Decorative icon states
    @State private var editingIconId: UUID?
    @State private var editIconLabel = ""
    @State private var showEditIconSheet = false

    // Hover states
    @State private var hoveredContainerId: UUID?
    @State private var hoveredNodeId: UUID?

    // Reconnect states
    @State private var reconnectingConnectionId: UUID?
    @State private var reconnectingEnd: ConnectionEnd?

    // Live drag arrow (draw.io style)
    @State private var mousePosition: CGPoint = .zero

    enum ConnectionEnd {
        case source, target
    }

    /// True when in any connection mode (new connection or reconnecting)
    private var isInConnectionMode: Bool {
        connectionSource != nil || reconnectingConnectionId != nil
    }

    private var devicesNotOnCanvas: [Device] {
        let nodeDeviceIds = Set(networkService.nodes.map { $0.deviceId })
        return sshService.devices.filter { !nodeDeviceIds.contains($0.id) }
    }

    private let containerColors = ["blue", "green", "purple", "orange", "red", "cyan", "yellow", "pink", "indigo", "teal", "gray"]

    private var hasCanvasContent: Bool {
        !networkService.nodes.isEmpty || !networkService.containers.isEmpty || !networkService.decorativeIcons.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            toolbar

            Divider()
                .background(Theme.divider)

            // Canvas
            if hasCanvasContent {
                canvas
            } else {
                emptyState
            }
        }
        .alert("Connection Label", isPresented: $showLabelEditor) {
            TextField("Label (optional)", text: $connectionLabel)
            Button("Add") {
                if let source = connectionSource, let target = pendingConnectionTarget {
                    networkService.addConnection(source: source, target: target, label: connectionLabel)
                }
                resetConnectionMode()
            }
            Button("Cancel", role: .cancel) {
                resetConnectionMode()
            }
        } message: {
            Text("Add an optional label for this connection (e.g., Ethernet, WiFi, VPN)")
        }
        .alert("New Container", isPresented: $showContainerEditor) {
            TextField("Label", text: $newContainerLabel)
            Button("Add") {
                let pos = CGPoint(
                    x: canvasSize.width / 2 + Double.random(in: -50...50),
                    y: canvasSize.height / 2 + Double.random(in: -50...50)
                )
                networkService.addContainer(label: newContainerLabel.isEmpty ? "Group" : newContainerLabel, position: pos, color: newContainerColor)
                newContainerLabel = ""
            }
            Button("Cancel", role: .cancel) {
                newContainerLabel = ""
            }
        } message: {
            Text("Enter a label for this container group")
        }
        .alert("Edit Label", isPresented: $showEditContainerSheet) {
            TextField("Label", text: $editContainerLabel)
            Button("Save") {
                if let id = editingContainerId {
                    networkService.updateContainerLabel(id: id, label: editContainerLabel)
                }
                editingContainerId = nil
            }
            Button("Cancel", role: .cancel) {
                editingContainerId = nil
            }
        }
        .alert("Edit Icon Label", isPresented: $showEditIconSheet) {
            TextField("Label", text: $editIconLabel)
            Button("Save") {
                if let id = editingIconId {
                    networkService.updateDecorativeIconLabel(id: id, label: editIconLabel)
                }
                editingIconId = nil
            }
            Button("Cancel", role: .cancel) {
                editingIconId = nil
            }
        }
    }

    // MARK: - Toolbar

    @ViewBuilder
    private var toolbar: some View {
        HStack(spacing: Theme.paddingMedium) {
            // Add Device
            if !devicesNotOnCanvas.isEmpty {
                Menu {
                    ForEach(devicesNotOnCanvas) { device in
                        Button {
                            let pos = CGPoint(
                                x: canvasSize.width / 2 + Double.random(in: -100...100),
                                y: canvasSize.height / 2 + Double.random(in: -100...100)
                            )
                            networkService.addNode(deviceId: device.id, position: pos)
                        } label: {
                            Label(device.displayName, systemImage: device.category.icon)
                        }
                    }
                } label: {
                    Label("Add Device", systemImage: "plus.circle")
                        .padding(.horizontal, Theme.paddingSmall)
                        .padding(.vertical, 4)
                }
            }

            // Add All button
            if devicesNotOnCanvas.count > 1 {
                Button {
                    addAllDevices()
                } label: {
                    Label("Add All", systemImage: "rectangle.stack.badge.plus")
                        .padding(.horizontal, Theme.paddingSmall)
                        .padding(.vertical, 4)
                }
            }

            Divider()
                .frame(height: 20)

            // Add Container
            Menu {
                ForEach(containerColors, id: \.self) { c in
                    Button {
                        newContainerColor = c
                        showContainerEditor = true
                    } label: {
                        Label(c.capitalized, systemImage: "rectangle.dashed")
                    }
                }
            } label: {
                Label("Container", systemImage: "rectangle.dashed")
                    .padding(.horizontal, Theme.paddingSmall)
                    .padding(.vertical, 4)
            }

            // Add Decorative Icon
            Menu {
                ForEach(DecorativeIconType.allCases, id: \.self) { iconType in
                    Button {
                        let pos = CGPoint(
                            x: canvasSize.width / 2 + Double.random(in: -80...80),
                            y: canvasSize.height / 2 + Double.random(in: -80...80)
                        )
                        networkService.addDecorativeIcon(type: iconType, position: pos)
                    } label: {
                        Label(iconType.rawValue, systemImage: iconType.icon)
                    }
                }
            } label: {
                Label("Icon", systemImage: "star.square")
                    .padding(.horizontal, Theme.paddingSmall)
                    .padding(.vertical, 4)
            }

            Divider()
                .frame(height: 20)

            // Auto Layout
            Button {
                withAnimation(Theme.animationMedium) {
                    networkService.autoLayout(devices: sshService.devices, in: canvasSize)
                }
            } label: {
                Label("Auto Layout", systemImage: "circle.grid.3x3")
                    .padding(.horizontal, Theme.paddingSmall)
                    .padding(.vertical, 4)
            }
            .disabled(networkService.nodes.isEmpty)

            Spacer()

            // Stats
            if hasCanvasContent {
                Text(statsText)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }

            // Export
            if hasCanvasContent {
                Button {
                    exportTopologyAsPNG()
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }

            // Clear All
            if hasCanvasContent {
                Button(role: .destructive) {
                    networkService.nodes.removeAll()
                    networkService.connections.removeAll()
                    networkService.containers.removeAll()
                    networkService.decorativeIcons.removeAll()
                    networkService.saveTopology()
                } label: {
                    Label("Clear", systemImage: "trash")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .tint(Theme.error)
            }
        }
        .padding(Theme.paddingMedium)
        .background(Theme.secondaryBackground)
    }

    private var statsText: String {
        var parts: [String] = []
        if !networkService.nodes.isEmpty {
            parts.append("\(networkService.nodes.count) devices")
        }
        if !networkService.connections.isEmpty {
            parts.append("\(networkService.connections.count) connections")
        }
        if !networkService.containers.isEmpty {
            parts.append("\(networkService.containers.count) groups")
        }
        if !networkService.decorativeIcons.isEmpty {
            parts.append("\(networkService.decorativeIcons.count) icons")
        }
        return parts.joined(separator: ", ")
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: Theme.paddingLarge) {
            Spacer()

            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 48))
                .foregroundStyle(Theme.tertiaryText)

            Text("Network Topology")
                .font(.title3)
                .fontWeight(.semibold)

            Text("Add devices to build your network map")
                .font(.body)
                .foregroundStyle(Theme.secondaryText)

            if !sshService.devices.isEmpty {
                Button {
                    addAllDevices()
                } label: {
                    Label("Add All Devices", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            GeometryReader { geo in
                Color.clear.onAppear { canvasSize = geo.size }
                    .onChange(of: geo.size) { _, newSize in canvasSize = newSize }
            }
        )
    }

    // MARK: - Canvas

    @ViewBuilder
    private var canvas: some View {
        GeometryReader { geo in
            ZStack {
                // Grid Background
                gridBackground(in: geo.size)

                // Containers (behind everything)
                ForEach(networkService.containers) { container in
                    containerView(container)
                }

                // Connections
                ForEach(networkService.connections) { connection in
                    connectionLine(connection, in: geo.size)
                }

                // Decorative Icons
                ForEach(networkService.decorativeIcons) { icon in
                    decorativeIconView(icon)
                }

                // Nodes
                ForEach(networkService.nodes) { node in
                    if let device = sshService.deviceById(node.deviceId) {
                        let isNodeSource = connectionSource == device.id

                        TopologyNodeView(
                            device: device,
                            metrics: monitor.getLatestMetrics(for: device.id),
                            isConnecting: isInConnectionMode,
                            isConnectionSource: isNodeSource,
                            isConnectionTarget: (connectionSource != nil || reconnectingConnectionId != nil) && !isNodeSource,
                            position: node.position.cgPoint
                        )
                        .position(node.position.cgPoint)
                        .onHover { hovering in
                            withAnimation(.easeInOut(duration: 0.15)) {
                                hoveredNodeId = hovering ? device.id : nil
                            }
                        }
                        .gesture(
                            DragGesture(minimumDistance: 3)
                                .onChanged { value in
                                    if !isInConnectionMode {
                                        networkService.updateNodePosition(
                                            deviceId: node.deviceId,
                                            position: value.location
                                        )
                                    }
                                }
                        )
                        .simultaneousGesture(
                            TapGesture()
                                .onEnded {
                                    handleNodeTap(deviceId: device.id)
                                }
                        )
                        .contextMenu {
                            Button {
                                connectionSource = device.id
                            } label: {
                                Label("Connect from Here", systemImage: "arrow.right.circle")
                            }

                            Divider()

                            Button(role: .destructive) {
                                withAnimation(Theme.animationMedium) {
                                    networkService.removeNode(deviceId: device.id)
                                }
                            } label: {
                                Label("Remove from Map", systemImage: "trash")
                            }
                        }
                    }
                }

                // Connection overlay layers
                if isInConnectionMode {
                    anchorDotsLayer
                    liveArrowPreview
                    connectionModeIndicator
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
                // Tap on empty canvas cancels connection mode
                if isInConnectionMode {
                    resetConnectionMode()
                }
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    if connectionSource != nil {
                        mousePosition = location
                    }
                case .ended:
                    break
                }
            }
            .onKeyPress(.escape) {
                if isInConnectionMode {
                    resetConnectionMode()
                    return .handled
                }
                return .ignored
            }
            .focusable()
            .onAppear {
                canvasSize = geo.size
                autoAddConnectedDevices()
            }
            .onChange(of: geo.size) { _, newSize in canvasSize = newSize }
            .onChange(of: sshService.connectedDevices.count) {
                autoAddConnectedDevices()
            }
        }
        .background(Theme.background)
    }

    // MARK: - Anchor Dots Layer

    @ViewBuilder
    private var anchorDotsLayer: some View {
        let hasSource = connectionSource != nil

        // Container anchor dots
        ForEach(networkService.containers) { container in
            let isSource = connectionSource == container.id
            let showAnchors = hasSource || hoveredContainerId == container.id
            if showAnchors {
                let anchors = networkService.anchorPoints(for: container)
                let dotColor: Color = isSource ? Theme.accent : Theme.success
                ForEach(0..<anchors.count, id: \.self) { i in
                    Circle()
                        .fill(dotColor)
                        .frame(width: 12, height: 12)
                        .overlay(Circle().stroke(Color.white.opacity(0.8), lineWidth: 1))
                        .shadow(color: dotColor.opacity(0.5), radius: 3)
                        .contentShape(Circle().scale(1.5))
                        .onTapGesture { handleElementTap(id: container.id) }
                        .position(anchors[i])
                }
            }
        }

        // Device node anchor dots
        ForEach(networkService.nodes) { node in
            if let device = sshService.deviceById(node.deviceId) {
                let isNodeSource = connectionSource == device.id
                let showAnchors = hasSource || hoveredNodeId == device.id
                if showAnchors {
                    let dotColor: Color = isNodeSource ? Theme.accent : Theme.success
                    let nodeAnchors = networkService.anchorPointsForNode(at: node.position.cgPoint)
                    ForEach(0..<nodeAnchors.count, id: \.self) { i in
                        Circle()
                            .fill(dotColor)
                            .frame(width: 10, height: 10)
                            .overlay(Circle().stroke(Color.white.opacity(0.8), lineWidth: 1))
                            .shadow(color: dotColor.opacity(0.5), radius: 3)
                            .contentShape(Circle().scale(1.5))
                            .onTapGesture { handleNodeTap(deviceId: device.id) }
                            .position(nodeAnchors[i])
                    }
                }
            }
        }

        // Decorative icon anchor dots
        if hasSource {
            ForEach(networkService.decorativeIcons) { icon in
                if connectionSource != icon.id {
                    Circle()
                        .fill(Theme.success)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(Color.white.opacity(0.8), lineWidth: 1))
                        .shadow(color: Theme.success.opacity(0.5), radius: 3)
                        .contentShape(Circle().scale(1.5))
                        .onTapGesture { handleElementTap(id: icon.id) }
                        .position(icon.position.cgPoint)
                }
            }
        }
    }

    // MARK: - Live Arrow Preview

    @ViewBuilder
    private var liveArrowPreview: some View {
        if let sourceId = connectionSource {
            let sourcePos = networkService.connectionPoint(for: sourceId, towards: mousePosition)
                ?? networkService.positionForElement(id: sourceId)
            if let from = sourcePos {
                Path { path in
                    path.move(to: from)
                    path.addLine(to: mousePosition)
                }
                .stroke(Theme.accent.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))

                arrowHead(from: from, to: mousePosition, color: Theme.accent.opacity(0.6), size: 10)
            }
        }
    }

    // MARK: - Connection Mode Indicator

    @ViewBuilder
    private var connectionModeIndicator: some View {
        VStack {
            Spacer()
            HStack {
                Image(systemName: reconnectingConnectionId != nil ? "arrow.triangle.swap" : "arrow.right.circle")
                if reconnectingConnectionId != nil {
                    let endName = reconnectingEnd == .source ? "source" : "target"
                    Text("Click an element to set as new \(endName)")
                } else {
                    Text("Click a target element to connect")
                }
                Button("Cancel") { resetConnectionMode() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .font(.caption)
            .foregroundStyle(reconnectingConnectionId != nil ? Theme.warning : Theme.accent)
            .padding(Theme.paddingSmall)
            .background((reconnectingConnectionId != nil ? Theme.warning : Theme.accent).opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
            .padding(Theme.paddingMedium)
        }
    }

    // MARK: - Container View

    @ViewBuilder
    private func containerView(_ container: TopologyContainer) -> some View {
        let color = colorFromString(container.color)
        let isSource = connectionSource == container.id
        let isTarget = (connectionSource != nil || reconnectingConnectionId != nil) && !isSource
        let w = container.size.cgSize.width
        let h = container.size.cgSize.height

        let strokeColor: Color = isSource ? Theme.accent :
            (isTarget ? Theme.success.opacity(hoveredContainerId == container.id ? 1 : 0.6) : color.opacity(0.4))
        let strokeWidth: CGFloat = isSource ? 2.5 : (isTarget ? 2 : 1.5)

        ZStack(alignment: .topLeading) {
            // Container rectangle
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(isSource ? 0.12 : (isTarget ? 0.08 : 0.05)))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            strokeColor,
                            style: StrokeStyle(lineWidth: strokeWidth, dash: isTarget ? [] : [8, 4])
                        )
                )
                .frame(width: w, height: h)

            // Label header
            HStack(spacing: 4) {
                Image(systemName: container.icon)
                    .font(.caption2)
                Text(container.label)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundStyle(isSource ? Theme.accent : color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background((isSource ? Theme.accent : color).opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .offset(x: 8, y: -12)

            // Resize handle (bottom-right corner)
            if !isInConnectionMode {
                ZStack {
                    // Larger invisible hit area
                    Color.clear
                        .frame(width: 24, height: 24)
                    // Visible grip lines
                    Path { path in
                        // Three diagonal lines (resize grip)
                        for i in 0..<3 {
                            let offset = CGFloat(i) * 4
                            path.move(to: CGPoint(x: 14 - offset, y: 14))
                            path.addLine(to: CGPoint(x: 14, y: 14 - offset))
                        }
                    }
                    .stroke(
                        hoveredContainerId == container.id ? color : color.opacity(0.4),
                        lineWidth: hoveredContainerId == container.id ? 1.5 : 1
                    )
                }
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
                .offset(x: w - 12, y: h - 12)
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            let newWidth = max(150, value.location.x)
                            let newHeight = max(100, value.location.y)
                            networkService.updateContainerSize(
                                id: container.id,
                                size: CGSize(width: newWidth, height: newHeight)
                            )
                        }
                )
                .onHover { hovering in
                    if hovering {
                        NSCursor(image: NSImage(systemSymbolName: "arrow.up.left.and.arrow.down.right", accessibilityDescription: nil) ?? NSImage(), hotSpot: NSPoint(x: 8, y: 8)).push()
                    } else {
                        NSCursor.pop()
                    }
                }
            }
        }
        .shadow(color: isSource ? Theme.accent.opacity(0.4) : (isTarget ? Theme.success.opacity(0.2) : .clear), radius: 10)
        .position(x: container.position.cgPoint.x + w / 2, y: container.position.cgPoint.y + h / 2)
        .gesture(
            DragGesture(minimumDistance: 3)
                .onChanged { value in
                    if !isInConnectionMode {
                        let newX = value.location.x - w / 2
                        let newY = value.location.y - h / 2
                        networkService.updateContainerPosition(
                            id: container.id,
                            position: CGPoint(x: newX, y: newY)
                        )
                    }
                }
        )
        .simultaneousGesture(
            TapGesture()
                .onEnded {
                    handleElementTap(id: container.id)
                }
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                hoveredContainerId = hovering ? container.id : nil
            }
        }
        .contextMenu {
            Button {
                connectionSource = container.id
            } label: {
                Label("Connect from Here", systemImage: "arrow.right.circle")
            }

            Divider()

            Button {
                editingContainerId = container.id
                editContainerLabel = container.label
                showEditContainerSheet = true
            } label: {
                Label("Edit Label", systemImage: "pencil")
            }

            Menu("Color") {
                ForEach(containerColors, id: \.self) { c in
                    Button(c.capitalized) {
                        networkService.updateContainerColor(id: container.id, color: c)
                    }
                }
            }

            Divider()

            Button(role: .destructive) {
                withAnimation(Theme.animationMedium) {
                    networkService.removeContainer(id: container.id)
                }
            } label: {
                Label("Delete Container", systemImage: "trash")
            }
        }
        .cursor(isInConnectionMode ? .crosshair : .openHand)
    }

    // MARK: - Decorative Icon View

    @ViewBuilder
    private func decorativeIconView(_ icon: TopologyDecorativeIcon) -> some View {
        let color = colorFromString(icon.iconType.color)
        let isSource = connectionSource == icon.id
        let isTarget = (connectionSource != nil || reconnectingConnectionId != nil) && !isSource

        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill((isSource ? Theme.accent : (isTarget ? Theme.success : color)).opacity(isSource ? 0.25 : (isTarget ? 0.2 : 0.15)))
                    .frame(width: 48, height: 48)

                Circle()
                    .stroke(
                        isSource ? Theme.accent : (isTarget ? Theme.success.opacity(0.6) : color.opacity(0.4)),
                        style: StrokeStyle(lineWidth: isSource ? 2.5 : (isTarget ? 2 : 1), dash: (isSource || isTarget) ? [] : [4, 3])
                    )
                    .frame(width: 48, height: 48)

                Image(systemName: icon.iconType.icon)
                    .font(.system(size: 22))
                    .foregroundStyle(isSource ? Theme.accent : color)
            }
            .shadow(color: isSource ? Theme.accent.opacity(0.5) : .clear, radius: 8)

            Text(icon.label)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(isSource ? Theme.accent : color)
                .lineLimit(1)
        }
        .frame(width: 70)
        .contentShape(Rectangle())
        .position(icon.position.cgPoint)
        .gesture(
            DragGesture(minimumDistance: 3)
                .onChanged { value in
                    if !isInConnectionMode {
                        networkService.updateDecorativeIconPosition(id: icon.id, position: value.location)
                    }
                }
        )
        .simultaneousGesture(
            TapGesture()
                .onEnded {
                    handleElementTap(id: icon.id)
                }
        )
        .contextMenu {
            Button {
                connectionSource = icon.id
            } label: {
                Label("Connect from Here", systemImage: "arrow.right.circle")
            }

            Divider()

            Button {
                editingIconId = icon.id
                editIconLabel = icon.label
                showEditIconSheet = true
            } label: {
                Label("Edit Label", systemImage: "pencil")
            }

            Divider()

            Button(role: .destructive) {
                withAnimation(Theme.animationMedium) {
                    networkService.removeDecorativeIcon(id: icon.id)
                }
            } label: {
                Label("Delete Icon", systemImage: "trash")
            }
        }
        .cursor(isInConnectionMode ? .crosshair : .openHand)
    }

    // MARK: - Grid Background

    @ViewBuilder
    private func gridBackground(in size: CGSize) -> some View {
        Canvas { context, canvasSize in
            let gridSpacing: CGFloat = 40
            let color = Color.white.opacity(0.03)

            // Vertical lines
            var x: CGFloat = 0
            while x < canvasSize.width {
                let path = Path { p in
                    p.move(to: CGPoint(x: x, y: 0))
                    p.addLine(to: CGPoint(x: x, y: canvasSize.height))
                }
                context.stroke(path, with: .color(color), lineWidth: 1)
                x += gridSpacing
            }

            // Horizontal lines
            var y: CGFloat = 0
            while y < canvasSize.height {
                let path = Path { p in
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: canvasSize.width, y: y))
                }
                context.stroke(path, with: .color(color), lineWidth: 1)
                y += gridSpacing
            }
        }
    }

    // MARK: - Connection Line

    @ViewBuilder
    private func connectionLine(_ connection: TopologyConnection, in size: CGSize) -> some View {
        let rawSource = networkService.positionForElement(id: connection.sourceDeviceId)
        let rawTarget = networkService.positionForElement(id: connection.targetDeviceId)
        let sourcePos = rawTarget.flatMap { networkService.connectionPoint(for: connection.sourceDeviceId, towards: $0) }
        let targetPos = rawSource.flatMap { networkService.connectionPoint(for: connection.targetDeviceId, towards: $0) }

        if let from = sourcePos, let to = targetPos {
            let isReconnecting = reconnectingConnectionId == connection.id
            let isSelected = selectedConnectionId == connection.id
            let lineColor: Color = isReconnecting ? Theme.warning :
                (isSelected ? Theme.accent : Color.white.opacity(0.3))
            let lineWidth: CGFloat = (isSelected || isReconnecting) ? 2.5 : 1.5

            ZStack {
                // Line
                Path { path in
                    path.move(to: from)
                    path.addLine(to: to)
                }
                .stroke(
                    lineColor,
                    style: StrokeStyle(
                        lineWidth: lineWidth,
                        dash: isReconnecting ? [4, 4] : []
                    )
                )

                // Arrowhead at target
                arrowHead(from: from, to: to, color: lineColor, size: isSelected ? 12 : 10)

                // Label at midpoint
                if !connection.label.isEmpty {
                    let mid = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
                    Text(connection.label)
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.secondaryBackground.opacity(0.9))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .position(mid)
                }

                // Tap target (invisible wider path)
                Path { path in
                    path.move(to: from)
                    path.addLine(to: to)
                }
                .stroke(Color.clear, lineWidth: 20)
                .contentShape(
                    Path { path in
                        path.move(to: from)
                        path.addLine(to: to)
                    }
                    .strokedPath(StrokeStyle(lineWidth: 20))
                )
                .onTapGesture {
                    if selectedConnectionId == connection.id {
                        selectedConnectionId = nil
                    } else {
                        selectedConnectionId = connection.id
                    }
                }
                .contextMenu {
                    Button {
                        withAnimation(Theme.animationMedium) {
                            networkService.reverseConnection(id: connection.id)
                        }
                    } label: {
                        Label("Reverse Direction", systemImage: "arrow.left.arrow.right")
                    }

                    Divider()

                    Button {
                        reconnectingConnectionId = connection.id
                        reconnectingEnd = .source
                        selectedConnectionId = connection.id
                    } label: {
                        Label("Change Source", systemImage: "arrow.backward.circle")
                    }

                    Button {
                        reconnectingConnectionId = connection.id
                        reconnectingEnd = .target
                        selectedConnectionId = connection.id
                    } label: {
                        Label("Change Target", systemImage: "arrow.forward.circle")
                    }

                    Divider()

                    Button(role: .destructive) {
                        withAnimation(Theme.animationMedium) {
                            networkService.removeConnection(id: connection.id)
                            selectedConnectionId = nil
                        }
                    } label: {
                        Label("Delete Connection", systemImage: "trash")
                    }
                }
            }
        }
    }

    /// Draws a triangular arrowhead pointing at `to` from `from`.
    @ViewBuilder
    private func arrowHead(from: CGPoint, to: CGPoint, color: Color, size: CGFloat) -> some View {
        let dx = to.x - from.x
        let dy = to.y - from.y
        let length = sqrt(dx * dx + dy * dy)
        if length > 0 {
            let unitX = dx / length
            let unitY = dy / length
            // Arrow tip is at `to`
            let tip = to
            // Base points perpendicular to the line
            let baseCenter = CGPoint(x: tip.x - unitX * size, y: tip.y - unitY * size)
            let perpX = -unitY
            let perpY = unitX
            let halfWidth = size * 0.5
            let left = CGPoint(x: baseCenter.x + perpX * halfWidth, y: baseCenter.y + perpY * halfWidth)
            let right = CGPoint(x: baseCenter.x - perpX * halfWidth, y: baseCenter.y - perpY * halfWidth)

            Path { path in
                path.move(to: tip)
                path.addLine(to: left)
                path.addLine(to: right)
                path.closeSubpath()
            }
            .fill(color)
        }
    }

    // MARK: - Helpers

    private func colorFromString(_ name: String) -> Color {
        switch name {
        case "blue": return .blue
        case "purple": return .purple
        case "green": return .green
        case "red": return .red
        case "orange": return .orange
        case "cyan": return .cyan
        case "yellow": return .yellow
        case "pink": return .pink
        case "indigo": return .indigo
        case "teal": return .teal
        default: return .gray
        }
    }

    private func handleNodeTap(deviceId: UUID) {
        if isInConnectionMode {
            handleElementTap(id: deviceId)
        } else {
            NotificationCenter.default.post(name: .showDeviceDetail, object: deviceId)
        }
    }

    private func handleElementTap(id: UUID) {
        // Reconnect mode: update the connection's source or target
        if let connId = reconnectingConnectionId, let end = reconnectingEnd {
            withAnimation(Theme.animationMedium) {
                switch end {
                case .source:
                    networkService.updateConnectionSource(id: connId, newSource: id)
                case .target:
                    networkService.updateConnectionTarget(id: connId, newTarget: id)
                }
            }
            reconnectingConnectionId = nil
            reconnectingEnd = nil
            selectedConnectionId = nil
            return
        }

        // Normal connection mode: source already set via context menu
        guard connectionSource != nil, connectionSource != id else { return }
        pendingConnectionTarget = id
        connectionLabel = ""
        showLabelEditor = true
    }

    private func resetConnectionMode() {
        connectionSource = nil
        pendingConnectionTarget = nil
        connectionLabel = ""
        reconnectingConnectionId = nil
        reconnectingEnd = nil
    }

    private func autoAddConnectedDevices() {
        let nodeDeviceIds = Set(networkService.nodes.map { $0.deviceId })
        let missingConnected = sshService.devices.filter {
            sshService.isConnected(deviceId: $0.id) && !nodeDeviceIds.contains($0.id)
        }
        guard !missingConnected.isEmpty, canvasSize.width > 0 else { return }

        let existingCount = networkService.nodes.count
        for (index, device) in missingConnected.enumerated() {
            let offset = Double(existingCount + index)
            let x = canvasSize.width / 2 + cos(offset * 1.3) * 120
            let y = canvasSize.height / 2 + sin(offset * 1.3) * 120
            networkService.addNode(deviceId: device.id, position: CGPoint(x: x, y: y))
        }
    }

    @MainActor
    private func exportTopologyAsPNG() {
        let exportView = TopologyExportView(
            nodes: networkService.nodes,
            connections: networkService.connections,
            containers: networkService.containers,
            decorativeIcons: networkService.decorativeIcons,
            devices: sshService.devices,
            metrics: sshService.devices.compactMap { monitor.getLatestMetrics(for: $0.id) },
            canvasSize: canvasSize,
            networkService: networkService
        )

        let renderer = ImageRenderer(content: exportView)
        renderer.scale = 2.0

        guard let nsImage = renderer.nsImage else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "topology.png"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            guard let tiffData = nsImage.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiffData),
                  let pngData = bitmap.representation(using: .png, properties: [:]) else { return }
            try? pngData.write(to: url)
        }
    }

    private func addAllDevices() {
        let count = devicesNotOnCanvas.count
        let centerX = canvasSize.width / 2
        let centerY = canvasSize.height / 2
        let radius = min(canvasSize.width, canvasSize.height) * 0.3

        for (index, device) in devicesNotOnCanvas.enumerated() {
            let angle = (2 * Double.pi / Double(max(count, 1))) * Double(index) - Double.pi / 2
            let x = centerX + radius * cos(angle)
            let y = centerY + radius * sin(angle)
            networkService.addNode(deviceId: device.id, position: CGPoint(x: x, y: y))
        }
    }
}

// MARK: - Topology Node View

struct TopologyNodeView: View {
    let device: Device
    let metrics: SystemMetrics?
    let isConnecting: Bool
    let isConnectionSource: Bool
    var isConnectionTarget: Bool = false
    let position: CGPoint

    @State private var isHovered = false

    private var borderColor: Color {
        if isConnectionSource { return Theme.accent }
        if isConnectionTarget && isHovered { return Theme.success }
        if isConnectionTarget { return Theme.success.opacity(0.6) }
        return categoryColor.opacity(isHovered ? 0.8 : 0.5)
    }

    private var borderWidth: CGFloat {
        if isConnectionSource { return 2.5 }
        if isConnectionTarget { return isHovered ? 2.5 : 2 }
        return isHovered ? 2 : 1.5
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                // Background circle
                Circle()
                    .fill(categoryColor.opacity(isHovered ? 0.35 : 0.2))
                    .frame(width: 56, height: 56)

                Circle()
                    .stroke(borderColor, lineWidth: borderWidth)
                    .frame(width: 56, height: 56)

                // Device icon
                DeviceIconView(category: device.category, size: 32)

                // Online status dot
                Circle()
                    .fill(device.isOnline ? Theme.success : Theme.error)
                    .frame(width: 10, height: 10)
                    .overlay(
                        Circle()
                            .stroke(Theme.background, lineWidth: 2)
                    )
                    .offset(x: 20, y: -20)
            }
            .shadow(color: isConnectionSource ? Theme.accent.opacity(0.5) : (isConnectionTarget ? Theme.success.opacity(0.3) : (isHovered ? categoryColor.opacity(0.3) : .clear)), radius: isConnectionTarget ? 10 : (isHovered ? 10 : 8))

            // Device name
            Text(device.displayName)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(Theme.text)
                .lineLimit(1)

            // Category label
            Text(device.category.rawValue)
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(categoryColor)
                .lineLimit(1)

            // Metrics badge
            if let metrics = metrics {
                Text(String(format: "CPU %.0f%%", metrics.cpuUsage))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(metrics.cpuUsage > 80 ? Theme.error : Theme.secondaryText)
            }
        }
        .frame(width: 100)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
            if hovering {
                (isConnecting ? NSCursor.crosshair : NSCursor.openHand).push()
            } else {
                NSCursor.pop()
            }
        }
        .help(tooltipText)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }

    private var tooltipText: String {
        var lines = [
            device.displayName,
            device.category.rawValue,
            device.hostname,
            device.isOnline ? "Online" : "Offline"
        ]
        if let metrics = metrics {
            lines.append(String(format: "CPU: %.1f%%  Mem: %.1f/%.1fGB", metrics.cpuUsage, metrics.memoryUsedGB, metrics.memoryTotalGB))
            if let temp = metrics.temperature {
                lines.append(String(format: "Temp: %.0f°C", temp))
            }
        }
        return lines.joined(separator: "\n")
    }

    private var categoryColor: Color {
        switch device.category.color {
        case "blue": return .blue
        case "purple": return .purple
        case "green": return .green
        case "red": return .red
        case "orange": return .orange
        case "cyan": return .cyan
        default: return .gray
        }
    }
}

// MARK: - Topology Export View

struct TopologyExportView: View {
    let nodes: [TopologyNode]
    let connections: [TopologyConnection]
    let containers: [TopologyContainer]
    let decorativeIcons: [TopologyDecorativeIcon]
    let devices: [Device]
    let metrics: [SystemMetrics]
    let canvasSize: CGSize
    let networkService: NetworkScanService

    var body: some View {
        ZStack {
            // Background
            Color(nsColor: NSColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1))

            // Containers
            ForEach(containers) { container in
                exportContainer(container)
            }

            // Connections
            ForEach(connections) { connection in
                exportConnectionLine(connection)
            }

            // Decorative Icons
            ForEach(decorativeIcons) { icon in
                exportDecorativeIcon(icon)
            }

            // Nodes
            ForEach(nodes) { node in
                if let device = devices.first(where: { $0.id == node.deviceId }) {
                    exportNode(device: device, position: node.position.cgPoint)
                }
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .preferredColorScheme(.dark)
    }

    private func colorFromString(_ name: String) -> Color {
        switch name {
        case "blue": return .blue
        case "purple": return .purple
        case "green": return .green
        case "red": return .red
        case "orange": return .orange
        case "cyan": return .cyan
        case "yellow": return .yellow
        case "pink": return .pink
        case "indigo": return .indigo
        case "teal": return .teal
        default: return .gray
        }
    }

    @ViewBuilder
    private func exportContainer(_ container: TopologyContainer) -> some View {
        let color = colorFromString(container.color)
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(color.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [8, 4]))
                )
                .frame(width: container.size.cgSize.width, height: container.size.cgSize.height)

            HStack(spacing: 4) {
                Image(systemName: container.icon).font(.caption2)
                Text(container.label).font(.caption).fontWeight(.medium)
            }
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .offset(x: 8, y: -12)
        }
        .position(
            x: container.position.cgPoint.x + container.size.cgSize.width / 2,
            y: container.position.cgPoint.y + container.size.cgSize.height / 2
        )
    }

    @ViewBuilder
    private func exportConnectionLine(_ connection: TopologyConnection) -> some View {
        let rawSource = networkService.positionForElement(id: connection.sourceDeviceId)
        let rawTarget = networkService.positionForElement(id: connection.targetDeviceId)
        let from = rawTarget.flatMap { networkService.connectionPoint(for: connection.sourceDeviceId, towards: $0) }
        let to = rawSource.flatMap { networkService.connectionPoint(for: connection.targetDeviceId, towards: $0) }

        if let from, let to {
            let lineColor = Color.white.opacity(0.3)
            ZStack {
                Path { path in path.move(to: from); path.addLine(to: to) }
                    .stroke(lineColor, lineWidth: 1.5)

                // Arrowhead
                exportArrowHead(from: from, to: to, color: lineColor)

                if !connection.label.isEmpty {
                    let mid = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
                    Text(connection.label)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .position(mid)
                }
            }
        }
    }

    @ViewBuilder
    private func exportArrowHead(from: CGPoint, to: CGPoint, color: Color) -> some View {
        let dx = to.x - from.x
        let dy = to.y - from.y
        let length = sqrt(dx * dx + dy * dy)
        if length > 0 {
            let unitX = dx / length
            let unitY = dy / length
            let tip = to
            let baseCenter = CGPoint(x: tip.x - unitX * 10, y: tip.y - unitY * 10)
            let perpX = -unitY
            let perpY = unitX
            let left = CGPoint(x: baseCenter.x + perpX * 5, y: baseCenter.y + perpY * 5)
            let right = CGPoint(x: baseCenter.x - perpX * 5, y: baseCenter.y - perpY * 5)

            Path { path in
                path.move(to: tip)
                path.addLine(to: left)
                path.addLine(to: right)
                path.closeSubpath()
            }
            .fill(color)
        }
    }

    @ViewBuilder
    private func exportDecorativeIcon(_ icon: TopologyDecorativeIcon) -> some View {
        let color = colorFromString(icon.iconType.color)
        VStack(spacing: 4) {
            ZStack {
                Circle().fill(color.opacity(0.15)).frame(width: 48, height: 48)
                Circle().stroke(color.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 3])).frame(width: 48, height: 48)
                Image(systemName: icon.iconType.icon).font(.system(size: 22)).foregroundStyle(color)
            }
            Text(icon.label).font(.caption2).fontWeight(.medium).foregroundStyle(color).lineLimit(1)
        }
        .frame(width: 70)
        .position(icon.position.cgPoint)
    }

    @ViewBuilder
    private func exportNode(device: Device, position: CGPoint) -> some View {
        let categoryColor = colorFromString(device.category.color)
        VStack(spacing: 4) {
            ZStack {
                Circle().fill(categoryColor.opacity(0.2)).frame(width: 56, height: 56)
                Circle().stroke(categoryColor.opacity(0.5), lineWidth: 1.5).frame(width: 56, height: 56)
                DeviceIconView(category: device.category, size: 32)
                Circle()
                    .fill(device.isOnline ? Color.green : Color.red)
                    .frame(width: 10, height: 10)
                    .overlay(Circle().stroke(Color(nsColor: NSColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1)), lineWidth: 2))
                    .offset(x: 20, y: -20)
            }
            Text(device.displayName).font(.caption).fontWeight(.medium).foregroundStyle(.white).lineLimit(1)
            Text(device.category.rawValue).font(.system(.caption2, design: .rounded)).foregroundStyle(categoryColor).lineLimit(1)
        }
        .frame(width: 100)
        .position(position)
    }
}

// MARK: - Cursor Extension

extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        self.onHover { hovering in
            if hovering {
                cursor.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
