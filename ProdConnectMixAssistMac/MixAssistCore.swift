import AudioToolbox
import AVFoundation
import Combine
#if canImport(CoreMIDI)
import CoreMIDI
#endif
import Foundation
import Network
import SwiftUI

enum MixAssistSourceKind: String, CaseIterable, Identifiable, Codable {
    case dante = "Dante"
    case usb = "USB Audio"
    case stereo = "Stereo L/R"

    var id: String { rawValue }
}

enum MixAssistControlKind: String, CaseIterable, Identifiable, Codable {
    case midi = "MIDI"
    case osc = "OSC"
    case eucon = "EUCON / DAW Remote"
    case vendor = "Console Adapter"

    var id: String { rawValue }
}

enum MixAssistMode: String, CaseIterable, Identifiable {
    case reference = "Reference Capture"
    case follow = "Auto Match"
    case channel = "Channel Assist"

    var id: String { rawValue }
}

enum MixAssistReferenceScope: String, CaseIterable, Codable, Identifiable {
    case stream = "Stream Mix"
    case foh = "FOH Mix"
    case channel = "Channel Tone"

    var id: String { rawValue }
}

enum MixAssistRecommendationKind: String, Codable, Identifiable {
    case fader = "Fader"
    case eq = "EQ"
    case compressor = "Compressor"
    case gate = "Gate"

    var id: String { rawValue }
}

enum MixAssistRecommendationSeverity: String, Codable, Identifiable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"

    var id: String { rawValue }
}

enum MixAssistTransportMode: String, Codable, Identifiable {
    case sandbox = "Sandbox Preview"
    case liveOSC = "Live OSC"
    case liveMIDI = "Live MIDI"
    case liveRCP = "Live RCP"

    var id: String { rawValue }
}

struct MixAssistReferenceProfile: Identifiable, Codable, Hashable {
    var id: String = UUID().uuidString
    var name: String
    var scope: MixAssistReferenceScope
    var sourceKind: MixAssistSourceKind
    var controlKind: MixAssistControlKind
    var notes: String
    var runOfShowID: String?
    var runOfShowItemID: String?
    var patchRowIDs: [String]
    var targetIntegratedLUFS: Double
    var targetSpectralCentroid: Double
    var targetDynamicRange: Double
    var targetStereoSpread: Double
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
}

// Mix preset captured for a specific Run of Show item.
// When that item becomes live, Mix Assist transitions faders to these levels.
struct MixAssistItemPreset: Identifiable, Codable, Hashable {
    var id: String = UUID().uuidString
    var rosItemID: String
    var rosItemTitle: String
    // Keys are String(destinationIndex) so the dict serialises to JSON cleanly
    var destinationLevelsDB: [String: Double]
    var targetOutputPreset: MixAssistTargetOutputPreset = .facebook
    var targetOutputLUFS: Double = -16.0
    var truePeakCeilingDBTP: Double = -1.0
    var autoAdjustSessionLimitDB: Double = 3.0
    var channelPriorities: [String: MixAssistChannelPriority] = [:]
    var capturedAt: Date = Date()

    func level(for destIdx: Int) -> Double? { destinationLevelsDB[String(destIdx)] }

    var targetSummary: String {
        "\(targetOutputPreset.name) \(String(format: "%.1f", targetOutputLUFS)) LUFS / \(String(format: "%.1f", truePeakCeilingDBTP)) dBTP"
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case rosItemID
        case rosItemTitle
        case destinationLevelsDB
        case targetOutputPreset
        case targetOutputLUFS
        case truePeakCeilingDBTP
        case autoAdjustSessionLimitDB
        case channelPriorities
        case capturedAt
    }

    init(
        id: String = UUID().uuidString,
        rosItemID: String,
        rosItemTitle: String,
        destinationLevelsDB: [String: Double],
        targetOutputPreset: MixAssistTargetOutputPreset = .facebook,
        targetOutputLUFS: Double = -16.0,
        truePeakCeilingDBTP: Double = -1.0,
        autoAdjustSessionLimitDB: Double = 3.0,
        channelPriorities: [String: MixAssistChannelPriority] = [:],
        capturedAt: Date = Date()
    ) {
        self.id = id
        self.rosItemID = rosItemID
        self.rosItemTitle = rosItemTitle
        self.destinationLevelsDB = destinationLevelsDB
        self.targetOutputPreset = targetOutputPreset
        self.targetOutputLUFS = targetOutputLUFS
        self.truePeakCeilingDBTP = truePeakCeilingDBTP
        self.autoAdjustSessionLimitDB = autoAdjustSessionLimitDB
        self.channelPriorities = channelPriorities
        self.capturedAt = capturedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        rosItemID = try c.decode(String.self, forKey: .rosItemID)
        rosItemTitle = try c.decode(String.self, forKey: .rosItemTitle)
        destinationLevelsDB = try c.decodeIfPresent([String: Double].self, forKey: .destinationLevelsDB) ?? [:]
        targetOutputPreset = try c.decodeIfPresent(MixAssistTargetOutputPreset.self, forKey: .targetOutputPreset) ?? .facebook
        targetOutputLUFS = try c.decodeIfPresent(Double.self, forKey: .targetOutputLUFS) ?? targetOutputPreset.defaultLUFS
        truePeakCeilingDBTP = try c.decodeIfPresent(Double.self, forKey: .truePeakCeilingDBTP) ?? targetOutputPreset.defaultTruePeakDBTP
        autoAdjustSessionLimitDB = try c.decodeIfPresent(Double.self, forKey: .autoAdjustSessionLimitDB) ?? 3.0
        channelPriorities = try c.decodeIfPresent([String: MixAssistChannelPriority].self, forKey: .channelPriorities) ?? [:]
        capturedAt = try c.decodeIfPresent(Date.self, forKey: .capturedAt) ?? Date()
    }
}

struct MixAssistSceneBinding: Identifiable, Codable, Hashable {
    var id: String = UUID().uuidString
    var profileID: String
    var runOfShowID: String?
    var runOfShowItemID: String?
    var patchRowIDs: [String]
    var sceneName: String
    var notes: String = ""
    var createdAt: Date = Date()
}

struct MixAssistAdapterDescriptor: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var controlKind: MixAssistControlKind
    var endpointSummary: String
    var stateSummary: String
}

struct MixAssistSimulationSnapshot: Identifiable, Codable, Hashable {
    var id: String = UUID().uuidString
    var profileID: String
    var sceneName: String
    var capturedAt: Date
    var measuredIntegratedLUFS: Double
    var measuredSpectralCentroid: Double
    var measuredDynamicRange: Double
    var measuredStereoSpread: Double
    var aggregateDeviationScore: Double
}

struct MixAssistRecommendation: Identifiable, Codable, Hashable {
    var id: String = UUID().uuidString
    var patchRowID: String?
    var patchRowName: String
    var kind: MixAssistRecommendationKind
    var severity: MixAssistRecommendationSeverity
    var controlKind: MixAssistControlKind
    var summary: String
    var deltaDescription: String
}

struct MixAssistTransportCommand: Identifiable, Codable, Hashable {
    var id: String = UUID().uuidString
    var adapterID: String
    var patchRowName: String
    var commandText: String
    var address: String
    var valueSummary: String
    var safetyNote: String
}

struct MixAssistTransportBatch: Identifiable, Codable, Hashable {
    var id: String = UUID().uuidString
    var createdAt: Date
    var adapterID: String
    var adapterName: String
    var mode: MixAssistTransportMode
    var commandCount: Int
    var sceneName: String
    var summary: String
    var commands: [MixAssistTransportCommand]
}

struct MixAssistLiveOSCSettings: Codable, Hashable {
    var host: String = "127.0.0.1"
    var port: String = "53000"
    var autoDisarmSeconds: Double = 30
}

enum MixAssistConsoleManufacturer: String, CaseIterable, Codable, Identifiable {
    case yamaha     = "Yamaha"
    case allenHeath = "Allen & Heath"
    case behringer  = "Behringer"
    case daw        = "DAW"

    var id: String { rawValue }

    var consoleModels: [MixAssistConsoleModel] {
        MixAssistConsoleModel.allCases.filter { $0.manufacturer == self }
    }
}

enum MixAssistConsoleModel: String, CaseIterable, Codable, Identifiable {
    // Yamaha
    case yamahaQL3 = "QL3"
    case yamahaQL5 = "QL5"
    case yamahaCL3 = "CL3"
    case yamahaCL5 = "CL5"
    case yamahaDM3 = "DM3"
    case yamahaDM7 = "DM7"
    // Allen & Heath
    case ahDLive   = "dLive"
    case ahAvantis = "Avantis"
    // Behringer
    case behringerWing = "Wing"
    case behringerX32  = "X32 / M32"
    // DAW
    case dawGarageBand = "GarageBand"
    case dawProTools   = "Pro Tools"
    case dawLogicPro   = "Logic Pro"
    case dawReaper     = "Reaper"

    var id: String { rawValue }

    var manufacturer: MixAssistConsoleManufacturer {
        switch self {
        case .yamahaQL3, .yamahaQL5, .yamahaCL3, .yamahaCL5, .yamahaDM3, .yamahaDM7: return .yamaha
        case .ahDLive, .ahAvantis: return .allenHeath
        case .behringerWing, .behringerX32: return .behringer
        case .dawGarageBand, .dawProTools, .dawLogicPro, .dawReaper: return .daw
        }
    }

    var requiresIPAddress: Bool { true }

    var defaultPort: Int {
        switch self {
        case .yamahaQL3, .yamahaQL5, .yamahaCL3, .yamahaCL5, .yamahaDM3: return 49280
        case .yamahaDM7: return 8765
        case .ahDLive:       return 51325
        case .ahAvantis:     return 51325
        case .behringerWing: return 2223
        case .behringerX32:  return 10023
        case .dawGarageBand: return 50002
        case .dawProTools:   return 53000
        case .dawLogicPro:   return 50002
        case .dawReaper:     return 8000
        }
    }

    var usesRCP: Bool {
        switch self {
        case .yamahaQL3, .yamahaQL5, .yamahaCL3, .yamahaCL5, .yamahaDM3:
            return true
        default:
            return false
        }
    }

    var usesMIDI: Bool { false }

    var usesOSC: Bool { !usesRCP && !usesMIDI }

    // Default IP to use when this model is first selected
    var defaultIP: String {
        switch self {
        case .dawGarageBand, .dawProTools, .dawLogicPro, .dawReaper: return "127.0.0.1"
        default: return "192.168.0.128"
        }
    }

    var connectionSummary: String {
        switch self {
        case .yamahaQL3, .yamahaQL5: return "Yamaha RCP over TCP — mixer control port 49280"
        case .yamahaCL3, .yamahaCL5: return "Yamaha RCP over TCP — mixer control port 49280"
        case .yamahaDM3:             return "Yamaha RCP over TCP — mixer control port 49280"
        case .yamahaDM7:             return "Yamaha OSC — console IP, port 8765"
        case .ahDLive:               return "Allen & Heath dLive OSC — console IP, port 51325"
        case .ahAvantis:             return "Allen & Heath Avantis OSC — console IP, port 51325"
        case .behringerWing:         return "Behringer Wing OSC — console IP, port 2223"
        case .behringerX32:          return "X32 / M32 OSC — console IP, port 10023"
        case .dawGarageBand:         return "GarageBand — OSC via localhost, port 50002"
        case .dawProTools:           return "Pro Tools — OSC via localhost, port 53000"
        case .dawLogicPro:           return "Logic Pro — OSC via localhost, port 50002"
        case .dawReaper:             return "Reaper — OSC via localhost, port 8000"
        }
    }
}

// Which console signal path the auto-adjust OSC targets
enum MixAssistConsoleBusType: String, CaseIterable, Codable, Identifiable {
    case inputChannel = "Input Channel Faders"
    case mixBusSend   = "Mix Bus Sends"
    case matrixSend   = "Matrix Sends"
    var id: String { rawValue }
}

enum MixAssistTargetOutputPreset: String, CaseIterable, Codable, Identifiable {
    case youtube
    case facebook
    case recording
    case custom

    var id: String { rawValue }

    var name: String {
        switch self {
        case .youtube: return "YouTube"
        case .facebook: return "Facebook"
        case .recording: return "Recording"
        case .custom: return "Custom"
        }
    }

    var defaultLUFS: Double {
        switch self {
        case .youtube: return -14.0
        case .facebook: return -16.0
        case .recording: return -18.0
        case .custom: return -16.0
        }
    }

    var defaultTruePeakDBTP: Double {
        switch self {
        case .youtube, .facebook: return -1.0
        case .recording: return -3.0
        case .custom: return -1.0
        }
    }

    var description: String {
        switch self {
        case .youtube:
            return "Streaming delivery target for YouTube playback normalization."
        case .facebook:
            return "Social video target with room for voice-forward program material."
        case .recording:
            return "Capture target with extra headroom before post-production."
        case .custom:
            return "Manual loudness and true peak targets."
        }
    }

    var displayName: String {
        "\(name) (\(String(format: "%.1f", defaultLUFS)) LUFS)"
    }
}

enum MixAssistChannelPriority: String, CaseIterable, Codable, Identifiable {
    case background
    case normal
    case speech
    case leadSpeech

    var id: String { rawValue }

    var label: String {
        switch self {
        case .background: return "BG"
        case .normal: return "N"
        case .speech: return "SP"
        case .leadSpeech: return "LD"
        }
    }

    var name: String {
        switch self {
        case .background: return "Background"
        case .normal: return "Normal"
        case .speech: return "Speech"
        case .leadSpeech: return "Lead Speech"
        }
    }

    var boostScale: Double {
        switch self {
        case .background: return 0.45
        case .normal: return 0.75
        case .speech: return 1.0
        case .leadSpeech: return 1.25
        }
    }

    var cutScale: Double {
        switch self {
        case .background: return 1.25
        case .normal: return 0.9
        case .speech: return 0.6
        case .leadSpeech: return 0.4
        }
    }
}

struct MixAssistConsoleSettings: Codable, Hashable {
    var manufacturer: MixAssistConsoleManufacturer = .yamaha
    var model: MixAssistConsoleModel = .yamahaDM7
    var consoleIPAddress: String = "192.168.0.128"
    var selectedMIDIDestinationID: String?
    var midiChannel: Int = 1
    var faderCCBase: Int = 20
    var eqCCBase: Int = 40
    var compressorCCBase: Int = 60
    var gateCCBase: Int = 80
    var targetOutputPreset: MixAssistTargetOutputPreset = .facebook
    var targetOutputLUFS: Double = -16.0
    var truePeakCeilingDBTP: Double = -1.0
    var masterFaderCC: Int = 100
    var autoAdjustEnabled: Bool = false
    var autoAdjustIntervalSeconds: Double = 1.0
    var autoAdjustDeadbandLUFS: Double = 0.5
    var autoAdjustMaxDeltaDB: Double = 0.25
    var autoAdjustSessionLimitDB: Double = 3.0
    // 1-indexed Dante channel that carries the console mix output return; nil = not set
    var mixOutputDanteChannel: Int? = nil
    // Which signal path to target; inputChannel = main channel faders (default)
    var targetBusType: MixAssistConsoleBusType = .inputChannel
    // 1-indexed bus number used when targetBusType != .inputChannel
    var targetBusNumber: Int = 1
    // Per-channel reference audio levels (RMS in dB) captured during sound check.
    // Keys are 0-indexed channel numbers as strings. When non-empty, auto-adjust
    // drives each fader independently toward its captured level instead of using
    // the global LUFS approach.
    var targetChannelLevelsDB: [String: Double] = [:]

