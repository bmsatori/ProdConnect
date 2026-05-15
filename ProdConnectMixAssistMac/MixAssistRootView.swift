import SwiftUI
import UniformTypeIdentifiers

private enum MixAssistViewTab: String, CaseIterable, Identifiable {
    case operator_ = "Operator"
    case routing  = "Routing"
    case settings = "Settings"
    var id: String { rawValue }
}

private struct MixAssistTransferDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - Channel Strip (fader + meter)

private struct MixAssistChannelStripView: View {
    let level: Float
    let peak: Float
    let faderPosition: Double   // 0.0=bottom 1.0=top, nominal ~0.75
    let isActive: Bool
    let isSoloed: Bool
    let isLocked: Bool
    let priority: MixAssistChannelPriority
    let channelName: String
    let onToggle: () -> Void
    let onSolo: () -> Void
    let onLock: () -> Void
    let onPriorityChange: (MixAssistChannelPriority) -> Void

    private let trackH: CGFloat = 180
    private let trackW: CGFloat = 26

    private var normLevel: Double {
        level <= 0 ? 0 : (max(-60, 20 * log10(Double(level))) + 60) / 60
    }
    private var normPeak: Double {
        peak <= 0 ? 0 : (max(-60, 20 * log10(Double(peak))) + 60) / 60
    }
    private var meterColor: Color {
        if normLevel > 0.88 { return .red }
        if normLevel > 0.66 { return .yellow }
        return Color(red: 0.2, green: 0.9, blue: 0.4)
    }

    var body: some View {
        VStack(spacing: 5) {
            ZStack(alignment: .bottom) {
                // Track background
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.07))
                    .frame(width: trackW, height: trackH)

                // VU meter fill (behind fader)
                GeometryReader { geo in
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(meterColor.opacity(isActive ? 0.38 : 0.12))
                            .frame(width: trackW, height: max(0, geo.size.height * normLevel))
                    }
                }
                .frame(width: trackW, height: trackH)

                // Peak hold tick
                if normPeak > 0.01 {
                    GeometryReader { geo in
                        Rectangle()
                            .fill(Color.white.opacity(0.55))
                            .frame(width: trackW, height: 1)
                            .offset(y: geo.size.height * (1 - normPeak) - 1)
                    }
                    .frame(width: trackW, height: trackH)
                }

                // Fader knob
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(LinearGradient(
                            colors: [Color(white: 0.92), Color(white: 0.70)],
                            startPoint: .top, endPoint: .bottom
                        ))
                        .overlay(
                            Rectangle()
                                .fill(Color.gray.opacity(0.55))
                                .frame(height: 1.5)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 2)
                                .stroke(Color.white.opacity(0.25), lineWidth: 0.5)
                        )
                        .frame(width: trackW + 10, height: 16)
                        .offset(x: -5, y: geo.size.height * (1 - faderPosition) - 8)
                        .animation(.spring(response: 0.75, dampingFraction: 0.88), value: faderPosition)
                        .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                }
                .frame(width: trackW, height: trackH)
            }

            Text(channelName)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(isActive ? .primary : .secondary)
                .lineLimit(1)

            Button(action: onToggle) {
                Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12))
                    .foregroundStyle(isActive ? Color(red: 0.2, green: 0.9, blue: 0.4) : .secondary)
            }
            .buttonStyle(.plain)
            .help("Toggle channel")

            Button(action: onLock) {
                Image(systemName: isLocked ? "lock.fill" : "lock.open")
                    .font(.system(size: 11))
                    .frame(width: 20, height: 18)
                    .foregroundStyle(isLocked ? Color.orange : .secondary)
                    .background(
                        isLocked ? Color.orange.opacity(0.18) : Color.white.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 3)
                    )
            }
            .buttonStyle(.plain)
            .help(isLocked ? "Override ON — excluded from auto-mix" : "Override OFF — auto-mix controls this channel")

            Menu {
                ForEach(MixAssistChannelPriority.allCases) { option in
                    Button {
                        onPriorityChange(option)
                    } label: {
                        Label(option.name, systemImage: option == priority ? "checkmark" : "circle")
                    }
                }
            } label: {
                Text(priority.label)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .frame(width: 24, height: 18)
                    .foregroundStyle(priority == .normal ? .secondary : priorityColor)
                    .background(
                        priority == .normal ? Color.white.opacity(0.08) : priorityColor.opacity(0.16),
                        in: RoundedRectangle(cornerRadius: 3)
                    )
            }
            .menuStyle(.borderlessButton)
            .frame(width: 26, height: 20)
            .help("Auto-mix priority: \(priority.name)")

            Button(action: onSolo) {
                Text("S")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .frame(width: 20, height: 18)
                    .foregroundStyle(isSoloed ? .black : .primary)
                    .background(
                        isSoloed ? Color.yellow : Color.white.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 3)
                    )
            }
            .buttonStyle(.plain)
            .help("Solo this channel")
        }
        .frame(width: 44)
    }

    private var priorityColor: Color {
        switch priority {
        case .background: return .gray
        case .normal: return .secondary
        case .speech: return .blue
        case .leadSpeech: return .purple
        }
    }
}

// MARK: - Root View

struct MixAssistRootView: View {
    @EnvironmentObject private var store: ProdConnectStore
    @StateObject private var engine = MixAssistEngine()
    @StateObject private var audioMonitor = MixAssistAudioMonitor()

    @State private var viewTab: MixAssistViewTab = .operator_
    // selectedSource kept for profile compatibility but derived from device; see inferredSourceKind
    @State private var selectedSource: MixAssistSourceKind = .dante
    @State private var selectedControl: MixAssistControlKind = .osc
    @State private var referenceScope: MixAssistReferenceScope = .stream
    @State private var referenceName = ""
    @State private var liveSafetyPhrase = ""
    @State private var exportDocument: MixAssistTransferDocument?
    @State private var isExportingState = false
    @State private var isImportingState = false
    @State private var transferAlertMessage: String?

    private var activeShow: RunOfShowDocument? { store.runOfShows.first }