    private enum CodingKeys: String, CodingKey {
        case manufacturer, model, consoleIPAddress
        case selectedMIDIDestinationID, midiChannel
        case faderCCBase, eqCCBase, compressorCCBase, gateCCBase
        case targetOutputPreset, targetOutputLUFS, truePeakCeilingDBTP, masterFaderCC
        case autoAdjustEnabled, autoAdjustIntervalSeconds
        case autoAdjustDeadbandLUFS, autoAdjustMaxDeltaDB, autoAdjustSessionLimitDB
        case mixOutputDanteChannel
        case targetBusType, targetBusNumber
        case targetChannelLevelsDB
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        manufacturer              = try c.decodeIfPresent(MixAssistConsoleManufacturer.self, forKey: .manufacturer)              ?? .yamaha
        model                     = try c.decodeIfPresent(MixAssistConsoleModel.self,         forKey: .model)                     ?? .yamahaDM7
        consoleIPAddress          = try c.decodeIfPresent(String.self,                        forKey: .consoleIPAddress)          ?? "192.168.0.128"
        selectedMIDIDestinationID = try c.decodeIfPresent(String.self,                        forKey: .selectedMIDIDestinationID)
        midiChannel               = try c.decodeIfPresent(Int.self,                           forKey: .midiChannel)               ?? 1
        faderCCBase               = try c.decodeIfPresent(Int.self,                           forKey: .faderCCBase)               ?? 20
        eqCCBase                  = try c.decodeIfPresent(Int.self,                           forKey: .eqCCBase)                  ?? 40
        compressorCCBase          = try c.decodeIfPresent(Int.self,                           forKey: .compressorCCBase)          ?? 60
        gateCCBase                = try c.decodeIfPresent(Int.self,                           forKey: .gateCCBase)                ?? 80
        targetOutputPreset        = try c.decodeIfPresent(MixAssistTargetOutputPreset.self,   forKey: .targetOutputPreset)        ?? .facebook
        targetOutputLUFS          = try c.decodeIfPresent(Double.self,                        forKey: .targetOutputLUFS)          ?? targetOutputPreset.defaultLUFS
        truePeakCeilingDBTP       = try c.decodeIfPresent(Double.self,                        forKey: .truePeakCeilingDBTP)       ?? targetOutputPreset.defaultTruePeakDBTP
        masterFaderCC             = try c.decodeIfPresent(Int.self,                           forKey: .masterFaderCC)             ?? 100
        autoAdjustEnabled         = try c.decodeIfPresent(Bool.self,                          forKey: .autoAdjustEnabled)         ?? false
        autoAdjustIntervalSeconds = try c.decodeIfPresent(Double.self,                        forKey: .autoAdjustIntervalSeconds) ?? 1.0
        autoAdjustDeadbandLUFS    = try c.decodeIfPresent(Double.self,                        forKey: .autoAdjustDeadbandLUFS)    ?? 0.5
        autoAdjustMaxDeltaDB      = try c.decodeIfPresent(Double.self,                        forKey: .autoAdjustMaxDeltaDB)      ?? 0.25
        autoAdjustSessionLimitDB  = try c.decodeIfPresent(Double.self,                        forKey: .autoAdjustSessionLimitDB)  ?? 3.0
        mixOutputDanteChannel     = try c.decodeIfPresent(Int.self,                           forKey: .mixOutputDanteChannel)
        targetBusType             = try c.decodeIfPresent(MixAssistConsoleBusType.self,        forKey: .targetBusType)             ?? .inputChannel
        targetBusNumber           = try c.decodeIfPresent(Int.self,                           forKey: .targetBusNumber)           ?? 1
        targetChannelLevelsDB     = try c.decodeIfPresent([String: Double].self,              forKey: .targetChannelLevelsDB)     ?? [:]
    }
}

// Keep as a legacy alias so saved state doesn't crash on decode
typealias MixAssistYamahaConsoleModel = MixAssistConsoleModel
typealias MixAssistYamahaControlSettings = MixAssistConsoleSettings

struct MixAssistMIDIDestinationDescriptor: Identifiable, Codable, Hashable {
    var id: String
    var name: String
}

struct MixAssistRoutingMatrix: Codable, Hashable {
    // Key: "\(inputChannelIndex)|\(destinationID)" → enabled
    var connections: [String: Bool] = [:]

    func isConnected(input: Int, destinationID: String) -> Bool {
        connections[routeKey(input, destinationID)] == true
    }

    mutating func toggle(input: Int, destinationID: String) {
        let k = routeKey(input, destinationID)
        connections[k] = !(connections[k] ?? false)
    }

    // Exclusive per destination: each destination accepts at most one input.
    // An input may fan out to multiple destinations freely.
    mutating func toggleExclusiveDest(input: Int, destinationID: String) {
        let k = routeKey(input, destinationID)
        if connections[k] == true {
            connections[k] = false
        } else {
            clearDestination(destinationID)   // evict any other input feeding this dest
            connections[k] = true
        }
    }

    mutating func clearInput(_ input: Int) {
        connections = connections.filter { !$0.key.hasPrefix("\(input)|") }
    }

    mutating func clearDestination(_ destinationID: String) {
        connections = connections.filter { key, _ in
            guard let pipe = key.firstIndex(of: "|") else { return true }
            return String(key[key.index(after: pipe)...]) != destinationID
        }
    }

    mutating func clearAll() {
        connections.removeAll()
    }

    // Returns all input indices routed to a given destination
    func inputs(for destinationID: String, total: Int) -> [Int] {
        (0..<total).filter { isConnected(input: $0, destinationID: destinationID) }
    }

    // Returns all destination IDs routed from a given input
    func destinations(for input: Int) -> [String] {
        connections.compactMap { key, on in
            guard on, key.hasPrefix("\(input)|") else { return nil }
            return String(key.dropFirst("\(input)|".count))
        }
    }

    private func routeKey(_ input: Int, _ dest: String) -> String { "\(input)|\(dest)" }
}

private struct MixAssistPersistedState: Codable {
    var referenceProfiles: [MixAssistReferenceProfile]
    var sceneBindings: [MixAssistSceneBinding]
    var selectedProfileID: String?
    var selectedAdapterID: String?
    var transportHistory: [MixAssistTransportBatch]
    var liveOSCSettings: MixAssistLiveOSCSettings
    var yamahaSettings: MixAssistYamahaControlSettings
    var routingMatrix: MixAssistRoutingMatrix
    var routingInputCount: Int
    var lockedDestinations: [Int]
    var channelPriorities: [String: MixAssistChannelPriority]
    var selectedAudioDeviceUID: String?
    var itemPresets: [MixAssistItemPreset]

    private enum CodingKeys: String, CodingKey {
        case referenceProfiles
        case sceneBindings
        case selectedProfileID
        case selectedAdapterID
        case transportHistory
        case liveOSCSettings
        case yamahaSettings
        case routingMatrix
        case routingInputCount
        case lockedDestinations
        case channelPriorities
        case selectedAudioDeviceUID
        case itemPresets
    }

    init(
        referenceProfiles: [MixAssistReferenceProfile],
        sceneBindings: [MixAssistSceneBinding],
        selectedProfileID: String?,
        selectedAdapterID: String?,
        transportHistory: [MixAssistTransportBatch],
        liveOSCSettings: MixAssistLiveOSCSettings,
        yamahaSettings: MixAssistYamahaControlSettings,
        routingMatrix: MixAssistRoutingMatrix,
        routingInputCount: Int,
        lockedDestinations: [Int],
        channelPriorities: [String: MixAssistChannelPriority],
        selectedAudioDeviceUID: String?,
        itemPresets: [MixAssistItemPreset]
    ) {
        self.referenceProfiles = referenceProfiles
        self.sceneBindings = sceneBindings
        self.selectedProfileID = selectedProfileID
        self.selectedAdapterID = selectedAdapterID
        self.transportHistory = transportHistory
        self.liveOSCSettings = liveOSCSettings
        self.yamahaSettings = yamahaSettings
        self.routingMatrix = routingMatrix
        self.routingInputCount = routingInputCount
        self.lockedDestinations = lockedDestinations
        self.channelPriorities = channelPriorities
        self.selectedAudioDeviceUID = selectedAudioDeviceUID
        self.itemPresets = itemPresets
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        referenceProfiles = try container.decodeIfPresent([MixAssistReferenceProfile].self, forKey: .referenceProfiles) ?? []
        sceneBindings = try container.decodeIfPresent([MixAssistSceneBinding].self, forKey: .sceneBindings) ?? []
        selectedProfileID = try container.decodeIfPresent(String.self, forKey: .selectedProfileID)
        selectedAdapterID = try container.decodeIfPresent(String.self, forKey: .selectedAdapterID)
        transportHistory = try container.decodeIfPresent([MixAssistTransportBatch].self, forKey: .transportHistory) ?? []
        liveOSCSettings = try container.decodeIfPresent(MixAssistLiveOSCSettings.self, forKey: .liveOSCSettings) ?? MixAssistLiveOSCSettings()
        yamahaSettings = try container.decodeIfPresent(MixAssistYamahaControlSettings.self, forKey: .yamahaSettings) ?? MixAssistYamahaControlSettings()
        routingMatrix = try container.decodeIfPresent(MixAssistRoutingMatrix.self, forKey: .routingMatrix) ?? MixAssistRoutingMatrix()
        routingInputCount = try container.decodeIfPresent(Int.self, forKey: .routingInputCount) ?? 32
        lockedDestinations = try container.decodeIfPresent([Int].self, forKey: .lockedDestinations) ?? []
        channelPriorities = try container.decodeIfPresent([String: MixAssistChannelPriority].self, forKey: .channelPriorities) ?? [:]
        selectedAudioDeviceUID = try container.decodeIfPresent(String.self, forKey: .selectedAudioDeviceUID)
        itemPresets = try container.decodeIfPresent([MixAssistItemPreset].self, forKey: .itemPresets) ?? []
    }
}

private protocol MixAssistAdapter {
    var descriptor: MixAssistAdapterDescriptor { get }
    func makeCommands(
        recommendations: [MixAssistRecommendation],
        profile: MixAssistReferenceProfile,
        binding: MixAssistSceneBinding?
    ) -> [MixAssistTransportCommand]
}

private protocol MixAssistTransport {
    func dispatch(
        commands: [MixAssistTransportCommand],
        through adapter: MixAssistAdapterDescriptor,
        sceneName: String
    ) -> MixAssistTransportBatch
}

private protocol MixAssistLiveTransport {
    func dispatchLive(
        commands: [MixAssistTransportCommand],
        through adapter: MixAssistAdapterDescriptor,
        settings: MixAssistLiveOSCSettings,
        sceneName: String
    ) throws -> MixAssistTransportBatch
}

private struct GenericOSCAdapter: MixAssistAdapter {
    let descriptor = MixAssistAdapterDescriptor(
        id: "generic-osc",
        name: "Generic OSC Console",
        controlKind: .osc,
        endpointSummary: "10.0.0.45:53000",
        stateSummary: "Sandbox Ready"
    )

    func makeCommands(
        recommendations: [MixAssistRecommendation],
        profile: MixAssistReferenceProfile,
        binding: MixAssistSceneBinding?
    ) -> [MixAssistTransportCommand] {
        recommendations.map { recommendation in
            MixAssistTransportCommand(
                adapterID: descriptor.id,
                patchRowName: recommendation.patchRowName,
                commandText: "Send OSC \(path(for: recommendation, binding: binding)) \(argument(for: recommendation))",
                address: path(for: recommendation, binding: binding),
                valueSummary: argument(for: recommendation),
                safetyNote: "Preview only. No OSC packet will be transmitted."
            )
        }
    }

    private func path(for recommendation: MixAssistRecommendation, binding: MixAssistSceneBinding?) -> String {
        let sceneSlug = slug(binding?.sceneName ?? "mix")
        let channelSlug = slug(recommendation.patchRowName)
        let parameterSlug = slug(recommendation.kind.rawValue)
        return "/mixassist/\(sceneSlug)/\(channelSlug)/\(parameterSlug)"
    }

    private func argument(for recommendation: MixAssistRecommendation) -> String {
        recommendation.deltaDescription.replacingOccurrences(of: "Adjust ", with: "")
    }
}

private struct GenericMIDIAdapter: MixAssistAdapter {
    let descriptor = MixAssistAdapterDescriptor(
        id: "generic-midi",
        name: "Generic MIDI Surface",
        controlKind: .midi,
        endpointSummary: "IAC Driver Bus 1",
        stateSummary: "Sandbox Ready"
    )

    func makeCommands(
        recommendations: [MixAssistRecommendation],
        profile: MixAssistReferenceProfile,
        binding: MixAssistSceneBinding?
    ) -> [MixAssistTransportCommand] {
        recommendations.enumerated().map { index, recommendation in
            let controlNumber = 20 + index
            return MixAssistTransportCommand(
                adapterID: descriptor.id,
                patchRowName: recommendation.patchRowName,
                commandText: "Send MIDI CC \(controlNumber) value preview for \(recommendation.deltaDescription)",
                address: "CC \(controlNumber)",
                valueSummary: recommendation.deltaDescription,
                safetyNote: "Preview only. No MIDI message will be transmitted."
            )
        }
    }
}

private struct EuconPreviewAdapter: MixAssistAdapter {
    let descriptor = MixAssistAdapterDescriptor(
        id: "protools",
        name: "Pro Tools",
        controlKind: .eucon,
        endpointSummary: "EUCON / MIDI bridge",
        stateSummary: "Research Sandbox"
    )

    func makeCommands(
        recommendations: [MixAssistRecommendation],
        profile: MixAssistReferenceProfile,
        binding: MixAssistSceneBinding?
    ) -> [MixAssistTransportCommand] {
        recommendations.map { recommendation in
            MixAssistTransportCommand(
                adapterID: descriptor.id,
                patchRowName: recommendation.patchRowName,
                commandText: "Queue EUCON action for \(recommendation.patchRowName): \(recommendation.deltaDescription)",
                address: "EUCON.\(slug(recommendation.patchRowName)).\(slug(recommendation.kind.rawValue))",
                valueSummary: recommendation.deltaDescription,
                safetyNote: "Preview only. DAW transport remains untouched."
            )
        }
    }
}

private struct VendorConsolePreviewAdapter: MixAssistAdapter {
    let descriptor = MixAssistAdapterDescriptor(
        id: "allen-heath",
        name: "Allen & Heath",
        controlKind: .vendor,
        endpointSummary: "Vendor TCP adapter",
        stateSummary: "Sandbox Ready"
    )

    func makeCommands(
        recommendations: [MixAssistRecommendation],
        profile: MixAssistReferenceProfile,
        binding: MixAssistSceneBinding?
    ) -> [MixAssistTransportCommand] {
        recommendations.map { recommendation in
            MixAssistTransportCommand(
                adapterID: descriptor.id,
                patchRowName: recommendation.patchRowName,
                commandText: "Queue vendor adapter preview for \(recommendation.kind.rawValue.lowercased()) on \(recommendation.patchRowName)",
                address: "vendor://mixassist/\(slug(recommendation.patchRowName))/\(slug(recommendation.kind.rawValue))",
                valueSummary: recommendation.deltaDescription,
                safetyNote: "Preview only. Vendor socket writes are disabled."
            )
        }
    }
}

private struct YamahaDM7PreviewAdapter: MixAssistAdapter {
    let descriptor = MixAssistAdapterDescriptor(
        id: "yamaha-dm7",
        name: "Yamaha DM7",
        controlKind: .osc,
        endpointSummary: "Vendor adapter over network",
        stateSummary: "Sandbox Ready"
    )

    func makeCommands(
        recommendations: [MixAssistRecommendation],
        profile: MixAssistReferenceProfile,
        binding: MixAssistSceneBinding?
    ) -> [MixAssistTransportCommand] {
        recommendations.map { recommendation in
            MixAssistTransportCommand(
                adapterID: descriptor.id,
                patchRowName: recommendation.patchRowName,
                commandText: "Queue DM7 preview command for \(recommendation.deltaDescription)",
                address: "/dm7/\(slug(recommendation.patchRowName))/\(slug(recommendation.kind.rawValue))",
                valueSummary: recommendation.deltaDescription,
                safetyNote: "Preview only. DM7 write path is not enabled."
            )
        }
    }
}

private struct YamahaRCPPreviewAdapter: MixAssistAdapter {
    let descriptor = MixAssistAdapterDescriptor(
        id: "yamaha-rcp",
        name: "Yamaha RCP",
        controlKind: .vendor,
        endpointSummary: "TCP 49280",
        stateSummary: "Direct Network"
    )

    func makeCommands(
        recommendations: [MixAssistRecommendation],
        profile: MixAssistReferenceProfile,
        binding: MixAssistSceneBinding?
    ) -> [MixAssistTransportCommand] {
        recommendations.map { recommendation in
            MixAssistTransportCommand(
                adapterID: descriptor.id,
                patchRowName: recommendation.patchRowName,
                commandText: "Queue Yamaha RCP preview command for \(recommendation.deltaDescription)",
                address: "MIXER:Current/InCh/Fader/Level",
                valueSummary: recommendation.deltaDescription,
                safetyNote: "Preview only. Live mode sends Yamaha RCP over TCP."
            )
        }
    }
}

private struct MixAssistSandboxTransport: MixAssistTransport {
    func dispatch(
        commands: [MixAssistTransportCommand],
        through adapter: MixAssistAdapterDescriptor,
        sceneName: String
    ) -> MixAssistTransportBatch {
        MixAssistTransportBatch(
            createdAt: Date(),
            adapterID: adapter.id,
            adapterName: adapter.name,
            mode: .sandbox,
            commandCount: commands.count,
            sceneName: sceneName,
            summary: commands.isEmpty
                ? "No sandbox commands generated."
                : "Generated \(commands.count) sandbox commands for \(adapter.name).",
            commands: commands
        )
    }
}

#if canImport(CoreMIDI)
@MainActor
private final class MixAssistMIDIRuntime {
    private var midiClient = MIDIClientRef()
    private var outputPort = MIDIPortRef()

    init() {
        MIDIClientCreateWithBlock("ProdConnect Mix Assist MIDI" as CFString, &midiClient) { _ in }
        MIDIOutputPortCreate(midiClient, "ProdConnect Mix Assist Output" as CFString, &outputPort)
    }

    deinit {
        if outputPort != 0 { MIDIPortDispose(outputPort) }
        if midiClient != 0 { MIDIClientDispose(midiClient) }
    }

    var destinations: [MixAssistMIDIDestinationDescriptor] {
        let count = MIDIGetNumberOfDestinations()
        var result: [MixAssistMIDIDestinationDescriptor] = []
        for index in 0..<count {
            let endpoint = MIDIGetDestination(index)
            var uniqueID = MIDIUniqueID()
            guard MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &uniqueID) == noErr else { continue }
            let name = midiDestinationName(for: endpoint) ?? "MIDI Destination \(index + 1)"
            result.append(MixAssistMIDIDestinationDescriptor(id: String(uniqueID), name: name))
        }
        return result
    }

    func sendControlChange(destinationID: String, channel: Int, controller: Int, value: Int) throws {
        guard let parsedUniqueID = Int32(destinationID),
              let uniqueID = MIDIUniqueID(exactly: parsedUniqueID),
              let destination = midiDestinationRef(for: uniqueID) else {
            throw MixAssistLiveTransportError.connectionFailed("Select a valid MIDI destination.")
        }

        let status = UInt8(0xB0 | UInt8(max(0, min(15, channel - 1))))
        let controllerByte = UInt8(max(0, min(127, controller)))
        let valueByte = UInt8(max(0, min(127, value)))
        let data = [status, controllerByte, valueByte]

        let packetListPointer = UnsafeMutablePointer<MIDIPacketList>.allocate(capacity: 1)
        defer { packetListPointer.deallocate() }

        let packet = MIDIPacketListInit(packetListPointer)
        _ = MIDIPacketListAdd(packetListPointer, 1024, packet, 0, data.count, data)

        let statusCode = MIDISend(outputPort, destination, packetListPointer)
        guard statusCode == noErr else {
            throw MixAssistLiveTransportError.connectionFailed("CoreMIDI send failed with status \(statusCode).")
        }
    }

    private func midiDestinationRef(for uniqueID: MIDIUniqueID) -> MIDIEndpointRef? {
        let count = MIDIGetNumberOfDestinations()
        for index in 0..<count {
            let endpoint = MIDIGetDestination(index)
            var endpointID = MIDIUniqueID()
            guard MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &endpointID) == noErr else { continue }
            if endpointID == uniqueID {
                return endpoint
            }
        }
        return nil
    }

    private func midiDestinationName(for endpoint: MIDIEndpointRef) -> String? {
        var unmanagedName: Unmanaged<CFString>?
        guard MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &unmanagedName) == noErr
                || MIDIObjectGetStringProperty(endpoint, kMIDIPropertyName, &unmanagedName) == noErr else {
            return nil
        }
        return unmanagedName?.takeRetainedValue() as String?
    }
}
#endif

private enum MixAssistLiveTransportError: LocalizedError {
    case invalidHost
    case invalidPort
    case unsupportedAdapter
    case encodingFailed(String)
    case connectionFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidHost:
            return "Enter a valid OSC host."
        case .invalidPort:
            return "Enter a valid OSC port."
        case .unsupportedAdapter:
            return "Only OSC adapters can send live commands right now."
        case .encodingFailed(let address):
            return "Failed to encode OSC command for \(address)."
        case .connectionFailed(let message):
            return message
        }
    }
}

enum MixAssistTransferError: LocalizedError {
    case missingStoreContext
    case exportFailed
    case importFailed

    var errorDescription: String? {
        switch self {
        case .missingStoreContext:
            return "Mix Assist store context is not ready yet."
        case .exportFailed:
            return "Failed to export Mix Assist state."
        case .importFailed:
            return "Failed to import Mix Assist state."
        }
    }
}

private struct MixAssistLiveOSCTransport: MixAssistLiveTransport {
    func dispatchLive(
        commands: [MixAssistTransportCommand],
        through adapter: MixAssistAdapterDescriptor,
        settings: MixAssistLiveOSCSettings,
        sceneName: String
    ) throws -> MixAssistTransportBatch {
        guard adapter.controlKind == .osc else {
            throw MixAssistLiveTransportError.unsupportedAdapter
        }

        let trimmedHost = settings.host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else {
            throw MixAssistLiveTransportError.invalidHost
        }
        guard let portValue = UInt16(settings.port.trimmingCharacters(in: .whitespacesAndNewlines)),
              let port = NWEndpoint.Port(rawValue: portValue) else {
            throw MixAssistLiveTransportError.invalidPort
        }

        let connection = NWConnection(host: NWEndpoint.Host(trimmedHost), port: port, using: .udp)
        let queue = DispatchQueue(label: "ProdConnectMixAssist.LiveOSC")
        connection.start(queue: queue)

        do {
            for command in commands {
                let packet = try encodeOSCMessage(address: command.address, value: command.valueSummary)
                try send(packet, over: connection)
            }
        } catch {
            connection.cancel()
            if let transportError = error as? MixAssistLiveTransportError {
                throw transportError
            }
            throw MixAssistLiveTransportError.connectionFailed(error.localizedDescription)
        }

        connection.cancel()

        return MixAssistTransportBatch(
            createdAt: Date(),
            adapterID: adapter.id,
            adapterName: adapter.name,
            mode: .liveOSC,
            commandCount: commands.count,
            sceneName: sceneName,
            summary: "Sent \(commands.count) OSC command\(commands.count == 1 ? "" : "s") to \(trimmedHost):\(portValue).",
            commands: commands
        )
    }

    private func send(_ packet: Data, over connection: NWConnection) throws {
        let semaphore = DispatchSemaphore(value: 0)
        var sendError: NWError?
        connection.send(content: packet, completion: .contentProcessed { error in
            sendError = error
            semaphore.signal()
        })
        semaphore.wait()
        if let sendError {
            throw MixAssistLiveTransportError.connectionFailed(sendError.localizedDescription)
        }
    }

    private func encodeOSCMessage(address: String, value: String) throws -> Data {
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAddress.isEmpty else {
            throw MixAssistLiveTransportError.encodingFailed(address)
        }

        var payload = Data()
        payload.append(oscPaddedString(trimmedAddress))

        if let intValue = parseIntegerValue(from: value) {
            payload.append(oscPaddedString(",i"))
            payload.append(oscInt32(Int32(intValue)))
        } else if let floatValue = parseNumericValue(from: value) {
            payload.append(oscPaddedString(",f"))
            payload.append(oscFloat32(floatValue))
        } else {
            payload.append(oscPaddedString(",s"))
            payload.append(oscPaddedString(value))
        }

        return payload
    }

    private func parseNumericValue(from text: String) -> Float? {
        let filtered = text.filter { "-+.0123456789".contains($0) }
        return Float(filtered)
    }

    private func parseIntegerValue(from text: String) -> Int? {
        guard !text.contains(".") else { return nil }
        return Int(text.trimmingCharacters(in: .whitespaces))
    }

    private func oscPaddedString(_ string: String) -> Data {
        var data = Data(string.utf8)
        data.append(0)
        while data.count % 4 != 0 {
            data.append(0)
        }
        return data
    }

    private func oscFloat32(_ value: Float) -> Data {
        let bitPattern = value.bitPattern.bigEndian
        return withUnsafeBytes(of: bitPattern) { Data($0) }
    }

    private func oscInt32(_ value: Int32) -> Data {
        let bitPattern = value.bigEndian
        return withUnsafeBytes(of: bitPattern) { Data($0) }
    }
}

// Persistent TCP session for Yamaha RCP auto-adjust.
// One connection is opened when auto-adjust starts and reused for every tick.
// This prevents the QL5's max-connections limit from being hit by per-tick
// connection churn, and eliminates the TCP RST / data-race bug seen with
// short single-connection sends.
private final class MixAssistRCPSession: @unchecked Sendable {
    private let lock = NSLock()
    private var connection: NWConnection?
    private var connectedHost: String = ""
    private var connectedPort: Int = 0
    var onDisconnect: ((String) -> Void)?

    // Ensures a live connection to host:port. No-op if already connected there.
    // Reconnects automatically if the previous connection failed.
    func ensureConnected(host: String, port: Int) {
        lock.lock()
        defer { lock.unlock() }
        if connectedHost == host, connectedPort == port, let c = connection {
            switch c.state {
            case .ready, .preparing, .setup, .waiting: return
            default: break
            }
        }
        connection?.cancel()
        connectedHost = host
        connectedPort = port
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else { return }
        let c = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        c.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed(let err):
                self?.lock.lock()
                if self?.connection === c { self?.connection = nil }
                self?.lock.unlock()
                self?.onDisconnect?("RCP connection lost: \(err.localizedDescription)")
            case .cancelled:
                self?.lock.lock()
                if self?.connection === c { self?.connection = nil }
                self?.lock.unlock()
            default:
                break
            }
        }
        c.start(queue: DispatchQueue.global(qos: .userInitiated))
        connection = c
        startReceiveDrain(c)
    }

    // Drain incoming bytes and detect graceful close (FIN) from the console.
    // Without this, NWConnection stays .ready after the QL5 sends FIN, and
    // subsequent sends silently go into the kernel buffer but never arrive.
    private func startReceiveDrain(_ c: NWConnection) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] _, _, isComplete, error in
            if isComplete || error != nil {
                self?.lock.lock()
                if self?.connection === c { self?.connection = nil }
                self?.lock.unlock()
                return
            }
            // Discard any response data; loop to keep detecting future close
            self?.startReceiveDrain(c)
        }
    }

    // Non-blocking send. Uses contentProcessed so TCP write failures are detected
    // and the connection is cleared — ensureConnected() on the next tick will reconnect.
    func send(payload: String) {
        lock.lock()
        let c = connection
        lock.unlock()
        guard let c else { return }
        c.send(content: Data(payload.utf8),
               contentContext: .defaultMessage,
               isComplete: false,
               completion: .contentProcessed { [weak self] error in
                   guard error != nil else { return }
                   self?.lock.lock()
                   if self?.connection === c { self?.connection = nil }
                   self?.lock.unlock()
               })
    }

    func disconnect() {
        lock.lock()
        let c = connection
        connection = nil
        connectedHost = ""
        connectedPort = 0
        lock.unlock()
        c?.cancel()
    }
}

private struct MixAssistYamahaRCPTransport {
    func dispatchLive(
        commands: [MixAssistTransportCommand],
        host: String,
        port: Int,
        sceneName: String
    ) throws -> MixAssistTransportBatch {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else {
            throw MixAssistLiveTransportError.connectionFailed("No console IP set for Yamaha RCP.")
        }
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(max(1, min(65535, port)))) else {
            throw MixAssistLiveTransportError.connectionFailed("Invalid Yamaha RCP port \(port).")
        }

        let connection = NWConnection(host: NWEndpoint.Host(trimmedHost), port: nwPort, using: .tcp)
        let stateSemaphore = DispatchSemaphore(value: 0)
        let sendSemaphore = DispatchSemaphore(value: 0)
        var connectionError: Error?
        var sendError: Error?

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                stateSemaphore.signal()
            case .failed(let error):
                connectionError = error
                stateSemaphore.signal()
            default:
                break
            }
        }
        connection.start(queue: DispatchQueue.global(qos: .userInitiated))

        guard stateSemaphore.wait(timeout: .now() + 2.0) == .success else {
            connection.cancel()
            throw MixAssistLiveTransportError.connectionFailed("Timed out connecting to Yamaha RCP at \(trimmedHost):\(port).")
        }
        if let connectionError {
            connection.cancel()
            throw MixAssistLiveTransportError.connectionFailed(connectionError.localizedDescription)
        }

        let payload = commands.map(\.address).joined(separator: "\n") + "\n"

        // Send commands, then immediately send EOF (TCP FIN on the write side).
        // This ensures TCP flushes the payload to the QL5 before the connection
        // tears down. Without it, cancel() sends a RST that can arrive before
        // the data for small payloads (< 1 TCP segment), which the QL5 discards.
        connection.send(
            content: Data(payload.utf8),
            contentContext: .defaultMessage,
            isComplete: false,
            completion: .contentProcessed { error in
                sendError = error
                if error != nil {
                    sendSemaphore.signal()
                    return
                }
                // Half-close the write side (FIN) so TCP delivers the data
                // before tearing down the connection.
                connection.send(
                    content: nil,
                    contentContext: .finalMessage,
                    isComplete: true,
                    completion: .contentProcessed { _ in
                        sendSemaphore.signal()
                    }
                )
            }
        )

        guard sendSemaphore.wait(timeout: .now() + 3.0) == .success else {
            connection.cancel()
            throw MixAssistLiveTransportError.connectionFailed("Timed out sending Yamaha RCP commands.")
        }
        connection.cancel()
        if let sendError {
            throw MixAssistLiveTransportError.connectionFailed(sendError.localizedDescription)
        }

        return MixAssistTransportBatch(
            createdAt: Date(),
            adapterID: "yamaha-rcp",
            adapterName: "Yamaha RCP",
            mode: .liveRCP,
            commandCount: commands.count,
            sceneName: sceneName,
            summary: "Sent \(commands.count) Yamaha RCP command\(commands.count == 1 ? "" : "s") to \(trimmedHost):\(port).",
            commands: commands
        )
    }
}

// MARK: - Audio Monitor

struct MixAssistAudioInputDevice: Identifiable, Equatable {
    let uid: String
    let name: String
    var id: String { uid }
}

@MainActor
final class MixAssistAudioMonitor: ObservableObject {
    @Published var activeChannels: Set<Int> = []
    @Published private(set) var channelLevels: [Float] = []
    // Per-channel 3-second RMS average — stable enough for fader comparison
    @Published private(set) var channelShortTermRMS: [Float] = []
    @Published private(set) var peakLevels: [Float] = []
    @Published private(set) var channelCount: Int = 0
    @Published private(set) var detectedChannelCount: Int = 0   // hw channels reported by CoreAudio
    @Published private(set) var isMonitoring: Bool = false
    @Published private(set) var monitorError: String?
    @Published private(set) var integratedLUFS: Double = -60.0
    @Published private(set) var shortTermLUFS: Double = -60.0
    @Published private(set) var truePeakDBTP: Double = -120.0
    @Published private(set) var signalHealthSummary: String = "Monitor stopped."
    @Published private(set) var hasUsableSignal: Bool = false
    @Published private(set) var availableDevices: [MixAssistAudioInputDevice] = []
    @Published var selectedDeviceUID: String?
    // 0-indexed physical channel carrying the console mix output return; nil = average active channels
    @Published var mixMonitorChannel: Int? = nil