    // Derive source kind from selected audio device name for profile metadata
    private var inferredSourceKind: MixAssistSourceKind {
        guard let uid = audioMonitor.selectedDeviceUID,
              let device = audioMonitor.availableDevices.first(where: { $0.uid == uid }) else {
            return .dante
        }
        let name = device.name.lowercased()
        if name.contains("dante") { return .dante }
        if name.contains("usb") { return .usb }
        return .stereo
    }

    private var audioPatchRows: [PatchRow] {
        store.patchsheet.filter { row in
            let cat = row.category.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return cat.contains("audio") || cat.contains("mix")
                || cat.contains("broadcast") || cat.contains("stream") || cat.contains("input")
        }
        .sorted(by: PatchRow.autoSort)
    }

    private var activeBinding: MixAssistSceneBinding? {
        guard let profile = engine.selectedProfile else { return nil }
        return engine.sceneBindings.first(where: { $0.profileID == profile.id })
    }

    var body: some View {
        NavigationSplitView {
            sidebarContent
        } detail: {
            detailContent
        }
        .onAppear {
            engine.attach(store: store)
            engine.attachMonitor(audioMonitor)
            engine.refreshMIDIDestinations()
        }
        .onChange(of: store.runOfShows.count) { _, _ in engine.attach(store: store) }
        .onChange(of: store.patchsheet.count) { _, _ in engine.attach(store: store) }
        .onChange(of: engine.selectedProfileID) { _, _ in
            if let profile = engine.selectedProfile {
                selectedControl = profile.controlKind
                selectedSource = profile.sourceKind
            }
        }
        .onChange(of: audioMonitor.channelCount) { _, newCount in
            // Expand the routing row count if monitoring detects more channels,
            // but never shrink — the user's manual count is the floor.
            if newCount > engine.routingInputCount { engine.routingInputCount = newCount }
        }
        .onChange(of: engine.routingInputCount) { _, _ in
            engine.savePersistedState()
        }
        .onChange(of: store.runOfShows.first?.liveCurrentItemID) { _, newID in
            engine.handleLiveItemChange(itemID: newID, show: store.runOfShows.first)
        }
        .fileExporter(
            isPresented: $isExportingState,
            document: exportDocument,
            contentType: .json,
            defaultFilename: engine.suggestedExportFilename()
        ) { result in
            switch result {
            case .success: transferAlertMessage = "Mix Assist state exported."
            case .failure(let e): transferAlertMessage = "Export failed: \(e.localizedDescription)"
            }
            exportDocument = nil
        }
        .fileImporter(
            isPresented: $isImportingState,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .alert(
            "Mix Assist Transfer",
            isPresented: Binding(get: { transferAlertMessage != nil }, set: { if !$0 { transferAlertMessage = nil } })
        ) {
            Button("OK", role: .cancel) { transferAlertMessage = nil }
        } message: {
            Text(transferAlertMessage ?? "")
        }
    }

    // MARK: - Sidebar

    private var sidebarContent: some View {
        List(selection: selectedProfileSelection) {
            Section("Profiles") {
                if engine.referenceProfiles.isEmpty {
                    Text("No profiles yet")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                } else {
                    ForEach(engine.referenceProfiles) { profile in
                        Button {
                            engine.selectedProfileID = profile.id
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(profile.name)
                                    .font(.callout.weight(.medium))
                                Text(profile.scope.rawValue)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Delete Profile", role: .destructive) {
                                engine.deleteProfile(profile.id)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Mix Assist")
        .listStyle(.sidebar)
    }

    private var selectedProfileSelection: Binding<String?> {
        Binding(
            get: { engine.selectedProfileID },
            set: { engine.selectedProfileID = $0 }
        )
    }

    // MARK: - Detail shell

    private var detailContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Picker("", selection: $viewTab) {
                    ForEach(MixAssistViewTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)

                Spacer()

                if engine.isListening {
                    Label("Listening…", systemImage: "ear.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.green)
                }

                if engine.isLiveControlArmed {
                    Label("Auto Armed", systemImage: "bolt.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.orange)
                }

                statPillInline("Profiles", "\(engine.referenceProfiles.count)")
                statPillInline("Live Sends", "\(engine.liveSendCount)")
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.04))

            Divider().opacity(0.3)

            switch viewTab {
            case .operator_: operatorView
            case .routing:   routingView
            case .settings:  settingsView
            }
        }
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.06, blue: 0.09),
                    Color(red: 0.03, green: 0.11, blue: 0.16)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
    }

    // MARK: - Operator View

    private var operatorView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                operatorStatusCard
                audioMonitorCard
            }
            .padding(24)
        }
        .navigationTitle("ProdConnect Mix Assist")
    }

    private var operatorStatusCard: some View {
        VStack(alignment: .leading, spacing: 16) {

            // Profile + scene row
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(engine.selectedProfile?.name ?? "No Profile Selected")
                        .font(.title2.weight(.semibold))
                    if let binding = activeBinding {
                        Text(binding.sceneName).foregroundStyle(.secondary)
                    } else if let show = activeShow {
                        Text(show.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                             ? "Untitled Show" : show.title)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                HStack(spacing: 10) {
                    statPill("Live Sends", "\(engine.liveSendCount)")
                }
            }

            Divider().opacity(0.3)

            // LUFS meters row
            HStack(spacing: 0) {
                lufsGauge(
                    label: engine.yamahaSettings.mixOutputDanteChannel.map { ch in "MIX \(ch)/\(ch+1)" }
                        ?? "MEASURED",
                    value: audioMonitor.isMonitoring ? audioMonitor.integratedLUFS : nil,
                    color: lufsColor(audioMonitor.integratedLUFS,
                                    target: engine.yamahaSettings.targetOutputLUFS)
                )
                Spacer()
                lufsGauge(
                    label: "SHORT",
                    value: audioMonitor.isMonitoring ? audioMonitor.shortTermLUFS : nil,
                    color: lufsColor(audioMonitor.shortTermLUFS,
                                    target: engine.yamahaSettings.targetOutputLUFS)
                )
                Spacer()
                lufsGauge(
                    label: "TARGET",
                    value: engine.yamahaSettings.targetOutputLUFS,
                    color: .blue
                )
                Spacer()
                lufsGauge(
                    label: "DELTA",
                    value: audioMonitor.isMonitoring
                        ? engine.yamahaSettings.targetOutputLUFS - audioMonitor.integratedLUFS
                        : nil,
                    color: abs(engine.yamahaSettings.targetOutputLUFS - audioMonitor.integratedLUFS) <= engine.yamahaSettings.autoAdjustDeadbandLUFS ? .green : .orange,
                    showPlus: true
                )
                Spacer()
                lufsGauge(
                    label: "PEAK",
                    value: audioMonitor.isMonitoring ? audioMonitor.truePeakDBTP : nil,
                    color: audioMonitor.truePeakDBTP <= engine.yamahaSettings.truePeakCeilingDBTP ? .green : .red,
                    suffix: "dBTP"
                )
                if audioMonitor.isMonitoring && engine.yamahaSettings.mixOutputDanteChannel != nil {
                    Spacer()
                    Button {
                        audioMonitor.setMixListen(!audioMonitor.isMixListening)
                    } label: {
                        Image(systemName: audioMonitor.isMixListening ? "headphones.circle.fill" : "headphones.circle")
                            .font(.system(size: 22))
                            .foregroundStyle(audioMonitor.isMixListening ? Color.yellow : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(audioMonitor.isMixListening ? "Stop listening to mix output" : "Listen to mix output through system audio")
                }
            }
            .padding(.vertical, 4)

            // Target LUFS preset
            VStack(alignment: .leading, spacing: 8) {
                Text("TARGET OUTPUT: \(String(format: "%.1f", engine.yamahaSettings.targetOutputLUFS)) LUFS")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                HStack(alignment: .top, spacing: 14) {
                    Picker("Target Output", selection: Binding(
                        get: { engine.yamahaSettings.targetOutputPreset },
                        set: { engine.updateTargetOutputPreset($0) }
                    )) {
                        ForEach(MixAssistTargetOutputPreset.allCases) { preset in
                            Text(preset == .custom ? preset.name : preset.displayName).tag(preset)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 240)

                    Text(engine.yamahaSettings.targetOutputPreset.description)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if engine.yamahaSettings.targetOutputPreset == .custom {
                    HStack(spacing: 12) {
                        Stepper(
                            "LUFS \(String(format: "%.1f", engine.yamahaSettings.targetOutputLUFS))",
                            value: Binding(
                                get: { engine.yamahaSettings.targetOutputLUFS },
                                set: { engine.updateCustomTargetOutputLUFS($0) }
                            ),
                            in: -32 ... -6,
                            step: 0.5
                        )
                        Stepper(
                            "Peak \(String(format: "%.1f", engine.yamahaSettings.truePeakCeilingDBTP)) dBTP",
                            value: Binding(
                                get: { engine.yamahaSettings.truePeakCeilingDBTP },
                                set: { engine.updateTruePeakCeiling($0) }
                            ),
                            in: -12 ... 0,
                            step: 0.5
                        )
                    }
                    .font(.caption)
                } else {
                    Text("True peak ceiling: \(String(format: "%.1f", engine.yamahaSettings.truePeakCeilingDBTP)) dBTP")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                HStack(spacing: 12) {
                    Stepper(
                        "Session Limit \(String(format: "%.1f", engine.yamahaSettings.autoAdjustSessionLimitDB)) dB",
                        value: Binding(
                            get: { engine.yamahaSettings.autoAdjustSessionLimitDB },
                            set: { engine.updateAutoAdjustSessionLimit($0) }
                        ),
                        in: 0.5 ... 12,
                        step: 0.5
                    )
                    .font(.caption)

                    Label(audioMonitor.signalHealthSummary, systemImage: audioMonitor.hasUsableSignal ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(audioMonitor.hasUsableSignal ? .green : .orange)
                }
            }

            Divider().opacity(0.3)

            // Control buttons
            HStack(spacing: 12) {
                // Listen
                Button(action: listenAction) {
                    Label(engine.isListening ? "Listening…" : "Listen", systemImage: "ear.fill")
                        .frame(minWidth: 90)
                }
                .buttonStyle(.borderedProminent)
                .tint(engine.isListening ? .green : Color(white: 0.22))
                .help("Capture current mix state as the reference")

                // Auto / Mix toggle
                Button(action: toggleAutoAdjust) {
                    HStack(spacing: 6) {
                        if engine.isAutoAdjustRunning {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 8, height: 8)
                        }
                        Text(engine.isAutoAdjustRunning ? "Auto On" : "Auto / Mix")
                        if !engine.isAutoAdjustRunning {
                            Image(systemName: "waveform.path.ecg.rectangle.fill")
                        }
                    }
                    .frame(minWidth: 110)
                }
                .buttonStyle(.borderedProminent)
                .tint(engine.isAutoAdjustRunning ? .orange : Color(white: 0.22))
                .disabled(!audioMonitor.isMonitoring)
                .help(engine.isAutoAdjustRunning
                      ? "Stop — disable continuous auto adjustment"
                      : "Start — continuously measure LUFS and send adjustments to the console")

                if engine.isAutoAdjustRunning || engine.isLiveControlArmed {
                    Button("Stop") { engine.disarmLiveControl() }
                        .buttonStyle(.bordered)
                        .tint(.red)
                }
            }

            // Auto status
            if engine.isAutoAdjustRunning || !engine.lastAutoAdjustSummary.isEmpty {
                Text(engine.lastAutoAdjustSummary)
                    .font(.caption)
                    .foregroundStyle(engine.isAutoAdjustRunning ? .orange : .secondary)
                    .lineLimit(2)
            }

            // Active RoS preset badge
            if let preset = engine.activeItemPreset {
                HStack(spacing: 6) {
                    Image(systemName: "list.bullet.clipboard.fill")
                        .foregroundStyle(.purple)
                    Text("Preset active: \(preset.rosItemTitle)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.purple)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.purple.opacity(0.15), in: Capsule())
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func lufsGauge(label: String, value: Double?, color: Color, showPlus: Bool = false, suffix: String = "LUFS") -> some View {
        VStack(alignment: .center, spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
            if let v = value {
                let prefix = showPlus && v > 0 ? "+" : ""
                Text("\(prefix)\(String(format: "%.1f", v))")
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundStyle(color)
            } else {
                Text("—")
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            Text(suffix)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .frame(minWidth: 80)
    }

    private func lufsColor(_ measured: Double, target: Double) -> Color {
        let delta = abs(measured - target)
        if delta <= 0.5 { return .green }
        if delta <= 2.0 { return .yellow }
        return .red
    }

    private var audioMonitorCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Audio Input")
                    .font(.title2.weight(.semibold))
                if audioMonitor.isMonitoring {
                    let detected = audioMonitor.detectedChannelCount
                    let active = audioMonitor.channelCount
                    let mismatch = detected > 0 && detected != active
                    Text(mismatch ? "\(active) ch (hw: \(detected))" : "\(active) ch")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(active > 1 ? .green : .orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.08), in: Capsule())
                }
                Spacer()
                Button(audioMonitor.isMonitoring ? "Stop" : "Monitor") {
                    if audioMonitor.isMonitoring {
                        audioMonitor.stopMonitoring()
                    } else {
                        audioMonitor.startMonitoring()
                    }
                }
                .buttonStyle(.bordered)
                .tint(audioMonitor.isMonitoring ? .red : .green)
            }

            if let error = audioMonitor.monitorError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if routingDestinations.isEmpty {
                Text("Add audio channels to the Patchsheet to see channel strips here.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .bottom, spacing: 8) {
                        ForEach(routingDestinations.indices, id: \.self) { destIdx in
                            let dest = routingDestinations[destIdx]
                            // Find which physical input (if any) is patched to this destination
                            let sourceInputs = engine.routingMatrix.inputs(for: dest.id, total: engine.routingInputCount)
                            let srcCh = sourceInputs.first   // at most 1 input per dest
                            let isRouted = srcCh != nil
                            let dimmed = audioMonitor.soloedChannel != nil && audioMonitor.soloedChannel != destIdx
                            let level: Float = isRouted && audioMonitor.isMonitoring
                                ? (srcCh! < audioMonitor.channelLevels.count ? audioMonitor.channelLevels[srcCh!] : 0)
                                : 0
                            let peak: Float = isRouted && audioMonitor.isMonitoring
                                ? (srcCh! < audioMonitor.peakLevels.count ? audioMonitor.peakLevels[srcCh!] : 0)
                                : 0
                            MixAssistChannelStripView(
                                level: level,
                                peak: peak,
                                faderPosition: engine.channelFaderPositions[destIdx] ?? 0.75,
                                isActive: isRouted && !dimmed,
                                isSoloed: audioMonitor.soloedChannel == destIdx,
                                isLocked: engine.lockedDestinations.contains(destIdx),
                                priority: engine.priority(forChannel: destIdx),
                                channelName: dest.label,
                                onToggle: { audioMonitor.toggleChannel(destIdx) },
                                onSolo: {
                                    audioMonitor.setSolo(audioMonitor.soloedChannel == destIdx ? nil : destIdx)
                                },
                                onLock: { engine.toggleDestinationLock(destIdx) },
                                onPriorityChange: { engine.updateChannelPriority(destIdx, priority: $0) }
                            )
                            .opacity(dimmed ? 0.3 : (isRouted ? 1.0 : 0.4))
                        }
                    }
                    .padding(.vertical, 6)
                }
                if !audioMonitor.isMonitoring {
                    Text("Tap Monitor to start metering.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }

            if audioMonitor.soloedChannel != nil {
                HStack {
                    Label("Solo active — tap S again to clear", systemImage: "headphones")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                    Spacer()
                    Button("Clear Solo") { audioMonitor.setSolo(nil) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - Routing View

    private var routingView: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Audio Routing")
                        .font(.title3.weight(.semibold))
                    Text("Patch physical input channels to named mix destinations.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 10) {
                    Stepper(
                        "\(engine.routingInputCount) inputs",
                        value: Binding(get: { engine.routingInputCount }, set: { engine.routingInputCount = $0 }),
                        in: 1...64
                    )
                    .controlSize(.small)
                    if audioMonitor.channelCount > 0 {
                        Text("(\(audioMonitor.channelCount) detected)")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                    Button("Clear All") {
                        engine.clearAllRoutes()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.red)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.03))

            Divider().opacity(0.3)

            MixAssistRoutingGridView(
                inputCount: engine.routingInputCount,
                destinations: routingDestinations,
                matrix: Binding(
                    get: { engine.routingMatrix },
                    set: { _ in }
                ),
                onToggle: { input, destID in
                    engine.toggleRoute(input: input, destinationID: destID)
                },
                onClearDestination: { destID in
                    engine.clearDestinationRoutes(destID)
                }
            )
        }
    }

    private var routingDestinations: [(id: String, label: String, short: String)] {
        let rows = audioPatchRows
        if rows.isEmpty {
            // Fallback: generic console channel destinations
            return (1...32).map { ch in
                (id: "console-ch-\(ch)", label: "CH \(ch)", short: "CH\(ch)")
            }
        }
        return rows.map { row in
            let label = row.name.isEmpty ? row.input : row.name
            let short = String(label.prefix(6))
            return (id: row.id, label: label, short: short)
        }
    }

    // MARK: - Settings View

    private var settingsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ioSettingsCard
                referenceCaptureCard
                currentContextCard
                consoleControlCard
                rosPresetsCard
                liveControlCard
                localTransferCard
                architectureCard
            }
            .padding(24)
        }
        .navigationTitle("Settings")
    }

    private var ioSettingsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("I / O")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button {
                    audioMonitor.refreshDevices()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }

            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Audio Input Device")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if audioMonitor.availableDevices.isEmpty {
                        Text("No input devices found — tap Refresh")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Audio Input Device", selection: $audioMonitor.selectedDeviceUID) {
                            Text("System Default").tag(String?.none)
                            ForEach(audioMonitor.availableDevices) { device in
                                Text(device.name).tag(String?.some(device.uid))
                            }
                        }
                        .labelsHidden()
                        .onChange(of: audioMonitor.selectedDeviceUID) { _, _ in
                            if audioMonitor.isMonitoring { audioMonitor.startMonitoring() }
                            engine.saveSelectedAudioDevice(audioMonitor.selectedDeviceUID)
                        }
                        if let uid = audioMonitor.selectedDeviceUID,
                           let device = audioMonitor.availableDevices.first(where: { $0.uid == uid }),
                           device.name.localizedCaseInsensitiveContains("Dante") {
                            Label("Dante Virtual Soundcard selected", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                }

                Divider().frame(maxHeight: 60)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Control Layer")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Control Layer", selection: $selectedControl) {
                        ForEach(MixAssistControlKind.allCases) { c in Text(c.rawValue).tag(c) }
                    }
                    .labelsHidden()
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onAppear { audioMonitor.refreshDevices() }
    }

    private var referenceCaptureCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Reference Profiles")
                .font(.title2.weight(.semibold))

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Reference Name", text: $referenceName)
                        .textFieldStyle(.roundedBorder)

                    Picker("Scope", selection: $referenceScope) {
                        ForEach(MixAssistReferenceScope.allCases) { scope in
                            Text(scope.rawValue).tag(scope)
                        }
                    }
                    .pickerStyle(.segmented)

                    Button("Capture Current Reference") {
                        engine.captureReferenceProfile(
                            name: referenceName,
                            scope: referenceScope,
                            sourceKind: inferredSourceKind,
                            controlKind: selectedControl
                        )
                        referenceName = ""
                    }
                    .buttonStyle(.borderedProminent)
                }

                Divider()
                    .frame(maxHeight: 140)

                VStack(alignment: .leading, spacing: 8) {
                    if let profile = engine.selectedProfile {
                        Text(profile.name).font(.headline)
                        Text(profile.scope.rawValue).foregroundStyle(.secondary)
                        Text(String(format: "Target LUFS %.1f", profile.targetIntegratedLUFS)).font(.caption)
                        Text(String(format: "Centroid %.0f Hz", profile.targetSpectralCentroid)).font(.caption)
                        Text(String(format: "Dynamic Range %.1f dB", profile.targetDynamicRange)).font(.caption)
                        Text(String(format: "Stereo Spread %.2f", profile.targetStereoSpread)).font(.caption)
                        Text("Control: \(profile.controlKind.rawValue)").font(.caption)
                    } else {
                        Text("No profile selected").foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var currentContextCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Scene Binding")
                .font(.title2.weight(.semibold))

            if let binding = activeBinding {
                Text(binding.sceneName).font(.headline)
                Text("Bound patch rows: \(binding.patchRowIDs.count)").foregroundStyle(.secondary)
                Text("Notes: \(binding.notes)").font(.caption).foregroundStyle(.secondary)
                if let show = activeShow {
                    Text("Run of Show: \(show.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Show" : show.title)").font(.caption)
                }
            } else if let show = activeShow {
                Text("Active show: \(show.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Show" : show.title)")
                Text("Run of Show items: \(show.items.count)")
                Text("Audio patch rows: \(audioPatchRows.count)").foregroundStyle(.secondary)
            } else {
                Text("No Run of Show loaded yet. Mix Assist will bind references once team data is available.")
                    .foregroundStyle(.secondary)
            }

            if !audioPatchRows.isEmpty {
                Divider()
                ForEach(audioPatchRows.prefix(8)) { row in
                    HStack {
                        Text(row.name.isEmpty ? "Unnamed Patch" : row.name)
                        Spacer()
                        Text("\(row.input) → \(row.output)").foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var rosPresetsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Run of Show Presets")
                .font(.title2.weight(.semibold))

            Text("Capture the current fader mix, LUFS target, true peak ceiling, safety limit, and channel priorities for each Run of Show item. When that item goes live, Mix Assist automatically restores them.")
                .foregroundStyle(.secondary)

            if let show = activeShow, !show.items.isEmpty {
                let sortedItems = show.items.sorted { $0.position < $1.position }
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(sortedItems) { item in
                        let preset = engine.itemPresets.first(where: { $0.rosItemID == item.id })
                        let isActive = engine.activeItemPreset?.rosItemID == item.id
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    if isActive {
                                        Circle().fill(Color.purple).frame(width: 6, height: 6)
                                    }
                                    Text(item.title.isEmpty ? "Unnamed Item" : item.title)
                                        .font(.callout.weight(isActive ? .semibold : .regular))
                                        .foregroundStyle(isActive ? .purple : .primary)
                                }
                                if let preset {
                                    Text("\(preset.targetSummary) • Captured \(preset.capturedAt.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Button(preset != nil ? "Re-Capture" : "Capture Mix") {
                                engine.captureItemPreset(
                                    for: item,
                                    destinationCount: routingDestinations.count
                                )
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .tint(preset != nil ? .orange : .green)

                            if let preset {
                                Button(isActive ? "Selected" : "Select") {
                                    engine.selectItemPreset(for: preset.rosItemID)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(isActive)

                                Button {
                                    engine.deleteItemPreset(for: item.id)
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                                .help("Delete preset for \(item.title)")
                            }
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .background(
                            isActive ? Color.purple.opacity(0.1) : Color.white.opacity(0.03),
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                    }
                }

                Text("\(engine.itemPresets.count) of \(show.items.count) items have saved presets.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if activeShow == nil {
                Text("No Run of Show loaded. Load a show in ProdConnect to manage presets here.")
                    .foregroundStyle(.secondary)
            } else {
                Text("No items in the current Run of Show.")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var liveControlCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Live Control")
                .font(.title2.weight(.semibold))

            Text("Live writes use the selected console protocol. Yamaha QL/CL/DM3 send RCP over TCP; OSC consoles send OSC. Every send requires an explicit timed arm window.")
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 12) {
                    TextField(
                        engine.yamahaSettings.model.usesRCP ? "Console Host" : "OSC Host",
                        text: Binding(
                            get: { engine.liveOSCSettings.host },
                            set: { engine.updateLiveOSCHost($0) }
                        )
                    )
                    .textFieldStyle(.roundedBorder)

                    TextField(
                        engine.yamahaSettings.model.usesRCP ? "Console Port" : "OSC Port",
                        text: Binding(
                            get: { engine.liveOSCSettings.port },
                            set: { engine.updateLiveOSCPort($0) }
                        )
                    )
                    .textFieldStyle(.roundedBorder)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Arm Window: \(Int(engine.liveOSCSettings.autoDisarmSeconds)) sec")
                            .font(.caption.weight(.semibold))
                        Slider(
                            value: Binding(
                                get: { engine.liveOSCSettings.autoDisarmSeconds },
                                set: { engine.updateLiveOSCArmWindow($0.rounded()) }
                            ),
                            in: 10...90,
                            step: 5
                        )
                    }

                    TextField("Type ARM LIVE CONTROL", text: $liveSafetyPhrase)
                        .textFieldStyle(.roundedBorder)
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    statPill("Adapter", engine.selectedAdapter?.name ?? "None")
                    statPill("Host", engine.liveOSCSettings.host)
                    statPill("Port", engine.liveOSCSettings.port)
                    statPill("State", engine.isLiveControlArmed ? "Armed" : "Locked")
                    if let exp = engine.liveControlExpiresAt {
                        statPill("Expires", exp.formatted(date: .omitted, time: .standard))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 10) {
                Button(engine.isLiveControlArmed ? "Re-Arm" : "Arm Live Control") {
                    engine.armLiveControl()
                    liveSafetyPhrase = ""
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    normalizedLiveSafetyPhrase != "ARM LIVE CONTROL"
                        || !(engine.selectedAdapter?.controlKind == .osc || engine.yamahaSettings.model.usesRCP)
                )

                Button("Disarm") {
                    engine.stopAutoAdjust()
                    engine.disarmLiveControl()
                }
                    .buttonStyle(.bordered)
                    .disabled(!engine.isLiveControlArmed)

                if engine.yamahaSettings.model.usesRCP {
                    Label("Auto Adjust and Run of Show presets send RCP while armed", systemImage: "network")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Button("Send Live OSC Batch") { engine.sendLiveOSCPreview() }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .disabled(
                            !engine.isLiveControlArmed
                                || engine.selectedAdapter?.controlKind != .osc
                        )
                }
            }

            Text(engine.liveTransportSummary)
                .font(.caption)
                .foregroundStyle(engine.isLiveControlArmed ? .orange : .secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var consoleControlCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Console Control")
                .font(.title2.weight(.semibold))

            Text("Select manufacturer then model. CL/QL and DM3 use Yamaha RCP direct network control over TCP. DM7 uses OSC over IP. Allen & Heath and Behringer OSC support is in development. DAW models (GarageBand, Pro Tools, Logic Pro) send OSC to a bridge app running on the same Mac.")
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 12) {
                    // Manufacturer
                    Picker("Manufacturer", selection: Binding(
                        get: { engine.yamahaSettings.manufacturer },
                        set: { mfr in
                            let first = mfr.consoleModels.first ?? .yamahaDM7
                            engine.updateConsoleManufacturer(mfr, model: first)
                        }
                    )) {
                        ForEach(MixAssistConsoleManufacturer.allCases) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }

                    // Model (filtered by manufacturer)
                    Picker("Console", selection: Binding(
                        get: { engine.yamahaSettings.model },
                        set: { engine.updateYamahaModel($0) }
                    )) {
                        ForEach(engine.yamahaSettings.manufacturer.consoleModels) { model in
                            Text(model.rawValue).tag(model)
                        }
                    }

                    if engine.yamahaSettings.model.usesMIDI {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("MIDI Destination")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button {
                                    engine.refreshMIDIDestinations()
                                } label: {
                                    Label("Refresh", systemImage: "arrow.clockwise")
                                        .font(.caption)
                                }
                                .buttonStyle(.borderless)
                            }

                            Picker("MIDI Destination", selection: Binding(
                                get: { engine.yamahaSettings.selectedMIDIDestinationID ?? "" },
                                set: { engine.updateYamahaMIDIDestinationID($0) }
                            )) {
                                Text("Select MIDI Destination").tag("")
                                ForEach(engine.midiDestinations) { destination in
                                    Text(destination.name).tag(destination.id)
                                }
                            }
                            .labelsHidden()

                            Stepper(
                                "MIDI Channel \(engine.yamahaSettings.midiChannel)",
                                value: Binding(
                                    get: { engine.yamahaSettings.midiChannel },
                                    set: { engine.updateYamahaMIDIChannel($0) }
                                ),
                                in: 1...16
                            )

                            Stepper(
                                "Fader CC Base \(engine.yamahaSettings.faderCCBase)",
                                value: Binding(
                                    get: { engine.yamahaSettings.faderCCBase },
                                    set: { engine.updateYamahaFaderCCBase($0) }
                                ),
                                in: 0...127
                            )

                            Text("Legacy MIDI template fader control. Match the console's MIDI remote/control-change assignments to this CC base.")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    } else {
                        TextField(
                            "Console IP",
                            text: Binding(
                                get: { engine.yamahaSettings.consoleIPAddress },
                                set: { engine.updateYamahaConsoleIPAddress($0) }
                            )
                        )
                        .textFieldStyle(.roundedBorder)

                            Text(engine.yamahaSettings.model.usesRCP ? "Port \(engine.yamahaSettings.model.defaultPort) (Yamaha RCP)" : "Port \(engine.yamahaSettings.model.defaultPort) (auto)")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if engine.yamahaSettings.model.usesRCP {
                                Text("Mix Assist sends Yamaha RCP commands directly to the console IP. The QL/CL/DM3 control port is TCP 49280.")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                Button("Test RCP Connection") {
                                    engine.sendRCPConnectionTest()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .help("Sends a single command to set CH 1 to 0 dB. If the QL5 fader moves, RCP is working.")
                            }
                    }

                    Divider()

                    // LUFS mix output monitor: pick which Dante channel carries the console's mix output
                    VStack(alignment: .leading, spacing: 4) {
                        Text("LUFS Monitor Output")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text("Select the stereo Dante return pair carrying the console's mix output (e.g. Main LR). Mix Assist reads LUFS from both channels to drive auto-adjust.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        HStack(spacing: 10) {
                            let hasCh = engine.yamahaSettings.mixOutputDanteChannel != nil
                            // Default to 64 ch so options appear before the monitor starts
                            let maxCh = max(64, audioMonitor.channelCount)
                            // Pairs: Ch 1–2, Ch 3–4, Ch 5–6 ...
                            let pairs = stride(from: 1, through: maxCh - 1, by: 2).map { $0 }
                            Picker("Mix Output Pair", selection: Binding(
                                get: { engine.yamahaSettings.mixOutputDanteChannel ?? 0 },
                                set: { engine.updateMixOutputChannel($0 == 0 ? nil : $0) }
                            )) {
                                Text("Not set (avg inputs)").tag(0)
                                ForEach(pairs, id: \.self) { ch in
                                    Text("Ch \(ch) / \(ch + 1)  (L/R)").tag(ch)
                                }
                            }
                            .frame(maxWidth: 220)
                            if let ch = engine.yamahaSettings.mixOutputDanteChannel {
                                Label(
                                    "Ch \(ch)/\(ch + 1) stereo → LUFS",
                                    systemImage: "waveform.path.ecg"
                                )
                                .font(.caption)
                                .foregroundStyle(.green)
                            }
                        }
                    }

                    Divider()

                    Stepper(
                        "Auto Interval \(String(format: "%.1f", engine.yamahaSettings.autoAdjustIntervalSeconds))s",
                        value: Binding(
                            get: { engine.yamahaSettings.autoAdjustIntervalSeconds },
                            set: { engine.updateAutoAdjustInterval($0) }
                        ),
                        in: 0.5...10,
                        step: 0.25
                    )

                    Divider()

                    // Reference mix capture
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: engine.capturedTargetChannelCount > 0 ? "target" : "scope")
                                .foregroundStyle(engine.capturedTargetChannelCount > 0 ? .green : .secondary)
                            Text(engine.capturedTargetChannelCount > 0
                                 ? "Reference: \(engine.capturedTargetChannelCount) ch captured"
                                 : "No reference mix — using global LUFS")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(engine.capturedTargetChannelCount > 0 ? .green : .secondary)
                        }
                        Text("Get your mix sounding right, then capture. Auto-mix will drive each fader back to those levels independently.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        HStack(spacing: 8) {
                            Button(engine.capturedTargetChannelCount > 0 ? "Re-Capture" : "Capture Mix") {
                                engine.captureTargetMix()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                            .controlSize(.small)
                            .disabled(!(audioMonitor.isMonitoring))
                            if engine.capturedTargetChannelCount > 0 {
                                Button("Clear") { engine.clearTargetMix() }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .tint(.red)
                            }
                        }
                    }

                    Divider()

                    // Bus target selector
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Auto-Mix Target")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text("Which signal path auto-mix adjusts. Use Mix Bus Sends to target an aux or broadcast bus without touching the main mix.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Picker("Target", selection: Binding(
                            get: { engine.yamahaSettings.targetBusType },
                            set: { engine.updateTargetBusType($0) }
                        )) {
                            ForEach(MixAssistConsoleBusType.allCases) { bt in
                                Text(bt.rawValue).tag(bt)
                            }
                        }
                        .pickerStyle(.segmented)
                        if engine.yamahaSettings.targetBusType != .inputChannel {
                            HStack(spacing: 8) {
                                Text("Bus Number")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Stepper(
                                    "\(engine.yamahaSettings.targetBusNumber)",
                                    value: Binding(
                                        get: { engine.yamahaSettings.targetBusNumber },
                                        set: { engine.updateTargetBusNumber($0) }
                                    ),
                                    in: 1...32
                                )
                                .controlSize(.small)
                            }
                        }
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    statPill("Console", engine.yamahaSettings.model.rawValue)
                    statPill("Path", engine.yamahaSettings.model.connectionSummary)
                    if engine.yamahaSettings.model.usesMIDI {
                        let midiName = engine.midiDestinations.first(where: { $0.id == engine.yamahaSettings.selectedMIDIDestinationID })?.name
                        statPill("MIDI", midiName ?? "Not set")
                        statPill("CC Base", "\(engine.yamahaSettings.faderCCBase)")
                    } else if engine.yamahaSettings.model.usesRCP {
                        statPill("Protocol", "RCP TCP")
                        statPill("IP", engine.yamahaSettings.consoleIPAddress.isEmpty ? "Not set" : engine.yamahaSettings.consoleIPAddress)
                        statPill("Port", "\(engine.yamahaSettings.model.defaultPort)")
                    } else {
                        statPill("IP", engine.yamahaSettings.consoleIPAddress.isEmpty ? "Not set" : engine.yamahaSettings.consoleIPAddress)
                    }
                    let bt = engine.yamahaSettings.targetBusType
                    if bt == .inputChannel {
                        statPill("Target", "Main Faders")
                    } else {
                        statPill("Target", "\(bt.rawValue) \(engine.yamahaSettings.targetBusNumber)")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text(consoleFooterText)
                .font(.caption)
                .foregroundStyle(.orange)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var localTransferCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Local Transfer")
                .font(.title2.weight(.semibold))

            Text("Export the local Mix Assist state as JSON, then import it on another Mac to copy profiles, bindings, adapter selection, OSC settings, and history.")
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button("Export State File") { exportStateFile() }
                    .buttonStyle(.borderedProminent)

                Button("Import State File") { isImportingState = true }
                    .buttonStyle(.bordered)
            }

            Text("Import replaces the current machine's local state for the active user/team scope.")
                .font(.caption)
                .foregroundStyle(.orange)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var architectureCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Guardrails")
                .font(.title2.weight(.semibold))

            Text("Reference profiles, scene bindings, selected adapter, and sandbox history are persisted locally per user/team scope.")
                .foregroundStyle(.secondary)

            Text("Live control requires explicit arming, auto-disarms on a timer, and uses the selected console protocol.")
                .foregroundStyle(.secondary)

            Text("CL/QL and DM3 use Yamaha RCP directly over TCP. DM7 uses OSC. Allen & Heath and Behringer console support is in development.")
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - Actions

    private func listenAction() {
        engine.startListen(
            name: referenceName,
            scope: referenceScope,
            sourceKind: inferredSourceKind,
            controlKind: selectedControl
        )
    }

    private func toggleAutoAdjust() {
        if engine.isAutoAdjustRunning {
            engine.stopAutoAdjust()
        } else {
            engine.startAutoAdjust()
        }
    }

    // MARK: - Helpers

    private func statPill(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .lineLimit(2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func statPillInline(_ title: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.08), in: Capsule())
    }

    private func severityColor(_ severity: MixAssistRecommendationSeverity) -> Color {
        switch severity {
        case .low: return .blue
        case .medium: return .orange
        case .high: return .red
        }
    }

    private var normalizedLiveSafetyPhrase: String {
        liveSafetyPhrase.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private var consoleFooterText: String {
        switch engine.yamahaSettings.model {
        case .yamahaQL3, .yamahaQL5, .yamahaCL3, .yamahaCL5, .yamahaDM3:
            return "Yamaha QL/CL/DM3: enter the console IP on the same network. Mix Assist sends Yamaha RCP fader commands directly over TCP port \(engine.yamahaSettings.model.defaultPort)."
        case .yamahaDM7:
            return "Yamaha DM7: set the console IP and enable the OSC server on the console (Setup → Network → OSC). Port \(engine.yamahaSettings.model.defaultPort)."
        case .ahDLive, .ahAvantis:
            return "Allen & Heath: enable the OSC server in the dLive / Avantis Surface Manager. TCP port \(engine.yamahaSettings.model.defaultPort)."
        case .behringerWing:
            return "Behringer Wing: OSC is enabled by default. Enter the Wing's IP address. UDP port \(engine.yamahaSettings.model.defaultPort)."
        case .behringerX32:
            return "Behringer X32/M32: OSC is enabled by default. Enter the console's IP address. UDP port \(engine.yamahaSettings.model.defaultPort)."
        case .dawGarageBand:
            return "GarageBand: requires an OSC bridge app (e.g. OSCsmith or TouchOSC Bridge) running on the same Mac. Mix Assist sends to 127.0.0.1 port 50002."
        case .dawProTools:
            return "Pro Tools: requires an OSC control surface plugin or bridge (e.g. EUCON bridge or PT OSC). Mix Assist sends to 127.0.0.1 port 53000."
        case .dawLogicPro:
            return "Logic Pro: requires an OSC bridge app (e.g. OSCsmith or TouchOSC Bridge) running on the same Mac. Mix Assist sends to 127.0.0.1 port 50002."
        case .dawReaper:
            return "Reaper: enable the built-in OSC control surface under Preferences → Control Surfaces → Add → OSC. Set the listen port to 8000. Mix Assist sends to 127.0.0.1 port 8000."
        }
    }

    private func exportStateFile() {
        do {
            let data = try engine.exportStateData()
            exportDocument = MixAssistTransferDocument(data: data)
            isExportingState = true
        } catch {
            transferAlertMessage = error.localizedDescription
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed { url.stopAccessingSecurityScopedResource() }
            }
            do {
                let data = try Data(contentsOf: url)
                try engine.importStateData(data)
                if let profile = engine.selectedProfile {
                    selectedControl = profile.controlKind
                    selectedSource = profile.sourceKind
                }
                transferAlertMessage = "Mix Assist state imported."
            } catch {
                transferAlertMessage = "Import failed: \(error.localizedDescription)"
            }
        case .failure(let error):
            transferAlertMessage = "Import failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Routing Grid

private struct MixAssistRoutingGridView: View {
    let inputCount: Int
    let destinations: [(id: String, label: String, short: String)]
    @Binding var matrix: MixAssistRoutingMatrix
    let onToggle: (Int, String) -> Void
    let onClearDestination: (String) -> Void

    private let cellSize: CGFloat = 34
    private let destLabelW: CGFloat = 120
    private let srcHeaderH: CGFloat = 90

    var body: some View {
        if destinations.isEmpty {
            Text("No destinations found. Add audio channels to your patchsheet in ProdConnect, or start monitoring to detect device channels.")
                .foregroundStyle(.secondary)
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {

                    // Header row: top-left corner + source column headers
                    HStack(spacing: 0) {
                        // Top-left corner above output labels
                        ZStack {
                            Color.white.opacity(0.04)
                            Text("OUTPUT")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: destLabelW, height: srcHeaderH)

                        ForEach(0..<inputCount, id: \.self) { col in
                            ZStack(alignment: .bottomLeading) {
                                Color.white.opacity(0.04)
                                Text("CH \(col + 1)")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                    .rotationEffect(.degrees(-55), anchor: .bottomLeading)
                                    .offset(x: 10, y: -8)
                            }
                            .frame(width: cellSize, height: srcHeaderH)
                        }
                    }

                    Divider().opacity(0.4)

                    // Destination rows
                    ForEach(destinations.indices, id: \.self) { destIdx in
                        let dest = destinations[destIdx]
                        HStack(spacing: 0) {
                            // Destination label on the left
                            HStack(spacing: 4) {
                                Button {
                                    onClearDestination(dest.id)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 7, weight: .bold))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 14, height: 14)
                                }
                                .buttonStyle(.plain)
                                .help("Clear all inputs routed to \(dest.label)")

                                Text(dest.short)
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.horizontal, 6)
                            .frame(width: destLabelW, height: cellSize)
                            .background(Color.white.opacity(destIdx % 2 == 0 ? 0.03 : 0.0))

                            // One cell per source input
                            ForEach(0..<inputCount, id: \.self) { col in
                                let connected = matrix.isConnected(input: col, destinationID: dest.id)
                                Button {
                                    onToggle(col, dest.id)
                                } label: {
                                    ZStack {
                                        Rectangle()
                                            .fill(connected
                                                  ? Color(red: 0.18, green: 0.75, blue: 0.35).opacity(0.85)
                                                  : Color.white.opacity(destIdx % 2 == 0 ? 0.04 : 0.02))
                                        if connected {
                                            Circle()
                                                .fill(Color.white.opacity(0.9))
                                                .frame(width: 10, height: 10)
                                        }
                                        Rectangle()
                                            .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                                    }
                                    .frame(width: cellSize, height: cellSize)
                                }
                                .buttonStyle(.plain)
                                .help("CH \(col + 1) → \(dest.label)")
                            }
                        }
                    }
                }
            }
            .background(Color(red: 0.06, green: 0.07, blue: 0.1))
        }
    }
}