    // AudioDeviceIOProcID replaces AVAudioEngine — gives direct access to all hardware channels
    // without the engine's internal format conversion limiting us to ≤ 2 ch.
    private var ioProcID: AudioDeviceIOProcID?
    private var monitorDeviceID: AudioDeviceID = 0
    // nonisolated(unsafe): written by @MainActor code, read+written by the CoreAudio IO thread.
    // Thread safety is managed by bufferLock.
    nonisolated(unsafe) private var levelBuffer: [Float] = []
    nonisolated(unsafe) private var peakBuffer: [Float] = []
    nonisolated(unsafe) private var msAccumulator: [Double] = []
    nonisolated(unsafe) private var shortTermMSAccumulator: [Double] = []
    nonisolated(unsafe) private var msFrameCount: Int = 0
    nonisolated(unsafe) private var shortTermFrameCount: Int = 0
    nonisolated(unsafe) private var msWindowFrames: Int = 1323000
    nonisolated(unsafe) private var shortTermWindowFrames: Int = 132300
    private let bufferLock = NSLock()

    func startMonitoring() {
        stopMonitoring()
        monitorError = nil

        let deviceID: AudioDeviceID
        if let uid = selectedDeviceUID, let found = audioDeviceID(forUID: uid) {
            deviceID = found
        } else {
            // Fall back to system default input
            var addr = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultInputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var id: AudioDeviceID = 0
            var sz = UInt32(MemoryLayout<AudioDeviceID>.size)
            guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &sz, &id) == noErr, id != 0 else {
                monitorError = "No audio input device available."
                return
            }
            deviceID = id
        }

        let hwChannels = hardwareInputChannelCount(for: deviceID)
        detectedChannelCount = hwChannels
        let channels = max(1, hwChannels)

        // Query device nominal sample rate to size the LUFS window correctly
        var srAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var sampleRate: Float64 = 44100
        var srSz = UInt32(MemoryLayout<Float64>.size)
        AudioObjectGetPropertyData(deviceID, &srAddr, 0, nil, &srSz, &sampleRate)
        shortTermWindowFrames = Int(sampleRate * 3.0)
        msWindowFrames = Int(sampleRate * 30.0)
        deviceSampleRate = sampleRate

        channelCount = channels
        if activeChannels.isEmpty {
            activeChannels = Set(0..<channels)
        }

        bufferLock.lock()
        levelBuffer = Array(repeating: 0, count: channels)
        peakBuffer  = Array(repeating: 0, count: channels)
        msAccumulator = Array(repeating: 0, count: channels)
        shortTermMSAccumulator = Array(repeating: 0, count: channels)
        msFrameCount = 0
        shortTermFrameCount = 0
        bufferLock.unlock()

        channelLevels = Array(repeating: 0, count: channels)
        peakLevels    = Array(repeating: 0, count: channels)

        // Pass self as clientData via Unmanaged — safe because we destroy the proc before dealloc.
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let status = AudioDeviceCreateIOProcID(deviceID, { (_, _, inInputData, _, _, _, clientData) -> OSStatus in
            guard let clientData else { return noErr }
            let monitor = Unmanaged<MixAssistAudioMonitor>.fromOpaque(clientData).takeUnretainedValue()
            monitor.processIOInput(inInputData)
            return noErr
        }, selfPtr, &ioProcID)

        guard status == noErr, let procID = ioProcID else {
            monitorError = "Failed to create audio IO proc (OSStatus \(status))."
            return
        }

        let startStatus = AudioDeviceStart(deviceID, procID)
        guard startStatus == noErr else {
            AudioDeviceDestroyIOProcID(deviceID, procID)
            ioProcID = nil
            monitorError = "Failed to start audio device (OSStatus \(startStatus))."
            return
        }

        monitorDeviceID = deviceID
        isMonitoring = true
        scheduleUIUpdate()
    }

    // Called on the CoreAudio IO thread — accesses only lock-protected buffers.
    // nonisolated(unsafe) lets us call this from a non-actor context.
    nonisolated(unsafe) func processIOInput(_ abl: UnsafePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: abl))
        let totalCh = buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
        guard totalCh > 0 else { return }

        var newLevels = [Float](repeating: 0, count: totalCh)
        var newPeaks  = [Float](repeating: 0, count: totalCh)
        var newMS     = [Double](repeating: 0, count: totalCh)
        var frameCount = 0
        var globalCh = 0

        for buffer in buffers {
            let nCh = Int(buffer.mNumberChannels)
            guard let dataPtr = buffer.mData?.assumingMemoryBound(to: Float.self) else {
                globalCh += nCh
                continue
            }
            // For non-interleaved (nCh == 1) each buffer is one channel's samples.
            // For interleaved (nCh > 1) samples are [ch0fr0, ch1fr0, ch0fr1, ch1fr1, ...].
            let fc = Int(buffer.mDataByteSize) / (4 * max(1, nCh))
            if frameCount == 0 { frameCount = fc }

            for localCh in 0..<nCh {
                let ch = globalCh + localCh
                guard ch < totalCh, fc > 0 else { continue }
                var rms: Float = 0
                var peak: Float = 0
                var ms: Double = 0
                for i in 0..<fc {
                    let s = dataPtr[i * nCh + localCh]
                    rms += s * s
                    ms += Double(s * s)
                    let a = abs(s)
                    if a > peak { peak = a }
                }
                newLevels[ch] = sqrt(rms / Float(fc))
                newPeaks[ch]  = peak
                newMS[ch]     = ms
            }
            globalCh += nCh
        }

        guard frameCount > 0 else { return }

        // Mix listen: copy mix output channels into the SPSC ring buffer for AVAudioSourceNode
        if mixListenEnabled {
            let chL = mixListenChL
            let chR = mixListenChR
            let cap = listenCap
            let write = listenWritePos
            let read = listenReadPos
            let occupied = write - read
            if occupied + frameCount > cap - 256 {
                listenReadPos = write - cap / 2
            }
            var gCh2 = 0
            var ptrL: UnsafeMutablePointer<Float>? = nil
            var ptrR: UnsafeMutablePointer<Float>? = nil
            var strideL = 1
            var strideR = 1
            for buffer in buffers {
                let nCh = Int(buffer.mNumberChannels)
                if let data = buffer.mData?.assumingMemoryBound(to: Float.self) {
                    for localCh in 0..<nCh {
                        if gCh2 + localCh == chL { ptrL = data + localCh; strideL = nCh }
                        if gCh2 + localCh == chR { ptrR = data + localCh; strideR = nCh }
                    }
                }
                gCh2 += nCh
            }
            if let pl = ptrL {
                let pr = ptrR
                for i in 0..<frameCount {
                    let idx = (write + i) & (cap - 1)
                    listenBufL[idx] = pl[i * strideL]
                    listenBufR[idx] = pr.map { $0[i * strideR] } ?? pl[i * strideL]
                }
                listenWritePos = write + frameCount
            }
        }

        let windowFrames = msWindowFrames

        bufferLock.lock()
        for ch in 0..<min(totalCh, peakBuffer.count) {
            let held = peakBuffer[ch]
            peakBuffer[ch] = newPeaks[ch] > held ? newPeaks[ch] : held * 0.97
            if ch < msAccumulator.count { msAccumulator[ch] += newMS[ch] }
            if ch < shortTermMSAccumulator.count { shortTermMSAccumulator[ch] += newMS[ch] }
        }
        if totalCh <= levelBuffer.count { levelBuffer = newLevels }
        msFrameCount += frameCount
        shortTermFrameCount += frameCount
        if msFrameCount >= windowFrames {
            let scale = Double(msFrameCount - windowFrames) / Double(msFrameCount)
            for ch in 0..<msAccumulator.count { msAccumulator[ch] *= scale }
            msFrameCount = max(1, msFrameCount - windowFrames)
        }
        if shortTermFrameCount >= shortTermWindowFrames {
            let scale = Double(shortTermFrameCount - shortTermWindowFrames) / Double(shortTermFrameCount)
            for ch in 0..<shortTermMSAccumulator.count { shortTermMSAccumulator[ch] *= scale }
            shortTermFrameCount = max(1, shortTermFrameCount - shortTermWindowFrames)
        }
        bufferLock.unlock()
    }

    func stopMonitoring() {
        setMixListen(false)
        if monitorDeviceID != 0, let procID = ioProcID {
            AudioDeviceStop(monitorDeviceID, procID)
            AudioDeviceDestroyIOProcID(monitorDeviceID, procID)
            ioProcID = nil
            monitorDeviceID = 0
        }
        isMonitoring = false
        channelLevels = Array(repeating: 0, count: channelCount)
        peakLevels = Array(repeating: 0, count: channelCount)
        integratedLUFS = -60.0
        shortTermLUFS = -60.0
        truePeakDBTP = -120.0
        signalHealthSummary = "Monitor stopped."
        hasUsableSignal = false
    }

    // Enumerate macOS audio input devices via CoreAudio
    func refreshDevices() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize) == noErr else { return }
        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &deviceIDs) == noErr else { return }

        var found: [MixAssistAudioInputDevice] = []
        for deviceID in deviceIDs {
            // Check that the device has input channels
            var inputCfgAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamConfiguration,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            var cfgSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(deviceID, &inputCfgAddr, 0, nil, &cfgSize) == noErr, cfgSize > 0 else { continue }
            let rawPtr = UnsafeMutableRawPointer.allocate(byteCount: Int(cfgSize), alignment: MemoryLayout<AudioBufferList>.alignment)
            defer { rawPtr.deallocate() }
            guard AudioObjectGetPropertyData(deviceID, &inputCfgAddr, 0, nil, &cfgSize, rawPtr) == noErr else { continue }
            let bufList = rawPtr.load(as: AudioBufferList.self)
            guard bufList.mNumberBuffers > 0 else { continue }

            // Get UID
            var uidRef: CFString? = nil
            var uidSize = UInt32(MemoryLayout<CFString?>.size)
            var uidAddr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            AudioObjectGetPropertyData(deviceID, &uidAddr, 0, nil, &uidSize, &uidRef)
            let uid = (uidRef as String?) ?? "\(deviceID)"

            // Get name
            var nameRef: CFString? = nil
            var nameSize = UInt32(MemoryLayout<CFString?>.size)
            var nameAddr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceNameCFString, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            AudioObjectGetPropertyData(deviceID, &nameAddr, 0, nil, &nameSize, &nameRef)
            let name = (nameRef as String?) ?? "Device \(deviceID)"

            found.append(MixAssistAudioInputDevice(uid: uid, name: name))
        }

        availableDevices = found
        // Default to Dante Virtual Soundcard if no device explicitly selected
        if selectedDeviceUID == nil {
            selectedDeviceUID = found.first(where: { $0.name.localizedCaseInsensitiveContains("Dante") })?.uid
                ?? found.first?.uid
        }
    }

    // Counts input channels on a device by summing mNumberChannels across all input-scope stream buffers.
    private func hardwareInputChannelCount(for deviceID: AudioDeviceID) -> Int {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var sz: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &addr, 0, nil, &sz) == noErr, sz > 0 else { return 0 }
        let ptr = UnsafeMutableRawPointer.allocate(byteCount: Int(sz), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { ptr.deallocate() }
        guard AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &sz, ptr) == noErr else { return 0 }
        // UnsafeMutableAudioBufferListPointer handles the internal alignment of AudioBufferList correctly.
        let ablPtr = ptr.bindMemory(to: AudioBufferList.self, capacity: 1)
        return UnsafeMutableAudioBufferListPointer(ablPtr)
            .reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    // Enumerate all CoreAudio devices and return the ID of the one matching uid.
    // Avoids the CFString-qualifier trick in kAudioHardwarePropertyTranslateUIDToDevice,
    // which can silently fail due to Swift ARC / pointer-bridging issues.
    private func audioDeviceID(forUID uid: String) -> AudioDeviceID? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &dataSize) == noErr else { return nil }
        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &dataSize, &deviceIDs) == noErr else { return nil }

        for deviceID in deviceIDs {
            var uidRef: CFString? = nil
            var uidSize = UInt32(MemoryLayout<CFString?>.size)
            var uidAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceUID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectGetPropertyData(deviceID, &uidAddr, 0, nil, &uidSize, &uidRef)
            if let deviceUID = uidRef as String?, deviceUID == uid {
                return deviceID
            }
        }
        return nil
    }

    @Published private(set) var soloedChannel: Int? = nil

    // MARK: - Mix Listen (headphone monitor of the mix output pair)
    @Published private(set) var isMixListening: Bool = false
    private let listenCap = 16384   // must be power of 2
    nonisolated(unsafe) private var listenBufL: [Float] = Array(repeating: 0, count: 16384)
    nonisolated(unsafe) private var listenBufR: [Float] = Array(repeating: 0, count: 16384)
    nonisolated(unsafe) private var listenWritePos: Int = 0
    nonisolated(unsafe) private var listenReadPos: Int = 0
    nonisolated(unsafe) private var mixListenEnabled: Bool = false
    nonisolated(unsafe) private var mixListenChL: Int = 0
    nonisolated(unsafe) private var mixListenChR: Int = 1
    private var deviceSampleRate: Double = 48000
    private var listenEngine: AVAudioEngine?
    private var listenEngineConfigObserver: NSObjectProtocol?

    func setMixListen(_ on: Bool) {
        if on {
            guard let mixCh = mixMonitorChannel, isMonitoring else { return }
            mixListenChL = mixCh
            mixListenChR = min(mixCh + 1, channelCount - 1)
            listenWritePos = 0
            listenReadPos = 0
            startListenEngine()
            mixListenEnabled = true
            isMixListening = true
        } else {
            mixListenEnabled = false
            isMixListening = false
            teardownListenEngine()
        }
    }

    private func teardownListenEngine() {
        if let obs = listenEngineConfigObserver {
            NotificationCenter.default.removeObserver(obs)
            listenEngineConfigObserver = nil
        }
        listenEngine?.stop()
        listenEngine = nil
    }

    private func startListenEngine() {
        let rate = deviceSampleRate
        guard let fmt = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2) else { return }
        let cap = listenCap
        let engine = AVAudioEngine()
        let source = AVAudioSourceNode(format: fmt) { [weak self] _, _, frameCount, ablPtr in
            guard let self else { return noErr }
            let abl = UnsafeMutableAudioBufferListPointer(ablPtr)
            guard abl.count >= 2 else { return noErr }
            let n = Int(frameCount)
            let write = self.listenWritePos
            let read = self.listenReadPos
            let available = write - read
            let toRead = min(n, max(0, available))
            if let L = abl[0].mData?.bindMemory(to: Float.self, capacity: n),
               let R = abl[1].mData?.bindMemory(to: Float.self, capacity: n) {
                for i in 0..<toRead {
                    let idx = (read + i) & (cap - 1)
                    L[i] = self.listenBufL[idx]
                    R[i] = self.listenBufR[idx]
                }
                for i in toRead..<n { L[i] = 0; R[i] = 0 }
            }
            self.listenReadPos = read + toRead
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: fmt)
        engine.prepare()
        do {
            try engine.start()
            teardownListenEngine()   // clear any previous observer before storing new one
            listenEngine = engine
            // When the system output device changes, AVAudioEngine auto-stops and posts this
            // notification. Restart so the engine latches onto the new output device.
            listenEngineConfigObserver = NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange,
                object: engine,
                queue: .main
            ) { [weak self] _ in
                guard let self, self.isMixListening else { return }
                self.listenEngine = nil
                self.listenEngineConfigObserver = nil
                self.startListenEngine()
            }
        } catch {
            mixListenEnabled = false
            isMixListening = false
        }
    }

    func toggleChannel(_ index: Int) {
        if activeChannels.contains(index) {
            activeChannels.remove(index)
        } else {
            activeChannels.insert(index)
        }
    }

    func setSolo(_ channel: Int?) {
        soloedChannel = channel
    }

    private func scheduleUIUpdate() {
        guard isMonitoring else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self, self.isMonitoring else { return }
            self.bufferLock.lock()
            let lvl = self.levelBuffer
            let pk = self.peakBuffer
            let ms = self.msAccumulator
            let shortMS = self.shortTermMSAccumulator
            let frames = max(1, self.msFrameCount)
            let shortFrames = max(1, self.shortTermFrameCount)
            self.bufferLock.unlock()
            self.channelLevels = lvl
            self.peakLevels = pk
            self.channelShortTermRMS = shortMS.indices.map { ch in
                let ms = shortMS[ch] / Double(shortFrames)
                return ms > 0 ? Float(sqrt(ms)) : 0.0
            }
            // LUFS source: use the designated stereo mix output pair if set, else average active inputs
            let lufsChs: [Int]
            if let mixCh = self.mixMonitorChannel {
                // Use the L channel and R channel (mixCh+1) if both exist — BS.1770 stereo
                let r = mixCh + 1
                lufsChs = [mixCh, r].filter { $0 < ms.count }
            } else {
                lufsChs = self.activeChannels.filter { $0 < ms.count }.sorted()
            }
            if !lufsChs.isEmpty {
                let sumMS = lufsChs.reduce(Double(0)) { acc, ch in
                    acc + (ms[ch] / Double(frames))
                } / Double(lufsChs.count)
                let shortSumMS = lufsChs.reduce(Double(0)) { acc, ch in
                    acc + (shortMS[ch] / Double(shortFrames))
                } / Double(lufsChs.count)
                let peak = lufsChs.reduce(Double(0)) { acc, ch in
                    max(acc, ch < pk.count ? Double(pk[ch]) : 0)
                }
                self.integratedLUFS = sumMS > 0 ? (-0.691 + 10 * log10(sumMS)) : -60.0
                self.shortTermLUFS = shortSumMS > 0 ? (-0.691 + 10 * log10(shortSumMS)) : -60.0
                self.truePeakDBTP = peak > 0 ? 20 * log10(peak) : -120.0
                if self.integratedLUFS <= -55.0 && self.shortTermLUFS <= -55.0 {
                    self.hasUsableSignal = false
                    self.signalHealthSummary = "Waiting for usable mix signal."
                } else if self.truePeakDBTP >= -0.1 {
                    self.hasUsableSignal = false
                    self.signalHealthSummary = "Input is clipping. Auto-adjust paused."
                } else {
                    self.hasUsableSignal = true
                    self.signalHealthSummary = "Signal healthy."
                }
            }
            self.scheduleUIUpdate()
        }
    }
}

// MARK: - Engine

@MainActor
final class MixAssistEngine: ObservableObject {
    @Published private(set) var referenceProfiles: [MixAssistReferenceProfile] = []
    @Published private(set) var sceneBindings: [MixAssistSceneBinding] = []
    @Published private(set) var adapterDescriptors: [MixAssistAdapterDescriptor] = []
    @Published private(set) var transportHistory: [MixAssistTransportBatch] = []
    @Published private(set) var latestTransportBatch: MixAssistTransportBatch?
    @Published private(set) var persistenceSummary = "Local-only state not loaded yet."
    @Published private(set) var liveTransportSummary = "Live transport disarmed."
    @Published private(set) var isLiveControlArmed = false
    @Published private(set) var liveControlExpiresAt: Date?
    @Published private(set) var liveSendCount = 0
    @Published private(set) var midiDestinations: [MixAssistMIDIDestinationDescriptor] = []
    @Published private(set) var isListening: Bool = false
    @Published private(set) var isAutoAdjustRunning: Bool = false
    @Published private(set) var lastAutoAdjustSummary: String = ""
    @Published var selectedProfileID: String?
    @Published var selectedAdapterID: String?
    @Published var liveOSCSettings = MixAssistLiveOSCSettings()
    @Published var yamahaSettings = MixAssistYamahaControlSettings()
    @Published var routingMatrix = MixAssistRoutingMatrix()
    @Published var routingInputCount: Int = 32
    @Published private(set) var channelFaderPositions: [Int: Double] = [:]
    @Published var lockedDestinations: Set<Int> = []
    @Published var channelPriorities: [Int: MixAssistChannelPriority] = [:]
    @Published var itemPresets: [MixAssistItemPreset] = []
    @Published private(set) var activeItemPreset: MixAssistItemPreset?
    private var lastLiveItemID: String?
    private var savedAudioDeviceUID: String?   // staging until attachMonitor is called
    // Tracks absolute estimated fader level in dB per channel for OSC send
    private var channelFaderLevelsDB: [Int: Double] = [:]

    private weak var store: ProdConnectStore?
    private weak var audioMonitor: MixAssistAudioMonitor?
    private var loadedStorageScope: String?

    init() {
        // Load eagerly so the first SwiftUI render shows saved values, not defaults.
        // persistenceScope always returns "mix-assist-local" so store is not needed here.
        loadPersistedState(scope: "mix-assist-local")
        loadedStorageScope = "mix-assist-local"
    }

    private let transport = MixAssistSandboxTransport()
    private let liveTransport = MixAssistLiveOSCTransport()
    private let rcpTransport = MixAssistYamahaRCPTransport()
    private let rcpSession = MixAssistRCPSession()
    private let fileManager = FileManager.default
    private var liveDisarmWorkItem: DispatchWorkItem?
    private var autoAdjustTimer: Timer?
    private var autoAdjustSessionMovementDB: Double = 0
#if canImport(CoreMIDI)
    private let midiRuntime = MixAssistMIDIRuntime()
#endif

    var selectedProfile: MixAssistReferenceProfile? {
        referenceProfiles.first(where: { $0.id == selectedProfileID }) ?? referenceProfiles.first
    }

    var selectedAdapter: MixAssistAdapterDescriptor? {
        adapterDescriptors.first(where: { $0.id == selectedAdapterID }) ?? adapterDescriptors.first
    }

    func attach(store: ProdConnectStore) {
        self.store = store
        let scope = persistenceScope(for: store)
        if loadedStorageScope != scope {
            loadPersistedState(scope: scope)
            loadedStorageScope = scope
        }
        refreshMIDIDestinations()
        refreshBindings()
        if referenceProfiles.isEmpty {
            captureReferenceProfile(
                name: "",
                scope: .stream,
                sourceKind: .dante,
                controlKind: .osc
            )
        } else if selectedProfileID == nil {
            selectedProfileID = referenceProfiles.first?.id
        }
        refreshAdapters(preferredControlKind: selectedProfile?.controlKind ?? .osc)
    }

    func refreshMIDIDestinations() {
#if canImport(CoreMIDI)
        midiDestinations = midiRuntime.destinations
        if yamahaSettings.selectedMIDIDestinationID == nil {
            yamahaSettings.selectedMIDIDestinationID = midiDestinations.first?.id
        }
#else
        midiDestinations = []
#endif
    }

    func startListen(
        name: String,
        scope: MixAssistReferenceScope,
        sourceKind: MixAssistSourceKind,
        controlKind: MixAssistControlKind
    ) {
        isListening = true
        captureReferenceProfile(name: name, scope: scope, sourceKind: sourceKind, controlKind: controlKind)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.isListening = false
        }
    }

    func captureReferenceProfile(
        name: String,
        scope: MixAssistReferenceScope,
        sourceKind: MixAssistSourceKind,
        controlKind: MixAssistControlKind
    ) {
        guard let store else { return }
        let scene = currentSceneContext(in: store)
        let patchRows = relevantPatchRows(in: store)
        let patchIDs = patchRows.prefix(scope == .channel ? 1 : 8).map(\.id)
        let profileName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? defaultProfileName(for: scene)
            : name.trimmingCharacters(in: .whitespacesAndNewlines)

        let baseline = baselineMetrics(for: scene, patchRows: Array(patchRows))
        let profile = MixAssistReferenceProfile(
            name: profileName,
            scope: scope,
            sourceKind: sourceKind,
            controlKind: controlKind,
            notes: "Captured from Mix Assist simulation shell.",
            runOfShowID: scene.show?.id,
            runOfShowItemID: scene.item?.id,
            patchRowIDs: patchIDs,
            targetIntegratedLUFS: baseline.integratedLUFS,
            targetSpectralCentroid: baseline.spectralCentroid,
            targetDynamicRange: baseline.dynamicRange,
            targetStereoSpread: baseline.stereoSpread,
            createdAt: Date(),
            updatedAt: Date()
        )

        referenceProfiles.insert(profile, at: 0)
        selectedProfileID = profile.id

        let binding = MixAssistSceneBinding(
            profileID: profile.id,
            runOfShowID: scene.show?.id,
            runOfShowItemID: scene.item?.id,
            patchRowIDs: patchIDs,
            sceneName: scene.label,
            notes: "Auto-generated from current ProdConnect context.",
            createdAt: Date()
        )
        upsertBinding(binding)
        refreshAdapters(preferredControlKind: controlKind)
        savePersistedState()
    }

    func updateLiveOSCHost(_ host: String) {
        liveOSCSettings.host = host
        savePersistedState()
    }

    func updateLiveOSCPort(_ port: String) {
        liveOSCSettings.port = port
        savePersistedState()
    }

    func updateLiveOSCArmWindow(_ seconds: Double) {
        liveOSCSettings.autoDisarmSeconds = seconds
        if isLiveControlArmed {
            armLiveControl()
        } else {
            savePersistedState()
        }
    }

    func updateConsoleManufacturer(_ manufacturer: MixAssistConsoleManufacturer, model: MixAssistConsoleModel) {
        yamahaSettings.manufacturer = manufacturer
        updateYamahaModel(model)
    }

    func updateYamahaModel(_ model: MixAssistConsoleModel) {
        yamahaSettings.model = model
        // Pre-fill default IP if the current address is still the factory default or blank
        let currentIP = yamahaSettings.consoleIPAddress
        if currentIP.isEmpty || currentIP == "192.168.0.128" || currentIP == "127.0.0.1" {
            yamahaSettings.consoleIPAddress = model.defaultIP
        }
        liveOSCSettings.host = yamahaSettings.consoleIPAddress
        liveOSCSettings.port = String(model.defaultPort)
        selectedAdapterID = model.usesRCP ? "yamaha-rcp" : (model == .yamahaDM7 ? "yamaha-dm7" : "generic-osc")
        refreshAdapters(preferredControlKind: model.usesRCP ? .vendor : .osc)
        savePersistedState()
    }

    func updateYamahaConsoleIPAddress(_ host: String) {
        yamahaSettings.consoleIPAddress = host
        if yamahaSettings.model.requiresIPAddress {
            liveOSCSettings.host = host
        }
        savePersistedState()
    }

    func updateYamahaMIDIDestinationID(_ id: String) {
        yamahaSettings.selectedMIDIDestinationID = id.isEmpty ? nil : id
        savePersistedState()
    }

    func updateYamahaMIDIChannel(_ channel: Int) {
        yamahaSettings.midiChannel = min(max(channel, 1), 16)
        savePersistedState()
    }

    func updateYamahaFaderCCBase(_ cc: Int) {
        yamahaSettings.faderCCBase = min(max(cc, 0), 127)
        savePersistedState()
    }

    func armLiveControl() {
        let window = max(10, liveOSCSettings.autoDisarmSeconds)
        let expiresAt = Date().addingTimeInterval(window)
        isLiveControlArmed = true
        liveControlExpiresAt = expiresAt
        liveTransportSummary = "Live control armed until \(expiresAt.formatted(date: .omitted, time: .standard))."
        liveDisarmWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.disarmLiveControl(reason: "Arm window expired.")
            }
        }
        liveDisarmWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + window, execute: workItem)
    }

    func disarmLiveControl(reason: String = "Live control disarmed.") {
        // Only stop auto-adjust on an explicit user disarm, not an expiry —
        // autoAdjustTick keeps re-arming while running.
        if !isAutoAdjustRunning {
            stopAutoAdjust()
        }
        isLiveControlArmed = false
        liveControlExpiresAt = nil
        liveDisarmWorkItem?.cancel()
        liveDisarmWorkItem = nil
        liveTransportSummary = reason
    }

    func saveSelectedAudioDevice(_ uid: String?) {
        savedAudioDeviceUID = uid
        savePersistedState()
    }

    func attachMonitor(_ monitor: MixAssistAudioMonitor) {
        audioMonitor = monitor
        monitor.mixMonitorChannel = yamahaSettings.mixOutputDanteChannel.map { $0 - 1 }
        if let uid = savedAudioDeviceUID {
            monitor.selectedDeviceUID = uid
        }
    }

    func startAutoAdjust() {
        guard !isAutoAdjustRunning else { return }
        armLiveControl()
        isAutoAdjustRunning = true
        yamahaSettings.autoAdjustEnabled = true
        autoAdjustSessionMovementDB = 0
        if let monitor = audioMonitor {
            for ch in 0..<monitor.channelCount {
                if channelFaderPositions[ch] == nil { channelFaderPositions[ch] = 0.75 }
                if channelFaderLevelsDB[ch] == nil   { channelFaderLevelsDB[ch] = 0.0 }
            }
        }
        if yamahaSettings.model.usesRCP {
            let host = yamahaSettings.consoleIPAddress.trimmingCharacters(in: .whitespacesAndNewlines)
            if !host.isEmpty {
                rcpSession.onDisconnect = { [weak self] msg in
                    DispatchQueue.main.async { self?.lastAutoAdjustSummary = msg }
                }
                rcpSession.ensureConnected(host: host, port: yamahaSettings.model.defaultPort)
            }
        }
        scheduleAutoAdjustTimer()
        lastAutoAdjustSummary = "Auto adjust started."
        savePersistedState()
    }

    func stopAutoAdjust() {
        guard isAutoAdjustRunning else { return }
        isAutoAdjustRunning = false
        yamahaSettings.autoAdjustEnabled = false
        autoAdjustTimer?.invalidate()
        autoAdjustTimer = nil
        autoAdjustSessionMovementDB = 0
        if yamahaSettings.model.usesRCP {
            rcpSession.disconnect()
        }
        lastAutoAdjustSummary = "Auto adjust stopped."
        savePersistedState()
    }

    func updateTargetOutputLUFS(_ lufs: Double) {
        yamahaSettings.targetOutputPreset = .custom
        yamahaSettings.targetOutputLUFS = lufs
        savePersistedState()
    }

    func updateTargetOutputPreset(_ preset: MixAssistTargetOutputPreset) {
        yamahaSettings.targetOutputPreset = preset
        if preset != .custom {
            yamahaSettings.targetOutputLUFS = preset.defaultLUFS
            yamahaSettings.truePeakCeilingDBTP = preset.defaultTruePeakDBTP
        }
        savePersistedState()
    }

    func updateCustomTargetOutputLUFS(_ lufs: Double) {
        yamahaSettings.targetOutputPreset = .custom
        yamahaSettings.targetOutputLUFS = max(-32.0, min(-6.0, lufs))
        savePersistedState()
    }

    func updateTruePeakCeiling(_ dbtp: Double) {
        yamahaSettings.truePeakCeilingDBTP = max(-12.0, min(0.0, dbtp))
        savePersistedState()
    }

    func updateAutoAdjustSessionLimit(_ db: Double) {
        yamahaSettings.autoAdjustSessionLimitDB = max(0.5, min(12.0, db))
        savePersistedState()
    }

    // channel is 1-indexed (as shown in UI); nil clears the setting
    func updateMixOutputChannel(_ channel: Int?) {
        yamahaSettings.mixOutputDanteChannel = channel
        audioMonitor?.mixMonitorChannel = channel.map { $0 - 1 }
        savePersistedState()
    }

    func updateTargetBusType(_ busType: MixAssistConsoleBusType) {
        yamahaSettings.targetBusType = busType
        savePersistedState()
    }

    func updateTargetBusNumber(_ number: Int) {
        yamahaSettings.targetBusNumber = max(1, number)
        savePersistedState()
    }

    // Captures the current audio level of every active channel as the per-channel
    // reference target. Auto-adjust will drive each fader independently toward these
    // levels instead of using the global LUFS approach.
    func captureTargetMix() {
        guard let monitor = audioMonitor, monitor.isMonitoring else { return }
        // Exclude the LUFS mix-output pair — those are the console's mix return,
        // not individual input channels, so they must not receive fader commands.
        let lufsExcluded: Set<Int> = {
            guard let lufsCh = monitor.mixMonitorChannel else { return [] }
            return [lufsCh, lufsCh + 1]
        }()
        var captured: [String: Double] = [:]
        for ch in monitor.activeChannels {
            guard !lufsExcluded.contains(ch) else { continue }
            guard ch < monitor.channelShortTermRMS.count else { continue }
            let rms = Double(monitor.channelShortTermRMS[ch])
            // Only capture channels with meaningful signal — skip noise floor (< -50 dBFS)
            guard rms > 0.003 else { continue }
            captured[String(ch)] = 20.0 * log10(rms)
        }
        guard !captured.isEmpty else { return }
        yamahaSettings.targetChannelLevelsDB = captured
        // Reset fader tracker so per-channel mode starts from 0 dB (unity),
        // not from whatever LUFS mode accumulated.
        channelFaderLevelsDB = [:]
        autoAdjustSessionMovementDB = 0
        savePersistedState()
    }

    func clearTargetMix() {
        yamahaSettings.targetChannelLevelsDB = [:]
        savePersistedState()
    }

    var capturedTargetChannelCount: Int { yamahaSettings.targetChannelLevelsDB.count }

    // Nudges CH1 to -3 dB for 2 seconds then restores to 0 dB.
    // Uses the persistent session — no new TCP connections opened.
    func sendRCPConnectionTest() {
        let host = yamahaSettings.consoleIPAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else {
            lastAutoAdjustSummary = "RCP test failed: no console IP set."
            return
        }
        let port = yamahaSettings.model.defaultPort
        rcpSession.ensureConnected(host: host, port: port)
        lastAutoAdjustSummary = "RCP nudge: CH1 → -3 dB for 2 sec then back to 0. Watch the fader…"
        rcpSession.send(payload: "set MIXER:Current/InCh/Fader/Level 0 0 -300\n")
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.rcpSession.send(payload: "set MIXER:Current/InCh/Fader/Level 0 0 0\n")
            DispatchQueue.main.async {
                self?.lastAutoAdjustSummary = "RCP nudge done → \(host):\(port). Did CH1 dip -3 dB and return?"
            }
        }
    }

    func toggleRoute(input: Int, destinationID: String) {
        routingMatrix.toggleExclusiveDest(input: input, destinationID: destinationID)
        savePersistedState()
    }

    func clearInputRoutes(_ input: Int) {
        routingMatrix.clearInput(input)
        savePersistedState()
    }

    func clearDestinationRoutes(_ destinationID: String) {
        routingMatrix.clearDestination(destinationID)
        savePersistedState()
    }

    func clearAllRoutes() {
        routingMatrix.clearAll()
        savePersistedState()
    }

    func toggleDestinationLock(_ destIdx: Int) {
        if lockedDestinations.contains(destIdx) {
            lockedDestinations.remove(destIdx)
        } else {
            lockedDestinations.insert(destIdx)
        }
        savePersistedState()
    }

    func priority(forChannel index: Int) -> MixAssistChannelPriority {
        channelPriorities[index] ?? .normal
    }

    func updateChannelPriority(_ index: Int, priority: MixAssistChannelPriority) {
        if priority == .normal {
            channelPriorities.removeValue(forKey: index)
        } else {
            channelPriorities[index] = priority
        }
        savePersistedState()
    }

    // MARK: - RoS Item Presets

    func captureItemPreset(for item: RunOfShowItem, destinationCount: Int) {
        var levels: [String: Double] = [:]
        for i in 0..<destinationCount {
            levels[String(i)] = channelFaderLevelsDB[i] ?? 0.0
        }
        let preset = MixAssistItemPreset(
            rosItemID: item.id,
            rosItemTitle: item.title,
            destinationLevelsDB: levels,
            targetOutputPreset: yamahaSettings.targetOutputPreset,
            targetOutputLUFS: yamahaSettings.targetOutputLUFS,
            truePeakCeilingDBTP: yamahaSettings.truePeakCeilingDBTP,
            autoAdjustSessionLimitDB: yamahaSettings.autoAdjustSessionLimitDB,
            channelPriorities: Dictionary(uniqueKeysWithValues: channelPriorities.map { (String($0.key), $0.value) })
        )
        itemPresets.removeAll { $0.rosItemID == item.id }
        itemPresets.append(preset)
        savePersistedState()
    }

    func deleteItemPreset(for rosItemID: String) {
        itemPresets.removeAll { $0.rosItemID == rosItemID }
        if activeItemPreset?.rosItemID == rosItemID { activeItemPreset = nil }
        savePersistedState()
    }

    func selectItemPreset(for rosItemID: String) {
        guard let preset = itemPresets.first(where: { $0.rosItemID == rosItemID }) else { return }
        activeItemPreset = preset
        applyItemPreset(preset)
    }

    func handleLiveItemChange(itemID: String?, show: RunOfShowDocument?) {
        guard itemID != lastLiveItemID else { return }
        lastLiveItemID = itemID
        guard let itemID else {
            activeItemPreset = nil
            return
        }
        guard let preset = itemPresets.first(where: { $0.rosItemID == itemID }) else {
            activeItemPreset = nil
            return
        }
        activeItemPreset = preset
        applyItemPreset(preset)
    }

    private func applyItemPreset(_ preset: MixAssistItemPreset) {
        applyStoredTargets(from: preset)

        let host = yamahaSettings.consoleIPAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isLiveControlArmed || isAutoAdjustRunning else { return }

        if yamahaSettings.model.usesRCP {
            let commands = yamahaRCPCommands(destinationLevelsDB: preset.destinationLevelsDB)
            guard !commands.isEmpty else { return }
            _ = try? rcpTransport.dispatchLive(
                commands: commands,
                host: host,
                port: yamahaSettings.model.defaultPort,
                sceneName: preset.rosItemTitle
            )
            return
        }

        guard !host.isEmpty else { return }

        let busType   = yamahaSettings.targetBusType
        let busNumber = max(1, yamahaSettings.targetBusNumber)
        let commands: [MixAssistTransportCommand] = preset.destinationLevelsDB.compactMap { key, levelDB in
            guard let destIdx = Int(key) else { return nil }
            let chNum = destIdx + 1
            let address = consoleOSCAddress(
                channel: chNum, manufacturer: yamahaSettings.model.manufacturer,
                model: yamahaSettings.model, busType: busType, busNumber: busNumber
            )
            let valueStr: String

            switch yamahaSettings.model.manufacturer {
            case .yamaha:
                let clamped = max(-138.0, min(10.0, levelDB))
                valueStr = String(Int(clamped * 100.0))
            case .allenHeath, .behringer, .daw:
                let clamped = max(-90.0, min(10.0, levelDB))
                let f = Float(max(0, min(1, (clamped + 90.0) / 100.0)))
                valueStr = String(format: "%.4f", f)
            }

            // Update local tracking so auto-adjust continues from preset baseline
            channelFaderLevelsDB[destIdx] = levelDB
            let normalised = (levelDB + 90.0) / 100.0
            channelFaderPositions[destIdx] = max(0, min(1.0, normalised))

            return MixAssistTransportCommand(
                adapterID: "item-preset",
                patchRowName: "CH \(chNum)",
                commandText: "\(preset.rosItemTitle) preset → CH \(chNum): \(String(format: "%.1f", levelDB)) dB",
                address: address,
                valueSummary: valueStr,
                safetyNote: "RoS item preset transition."
            )
        }

        guard !commands.isEmpty else { return }
        var oscSettings = liveOSCSettings
        oscSettings.host = host
        oscSettings.port = String(yamahaSettings.model.defaultPort)
        let adapter = MixAssistAdapterDescriptor(
            id: "item-preset", name: yamahaSettings.model.rawValue,
            controlKind: .osc, endpointSummary: "\(host):\(oscSettings.port)", stateSummary: "Item Preset"
        )
        _ = try? liveTransport.dispatchLive(
            commands: commands, through: adapter,
            settings: oscSettings, sceneName: preset.rosItemTitle
        )
        liveSendCount += commands.count
    }

    private func applyStoredTargets(from preset: MixAssistItemPreset) {
        yamahaSettings.targetOutputPreset = preset.targetOutputPreset
        yamahaSettings.targetOutputLUFS = preset.targetOutputLUFS
        yamahaSettings.truePeakCeilingDBTP = preset.truePeakCeilingDBTP
        yamahaSettings.autoAdjustSessionLimitDB = preset.autoAdjustSessionLimitDB
        channelPriorities = Dictionary(
            uniqueKeysWithValues: preset.channelPriorities.compactMap { key, priority in
                guard let channel = Int(key) else { return nil }
                return (channel, priority)
            }
        )
        lastAutoAdjustSummary = "\(preset.rosItemTitle) targets loaded: \(preset.targetSummary)."
        savePersistedState()
    }

    func updateMasterFaderCC(_ cc: Int) {
        yamahaSettings.masterFaderCC = min(127, max(0, cc))
        savePersistedState()
    }

    func updateAutoAdjustInterval(_ seconds: Double) {
        yamahaSettings.autoAdjustIntervalSeconds = max(0.5, seconds)
        if isAutoAdjustRunning {
            scheduleAutoAdjustTimer()
        }
        savePersistedState()
    }

    private func scheduleAutoAdjustTimer() {
        autoAdjustTimer?.invalidate()
        let interval = max(0.5, yamahaSettings.autoAdjustIntervalSeconds)
        autoAdjustTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.autoAdjustTick() }
        }
    }

    private func autoAdjustTick() {
        guard isAutoAdjustRunning else { return }

        // Keep the arm window fresh on every tick so it never expires while running
        armLiveControl()

        let host = yamahaSettings.consoleIPAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else {
            lastAutoAdjustSummary = "No console IP set. Configure it in Settings → Console Control."
            return
        }

        guard let monitor = audioMonitor, monitor.isMonitoring else {
            lastAutoAdjustSummary = "Audio monitor not running. Tap Monitor in the Operator panel."
            return
        }

        guard monitor.hasUsableSignal else {
            lastAutoAdjustSummary = monitor.signalHealthSummary
            return
        }

        let truePeakExceeded = monitor.truePeakDBTP > yamahaSettings.truePeakCeilingDBTP
        if truePeakExceeded {
            lastAutoAdjustSummary = String(
                format: "True peak %.1f dBTP exceeds %.1f dBTP ceiling. Lowering mix carefully.",
                monitor.truePeakDBTP, yamahaSettings.truePeakCeilingDBTP
            )
        }

        let deadband = yamahaSettings.autoAdjustDeadbandLUFS
        let maxDelta = yamahaSettings.autoAdjustMaxDeltaDB
        let activeChs = Array(monitor.activeChannels).sorted()
            .filter { !lockedDestinations.contains($0) }

        let channelDeltas: [Int: Double]
        let hasReference = !yamahaSettings.targetChannelLevelsDB.isEmpty

        if hasReference {
            // Per-channel mode: drive each fader independently toward its captured reference level.
            // Exclude the LUFS mix-output pair — those monitor the master bus, not input faders.
            let lufsExcluded: Set<Int> = {
                guard let lufsCh = monitor.mixMonitorChannel else { return [] }
                return [lufsCh, lufsCh + 1]
            }()
            var deltas: [Int: Double] = [:]
            for ch in activeChs {
                guard !lufsExcluded.contains(ch) else { continue }
                guard let targetDB = yamahaSettings.targetChannelLevelsDB[String(ch)],
                      ch < monitor.channelShortTermRMS.count else { continue }
                let rms = Double(monitor.channelShortTermRMS[ch])
                guard rms > 1e-6 else { continue }
                let currentDB = 20.0 * log10(rms)
                // Skip channels more than 15 dB below their reference — they're likely quiet/off.
                // Chasing a low-signal channel's RMS would push the fader up unnecessarily.
                guard currentDB > targetDB - 15.0 else { continue }
                var d = targetDB - currentDB
                if truePeakExceeded { d = min(d, -maxDelta) }
                guard abs(d) > deadband else { continue }
                deltas[ch] = max(-maxDelta, min(maxDelta, d))
            }
            channelDeltas = deltas
            if channelDeltas.isEmpty && !truePeakExceeded {
                let chs = yamahaSettings.targetChannelLevelsDB.keys
                    .compactMap { Int($0) }.sorted().map { "CH\($0 + 1)" }.joined(separator: ",")
                lastAutoAdjustSummary = "Ref mix holding — all within \(String(format: "%.1f", deadband)) dB. Refs: \(chs)"
                return
            }
        } else {
            // Global LUFS mode — single delta applied to all channels proportionally.
            let measuredLUFS = monitor.integratedLUFS
            let targetLUFS = yamahaSettings.targetOutputLUFS
            let delta = targetLUFS - measuredLUFS

            guard abs(delta) > deadband || truePeakExceeded else {
                lastAutoAdjustSummary = String(
                    format: "Holding: %.1f LUFS is on target %.1f.",
                    measuredLUFS, targetLUFS
                )
                return
            }

            var clampedDelta = max(-maxDelta, min(maxDelta, delta))
            if truePeakExceeded { clampedDelta = min(clampedDelta, -maxDelta) }

            let sessionLimit = max(0.5, yamahaSettings.autoAdjustSessionLimitDB)
            let projectedMovement = autoAdjustSessionMovementDB + clampedDelta
            if abs(projectedMovement) > sessionLimit {
                let remaining = sessionLimit - abs(autoAdjustSessionMovementDB)
                guard remaining > 0.01 else {
                    lastAutoAdjustSummary = String(
                        format: "Safety limit reached: %.1f dB session movement. Auto-adjust holding.",
                        sessionLimit
                    )
                    return
                }
                clampedDelta = (clampedDelta >= 0 ? 1 : -1) * min(abs(clampedDelta), remaining)
            }
            channelDeltas = weightedAutoAdjustDeltas(baseDelta: clampedDelta, channels: activeChs)
        }

        // Update per-channel UI fader positions (subtle motion), skipping locked destinations
        for (ch, channelDelta) in channelDeltas {
            let normalizedMove = channelDelta / 20.0
            let current = channelFaderPositions[ch] ?? 0.75
            channelFaderPositions[ch] = max(0, min(1.0, current + normalizedMove))
        }

        // Build live console commands, excluding locked destinations
        var oscSettings = liveOSCSettings
        oscSettings.host = host
        oscSettings.port = String(yamahaSettings.model.defaultPort)

        if yamahaSettings.model.usesRCP {
            let commands = yamahaRCPCommands(channelDeltas: channelDeltas)
            guard !commands.isEmpty else {
                lastAutoAdjustSummary = "No RCP commands generated for \(yamahaSettings.model.rawValue)."
                return
            }
            // Use the persistent session — one connection for the lifetime of auto-adjust.
            // This prevents connection churn that exhaust the QL5's max-connections limit.
            rcpSession.ensureConnected(host: host, port: yamahaSettings.model.defaultPort)
            let payload = commands.map(\.address).joined(separator: "\n") + "\n"
            rcpSession.send(payload: payload)
            liveSendCount += commands.count
            let avgSignedDelta = channelDeltas.values.reduce(0, +) / Double(max(1, channelDeltas.count))
            autoAdjustSessionMovementDB += avgSignedDelta
            if hasReference {
                let chs = channelDeltas.keys.sorted().map { "CH\($0 + 1)" }.joined(separator: ",")
                lastAutoAdjustSummary = String(format: "Ref: %@ · avg %+.2f dB", chs, avgSignedDelta)
            } else {
                lastAutoAdjustSummary = String(format: "RCP %d ch · session %+.1f / %.1f dB.",
                         commands.count, autoAdjustSessionMovementDB,
                         yamahaSettings.autoAdjustSessionLimitDB)
            }
            return
        }

        let commands = consoleChannelAdjustOSCCommands(channelDeltas: channelDeltas)
        guard !commands.isEmpty else {
            lastAutoAdjustSummary = "No OSC commands generated for \(yamahaSettings.model.rawValue)."
            return
        }

        let adapterDesc = MixAssistAdapterDescriptor(
            id: "auto-adjust",
            name: yamahaSettings.model.rawValue,
            controlKind: .osc,
            endpointSummary: "\(host):\(yamahaSettings.model.defaultPort)",
            stateSummary: "Auto Adjust"
        )

        do {
            _ = try liveTransport.dispatchLive(
                commands: commands,
                through: adapterDesc,
                settings: oscSettings,
                sceneName: activeSceneName
            )
            liveSendCount += commands.count
            let avgSignedDeltaOSC = channelDeltas.values.reduce(0, +) / Double(max(1, channelDeltas.count))
            autoAdjustSessionMovementDB += avgSignedDeltaOSC
            if hasReference {
                let chs = channelDeltas.keys.sorted().map { "CH\($0 + 1)" }.joined(separator: ",")
                lastAutoAdjustSummary = String(format: "Ref: %@ · avg %+.2f dB", chs, avgSignedDeltaOSC)
            } else {
                lastAutoAdjustSummary = String(format: "OSC %d ch · session %+.1f / %.1f dB.",
                         commands.count, autoAdjustSessionMovementDB,
                         yamahaSettings.autoAdjustSessionLimitDB)
            }
        } catch {
            lastAutoAdjustSummary = "OSC send failed: \(error.localizedDescription)"
        }
    }

    // Returns the OSC address for a given channel and bus targeting configuration.
    private func consoleOSCAddress(
        channel chNum: Int,
        manufacturer: MixAssistConsoleManufacturer,
        model: MixAssistConsoleModel,
        busType: MixAssistConsoleBusType,
        busNumber: Int
    ) -> String {
        switch manufacturer {
        case .yamaha:
            switch busType {
            case .inputChannel: return "/yosc:req/set/MIXER:Current/InCh/Fader/Level/\(chNum)/1"
            case .mixBusSend:   return "/yosc:req/set/MIXER:Current/InCh/MixSend/Level/\(chNum)/\(busNumber)"
            case .matrixSend:   return "/yosc:req/set/MIXER:Current/InCh/MatSend/Level/\(chNum)/\(busNumber)"
            }
        case .allenHeath:
            switch busType {
            case .inputChannel: return "/ch/\(chNum)/mix/fader"
            case .mixBusSend:   return "/ch/\(chNum)/send/\(busNumber)/level"
            case .matrixSend:   return "/ch/\(chNum)/matrix/\(busNumber)/level"
            }
        case .behringer:
            let pad = model == .behringerX32
            switch busType {
            case .inputChannel:
                return pad ? "/ch/\(String(format: "%02d", chNum))/mix/fader" : "/ch/\(chNum)/fader"
            case .mixBusSend:
                return pad
                    ? "/ch/\(String(format: "%02d", chNum))/mix/\(String(format: "%02d", busNumber))/level"
                    : "/ch/\(chNum)/send/\(busNumber)/level"
            case .matrixSend:
                return pad
                    ? "/ch/\(String(format: "%02d", chNum))/mtx/\(String(format: "%02d", busNumber))/fader"
                    : "/ch/\(chNum)/matrix/\(busNumber)/level"
            }
        case .daw:
            if model == .dawReaper {
                // Reaper Default.ReaperOSC schema — /volume/db accepts a plain dB float
                switch busType {
                case .inputChannel: return "/track/\(chNum)/volume/db"
                case .mixBusSend:   return "/track/\(chNum)/send/\(busNumber)/volume/db"
                case .matrixSend:   return "/track/\(chNum)/send/\(busNumber)/volume/db"
                }
            } else {
                // Generic DAW OSC — compatible with most DAW OSC bridge plugins
                switch busType {
                case .inputChannel: return "/mix/ch/\(chNum)/fader"
                case .mixBusSend:   return "/mix/ch/\(chNum)/aux/\(busNumber)/send"
                case .matrixSend:   return "/mix/ch/\(chNum)/bus/\(busNumber)/send"
                }
            }
        }
    }

    private func weightedAutoAdjustDeltas(baseDelta: Double, channels: [Int]) -> [Int: Double] {
        Dictionary(uniqueKeysWithValues: channels.map { ch in
            let priority = priority(forChannel: ch)
            let scale = baseDelta >= 0 ? priority.boostScale : priority.cutScale
            return (ch, baseDelta * scale)
        })
    }

    private func yamahaRCPCommands(channelDeltas: [Int: Double]) -> [MixAssistTransportCommand] {
        channelDeltas.keys.sorted().map { ch in
            let delta = channelDeltas[ch] ?? 0
            let current = channelFaderLevelsDB[ch] ?? 0.0
            let newLevelDB = max(-138.0, min(10.0, current + delta))
            channelFaderLevelsDB[ch] = newLevelDB
            return yamahaRCPCommand(channel: ch, levelDB: newLevelDB, deltaDescription: String(format: "%+.2f dB", delta))
        }
    }

    private func yamahaRCPCommands(destinationLevelsDB: [String: Double]) -> [MixAssistTransportCommand] {
        destinationLevelsDB.keys.sorted { (Int($0) ?? 0) < (Int($1) ?? 0) }.compactMap { key in
            guard let ch = Int(key), let levelDB = destinationLevelsDB[key] else { return nil }
            let clamped = max(-138.0, min(10.0, levelDB))
            channelFaderLevelsDB[ch] = clamped
            let normalised = (clamped + 90.0) / 100.0
            channelFaderPositions[ch] = max(0, min(1.0, normalised))
            return yamahaRCPCommand(channel: ch, levelDB: clamped, deltaDescription: "stored level")
        }
    }

    private func yamahaRCPCommand(channel ch: Int, levelDB: Double, deltaDescription: String) -> MixAssistTransportCommand {
        let value = Int((levelDB * 100.0).rounded())
        let command = yamahaRCPSetCommand(channel: ch, value: value)
        return MixAssistTransportCommand(
            adapterID: "yamaha-rcp",
            patchRowName: "CH \(ch + 1)",
            commandText: "\(yamahaSettings.model.rawValue) RCP CH \(ch + 1): \(deltaDescription) -> \(String(format: "%.1f", levelDB)) dB",
            address: command,
            valueSummary: String(value),
            safetyNote: "Yamaha RCP direct network fader control."
        )
    }

    private func yamahaRCPSetCommand(channel ch: Int, value: Int) -> String {
        let busType = yamahaSettings.targetBusType
        let busNumber = max(1, yamahaSettings.targetBusNumber)
        switch busType {
        case .inputChannel:
            return "set MIXER:Current/InCh/Fader/Level \(ch) 0 \(value)"
        case .mixBusSend:
            return "set MIXER:Current/InCh/ToMix/Level \(ch) \(busNumber - 1) \(value)"
        case .matrixSend:
            return "set MIXER:Current/InCh/ToMtrx/Level \(ch) \(busNumber - 1) \(value)"
        }
    }

    // Generates per-channel absolute fader OSC commands using console-specific paths and encoding.
    private func consoleChannelAdjustOSCCommands(channelDeltas: [Int: Double]) -> [MixAssistTransportCommand] {
        let busType   = yamahaSettings.targetBusType
        let busNumber = max(1, yamahaSettings.targetBusNumber)
        return channelDeltas.keys.sorted().compactMap { ch in
            guard let delta = channelDeltas[ch] else { return nil }
            let chNum = ch + 1
            let current = channelFaderLevelsDB[ch] ?? 0.0
            let newLevelDB: Double
            let address: String
            let valueStr: String

            switch yamahaSettings.model.manufacturer {
            case .yamaha:
                newLevelDB = max(-18.0, min(10.0, current + delta))
                address = consoleOSCAddress(channel: chNum, manufacturer: .yamaha,
                                            model: yamahaSettings.model, busType: busType, busNumber: busNumber)
                // Yamaha OSC encodes fader levels as integers in 0.01 dB steps (0 = 0 dB)
                valueStr = String(Int(newLevelDB * 100.0))

            case .allenHeath:
                newLevelDB = max(-90.0, min(10.0, current + delta))
                address = consoleOSCAddress(channel: chNum, manufacturer: .allenHeath,
                                            model: yamahaSettings.model, busType: busType, busNumber: busNumber)
                // A&H OSC: 0.0–1.0 float; rough mapping treats -90→0.0, 0 dB→0.75, +10→1.0
                let f = Float(max(0, min(1, (newLevelDB + 90.0) / 100.0)))
                valueStr = String(format: "%.4f", f)

            case .behringer:
                newLevelDB = max(-90.0, min(10.0, current + delta))
                address = consoleOSCAddress(channel: chNum, manufacturer: yamahaSettings.model.manufacturer,
                                            model: yamahaSettings.model, busType: busType, busNumber: busNumber)
                let f = Float(max(0, min(1, (newLevelDB + 90.0) / 100.0)))
                valueStr = String(format: "%.4f", f)

            case .daw:
                newLevelDB = max(-90.0, min(10.0, current + delta))
                address = consoleOSCAddress(channel: chNum, manufacturer: .daw,
                                            model: yamahaSettings.model, busType: busType, busNumber: busNumber)
                if yamahaSettings.model == .dawReaper {
                    // /volume/db path takes a plain dB float — no curve conversion needed
                    valueStr = String(format: "%.2f", newLevelDB)
                } else {
                    let f = Float(max(0, min(1, (newLevelDB + 90.0) / 100.0)))
                    valueStr = String(format: "%.4f", f)
                }
            }

            channelFaderLevelsDB[ch] = newLevelDB

            return MixAssistTransportCommand(
                adapterID: "auto-adjust",
                patchRowName: "CH \(chNum)",
                commandText: "\(yamahaSettings.model.rawValue) CH \(chNum): \(String(format: "%+.2f", delta)) dB → \(String(format: "%.2f", newLevelDB)) dB",
                address: address,
                valueSummary: valueStr,
                safetyNote: "Auto-adjust: small transparent step."
            )
        }
    }

    func sendLiveOSCPreview() {
        guard isLiveControlArmed else {
            liveTransportSummary = "Live OSC is locked. Arm the transport before sending."
            return
        }
        guard let profile = selectedProfile,
              let adapter = selectedAdapter,
              let adapterImplementation = adapterImplementation(for: adapter.id) else {
            liveTransportSummary = "Select a profile and adapter before sending live OSC."
            return
        }
        let binding = sceneBindings.first(where: { $0.profileID == profile.id })
        let commands = adapterImplementation.makeCommands(
            recommendations: [],
            profile: profile,
            binding: binding
        )

        do {
            let batch = try liveTransport.dispatchLive(
                commands: commands,
                through: adapter,
                settings: liveOSCSettings,
                sceneName: binding?.sceneName ?? "Unscoped Scene"
            )
            latestTransportBatch = batch
            transportHistory.insert(batch, at: 0)
            transportHistory = Array(transportHistory.prefix(20))
            liveSendCount += batch.commandCount
            liveTransportSummary = batch.summary
            savePersistedState()
        } catch {
            liveTransportSummary = error.localizedDescription
        }
    }

    func sendLiveYamahaMIDIBatch() {
        guard isLiveControlArmed else {
            liveTransportSummary = "Live transport is locked. Arm the transport before sending Yamaha MIDI."
            return
        }
        guard yamahaSettings.model.usesMIDI else {
            liveTransportSummary = "\(yamahaSettings.model.rawValue) is not wired for live MIDI in Mix Assist yet."
            return
        }
        guard let destinationID = yamahaSettings.selectedMIDIDestinationID, !destinationID.isEmpty else {
            liveTransportSummary = "Select a Yamaha MIDI destination first."
            return
        }
        let commands = yamahaMIDICommands()
        _ = sendYamahaMIDICommands(commands, summary: "Sent \(commands.count) Yamaha MIDI template command\(commands.count == 1 ? "" : "s").")
    }

    func sendLiveYamahaBatch() {
        switch yamahaSettings.model.manufacturer {
        case .yamaha:
            sendLiveDM7OSC()
        case .allenHeath, .behringer, .daw:
            liveTransportSummary = "\(yamahaSettings.model.rawValue) batch send is in development."
        }
    }

    func deleteProfile(_ profileID: String) {
        referenceProfiles.removeAll { $0.id == profileID }
        sceneBindings.removeAll { $0.profileID == profileID }
        if selectedProfileID == profileID {
            selectedProfileID = referenceProfiles.first?.id
        }
        if let selectedProfile {
            refreshAdapters(preferredControlKind: selectedProfile.controlKind)
        }
        savePersistedState()
    }

    func exportStateData() throws -> Data {
        guard store != nil else {
            throw MixAssistTransferError.missingStoreContext
        }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return try encoder.encode(makePersistedState())
        } catch {
            persistenceSummary = "State export failed: \(error.localizedDescription)"
            throw MixAssistTransferError.exportFailed
        }
    }

    func importStateData(_ data: Data) throws {
        do {
            let decoded = try JSONDecoder().decode(MixAssistPersistedState.self, from: data)
            referenceProfiles = decoded.referenceProfiles.sorted { $0.updatedAt > $1.updatedAt }
            sceneBindings = decoded.sceneBindings
            selectedProfileID = decoded.selectedProfileID
            selectedAdapterID = decoded.selectedAdapterID
            transportHistory = decoded.transportHistory.sorted { $0.createdAt > $1.createdAt }
            latestTransportBatch = transportHistory.first
            liveOSCSettings = decoded.liveOSCSettings
            yamahaSettings = decoded.yamahaSettings
            routingMatrix = decoded.routingMatrix
            disarmLiveControl(reason: "Live transport disarmed after state import.")
            liveSendCount = decoded.transportHistory
                .filter { $0.mode == .liveOSC || $0.mode == .liveMIDI }
                .reduce(0) { $0 + $1.commandCount }
            if selectedProfileID == nil {
                selectedProfileID = referenceProfiles.first?.id
            }
            refreshAdapters(preferredControlKind: selectedProfile?.controlKind ?? .osc)
            savePersistedState()
            persistenceSummary = "Imported \(referenceProfiles.count) profiles and \(sceneBindings.count) bindings into local Mix Assist state."
        } catch {
            persistenceSummary = "State import failed: \(error.localizedDescription)"
            throw MixAssistTransferError.importFailed
        }
    }

    func suggestedExportFilename() -> String {
        let scope = loadedStorageScope ?? "mix-assist"
        let sanitized = scope
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
        return "prodconnect-mix-assist-\(sanitized)"
    }

    private func refreshBindings() {
        guard let store else { return }
        let scene = currentSceneContext(in: store)
        sceneBindings = referenceProfiles.map { profile in
            let existingBinding = sceneBindings.first(where: { $0.profileID == profile.id })
            return MixAssistSceneBinding(
                id: existingBinding?.id ?? "\(profile.id)-binding",
                profileID: profile.id,
                runOfShowID: existingBinding?.runOfShowID ?? profile.runOfShowID ?? scene.show?.id,
                runOfShowItemID: existingBinding?.runOfShowItemID ?? profile.runOfShowItemID ?? scene.item?.id,
                patchRowIDs: existingBinding?.patchRowIDs ?? profile.patchRowIDs,
                sceneName: existingBinding?.sceneName ?? scene.label,
                notes: existingBinding?.notes ?? "Resolved against current Run of Show context.",
                createdAt: existingBinding?.createdAt ?? profile.createdAt
            )
        }
    }

    private func refreshAdapters(preferredControlKind: MixAssistControlKind) {
        let descriptors = availableAdapters().map(\.descriptor)
        adapterDescriptors = descriptors.sorted { lhs, rhs in
            if lhs.controlKind == preferredControlKind, rhs.controlKind != preferredControlKind { return true }
            if lhs.controlKind != preferredControlKind, rhs.controlKind == preferredControlKind { return false }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        if let selectedAdapterID,
           adapterDescriptors.contains(where: { $0.id == selectedAdapterID }) {
            return
        }

        selectedAdapterID = adapterDescriptors.first(where: { $0.controlKind == preferredControlKind })?.id
            ?? adapterDescriptors.first?.id
    }

    private func availableAdapters() -> [MixAssistAdapter] {
        [
            GenericOSCAdapter(),
            YamahaDM7PreviewAdapter(),
            YamahaRCPPreviewAdapter(),
            VendorConsolePreviewAdapter(),
            EuconPreviewAdapter(),
            GenericMIDIAdapter()
        ]
    }

    private func adapterImplementation(for adapterID: String) -> MixAssistAdapter? {
        availableAdapters().first(where: { $0.descriptor.id == adapterID })
    }

    private func persistenceScope(for store: ProdConnectStore) -> String {
        // Use a stable local key — Mix Assist Mac is a single-user tool and auth state
        // may not be restored yet when onAppear fires, which would cause a scope mismatch
        // and reset all settings to defaults.
        return "mix-assist-local"
    }

    private func storageURL(scope: String) -> URL? {
        guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let directoryURL = appSupportURL
            .appendingPathComponent("ProdConnectMixAssist", isDirectory: true)
            .appendingPathComponent("State", isDirectory: true)
        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        } catch {
            persistenceSummary = "State directory error: \(error.localizedDescription)"
            return nil
        }
        return directoryURL.appendingPathComponent("\(scope).json")
    }

    private func loadPersistedState(scope: String) {
        guard let url = storageURL(scope: scope) else { return }
        guard let data = try? Data(contentsOf: url) else {
            referenceProfiles = []
            sceneBindings = []
            transportHistory = []
            latestTransportBatch = nil
            liveOSCSettings = MixAssistLiveOSCSettings()
            yamahaSettings = MixAssistYamahaControlSettings()
            channelPriorities = [:]
            isLiveControlArmed = false
            liveControlExpiresAt = nil
            liveSendCount = 0
            persistenceSummary = "Local state ready for \(scope). No saved profiles yet."
            liveTransportSummary = "Live transport disarmed."
            return
        }

        do {
            let decoded = try JSONDecoder().decode(MixAssistPersistedState.self, from: data)
            referenceProfiles = decoded.referenceProfiles.sorted { $0.updatedAt > $1.updatedAt }
            sceneBindings = decoded.sceneBindings
            selectedProfileID = decoded.selectedProfileID
            selectedAdapterID = decoded.selectedAdapterID
            transportHistory = decoded.transportHistory.sorted { $0.createdAt > $1.createdAt }
            latestTransportBatch = transportHistory.first
            liveOSCSettings = decoded.liveOSCSettings
            yamahaSettings = decoded.yamahaSettings
            routingMatrix = decoded.routingMatrix
            routingInputCount = decoded.routingInputCount
            lockedDestinations = Set(decoded.lockedDestinations)
            channelPriorities = Dictionary(
                uniqueKeysWithValues: decoded.channelPriorities.compactMap { key, priority in
                    guard let channel = Int(key) else { return nil }
                    return (channel, priority)
                }
            )
            itemPresets = decoded.itemPresets
            savedAudioDeviceUID = decoded.selectedAudioDeviceUID
            audioMonitor?.selectedDeviceUID = decoded.selectedAudioDeviceUID
            audioMonitor?.mixMonitorChannel = decoded.yamahaSettings.mixOutputDanteChannel.map { $0 - 1 }
            isLiveControlArmed = false
            liveControlExpiresAt = nil
            liveSendCount = decoded.transportHistory
                .filter { $0.mode == .liveOSC || $0.mode == .liveMIDI }
                .reduce(0) { $0 + $1.commandCount }
            // Clear any reference capture from a previous session — it was taken with
            // instantaneous RMS and is incompatible with the 3-second average used now.
            // The user must re-capture before running per-channel mode.
            yamahaSettings.targetChannelLevelsDB = [:]
            persistenceSummary = "Loaded \(referenceProfiles.count) profiles and \(sceneBindings.count) bindings. Capture a new reference mix to use per-channel mode."
            liveTransportSummary = "Live transport disarmed."
        } catch {
            referenceProfiles = []
            sceneBindings = []
            transportHistory = []
            latestTransportBatch = nil
            liveOSCSettings = MixAssistLiveOSCSettings()
            yamahaSettings = MixAssistYamahaControlSettings()
            channelPriorities = [:]
            isLiveControlArmed = false
            liveControlExpiresAt = nil
            liveSendCount = 0
            persistenceSummary = "State load failed: \(error.localizedDescription)"
            liveTransportSummary = "Live transport disarmed."
        }
    }

    func savePersistedState() {
        guard let store else { return }
        let scope = persistenceScope(for: store)
        guard let url = storageURL(scope: scope) else { return }

        let payload = makePersistedState()

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(payload)
            try data.write(to: url, options: .atomic)
            persistenceSummary = "Saved Mix Assist state locally for \(scope)."
        } catch {
            persistenceSummary = "State save failed: \(error.localizedDescription)"
        }
    }

    private func makePersistedState() -> MixAssistPersistedState {
        MixAssistPersistedState(
            referenceProfiles: referenceProfiles,
            sceneBindings: sceneBindings,
            selectedProfileID: selectedProfileID,
            selectedAdapterID: selectedAdapterID,
            transportHistory: Array(transportHistory.prefix(20)),
            liveOSCSettings: liveOSCSettings,
            yamahaSettings: yamahaSettings,
            routingMatrix: routingMatrix,
            routingInputCount: routingInputCount,
            lockedDestinations: Array(lockedDestinations),
            channelPriorities: Dictionary(uniqueKeysWithValues: channelPriorities.map { (String($0.key), $0.value) }),
            selectedAudioDeviceUID: audioMonitor?.selectedDeviceUID,
            itemPresets: itemPresets
        )
    }

    private var activeSceneName: String {
        if let profile = selectedProfile,
           let binding = sceneBindings.first(where: { $0.profileID == profile.id }) {
            return binding.sceneName
        }
        return "Unscoped Scene"
    }

    private func yamahaMIDICommands() -> [MixAssistTransportCommand] {
        let activeChannels = audioMonitor?.activeChannels.sorted() ?? []
        let levels = Dictionary(uniqueKeysWithValues: activeChannels.map { ch in
            (String(ch), channelFaderLevelsDB[ch] ?? 0.0)
        })
        return yamahaMIDICommands(destinationLevelsDB: levels)
    }

    private func yamahaMIDICommands(channelDeltas: [Int: Double]) -> [MixAssistTransportCommand] {
        channelDeltas.keys.sorted().map { ch in
            let delta = channelDeltas[ch] ?? 0
            let current = channelFaderLevelsDB[ch] ?? 0.0
            let newLevelDB = max(-90.0, min(10.0, current + delta))
            channelFaderLevelsDB[ch] = newLevelDB
            return yamahaMIDICommand(channel: ch, levelDB: newLevelDB, deltaDescription: String(format: "%+.2f dB", delta))
        }
    }

    private func yamahaMIDICommands(destinationLevelsDB: [String: Double]) -> [MixAssistTransportCommand] {
        destinationLevelsDB.keys.sorted { (Int($0) ?? 0) < (Int($1) ?? 0) }.compactMap { key in
            guard let ch = Int(key), let levelDB = destinationLevelsDB[key] else { return nil }
            let clamped = max(-90.0, min(10.0, levelDB))
            channelFaderLevelsDB[ch] = clamped
            let normalised = (clamped + 90.0) / 100.0
            channelFaderPositions[ch] = max(0, min(1.0, normalised))
            return yamahaMIDICommand(channel: ch, levelDB: clamped, deltaDescription: "stored level")
        }
    }

    private func yamahaMIDICommand(channel ch: Int, levelDB: Double, deltaDescription: String) -> MixAssistTransportCommand {
        let controller = min(127, yamahaSettings.faderCCBase + ch)
        let value = yamahaMIDIValue(forLevelDB: levelDB)
        return MixAssistTransportCommand(
            adapterID: "yamaha-midi",
            patchRowName: "CH \(ch + 1)",
            commandText: "Send CC \(controller) value \(value) to \(yamahaSettings.model.rawValue) CH \(ch + 1) on MIDI channel \(yamahaSettings.midiChannel) (\(deltaDescription), \(String(format: "%.1f", levelDB)) dB)",
            address: String(controller),
            valueSummary: String(value),
            safetyNote: "Template MIDI fader control. Match CC assignments on the console before using live mode."
        )
    }

    private func sendYamahaMIDICommands(_ commands: [MixAssistTransportCommand], summary: String) -> Bool {
        guard yamahaSettings.model.usesMIDI else {
            liveTransportSummary = "\(yamahaSettings.model.rawValue) is not wired for live MIDI in Mix Assist yet."
            return false
        }
        guard let destinationID = yamahaSettings.selectedMIDIDestinationID, !destinationID.isEmpty else {
            liveTransportSummary = "Select a Yamaha MIDI destination first."
            return false
        }
        guard !commands.isEmpty else {
            liveTransportSummary = "No Yamaha MIDI commands generated."
            return false
        }
#if canImport(CoreMIDI)
        do {
            for command in commands {
                let controller = Int(command.address) ?? 0
                let value = Int(command.valueSummary) ?? 64
                try midiRuntime.sendControlChange(
                    destinationID: destinationID,
                    channel: yamahaSettings.midiChannel,
                    controller: controller,
                    value: value
                )
            }

            let batch = MixAssistTransportBatch(
                createdAt: Date(),
                adapterID: "yamaha-midi",
                adapterName: "\(yamahaSettings.model.rawValue) MIDI",
                mode: .liveMIDI,
                commandCount: commands.count,
                sceneName: activeSceneName,
                summary: summary,
                commands: commands
            )
            latestTransportBatch = batch
            transportHistory.insert(batch, at: 0)
            transportHistory = Array(transportHistory.prefix(20))
            liveSendCount += batch.commandCount
            liveTransportSummary = batch.summary
            savePersistedState()
            return true
        } catch {
            liveTransportSummary = error.localizedDescription
            return false
        }
#else
        liveTransportSummary = "CoreMIDI is not available in this build."
        return false
#endif
    }

    private func yamahaMIDIValue(forLevelDB levelDB: Double) -> Int {
        let clamped = max(-90.0, min(10.0, levelDB))
        return Int(((clamped + 90.0) / 100.0) * 127.0)
    }

    private func yamahaControllerNumber(for kind: MixAssistRecommendationKind, index: Int) -> Int {
        let base: Int
        switch kind {
        case .fader:
            base = yamahaSettings.faderCCBase
        case .eq:
            base = yamahaSettings.eqCCBase
        case .compressor:
            base = yamahaSettings.compressorCCBase
        case .gate:
            base = yamahaSettings.gateCCBase
        }
        return min(127, base + index)
    }

    private func yamahaValue(for recommendation: MixAssistRecommendation) -> Int {
        let numericText = recommendation.deltaDescription.filter { "-+.0123456789".contains($0) }
        let numericValue = Double(numericText) ?? 0
        let normalized = max(-12.0, min(12.0, numericValue))
        return Int(((normalized + 12.0) / 24.0) * 127.0)
    }

    private func sendLiveDM7OSC() {
        guard isLiveControlArmed else {
            liveTransportSummary = "Live transport is locked. Arm the transport before sending."
            return
        }

        let host = yamahaSettings.consoleIPAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else {
            liveTransportSummary = "No console IP set. Configure it in Settings → Console Control."
            return
        }

        var oscSettings = liveOSCSettings
        oscSettings.host = host
        oscSettings.port = String(yamahaSettings.model.defaultPort)

        let adapterDesc = MixAssistAdapterDescriptor(
            id: "yamaha-osc",
            name: yamahaSettings.model.rawValue,
            controlKind: .osc,
            endpointSummary: "\(host):\(yamahaSettings.model.defaultPort)",
            stateSummary: "Live OSC"
        )

        let commands = dm7OSCCommands()
        guard !commands.isEmpty else {
            liveTransportSummary = "No OSC commands generated from the current recommendations."
            return
        }

        do {
            let batch = try liveTransport.dispatchLive(
                commands: commands,
                through: adapterDesc,
                settings: oscSettings,
                sceneName: activeSceneName
            )
            latestTransportBatch = batch
            transportHistory.insert(batch, at: 0)
            transportHistory = Array(transportHistory.prefix(20))
            liveSendCount += batch.commandCount
            liveTransportSummary = batch.summary
            savePersistedState()
        } catch {
            liveTransportSummary = error.localizedDescription
        }
    }

    private func dm7OSCCommands() -> [MixAssistTransportCommand] {
        let recommendations: [MixAssistRecommendation] = []
        let patchRows = relevantPatchRows(in: store ?? ProdConnectStore.shared)
        let rowNumbers = Dictionary(uniqueKeysWithValues: patchRows.enumerated().map { index, row in
            (row.id, index + 1)
        })

        return recommendations.compactMap { recommendation in
            let rowNumber = recommendation.patchRowID.flatMap { rowNumbers[$0] } ?? 1
            switch recommendation.kind {
            case .fader:
                return MixAssistTransportCommand(
                    adapterID: "yamaha-dm7",
                    patchRowName: recommendation.patchRowName,
                    commandText: "DM7 input channel \(rowNumber) fader level",
                    address: "/yosc:req/set/MIXER:Current/InCh/Fader/Level/\(rowNumber)/1",
                    valueSummary: String(dm7FaderValue(from: recommendation)),
                    safetyNote: "Official DM7 OSC fader command."
                )
            case .eq:
                return MixAssistTransportCommand(
                    adapterID: "yamaha-dm7",
                    patchRowName: recommendation.patchRowName,
                    commandText: "DM7 input channel \(rowNumber) PEQ band 3 gain",
                    address: "/yosc:req/set/MIXER:Current/InCh/PEQ/Band/Gain/\(rowNumber)/3",
                    valueSummary: String(dm7EQGainValue(from: recommendation)),
                    safetyNote: "Official DM7 OSC PEQ band gain command."
                )
            case .compressor, .gate:
                return nil
            }
        }
    }

    private func dm7FaderValue(from recommendation: MixAssistRecommendation) -> Int {
        let numericText = recommendation.deltaDescription.filter { "-+.0123456789".contains($0) }
        let delta = Double(numericText) ?? 0
        let clamped = max(-10.0, min(10.0, delta))
        return Int(clamped * 100.0)
    }

    private func dm7EQGainValue(from recommendation: MixAssistRecommendation) -> Int {
        let numericText = recommendation.deltaDescription.filter { "-+.0123456789".contains($0) }
        let delta = Double(numericText) ?? 0
        let clamped = max(-18.0, min(18.0, delta))
        return Int(clamped * 10.0)
    }

    private func upsertBinding(_ binding: MixAssistSceneBinding) {
        if let index = sceneBindings.firstIndex(where: { $0.profileID == binding.profileID }) {
            sceneBindings[index] = binding
        } else {
            sceneBindings.insert(binding, at: 0)
        }
    }

    private func relevantPatchRows(in store: ProdConnectStore) -> [PatchRow] {
        let filtered = store.patchsheet.filter { row in
            let category = row.category.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if category.isEmpty { return false }
            return category.contains("audio")
                || category.contains("mix")
                || category.contains("broadcast")
                || category.contains("stream")
                || category.contains("input")
        }
        return filtered.sorted(by: PatchRow.autoSort)
    }

    private func currentSceneContext(in store: ProdConnectStore) -> (show: RunOfShowDocument?, item: RunOfShowItem?, label: String) {
        let show = store.runOfShows.sorted { lhs, rhs in
            if lhs.isLiveActive != rhs.isLiveActive { return lhs.isLiveActive && !rhs.isLiveActive }
            return lhs.updatedAt > rhs.updatedAt
        }.first

        let item: RunOfShowItem? = {
            guard let show else { return nil }
            if let liveID = show.liveCurrentItemID,
               let liveItem = show.items.first(where: { $0.id == liveID }) {
                return liveItem
            }
            return show.items.sorted { $0.position < $1.position }.first
        }()

        let labelParts = [
            show?.title.trimmingCharacters(in: .whitespacesAndNewlines),
            item?.title.trimmingCharacters(in: .whitespacesAndNewlines)
        ]
        let label = labelParts.compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return value
        }.joined(separator: " / ")

        return (show, item, label.isEmpty ? "Unscoped Scene" : label)
    }

    private func defaultProfileName(for scene: (show: RunOfShowDocument?, item: RunOfShowItem?, label: String)) -> String {
        scene.label == "Unscoped Scene" ? "Reference Mix" : "\(scene.label) Reference"
    }

    private func baselineMetrics(
        for scene: (show: RunOfShowDocument?, item: RunOfShowItem?, label: String),
        patchRows: [PatchRow]
    ) -> (integratedLUFS: Double, spectralCentroid: Double, dynamicRange: Double, stereoSpread: Double) {
        let seed = stableSeed(scene.label) + patchRows.prefix(12).reduce(0) { $0 + stableSeed($1.name + $1.input + $1.output) }
        return (
            integratedLUFS: -16.0 + normalized(seed, offset: 11, range: 3.0),
            spectralCentroid: 2150 + normalized(seed, offset: 29, range: 900),
            dynamicRange: 8.5 + normalized(seed, offset: 47, range: 5.0),
            stereoSpread: 0.42 + normalized(seed, offset: 71, range: 0.28)
        )
    }

    private func stableSeed(_ text: String) -> Int {
        text.unicodeScalars.reduce(0) { partial, scalar in
            (partial * 31 + Int(scalar.value)) % 100_000
        }
    }

    private func normalized(_ seed: Int, offset: Int, range: Double) -> Double {
        Double((seed + offset * 97) % 1000) / 1000 * range
    }

    private func signedNormalized(_ seed: Int, offset: Int, range: Double) -> Double {
        normalized(seed, offset: offset, range: range * 2) - range
    }
}

private func slug(_ value: String) -> String {
    value
        .lowercased()
        .components(separatedBy: CharacterSet.alphanumerics.inverted)
        .filter { !$0.isEmpty }
        .joined(separator: "-")
}
