import AVKit
import AppKit
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import StoreKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

private enum MacRoute: String, CaseIterable, Identifiable {
    case chat
    case patchsheet
    case training
    case gear
    case checklists
    case ideas
    case customize
    case users
    case account

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chat: return "Chat"
        case .patchsheet: return "Patchsheet"
        case .training: return "Training"
        case .gear: return "Gear"
        case .checklists: return "Checklist"
        case .ideas: return "Ideas"
        case .customize: return "Customize"
        case .users: return "Users"
        case .account: return "Account"
        }
    }

    var icon: String {
        switch self {
        case .chat: return "message"
        case .patchsheet: return "square.grid.3x2"
        case .training: return "graduationcap"
        case .gear: return "shippingbox"
        case .checklists: return "checklist"
        case .ideas: return "lightbulb"
        case .customize: return "paintbrush"
        case .users: return "person.3"
        case .account: return "person.crop.circle"
        }
    }
}

struct MacRootView: View {
    @EnvironmentObject private var store: ProdConnectStore
    @State private var selectedRoute: MacRoute? = .chat

    private var shellGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.02, green: 0.04, blue: 0.1),
                Color(red: 0.03, green: 0.18, blue: 0.3),
                Color.black
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        Group {
            if store.user == nil {
                MacLoginView()
            } else {
                ZStack {
                    shellGradient
                        .ignoresSafeArea()

                    NavigationSplitView {
                        sidebar
                    } detail: {
                        detail
                    }
                    .navigationSplitViewStyle(.balanced)
                }
                .onAppear {
                    store.listenToTeamData()
                    store.listenToTeamMembers()
                }
            }
        }
    }

    private var sidebar: some View {
        List(MacRoute.allCases, selection: $selectedRoute) { route in
            Label(route.title, systemImage: route.icon)
                .tag(route)
        }
        .navigationTitle("ProdConnect")
        .scrollContentBackground(.hidden)
        .background(Color.black.opacity(0.2))
    }

    @ViewBuilder
    private var detail: some View {
        switch selectedRoute ?? .chat {
        case .chat:
            MacChatView()
        case .patchsheet:
            MacPatchsheetView()
        case .training:
            MacTrainingView()
        case .gear:
            MacGearView()
        case .checklists:
            MacChecklistView()
        case .ideas:
            MacIdeasView()
        case .customize:
            MacCustomizeView()
        case .users:
            MacUsersView()
        case .account:
            MacAccountView()
        }
    }
}

private struct MacLoginView: View {
    @EnvironmentObject private var store: ProdConnectStore
    @State private var isSignUp = false
    @State private var email = ""
    @State private var password = ""
    @State private var teamCode = ""
    @State private var errorMessage = ""
    @State private var isWorking = false

    var body: some View {
        ZStack {
            Group {
                if NSImage(named: "BackgroundImage") != nil {
                    Image("BackgroundImage")
                        .resizable()
                        .scaledToFill()
                        .ignoresSafeArea()
                } else {
                    Color.black.ignoresSafeArea()
                }
            }

            VStack(spacing: 28) {
                VStack(spacing: 8) {
                    Text("ProdConnect")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                    Text("Where Production Comes Together")
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 14) {
                    Picker("Mode", selection: $isSignUp) {
                        Text("Sign In").tag(false)
                        Text("Create Account").tag(true)
                    }
                    .pickerStyle(.segmented)

                    TextField("Email", text: $email)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(trySubmitFromKeyboard)

                    SecureField("Password", text: $password)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(trySubmitFromKeyboard)

                    if isSignUp {
                        TextField("Team Code (optional)", text: $teamCode)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(trySubmitFromKeyboard)
                    }

                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button(isSignUp ? "Create Account" : "Sign In", action: submit)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(isWorking || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty)
                }
                .frame(width: 460)
                .padding(40)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .frame(width: 560)
            }
        }
    }

    private func submit() {
        isWorking = true
        errorMessage = ""
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCode = teamCode.trimmingCharacters(in: .whitespacesAndNewlines)

        let finish: (Result<Void, Error>) -> Void = { result in
            DispatchQueue.main.async {
                isWorking = false
                if case .failure(let error) = result {
                    errorMessage = error.localizedDescription
                }
            }
        }

        if isSignUp {
            store.signUp(email: trimmedEmail, password: password, teamCode: trimmedCode.isEmpty ? nil : trimmedCode, completion: finish)
        } else {
            store.signIn(email: trimmedEmail, password: password, completion: finish)
        }
    }

    private func trySubmitFromKeyboard() {
        guard !isWorking else { return }
        guard !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard !password.isEmpty else { return }
        submit()
    }
}

private struct MacChatView: View {
    @EnvironmentObject private var store: ProdConnectStore
    @State private var selectedChannelID: String?
    @State private var newChannelName = ""
    @State private var draftMessage = ""
    @State private var editingMessageID: String?
    @State private var pendingDeleteMessage: ChatMessage?
    @State private var pendingAttachmentURL: URL?
    @State private var pendingAttachmentName: String?
    @State private var pendingAttachmentKind: ChatAttachmentKind?
    @State private var previewAttachment: MacChatAttachmentPreviewItem?
    @State private var isUploadingAttachment = false
    @State private var attachmentError: String?

    private var groupChannels: [ChatChannel] {
        store.channels
            .filter { $0.kind == .group }
            .sorted { $0.position < $1.position }
    }

    private var directChannels: [ChatChannel] {
        store.channels
            .filter { $0.kind == .direct }
            .sorted { lhs, rhs in
                let lhsDate = lhs.lastMessageAt ?? .distantPast
                let rhsDate = rhs.lastMessageAt ?? .distantPast
                if lhsDate == rhsDate {
                    return channelTitle(lhs) < channelTitle(rhs)
                }
                return lhsDate > rhsDate
            }
    }

    private var selectedChannel: ChatChannel? {
        store.channels.first(where: { $0.id == selectedChannelID }) ?? groupChannels.first ?? directChannels.first
    }

    var body: some View {
        GeometryReader { proxy in
            let sidebarWidth = min(300, max(240, proxy.size.width * 0.26))

            HStack(spacing: 0) {
                VStack(spacing: 12) {
                    HStack {
                        TextField("New channel", text: $newChannelName)
                        Button("Add") {
                            let name = newChannelName.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !name.isEmpty else { return }
                            let channel = ChatChannel(
                                name: name,
                                teamCode: store.teamCode ?? "",
                                position: store.nextChannelPosition()
                            )
                            store.saveChannel(channel)
                            selectedChannelID = channel.id
                            newChannelName = ""
                        }
                    }
                    List(selection: $selectedChannelID) {
                        Section("Channels") {
                            ForEach(groupChannels) { channel in
                                channelRow(channel)
                                    .tag(channel.id)
                            }
                            .onMove(perform: moveChannels)
                        }
                        Section("Direct Messages") {
                            ForEach(directChannels) { channel in
                                channelRow(channel)
                                    .tag(channel.id)
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
                .frame(width: sidebarWidth, alignment: .topLeading)
                .frame(maxHeight: .infinity, alignment: .topLeading)
                .padding()
                .background(Color.clear)

                Divider()

                Group {
                    if let channel = selectedChannel {
                        VStack(spacing: 0) {
                            ScrollViewReader { reader in
                                GeometryReader { scrollProxy in
                                    ScrollView {
                                        LazyVStack(alignment: .leading, spacing: 0) {
                                            ForEach(channel.messages) { message in
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text(displayName(for: message.author)).font(.headline)
                                                    if !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                                        Text(message.text)
                                                    }
                                                    HStack(spacing: 8) {
                                                        Text(message.timestamp, style: .time)
                                                        if message.editedAt != nil {
                                                            Text("Edited")
                                                        }
                                                    }
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                    attachmentView(for: message)
                                                }
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .padding(.vertical, 14)
                                                .padding(.leading, 12)
                                                .padding(.trailing, 12)
                                                .overlay(alignment: .bottom) {
                                                    Divider()
                                                }
                                                .contextMenu {
                                                    Button("Edit") {
                                                        beginEditing(message)
                                                    }
                                                    .disabled(channel.isReadOnly)

                                                    Button("Delete", role: .destructive) {
                                                        pendingDeleteMessage = message
                                                    }
                                                    .disabled(channel.isReadOnly)
                                                }
                                                .id(message.id)
                                            }
                                        }
                                        .frame(width: scrollProxy.size.width, alignment: .leading)
                                    }
                                    .onAppear {
                                        scrollToLatestMessage(using: reader, in: channel)
                                    }
                                    .onChange(of: channel.messages.count) { _ in
                                        scrollToLatestMessage(using: reader, in: channel)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                            Divider()

                            VStack(spacing: 8) {
                                if let pendingAttachmentName {
                                    HStack(spacing: 8) {
                                        Image(systemName: pendingAttachmentKind == .image ? "photo" : "doc")
                                            .foregroundStyle(.secondary)
                                        Text(pendingAttachmentName)
                                            .font(.caption)
                                            .lineLimit(1)
                                        Button(role: .destructive) {
                                            clearPendingAttachment()
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                        }
                                    }
                                }

                                HStack {
                                    Button {
                                        pickAttachment(allowedTypes: [.image], preferredKind: .image)
                                    } label: {
                                        Image(systemName: "photo.on.rectangle")
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(channel.isReadOnly || isUploadingAttachment || editingMessageID != nil)

                                    Button {
                                        pickAttachment(allowedTypes: [.data], preferredKind: .file)
                                    } label: {
                                        Image(systemName: "paperclip")
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(channel.isReadOnly || isUploadingAttachment || editingMessageID != nil)

                                    TextField("Message", text: $draftMessage)
                                        .onSubmit {
                                            saveMessage(in: channel)
                                        }
                                        .disabled(isUploadingAttachment)
                                    if editingMessageID != nil {
                                        Button("Cancel") {
                                            cancelMessageEditing()
                                        }
                                    }
                                    Button(editingMessageID == nil ? "Send" : "Save") {
                                        saveMessage(in: channel)
                                    }
                                    .controlSize(.large)
                                    .disabled(channel.isReadOnly || isUploadingAttachment)
                                }

                                if isUploadingAttachment {
                                    ProgressView()
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }

                                if let attachmentError {
                                    Text(attachmentError)
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 16)
                            .padding(.leading, 16)
                            .padding(.bottom, 16)
                            .padding(.trailing, 28)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .navigationTitle(channelTitle(channel))
                        .background(Color.clear)
                        .alert("Delete Message?", isPresented: isShowingDeleteMessageAlert, presenting: pendingDeleteMessage) { message in
                            Button("Cancel", role: .cancel) { }
                            Button("Delete", role: .destructive) {
                                deleteMessage(message, from: channel)
                            }
                        } message: { _ in
                            Text("This will permanently remove the message.")
                        }
                    } else {
                        ContentUnavailableView("No Channels", systemImage: "message", description: Text("Create or select a channel."))
                    }
                }
                .frame(width: max(proxy.size.width - sidebarWidth - 13, 0), alignment: .topLeading)
                .padding(.trailing, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            selectedChannelID = selectedChannelID ?? groupChannels.first?.id ?? directChannels.first?.id
        }
        .onChange(of: selectedChannelID) { _ in
            cancelMessageEditing()
        }
        .sheet(item: $previewAttachment) { item in
            MacChatAttachmentPreviewView(item: item)
        }
    }

    @ViewBuilder
    private func channelRow(_ channel: ChatChannel) -> some View {
        Text(channelTitle(channel))
    }

    private func displayName(for email: String) -> String {
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.isEmpty {
            return "Unknown"
        }
        if let member = store.teamMembers.first(where: {
            $0.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalized
        }) {
            return member.displayName
        }
        if let user = store.user,
           user.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalized {
            return user.displayName
        }
        return email.components(separatedBy: "@").first ?? email
    }

    private func channelTitle(_ channel: ChatChannel) -> String {
        guard channel.kind == .direct else { return channel.name }

        let currentUserEmail = store.user?.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let names = channel.participantEmails
            .filter { email in
                let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return normalized != currentUserEmail
            }
            .map(displayName(for:))

        if !names.isEmpty {
            return names.joined(separator: ", ")
        }
        return channel.name
    }

    private func moveChannels(from source: IndexSet, to destination: Int) {
        var reordered = groupChannels
        reordered.move(fromOffsets: source, toOffset: destination)

        for (index, channel) in reordered.enumerated() {
            var updated = channel
            updated.position = index
            store.saveChannel(updated)
        }
    }

    private var isShowingDeleteMessageAlert: Binding<Bool> {
        Binding(
            get: { pendingDeleteMessage != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDeleteMessage = nil
                }
            }
        )
    }

    private func beginEditing(_ message: ChatMessage) {
        editingMessageID = message.id
        draftMessage = message.text
        attachmentError = nil
    }

    private func cancelMessageEditing() {
        editingMessageID = nil
        draftMessage = ""
        pendingDeleteMessage = nil
        attachmentError = nil
    }

    private func saveMessage(in channel: ChatChannel) {
        let text = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        if let currentEditingMessageID = editingMessageID,
           let index = channel.messages.firstIndex(where: { $0.id == currentEditingMessageID }) {
            guard !text.isEmpty else { return }
            var updated = channel
            updated.messages[index].text = text
            updated.messages[index].editedAt = Date()
            updated.lastMessageAt = updated.messages.last?.timestamp
            store.saveChannel(updated)
            editingMessageID = nil
            draftMessage = ""
            return
        }

        if let pendingAttachmentName,
           let pendingAttachmentKind,
           let pendingAttachmentURL {
            isUploadingAttachment = true
            attachmentError = nil
            uploadAttachment(localURL: pendingAttachmentURL, for: channel) { result in
                DispatchQueue.main.async {
                    self.isUploadingAttachment = false
                    switch result {
                    case .success(let urlString):
                        var updated = channel
                        updated.messages.append(
                            ChatMessage(
                                author: store.user?.email ?? "unknown",
                                text: text,
                                timestamp: Date(),
                                editedAt: nil,
                                attachmentURL: urlString,
                                attachmentName: pendingAttachmentName,
                                attachmentKind: pendingAttachmentKind
                            )
                        )
                        updated.lastMessageAt = updated.messages.last?.timestamp
                        store.saveChannel(updated)
                        clearPendingAttachment()
                        draftMessage = ""
                    case .failure(let error):
                        attachmentError = "Attachment upload failed: \(error.localizedDescription)"
                    }
                }
            }
        } else {
            guard !text.isEmpty else { return }
            var updated = channel
            updated.messages.append(
                ChatMessage(
                    author: store.user?.email ?? "unknown",
                    text: text,
                    timestamp: Date()
                )
            )
            updated.lastMessageAt = updated.messages.last?.timestamp
            store.saveChannel(updated)
            draftMessage = ""
        }
    }

    private func deleteMessage(_ message: ChatMessage, from channel: ChatChannel) {
        var updated = channel
        updated.messages.removeAll { $0.id == message.id }
        updated.lastMessageAt = updated.messages.last?.timestamp
        store.saveChannel(updated)
        pendingDeleteMessage = nil
        if editingMessageID == message.id {
            cancelMessageEditing()
        }
    }

    @ViewBuilder
    private func attachmentView(for message: ChatMessage) -> some View {
        if let urlString = message.attachmentURL,
           let url = URL(string: urlString) {
            if message.attachmentKind == .image {
                Button {
                    openAttachmentURL(url, kind: .image)
                } label: {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: 260, maxHeight: 180)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        case .failure:
                            attachmentLinkLabel(name: message.attachmentName ?? "Image")
                        default:
                            ProgressView()
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .buttonStyle(.plain)
            } else {
                attachmentLink(url: url, name: message.attachmentName ?? "Attachment")
            }
        }
    }

    private func attachmentLink(url: URL, name: String) -> some View {
        Button {
            openAttachmentURL(url, kind: .file)
        } label: {
            attachmentLinkLabel(name: name)
        }
        .buttonStyle(.plain)
    }

    private func attachmentLinkLabel(name: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "doc")
            Text(name)
                .lineLimit(1)
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func openAttachmentURL(_ url: URL, kind: ChatAttachmentKind) {
        let scheme = (url.scheme ?? "").lowercased()
        let supportedSchemes = ["https", "http", "file"]
        guard supportedSchemes.contains(scheme) else {
            attachmentError = "Unsupported attachment URL."
            return
        }
        previewAttachment = MacChatAttachmentPreviewItem(url: url, kind: kind)
    }

    private func setPendingAttachment(url: URL, kind: ChatAttachmentKind) {
        let inferredType = UTType(filenameExtension: url.pathExtension.lowercased())
        let resolvedKind = kind == .file && inferredType?.conforms(to: .image) == true ? ChatAttachmentKind.image : kind
        pendingAttachmentURL = url
        pendingAttachmentName = url.lastPathComponent
        pendingAttachmentKind = resolvedKind
    }

    private func clearPendingAttachment() {
        pendingAttachmentURL = nil
        pendingAttachmentName = nil
        pendingAttachmentKind = nil
        attachmentError = nil
    }

    private func uploadAttachment(localURL: URL, for channel: ChatChannel, completion: @escaping (Result<String, Error>) -> Void) {
        let filename = (pendingAttachmentName ?? localURL.lastPathComponent)
            .replacingOccurrences(of: " ", with: "_")
        let path = "chatAttachments/\(channel.id)/\(UUID().uuidString)-\(filename)"
        let storageRef = Storage.storage().reference().child(path)

        let didAccess = localURL.startAccessingSecurityScopedResource()
        storageRef.putFile(from: localURL, metadata: nil) { _, error in
            if didAccess {
                localURL.stopAccessingSecurityScopedResource()
            }

            if let error {
                completion(.failure(error))
                return
            }

            storageRef.downloadURL { url, downloadError in
                if let downloadError {
                    completion(.failure(downloadError))
                } else if let absoluteString = url?.absoluteString {
                    completion(.success(absoluteString))
                } else {
                    completion(.failure(NSError(
                        domain: "ProdConnectMacChat",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Missing download URL."]
                    )))
                }
            }
        }
    }

    @MainActor
    private func pickAttachment(allowedTypes: [UTType], preferredKind: ChatAttachmentKind) {
        attachmentError = nil

        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = allowedTypes

        if let keyWindow = NSApp.keyWindow {
            panel.beginSheetModal(for: keyWindow) { response in
                guard response == .OK, let url = panel.url else { return }
                self.setPendingAttachment(url: url, kind: preferredKind)
            }
            return
        }

        if panel.runModal() == .OK, let url = panel.url {
            setPendingAttachment(url: url, kind: preferredKind)
        }
    }

    private func scrollToLatestMessage(using reader: ScrollViewProxy, in channel: ChatChannel) {
        guard let lastMessageID = channel.messages.last?.id else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.easeOut(duration: 0.2)) {
                reader.scrollTo(lastMessageID, anchor: .bottom)
            }
        }
    }
}

private struct MacChatAttachmentPreviewItem: Identifiable {
    let url: URL
    let kind: ChatAttachmentKind

    var id: String { url.absoluteString }
}

private struct MacChatAttachmentPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    let item: MacChatAttachmentPreviewItem

    var body: some View {
        NavigationStack {
            Group {
                if item.kind == .image {
                    ScrollView {
                        AsyncImage(url: item.url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .padding()
                            case .failure:
                                MacWebVideoView(url: item.url)
                            default:
                                ProgressView()
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        }
                    }
                } else {
                    MacWebVideoView(url: item.url)
                }
            }
            .navigationTitle("Attachment")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .frame(minWidth: 720, minHeight: 520)
    }
}

private struct MacPatchsheetView: View {
    @EnvironmentObject private var store: ProdConnectStore
    @State private var selectedCategory = "Audio"
    @State private var field1 = ""
    @State private var field2 = ""
    @State private var field3 = ""
    @State private var field4 = ""

    private let categories = ["Audio", "Video", "Lighting"]

    private var filtered: [PatchRow] {
        store.patchsheet
            .filter { $0.category == selectedCategory }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Category", selection: $selectedCategory) {
                ForEach(categories, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.segmented)

            List {
                ForEach(filtered) { item in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(item.name).font(.headline)
                            Text("\(item.input) -> \(item.output)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if !item.campus.isEmpty {
                            Text(item.campus)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        store.deletePatch(filtered[index])
                    }
                }
            }
            .scrollContentBackground(.hidden)

            GroupBox("Add Patch") {
                VStack(spacing: 10) {
                    TextField(selectedCategory == "Lighting" ? "Fixture" : "Name", text: $field1)
                    HStack(spacing: 10) {
                        TextField(primaryPlaceholder, text: $field2)
                        TextField(secondaryPlaceholder, text: $field3)
                    }
                    if selectedCategory == "Lighting" {
                        TextField("Universe", text: $field4)
                    }
                    Button("Save Patch") {
                        store.savePatch(
                            PatchRow(
                                name: field1,
                                input: field2,
                                output: field3,
                                teamCode: store.teamCode ?? "",
                                category: selectedCategory,
                                campus: "",
                                room: "",
                                channelCount: selectedCategory == "Lighting" ? Int(field3.trimmingCharacters(in: .whitespacesAndNewlines)) : nil,
                                universe: selectedCategory == "Lighting" ? field4.trimmingCharacters(in: .whitespacesAndNewlines) : nil
                            )
                        )
                        field1 = ""
                        field2 = ""
                        field3 = ""
                        field4 = ""
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(field1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding()
        .background(Color.clear)
        .navigationTitle("Patchsheet")
    }

    private var primaryPlaceholder: String {
        switch selectedCategory {
        case "Video": return "Source"
        case "Lighting": return "DMX Channel"
        default: return "Input"
        }
    }

    private var secondaryPlaceholder: String {
        switch selectedCategory {
        case "Video": return "Destination"
        case "Lighting": return "Channel Count"
        default: return "Output"
        }
    }
}

private struct MacTrainingView: View {
    @EnvironmentObject private var store: ProdConnectStore
    @State private var selectedLesson: TrainingLesson?
    @State private var title = ""
    @State private var category = "Audio"
    @State private var urlString = ""

    private let categories = ["Audio", "Video", "Lighting", "Misc"]

    var body: some View {
        if let selectedLesson {
            VStack(alignment: .leading, spacing: 16) {
                Button {
                    self.selectedLesson = nil
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.bordered)

                MacTrainingLessonPlayerView(lesson: selectedLesson)
            }
            .padding()
            .background(Color.clear)
            .navigationTitle(selectedLesson.title)
        } else {
        VStack(alignment: .leading, spacing: 16) {
            List {
                ForEach(store.lessons.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }) { lesson in
                    Button {
                        selectedLesson = lesson
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(lesson.title).font(.headline)
                                Text(lesson.category).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if hasPlayableURL(lesson) {
                                Image(systemName: "play.circle.fill")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { indexSet in
                    let lessons = store.lessons.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
                    for index in indexSet {
                        store.deleteLesson(lessons[index])
                    }
                }
            }
            .scrollContentBackground(.hidden)

            GroupBox("Add Training") {
                VStack(spacing: 10) {
                    TextField("Title", text: $title)
                    Picker("Category", selection: $category) {
                        ForEach(categories, id: \.self) { Text($0).tag($0) }
                    }
                    TextField("Video URL (optional)", text: $urlString)
                    Button("Save Lesson") {
                        store.saveLesson(
                            TrainingLesson(
                                title: title,
                                category: category,
                                teamCode: store.teamCode ?? "",
                                urlString: urlString.isEmpty ? nil : urlString
                            )
                        )
                        title = ""
                        urlString = ""
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding()
        .background(Color.clear)
        .navigationTitle("Training")
        }
    }

    private func hasPlayableURL(_ lesson: TrainingLesson) -> Bool {
        let raw = lesson.urlString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !raw.isEmpty && URL(string: raw) != nil
    }
}

private struct MacTrainingLessonPlayerView: View {
    let lesson: TrainingLesson

    private var lessonURL: URL? {
        let raw = lesson.urlString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty else { return nil }
        return URL(string: raw)
    }

    private var youTubeWatchURL: URL? {
        guard let url = lessonURL else { return nil }
        guard let host = url.host?.lowercased() else { return nil }

        if host.contains("youtu.be") {
            let id = url.pathComponents.dropFirst().first ?? ""
            return id.isEmpty ? nil : URL(string: "https://www.youtube.com/watch?v=\(id)")
        }

        if host.contains("youtube.com") {
            if url.path.lowercased() == "/watch",
               let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let id = components.queryItems?.first(where: { $0.name == "v" })?.value,
               !id.isEmpty,
               let normalized = URL(string: "https://www.youtube.com/watch?v=\(id)") {
                return normalized
            }
            if url.path.lowercased().contains("/embed/"),
               let embedID = url.pathComponents.last,
               !embedID.isEmpty {
                return URL(string: "https://www.youtube.com/watch?v=\(embedID)")
            }
        }

        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(lesson.title)
                    .font(.title2.weight(.semibold))
                Text(lesson.category)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let watchURL = youTubeWatchURL {
                MacWebVideoView(url: watchURL)
                    .frame(minHeight: 480)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else if let url = lessonURL {
                VideoPlayer(player: AVPlayer(url: url))
                    .frame(minHeight: 480)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                ContentUnavailableView(
                    "No Video URL",
                    systemImage: "play.slash",
                    description: Text("This lesson does not have a playable video URL yet.")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct MacWebVideoView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsBackForwardNavigationGestures = false
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if webView.url != url {
            webView.load(URLRequest(url: url))
        }
    }
}

private struct MacGearView: View {
    @EnvironmentObject private var store: ProdConnectStore
    @State private var selectedGearItem: GearItem?
    @State private var showAddGearForm = false
    @State private var editingGearID: String?
    @State private var editingImageURL: String?
    @State private var editingCreatedBy: String?
    @State private var searchText = ""
    @State private var selectedCategory: String?
    @State private var selectedStatus: GearItem.GearStatus?
    @State private var selectedLocation: String?
    @State private var name = ""
    @State private var category = "Audio"
    @State private var status: GearItem.GearStatus = .available
    @State private var location = ""
    @State private var campus = ""
    @State private var purchaseDate = Date()
    @State private var purchasedFrom = ""
    @State private var costText = ""
    @State private var serialNumber = ""
    @State private var assetId = ""
    @State private var installDate = Date()
    @State private var maintenanceIssue = ""
    @State private var maintenanceCostText = ""
    @State private var maintenanceRepairDate = Date()
    @State private var maintenanceNotes = ""

    private var availableCategories: [String] {
        Array(Set(store.gear.map(\.category))).filter { !$0.isEmpty }.sorted()
    }

    private var allGearLocations: [String] {
        Array(Set(store.gear.map(\.location))).filter { !$0.isEmpty }.sorted()
    }

    private var filteredGear: [GearItem] {
        var result = store.gear
        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.category.localizedCaseInsensitiveContains(searchText) ||
                $0.location.localizedCaseInsensitiveContains(searchText)
            }
        }
        if let selectedCategory {
            result = result.filter { $0.category == selectedCategory }
        }
        if let selectedStatus {
            result = result.filter { $0.status == selectedStatus }
        }
        if let selectedLocation {
            result = result.filter { $0.location == selectedLocation }
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        Group {
            if editingGearID != nil {
                VStack(alignment: .leading, spacing: 16) {
                    Button {
                        editingGearID = nil
                        editingImageURL = nil
                        editingCreatedBy = nil
                        resetGearForm()
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .buttonStyle(.bordered)

                    gearEditor(title: "Edit Gear", buttonTitle: "Save Changes", fullScreen: true)
                }
                .padding()
                .background(Color.clear)
                .navigationTitle(name.isEmpty ? "Edit Gear" : name)
            } else
            if let selectedGearItem {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Button {
                            self.selectedGearItem = nil
                        } label: {
                            Label("Back", systemImage: "chevron.left")
                        }
                        .buttonStyle(.bordered)

                        Button("Edit") {
                            beginEditing(selectedGearItem)
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    MacGearDetailView(
                        item: selectedGearItem,
                        statusColor: statusColor(for: selectedGearItem.status)
                    )
                }
                .padding()
                .background(Color.clear)
                .navigationTitle(selectedGearItem.name)
            } else {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Spacer()
                if showAddGearForm {
                    Button("Cancel") {
                        showAddGearForm = false
                        if editingGearID == nil {
                            resetGearForm()
                        }
                    }
                    .buttonStyle(.bordered)
                }
                Button {
                    if showAddGearForm {
                        showAddGearForm = false
                    } else {
                        resetGearForm()
                        showAddGearForm = true
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }

            TextField("Search gear...", text: $searchText)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 12) {
                Menu {
                    Button("Clear") { selectedCategory = nil }
                    Divider()
                    ForEach(availableCategories, id: \.self) { option in
                        Button(option) { selectedCategory = option }
                    }
                } label: {
                    filterChip(
                        title: selectedCategory ?? "Category",
                        icon: "line.3.horizontal.decrease.circle",
                        isActive: selectedCategory != nil
                    )
                }

                if !allGearLocations.isEmpty {
                    Menu {
                        Button("Clear") { selectedLocation = nil }
                        Divider()
                        ForEach(allGearLocations, id: \.self) { option in
                            Button(option) { selectedLocation = option }
                        }
                    } label: {
                        filterChip(
                            title: selectedLocation ?? "Location",
                            icon: "mappin.circle",
                            isActive: selectedLocation != nil
                        )
                    }
                }

                Menu {
                    Button("Clear") { selectedStatus = nil }
                    Divider()
                    ForEach(GearItem.GearStatus.allCases, id: \.self) { option in
                        Button(option.rawValue) { selectedStatus = option }
                    }
                } label: {
                    filterChip(
                        title: selectedStatus?.rawValue ?? "Status",
                        icon: "checkmark.circle",
                        isActive: selectedStatus != nil
                    )
                }
            }

            List {
                ForEach(filteredGear) { item in
                    Button {
                        selectedGearItem = item
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(item.name).font(.headline)
                                Text(item.category).font(.caption).foregroundStyle(.secondary)
                                if !item.location.isEmpty {
                                    Text(item.location).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(item.status.rawValue)
                                .font(.caption2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(statusColor(for: item.status).opacity(0.2))
                                .foregroundStyle(statusColor(for: item.status))
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        store.deleteGear(items: [filteredGear[index]])
                    }
                }
            }
            .scrollContentBackground(.hidden)

            if showAddGearForm {
                gearEditor(title: "Add Gear", buttonTitle: "Save Gear", fullScreen: false)
            }
        }
        .padding()
        .background(Color.clear)
        .navigationTitle("Gear")
            }
        }
    }

    @ViewBuilder
    private func filterChip(title: String, icon: String, isActive: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(title).lineLimit(1)
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isActive ? Color.blue : Color.gray.opacity(0.3))
        .foregroundColor(.white)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func statusColor(for status: GearItem.GearStatus) -> Color {
        switch status {
        case .available:
            return .green
        case .checkedOut:
            return .orange
        case .maintenance:
            return .yellow
        case .lost:
            return .red
        case .unknown:
            return .gray
        case .inUse:
            return .blue
        case .needsRepair:
            return .pink
        case .retired:
            return .gray
        case .missing:
            return .red
        case .blank:
            return .gray
        }
    }

    private func beginEditing(_ item: GearItem) {
        editingGearID = item.id
        editingImageURL = item.imageURL
        editingCreatedBy = item.createdBy
        name = item.name
        category = item.category.isEmpty ? "Audio" : item.category
        status = item.status
        location = item.location
        campus = item.campus
        purchaseDate = item.purchaseDate ?? Date()
        purchasedFrom = item.purchasedFrom
        costText = item.cost.map { "\($0)" } ?? ""
        serialNumber = item.serialNumber
        assetId = item.assetId
        installDate = item.installDate ?? Date()
        maintenanceIssue = item.maintenanceIssue
        maintenanceCostText = item.maintenanceCost.map { "\($0)" } ?? ""
        maintenanceRepairDate = item.maintenanceRepairDate ?? Date()
        maintenanceNotes = item.maintenanceNotes
        selectedGearItem = nil
        showAddGearForm = false
    }

    private func resetGearForm() {
        name = ""
        category = "Audio"
        status = .available
        location = ""
        campus = ""
        purchaseDate = Date()
        purchasedFrom = ""
        costText = ""
        serialNumber = ""
        assetId = ""
        installDate = Date()
        maintenanceIssue = ""
        maintenanceCostText = ""
        maintenanceRepairDate = Date()
        maintenanceNotes = ""
    }

    @ViewBuilder
    private func gearEditor(title: String, buttonTitle: String, fullScreen: Bool) -> some View {
        GroupBox(title) {
            ScrollView {
                VStack(spacing: 14) {
                    GroupBox("Details") {
                        VStack(spacing: 10) {
                            labeledTextField("Name", text: $name)
                            labeledTextField("Serial Number", text: $serialNumber)
                            labeledTextField("Asset ID", text: $assetId)
                            fieldHeader("Category")
                            Picker("Category", selection: $category) {
                                ForEach(["Audio", "Video", "Lighting", "Network", "Misc"], id: \.self) { option in
                                    Text(option).tag(option)
                                }
                            }
                            if store.locations.isEmpty {
                                labeledTextField("Location", text: $location)
                            } else {
                                fieldHeader("Location")
                                Picker("Location", selection: $location) {
                                    Text("Select location").tag("")
                                    ForEach(store.locations.sorted(), id: \.self) { option in
                                        Text(option).tag(option)
                                    }
                                }
                            }
                            if store.locations.isEmpty {
                                labeledTextField("Campus", text: $campus)
                            } else {
                                fieldHeader("Campus")
                                Picker("Campus", selection: $campus) {
                                    Text("Select campus").tag("")
                                    ForEach(store.locations.sorted(), id: \.self) { option in
                                        Text(option).tag(option)
                                    }
                                }
                            }
                            fieldHeader("Status")
                            Picker("Status", selection: $status) {
                                ForEach(GearItem.GearStatus.allCases, id: \.self) { option in
                                    Text(option.rawValue).tag(option)
                                }
                            }
                        }
                    }

                    GroupBox("Install Info") {
                        labeledDatePicker("Install Date", selection: $installDate)
                    }

                    GroupBox("Purchase Info") {
                        VStack(spacing: 10) {
                            labeledDatePicker("Purchase Date", selection: $purchaseDate)
                            labeledTextField("Purchased From", text: $purchasedFrom)
                            labeledTextField("Cost", text: $costText)
                        }
                    }

                    GroupBox("Maintenance") {
                        VStack(spacing: 10) {
                            labeledTextField("Issue", text: $maintenanceIssue)
                            labeledTextField("Cost", text: $maintenanceCostText)
                            labeledDatePicker("Repair Date", selection: $maintenanceRepairDate)
                            fieldHeader("Notes")
                            TextEditor(text: $maintenanceNotes)
                                .frame(minHeight: 90)
                        }
                    }

                    GroupBox("Image") {
                        HStack {
                            Image(systemName: "photo")
                            Text("Image upload is not wired on macOS yet.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button(buttonTitle) {
                        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmedName.isEmpty else { return }
                        store.saveGear(
                            GearItem(
                                id: editingGearID ?? UUID().uuidString,
                                name: trimmedName,
                                category: category,
                                status: status,
                                teamCode: store.teamCode ?? "",
                                purchaseDate: purchaseDate,
                                purchasedFrom: purchasedFrom.trimmingCharacters(in: .whitespacesAndNewlines),
                                cost: Double(costText),
                                location: location.trimmingCharacters(in: .whitespacesAndNewlines),
                                serialNumber: serialNumber.trimmingCharacters(in: .whitespacesAndNewlines),
                                campus: campus.trimmingCharacters(in: .whitespacesAndNewlines),
                                assetId: assetId.trimmingCharacters(in: .whitespacesAndNewlines),
                                installDate: installDate,
                                maintenanceIssue: maintenanceIssue.trimmingCharacters(in: .whitespacesAndNewlines),
                                maintenanceCost: Double(maintenanceCostText),
                                maintenanceRepairDate: maintenanceRepairDate,
                                maintenanceNotes: maintenanceNotes.trimmingCharacters(in: .whitespacesAndNewlines),
                                imageURL: editingImageURL,
                                createdBy: editingCreatedBy
                            )
                        )
                        editingGearID = nil
                        editingImageURL = nil
                        editingCreatedBy = nil
                        resetGearForm()
                        showAddGearForm = false
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .frame(maxHeight: fullScreen ? .infinity : 420)
        }
    }

    @ViewBuilder
    private func fieldHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func labeledTextField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            fieldHeader(title)
            TextField(title, text: text)
        }
    }

    @ViewBuilder
    private func labeledDatePicker(_ title: String, selection: Binding<Date>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            fieldHeader(title)
            DatePicker(title, selection: selection, displayedComponents: .date)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct MacGearDetailView: View {
    let item: GearItem
    let statusColor: Color

    var body: some View {
        Form {
            Section("Details") {
                detailRow("Name", item.name)
                detailRow("Category", item.category)
                detailRow("Status", item.status.rawValue, valueColor: statusColor)
                detailRow("Serial Number", item.serialNumber)
                detailRow("Asset ID", item.assetId)
                detailRow("Location", item.location)
                detailRow("Campus", item.campus)
            }

            Section("Install Info") {
                detailRow("Install Date", formatted(item.installDate))
            }

            Section("Purchase Info") {
                detailRow("Purchase Date", formatted(item.purchaseDate))
                detailRow("Purchased From", item.purchasedFrom)
                detailRow("Cost", currency(item.cost))
            }

            Section("Maintenance") {
                detailRow("Issue", item.maintenanceIssue)
                detailRow("Maintenance Cost", currency(item.maintenanceCost))
                detailRow("Repair Date", formatted(item.maintenanceRepairDate))
                detailRow("Notes", item.maintenanceNotes)
            }

            Section("Meta") {
                detailRow("Created By", item.createdBy)
                detailRow("Image URL", item.imageURL)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .navigationTitle(item.name)
    }

    @ViewBuilder
    private func detailRow(_ label: String, _ value: String?, valueColor: Color? = nil) -> some View {
        LabeledContent(label) {
            Text(displayValue(value))
                .foregroundStyle(valueColor ?? (isMissing(value) ? .secondary : .primary))
                .multilineTextAlignment(.trailing)
        }
    }

    private func displayValue(_ value: String?) -> String {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return "Not set"
        }
        return trimmed
    }

    private func isMissing(_ value: String?) -> Bool {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
    }

    private func formatted(_ date: Date?) -> String {
        guard let date else { return "Not set" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    private func currency(_ amount: Double?) -> String {
        guard let amount else { return "Not set" }
        return amount.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD"))
    }
}

private struct MacChecklistView: View {
    @EnvironmentObject private var store: ProdConnectStore
    @State private var selectedChecklist: ChecklistTemplate?
    @State private var isShowingAddChecklist = false
    @State private var title = ""
    @State private var firstTask = ""

    private var activeChecklists: [ChecklistTemplate] {
        store.checklists
            .filter { !isChecklistCompleted($0) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private var completedChecklists: [ChecklistTemplate] {
        store.checklists
            .filter { isChecklistCompleted($0) }
            .sorted { lhs, rhs in
                let lhsDate = lhs.completedAt ?? .distantPast
                let rhsDate = rhs.completedAt ?? .distantPast
                if lhsDate == rhsDate {
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
                return lhsDate > rhsDate
            }
    }

    var body: some View {
        if let selectedChecklist {
            VStack(alignment: .leading, spacing: 16) {
                Button {
                    self.selectedChecklist = nil
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.bordered)

                MacChecklistDetailView(checklist: selectedChecklist)
            }
            .padding()
            .background(Color.clear)
            .navigationTitle(selectedChecklist.title)
        } else {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Spacer()
                Button(isShowingAddChecklist ? "Cancel" : "Add") {
                    isShowingAddChecklist.toggle()
                    if !isShowingAddChecklist {
                        title = ""
                        firstTask = ""
                    }
                }
                .buttonStyle(.borderedProminent)
            }

            List {
                if !activeChecklists.isEmpty {
                    Section("Not Completed") {
                        ForEach(activeChecklists) { checklist in
                            checklistRow(checklist)
                        }
                    }
                }
                if !completedChecklists.isEmpty {
                    Section("Completed") {
                        ForEach(completedChecklists) { checklist in
                            checklistRow(checklist)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)

            if isShowingAddChecklist {
                GroupBox("Add Checklist") {
                    VStack(spacing: 10) {
                        TextField("Title", text: $title)
                        TextField("First Item", text: $firstTask)
                        Button("Save Checklist") {
                            let item = ChecklistItem(text: firstTask.isEmpty ? "New Item" : firstTask)
                            store.saveChecklist(
                                ChecklistTemplate(
                                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                                    teamCode: store.teamCode ?? "",
                                    items: [item],
                                    createdBy: store.user?.email
                                )
                            )
                            title = ""
                            firstTask = ""
                            isShowingAddChecklist = false
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
        .padding()
        .background(Color.clear)
        .navigationTitle("Checklist")
        }
    }

    @ViewBuilder
    private func checklistRow(_ checklist: ChecklistTemplate) -> some View {
        Button {
            isShowingAddChecklist = false
            selectedChecklist = checklist
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(checklist.title).font(.headline)
                Text("\(checklist.items.count) items")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if isChecklistCompleted(checklist) {
                    if let completedAt = checklist.completedAt {
                        let completedBy = checklist.completedBy?.trimmingCharacters(in: .whitespacesAndNewlines)
                        if let completedBy, !completedBy.isEmpty {
                            Text("Completed by \(completedBy) on \(completedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Completed on \(completedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Completed")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Edit") {
                isShowingAddChecklist = false
                selectedChecklist = checklist
            }

            Button(role: .destructive) {
                store.deleteChecklist(checklist)
            } label: {
                Text("Delete")
            }
        }
    }

    private func isChecklistCompleted(_ checklist: ChecklistTemplate) -> Bool {
        !checklist.items.isEmpty && checklist.items.allSatisfy(\.isDone)
    }
}

private struct MacChecklistDetailView: View {
    @EnvironmentObject private var store: ProdConnectStore
    @State private var checklist: ChecklistTemplate
    @State private var isEditing = false
    @State private var originalChecklist: ChecklistTemplate?
    @State private var newItemText = ""

    init(checklist: ChecklistTemplate) {
        _checklist = State(initialValue: checklist)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Spacer()
                if isEditing {
                    Button("Cancel") {
                        if let originalChecklist {
                            checklist = originalChecklist
                        }
                        originalChecklist = nil
                        isEditing = false
                        newItemText = ""
                    }
                    .buttonStyle(.bordered)

                    Button("Save") {
                        saveChecklistChanges()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(checklist.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } else {
                    Button("Edit") {
                        originalChecklist = checklist
                        isEditing = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            Form {
                if isEditing {
                    Section("Overview") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Title")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("Title", text: $checklist.title)
                        }
                        LabeledContent("Created By", value: textValue(checklist.createdBy))
                        LabeledContent("Due Date", value: dateValue(checklist.dueDate))
                    }

                    Section("Items") {
                        if checklist.items.isEmpty {
                            Text("No checklist items")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(Array(checklist.items.indices), id: \.self) { index in
                                HStack(spacing: 10) {
                                    TextField("Item", text: $checklist.items[index].text)
                                    Button(role: .destructive) {
                                        checklist.items.remove(at: index)
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                        }

                        HStack(spacing: 10) {
                            TextField("New Item", text: $newItemText)
                            Button("Add Item") {
                                let trimmed = newItemText.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !trimmed.isEmpty else { return }
                                checklist.items.append(ChecklistItem(text: trimmed))
                                newItemText = ""
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(newItemText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                } else {
                    Section("Overview") {
                        LabeledContent("Title", value: checklist.title)
                        LabeledContent("Items", value: "\(checklist.items.count)")
                        LabeledContent("Created By", value: textValue(checklist.createdBy))
                        LabeledContent("Due Date", value: dateValue(checklist.dueDate))
                        LabeledContent("Completed At", value: dateValue(checklist.completedAt))
                        LabeledContent("Completed By", value: textValue(checklist.completedBy))
                    }

                    Section("Items") {
                        if checklist.items.isEmpty {
                            Text("No checklist items")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(checklist.items) { item in
                                Button {
                                    toggleItem(itemID: item.id)
                                } label: {
                                    HStack(alignment: .top, spacing: 10) {
                                        Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(item.isDone ? Color.green : Color.secondary)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(item.text)
                                                .foregroundStyle(.primary)
                                            if item.isDone, let completedAt = item.completedAt {
                                                if let completedBy = item.completedBy?.trimmingCharacters(in: .whitespacesAndNewlines),
                                                   !completedBy.isEmpty {
                                                    Text("Checked by \(completedBy) on \(completedAt.formatted(date: .abbreviated, time: .shortened))")
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                } else {
                                                    Text("Checked on \(completedAt.formatted(date: .abbreviated, time: .shortened))")
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                }
                                            }
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
        }
        .navigationTitle(checklist.title)
    }

    private func textValue(_ value: String?) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Not set" : trimmed
    }

    private func dateValue(_ value: Date?) -> String {
        guard let value else { return "Not set" }
        return value.formatted(date: .abbreviated, time: .shortened)
    }

    private func toggleItem(itemID: String) {
        guard let idx = checklist.items.firstIndex(where: { $0.id == itemID }) else { return }
        checklist.items[idx].isDone.toggle()
        if checklist.items[idx].isDone {
            checklist.items[idx].completedAt = Date()
            checklist.items[idx].completedBy = completionUserLabel
        } else {
            checklist.items[idx].completedAt = nil
            checklist.items[idx].completedBy = nil
        }
        updateChecklistCompletionMetadata()
        store.saveChecklist(checklist)
    }

    private func updateChecklistCompletionMetadata() {
        if checklist.items.isEmpty {
            checklist.completedAt = nil
            checklist.completedBy = nil
            return
        }

        if checklist.items.allSatisfy(\.isDone) {
            if checklist.completedAt == nil {
                checklist.completedAt = Date()
            }
            if (checklist.completedBy ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                checklist.completedBy = completionUserLabel
            }
        } else {
            checklist.completedAt = nil
            checklist.completedBy = nil
        }
    }

    private func saveChecklistChanges() {
        checklist.title = checklist.title.trimmingCharacters(in: .whitespacesAndNewlines)
        checklist.items = checklist.items.compactMap { item in
            let trimmed = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            var updatedItem = item
            updatedItem.text = trimmed
            return updatedItem
        }
        updateChecklistCompletionMetadata()
        store.saveChecklist(checklist)
        originalChecklist = nil
        newItemText = ""
        isEditing = false
    }

    private var completionUserLabel: String {
        let displayName = store.user?.displayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !displayName.isEmpty { return displayName }
        let email = store.user?.email.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !email.isEmpty { return email }
        return "Unknown User"
    }
}

private struct MacIdeasView: View {
    @EnvironmentObject private var store: ProdConnectStore
    @State private var title = ""
    @State private var detail = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            List {
                ForEach(store.ideas.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }) { idea in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(idea.title).font(.headline)
                            if idea.implemented {
                                Text("Implemented")
                                    .font(.caption2)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.green.opacity(0.25), in: Capsule())
                            }
                        }
                        if !idea.detail.isEmpty {
                            Text(idea.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
                .onDelete { indexSet in
                    let list = store.ideas.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
                    for index in indexSet {
                        store.deleteIdea(list[index])
                    }
                }
            }
            .scrollContentBackground(.hidden)

            GroupBox("Add Idea") {
                VStack(spacing: 10) {
                    TextField("Title", text: $title)
                    TextField("Detail", text: $detail)
                    Button("Save Idea") {
                        store.saveIdea(
                            IdeaCard(
                                title: title,
                                detail: detail,
                                teamCode: store.teamCode ?? "",
                                createdBy: store.user?.email
                            )
                        )
                        title = ""
                        detail = ""
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding()
        .background(Color.clear)
        .navigationTitle("Ideas")
    }
}

private struct MacCustomizeView: View {
    @EnvironmentObject private var store: ProdConnectStore
    @State private var newLocation = ""
    @State private var newRoom = ""
    @State private var gearSheetLink = ""
    @State private var audioPatchSheetLink = ""
    @State private var videoPatchSheetLink = ""
    @State private var lightingPatchSheetLink = ""
    @State private var isImporting = false
    @State private var resultMessage = ""
    @State private var pendingResetAction: ResetAction?

    private enum ResetAction: String, Identifiable {
        case deleteAllGear
        case deleteAudioPatchsheet
        case deleteVideoPatchsheet
        case deleteLightingPatchsheet

        var id: String { rawValue }

        var title: String {
            switch self {
            case .deleteAllGear: return "Delete All Gear?"
            case .deleteAudioPatchsheet: return "Delete Audio Patchsheet?"
            case .deleteVideoPatchsheet: return "Delete Video Patchsheet?"
            case .deleteLightingPatchsheet: return "Delete Lighting Patchsheet?"
            }
        }

        var message: String {
            switch self {
            case .deleteAllGear:
                return "Are you sure you want to delete all gear items? This cannot be undone."
            case .deleteAudioPatchsheet:
                return "Are you sure you want to delete all audio patches? This cannot be undone."
            case .deleteVideoPatchsheet:
                return "Are you sure you want to delete all video patches? This cannot be undone."
            case .deleteLightingPatchsheet:
                return "Are you sure you want to delete all lighting patches? This cannot be undone."
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 20) {
                    GroupBox("Campuses") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                TextField("Add campus", text: $newLocation)
                                Button("Save") {
                                    let trimmed = newLocation.trimmingCharacters(in: .whitespacesAndNewlines)
                                    guard !trimmed.isEmpty else { return }
                                    store.saveLocation(trimmed)
                                    newLocation = ""
                                }
                            }
                            Button {
                                syncGearLocationsToCampuses()
                            } label: {
                                Label("Copy Locations from Gear", systemImage: "arrow.triangle.2.circlepath")
                            }
                            .buttonStyle(.bordered)

                            List {
                                ForEach(store.locations.sorted(), id: \.self) { location in
                                    HStack {
                                        Text(location)
                                        Spacer()
                                        Button(role: .destructive) {
                                            store.deleteLocation(location)
                                        } label: {
                                            Image(systemName: "trash")
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .frame(minHeight: 220)
                            .scrollContentBackground(.hidden)
                        }
                    }

                    GroupBox("Rooms") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                TextField("Add room", text: $newRoom)
                                Button("Save") {
                                    let trimmed = newRoom.trimmingCharacters(in: .whitespacesAndNewlines)
                                    guard !trimmed.isEmpty else { return }
                                    store.saveRoom(trimmed)
                                    newRoom = ""
                                }
                            }
                            List {
                                ForEach(store.rooms.sorted(), id: \.self) { room in
                                    HStack {
                                        Text(room)
                                        Spacer()
                                        Button(role: .destructive) {
                                            store.deleteRoom(room)
                                        } label: {
                                            Image(systemName: "trash")
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .frame(minHeight: 220)
                            .scrollContentBackground(.hidden)
                        }
                    }
                }

                GroupBox("Import from Google Sheets") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Paste your Google Sheet share link and click Import.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        importRow(title: "Gear sheet link", text: $gearSheetLink) {
                            importGearData()
                        }
                        importRow(title: "Audio patchsheet link", text: $audioPatchSheetLink) {
                            importPatchData(category: "Audio", link: audioPatchSheetLink)
                        }
                        importRow(title: "Video patchsheet link", text: $videoPatchSheetLink) {
                            importPatchData(category: "Video", link: videoPatchSheetLink)
                        }
                        importRow(title: "Lighting patchsheet link", text: $lightingPatchSheetLink) {
                            importPatchData(category: "Lighting", link: lightingPatchSheetLink)
                        }
                    }
                }

                GroupBox("Reset") {
                    VStack(alignment: .leading, spacing: 10) {
                        resetButton("Delete All Gear", action: .deleteAllGear)
                        resetButton("Delete Audio Patchsheet", action: .deleteAudioPatchsheet)
                        resetButton("Delete Video Patchsheet", action: .deleteVideoPatchsheet)
                        resetButton("Delete Lighting Patchsheet", action: .deleteLightingPatchsheet)
                    }
                }

                if !resultMessage.isEmpty {
                    Text(resultMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(Color.clear)
        .navigationTitle("Customize")
        .alert(item: $pendingResetAction) { action in
            Alert(
                title: Text(action.title),
                message: Text(action.message),
                primaryButton: .destructive(Text("Delete")) {
                    performReset(action)
                },
                secondaryButton: .cancel()
            )
        }
    }

    @ViewBuilder
    private func importRow(title: String, text: Binding<String>, action: @escaping () -> Void) -> some View {
        HStack {
            TextField(title, text: text)
            Button("Import", action: action)
                .buttonStyle(.borderedProminent)
                .disabled(text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isImporting)
        }
    }

    @ViewBuilder
    private func resetButton(_ title: String, action: ResetAction) -> some View {
        Button(role: .destructive) {
            pendingResetAction = action
        } label: {
            Label(title, systemImage: "trash.fill")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.borderless)
    }

    private func performReset(_ action: ResetAction) {
        switch action {
        case .deleteAllGear:
            store.deleteAllGear()
            resultMessage = "All gear has been deleted."
        case .deleteAudioPatchsheet:
            store.deletePatchesByCategory("Audio")
            resultMessage = "Audio patchsheet has been deleted."
        case .deleteVideoPatchsheet:
            store.deletePatchesByCategory("Video")
            resultMessage = "Video patchsheet has been deleted."
        case .deleteLightingPatchsheet:
            store.deletePatchesByCategory("Lighting")
            resultMessage = "Lighting patchsheet has been deleted."
        }
    }

    private func syncGearLocationsToCampuses() {
        var existing = Set(store.locations.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        let source = Array(Set(store.gear.map { $0.location.trimmingCharacters(in: .whitespacesAndNewlines) }))
            .filter { !$0.isEmpty }
            .sorted()

        var added = 0
        for location in source {
            let key = location.lowercased()
            if !existing.contains(key) {
                store.saveLocation(location)
                existing.insert(key)
                added += 1
            }
        }

        resultMessage = added == 0 ? "No new locations to copy from Gear." : "Added \(added) location(s) from Gear."
    }

    private func importGearData() {
        isImporting = true
        let csvURL = convertGoogleSheetLinkToCSV(gearSheetLink)

        URLSession.shared.dataTask(with: csvURL) { data, _, error in
            guard let data, error == nil else {
                DispatchQueue.main.async {
                    isImporting = false
                    resultMessage = "Failed to fetch sheet: \(error?.localizedDescription ?? "Unknown error")"
                }
                return
            }

            guard let csvString = String(data: data, encoding: .utf8) else {
                DispatchQueue.main.async {
                    isImporting = false
                    resultMessage = "Failed to decode CSV response."
                }
                return
            }

            let gearItems = parseGearCSV(csvString)
            DispatchQueue.main.async {
                store.replaceAllGear(gearItems)
                gearSheetLink = ""
                isImporting = false
                resultMessage = "Imported \(gearItems.count) gear items."
            }
        }.resume()
    }

    private func importPatchData(category: String, link: String) {
        isImporting = true
        let csvURL = convertGoogleSheetLinkToCSV(link)

        URLSession.shared.dataTask(with: csvURL) { data, _, error in
            guard let data, error == nil else {
                DispatchQueue.main.async {
                    isImporting = false
                    resultMessage = "Failed to fetch sheet: \(error?.localizedDescription ?? "Unknown error")"
                }
                return
            }

            guard let csvString = String(data: data, encoding: .utf8) else {
                DispatchQueue.main.async {
                    isImporting = false
                    resultMessage = "Failed to decode CSV response."
                }
                return
            }

            let patchRows = parsePatchCSV(csvString).map { row in
                var updated = row
                updated.category = category
                return updated
            }

            DispatchQueue.main.async {
                store.replaceAllPatch(patchRows)
                switch category {
                case "Audio":
                    audioPatchSheetLink = ""
                case "Video":
                    videoPatchSheetLink = ""
                case "Lighting":
                    lightingPatchSheetLink = ""
                default:
                    break
                }
                isImporting = false
                resultMessage = "Imported \(patchRows.count) \(category) patches."
            }
        }.resume()
    }

    private func convertGoogleSheetLinkToCSV(_ link: String) -> URL {
        let cleanLink = link.trimmingCharacters(in: .whitespacesAndNewlines)
        if let spreadsheetID = extractSpreadsheetID(from: cleanLink) {
            return URL(string: "https://docs.google.com/spreadsheets/d/\(spreadsheetID)/export?format=csv")!
        }
        return URL(string: cleanLink)!
    }

    private func extractSpreadsheetID(from link: String) -> String? {
        guard let range = link.range(of: "/d/") else { return nil }
        let afterD = link[range.upperBound...]
        if let slashRange = afterD.range(of: "/") {
            return String(afterD[..<slashRange.lowerBound])
        }
        return String(afterD)
    }

    private func parseGearCSV(_ csv: String) -> [GearItem] {
        let lines = csv.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard lines.count > 1 else { return [] }

        var items: [GearItem] = []
        let headers = lines[0].components(separatedBy: ",")

        for line in lines.dropFirst() {
            let values = line.components(separatedBy: ",")
            var item = GearItem(name: "", category: "", teamCode: store.teamCode ?? "")

            for (index, header) in headers.enumerated() {
                guard index < values.count else { continue }
                let value = values[index].trimmingCharacters(in: .whitespaces)

                switch header.lowercased() {
                case "name": item.name = value
                case "category": item.category = value
                case "location": item.location = value
                case "campus": item.campus = value
                case "serial", "serialnumber": item.serialNumber = value
                case "asset id", "assetid": item.assetId = value
                case "status":
                    let lowerValue = value.lowercased()
                    if lowerValue.contains("stock") || lowerValue.contains("available") {
                        item.status = .available
                    } else if lowerValue.contains("in use") {
                        item.status = .inUse
                    } else if lowerValue.contains("repair") {
                        item.status = .needsRepair
                    } else if lowerValue.contains("retired") {
                        item.status = .retired
                    } else if lowerValue.contains("missing") {
                        item.status = .missing
                    } else {
                        item.status = .blank
                    }
                case "purchased", "purchasedate": item.purchaseDate = parseDate(value)
                case "purchasedfrom", "purchased from": item.purchasedFrom = value
                case "cost": item.cost = Double(value)
                case "install date", "installdate": item.installDate = parseDate(value)
                case "maintenance issue", "maintenanceissue": item.maintenanceIssue = value
                case "maintenance cost", "maintenancecost": item.maintenanceCost = Double(value)
                case "maintenance repair date", "maintenancerepairdate": item.maintenanceRepairDate = parseDate(value)
                case "maintenance notes", "maintenancenotes": item.maintenanceNotes = value
                case "image url", "imageurl": item.imageURL = value
                default: break
                }
            }

            if !item.name.isEmpty {
                items.append(item)
            }
        }

        return items
    }

    private func parsePatchCSV(_ csv: String) -> [PatchRow] {
        let lines = csv.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard lines.count > 1 else { return [] }

        var rows: [PatchRow] = []
        let headers = lines[0].components(separatedBy: ",")

        for line in lines.dropFirst() {
            let values = line.components(separatedBy: ",")
            var row = PatchRow(name: "", input: "", output: "", teamCode: store.teamCode ?? "", category: "", campus: "", room: "")

            for (index, header) in headers.enumerated() {
                guard index < values.count else { continue }
                let value = values[index].trimmingCharacters(in: .whitespaces)

                switch header.lowercased() {
                case "name": row.name = value
                case "input": row.input = value
                case "output": row.output = value
                case "category": row.category = value
                case "campus": row.campus = value
                case "room": row.room = value
                case "universe": row.universe = value
                default: break
                }
            }

            if !row.name.isEmpty {
                rows.append(row)
            }
        }

        return rows
    }

    private func parseDate(_ dateString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: dateString)
    }
}

private struct MacUsersView: View {
    @EnvironmentObject private var store: ProdConnectStore

    var body: some View {
        List(store.teamMembers.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }) { user in
            VStack(alignment: .leading, spacing: 4) {
                Text(user.displayName).font(.headline)
                Text(user.email).font(.caption).foregroundStyle(.secondary)
                if !user.assignedCampus.isEmpty {
                    Text(user.assignedCampus).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .navigationTitle("Users")
    }
}

private struct MacAccountView: View {
    @EnvironmentObject private var store: ProdConnectStore
    @State private var showEditAccount = false
    @State private var showDeleteConfirm = false
    @State private var showSubscriptionOptions = false
    @State private var isDeletingAccount = false
    @State private var errorMessage: String?
    @State private var subscriptionErrorMessage: String?

    private var roleLabel: String {
        if store.user?.isOwner == true { return "Owner" }
        if store.user?.isAdmin == true { return "Admin" }
        return "Basic"
    }

    private var appVersionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        if !version.isEmpty && !build.isEmpty {
            return "\(version) (\(build))"
        }
        return version.isEmpty ? build : version
    }

    private var normalizedSubscriptionTier: String {
        store.user?.subscriptionTier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "free"
    }

    private var canManageSubscription: Bool {
        guard let user = store.user else { return false }
        if normalizedSubscriptionTier == "free" {
            return true
        }
        return normalizedSubscriptionTier == "basic" && user.isAdmin
    }

    private var subscriptionButtonTitle: String {
        normalizedSubscriptionTier == "free" ? "Subscribe" : "Upgrade Subscription"
    }

    var body: some View {
        Form {
            if let user = store.user {
                LabeledContent("Name", value: user.displayName)
                LabeledContent("Email", value: user.email)
                LabeledContent("Team Code", value: user.teamCode ?? "None")
                LabeledContent("Subscription", value: user.subscriptionTier.capitalized)
                LabeledContent("Role", value: roleLabel)
                if !appVersionText.isEmpty {
                    LabeledContent("App Version", value: appVersionText)
                }
                if !user.assignedCampus.isEmpty {
                    LabeledContent("Campus", value: user.assignedCampus)
                }
            }

            if canManageSubscription {
                Section("Subscription") {
                    Button(subscriptionButtonTitle) {
                        showSubscriptionOptions = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            Section("Actions") {
                Button("Edit Account") {
                    showEditAccount = true
                }

                Button("Support") {
                    if let url = URL(string: "mailto:prodconnectapp@gmail.com") {
                        NSWorkspace.shared.open(url)
                    }
                }

                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Text(isDeletingAccount ? "Deleting..." : "Delete Account")
                }
                .disabled(isDeletingAccount)

                Button("Sign Out") {
                    store.signOut()
                }
                .buttonStyle(.borderedProminent)
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding()
        .background(Color.clear)
        .navigationTitle("Account")
        .sheet(isPresented: $showEditAccount) {
            MacEditAccountView()
                .environmentObject(store)
        }
        .sheet(isPresented: $showSubscriptionOptions) {
            MacSubscriptionOptionsView(
                currentTier: normalizedSubscriptionTier,
                onPurchaseBasic: {
                    await purchaseSubscription(productID: "Basic3", targetTier: "basic")
                },
                onPurchasePremium: {
                    await purchaseSubscription(productID: "Premium2", targetTier: "premium")
                },
                onRestorePurchases: {
                    await restorePurchases()
                }
            )
        }
        .alert("Subscription Error", isPresented: subscriptionErrorAlertIsPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(subscriptionErrorMessage ?? "Unknown subscription error.")
        }
        .alert("Delete Account?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                performAccountDeletion()
            }
        } message: {
            Text("This permanently deletes your account. You may need to sign in again before retrying if Apple requires recent authentication.")
        }
    }

    private func performAccountDeletion() {
        guard let currentUser = Auth.auth().currentUser else {
            errorMessage = "No logged in user."
            return
        }

        isDeletingAccount = true
        errorMessage = nil
        let uid = currentUser.uid

        currentUser.delete { deleteError in
            DispatchQueue.main.async {
                if let deleteError = deleteError as NSError? {
                    self.isDeletingAccount = false
                    if deleteError.code == AuthErrorCode.requiresRecentLogin.rawValue {
                        self.errorMessage = "For security, sign out and back in, then try deleting your account again."
                    } else {
                        self.errorMessage = "Account deletion failed: \(deleteError.localizedDescription)"
                    }
                    return
                }

                self.store.db.collection("users").document(uid).delete { _ in
                    DispatchQueue.main.async {
                        self.isDeletingAccount = false
                        self.store.signOut()
                    }
                }
            }
        }
    }

    private var subscriptionErrorAlertIsPresented: Binding<Bool> {
        Binding(
            get: { subscriptionErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    subscriptionErrorMessage = nil
                }
            }
        )
    }

    private func purchaseSubscription(productID: String, targetTier: String) async {
        do {
            let products = try await Product.products(for: [productID])
            guard let product = products.first else {
                throw MacSubscriptionError.productNotFound
            }

            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                try await applySubscription(targetTier: targetTier)
                await transaction.finish()
                showSubscriptionOptions = false
            case .userCancelled:
                break
            case .pending:
                throw MacSubscriptionError.pending
            @unknown default:
                throw MacSubscriptionError.unknown
            }
        } catch {
            subscriptionErrorMessage = error.localizedDescription
        }
    }

    private func restorePurchases() async {
        do {
            try await AppStore.sync()

            var restoredTier: String?
            for try await verification in Transaction.currentEntitlements {
                let transaction = try checkVerified(verification)
                if transaction.productID == "Premium2" {
                    restoredTier = "premium"
                    break
                }
                if transaction.productID == "Basic3" {
                    restoredTier = "basic"
                }
            }

            guard let restoredTier else {
                throw MacSubscriptionError.noActiveSubscription
            }

            try await applySubscription(targetTier: restoredTier)
            showSubscriptionOptions = false
        } catch {
            subscriptionErrorMessage = error.localizedDescription
        }
    }

    private func applySubscription(targetTier: String) async throws {
        guard var user = store.user else {
            throw MacSubscriptionError.userNotLoaded
        }

        let resolvedTier = targetTier.lowercased() == "premium" ? "premium" : "basic"
        user.isAdmin = true
        user.subscriptionTier = resolvedTier
        user.canEditPatchsheet = true
        user.canEditTraining = true
        user.canEditGear = true
        user.canEditIdeas = true
        user.canEditChecklists = true

        if (user.teamCode ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let generatedCode = store.generateTeamCode()
            user.teamCode = generatedCode
            try await store.db.collection("teams").document(generatedCode).setData([
                "code": generatedCode,
                "createdAt": FieldValue.serverTimestamp(),
                "createdBy": user.email,
                "isActive": true
            ], merge: true)
        }

        let uid = Auth.auth().currentUser?.uid ?? user.id
        let updates: [String: Any] = [
            "isAdmin": true,
            "subscriptionTier": user.subscriptionTier,
            "teamCode": user.teamCode ?? "",
            "canEditPatchsheet": true,
            "canEditTraining": true,
            "canEditGear": true,
            "canEditIdeas": true,
            "canEditChecklists": true
        ]

        try await store.db.collection("users").document(uid).setData(updates, merge: true)

        store.user = user
        store.teamCode = user.teamCode
        store.listenToTeamData()
        store.listenToTeamMembers()
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, _):
            throw MacSubscriptionError.verificationFailed
        case .verified(let signedType):
            return signedType
        }
    }
}

private struct MacSubscriptionOptionsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var basicProduct: Product?
    @State private var premiumProduct: Product?
    @State private var isLoadingProducts = false
    @State private var isPurchasing = false

    let currentTier: String
    let onPurchaseBasic: () async -> Void
    let onPurchasePremium: () async -> Void
    let onRestorePurchases: () async -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("ProdConnect Subscriptions")
                        .font(.title3.weight(.semibold))

                    Text("Choose the plan that fits your production team. Subscriptions renew automatically unless canceled in your Apple account settings.")
                        .foregroundStyle(.secondary)

                    subscriptionCard(
                        title: basicProduct?.displayName ?? "Basic",
                        subtitle: "Team management, user permissions, and full access to gear, training, checklists, and ideas.",
                        price: priceText(for: basicProduct),
                        buttonTitle: currentTier == "free" ? "Choose Basic" : "Current or Included",
                        isPrimary: true,
                        isDisabled: isPurchasing || currentTier != "free"
                    ) {
                        await runPurchase(onPurchaseBasic)
                    }

                    subscriptionCard(
                        title: premiumProduct?.displayName ?? "Premium",
                        subtitle: "Everything in Basic plus premium workspace features and expanded team management.",
                        price: priceText(for: premiumProduct),
                        buttonTitle: currentTier == "premium" ? "Current Plan" : "Choose Premium",
                        isPrimary: false,
                        isDisabled: isPurchasing || currentTier == "premium"
                    ) {
                        await runPurchase(onPurchasePremium)
                    }

                    Button(isPurchasing ? "Working..." : "Restore Purchases") {
                        Task {
                            await runPurchase(onRestorePurchases)
                        }
                    }
                    .disabled(isPurchasing)
                }
                .padding()
            }
            .navigationTitle("Subscription")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task {
                await loadProducts()
            }
        }
        .frame(minWidth: 520, minHeight: 420)
    }

    @ViewBuilder
    private func subscriptionCard(
        title: String,
        subtitle: String,
        price: String,
        buttonTitle: String,
        isPrimary: Bool,
        isDisabled: Bool,
        action: @escaping () async -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            Text(price)
                .font(.subheadline.weight(.medium))
            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)

            if isPrimary {
                Button(buttonTitle) {
                    Task {
                        await action()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isDisabled)
            } else {
                Button(buttonTitle) {
                    Task {
                        await action()
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isDisabled)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func loadProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }

        do {
            let products = try await Product.products(for: ["Basic3", "Premium2"])
            basicProduct = products.first(where: { $0.id == "Basic3" })
            premiumProduct = products.first(where: { $0.id == "Premium2" })
        } catch {
            // Keep the fallback copy visible even if products fail to load.
        }
    }

    private func priceText(for product: Product?) -> String {
        if isLoadingProducts {
            return "Loading pricing..."
        }
        return product?.displayPrice ?? "Available in App Store"
    }

    private func runPurchase(_ action: @escaping () async -> Void) async {
        guard !isPurchasing else { return }
        isPurchasing = true
        await action()
        isPurchasing = false
    }
}

private enum MacSubscriptionError: LocalizedError {
    case productNotFound
    case pending
    case unknown
    case noActiveSubscription
    case userNotLoaded
    case verificationFailed

    var errorDescription: String? {
        switch self {
        case .productNotFound:
            return "The subscription product could not be loaded."
        case .pending:
            return "The purchase is still pending approval."
        case .unknown:
            return "An unknown subscription error occurred."
        case .noActiveSubscription:
            return "No active subscription was found to restore."
        case .userNotLoaded:
            return "Your account information is not loaded yet."
        case .verificationFailed:
            return "The App Store transaction could not be verified."
        }
    }
}

private struct MacEditAccountView: View {
    @EnvironmentObject private var store: ProdConnectStore
    @Environment(\.dismiss) private var dismiss
    @State private var displayName = ""
    @State private var newEmail = ""
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Display Name") {
                    TextField("Display Name", text: $displayName)
                }

                Section("Login Email") {
                    TextField("New Email", text: $newEmail)
                        .autocorrectionDisabled(true)
                }

                Section("Password") {
                    SecureField("Current Password", text: $currentPassword)
                    SecureField("New Password", text: $newPassword)
                }

                Section {
                    Button("Save Changes") {
                        saveChanges()
                    }
                    .disabled(isSaving)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Edit Account")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                displayName = store.user?.displayName ?? ""
            }
        }
    }

    private func saveChanges() {
        guard let currentUser = Auth.auth().currentUser else {
            errorMessage = "No logged in user."
            return
        }

        errorMessage = nil
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = newEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = newPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        let emailChanged = !trimmedEmail.isEmpty && trimmedEmail != currentUser.email
        let passwordChanged = !trimmedPassword.isEmpty
        let nameChanged = !trimmedName.isEmpty && trimmedName != (store.user?.displayName ?? "")
        let needsReauth = emailChanged || passwordChanged

        if needsReauth && currentPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorMessage = "Current password is required to change email or password."
            return
        }

        isSaving = true

        func finish(_ error: Error?) {
            DispatchQueue.main.async {
                self.isSaving = false
                if let error {
                    self.errorMessage = error.localizedDescription
                } else {
                    dismiss()
                }
            }
        }

        func updateDisplayNameIfNeeded(completion: @escaping (Error?) -> Void) {
            guard nameChanged, let uid = store.user?.id else {
                completion(nil)
                return
            }
            store.db.collection("users").document(uid).updateData(["displayName": trimmedName]) { error in
                if error == nil {
                    store.user?.displayName = trimmedName
                    store.listenToTeamMembers()
                }
                completion(error)
            }
        }

        func updateEmailIfNeeded(completion: @escaping (Error?) -> Void) {
            guard emailChanged else {
                completion(nil)
                return
            }
            currentUser.updateEmail(to: trimmedEmail) { error in
                if let error {
                    completion(error)
                    return
                }
                self.store.db.collection("users").document(currentUser.uid).updateData(["email": trimmedEmail]) { updateError in
                    if updateError == nil {
                        self.store.user?.email = trimmedEmail
                    }
                    completion(updateError)
                }
            }
        }

        func updatePasswordIfNeeded(completion: @escaping (Error?) -> Void) {
            guard passwordChanged else {
                completion(nil)
                return
            }
            currentUser.updatePassword(to: trimmedPassword, completion: completion)
        }

        func runUpdates() {
            updateEmailIfNeeded { emailError in
                if let emailError {
                    finish(emailError)
                    return
                }
                updatePasswordIfNeeded { passwordError in
                    if let passwordError {
                        finish(passwordError)
                        return
                    }
                    updateDisplayNameIfNeeded { nameError in
                        finish(nameError)
                    }
                }
            }
        }

        if needsReauth {
            guard let email = currentUser.email else {
                finish(NSError(domain: "Auth", code: 0, userInfo: [NSLocalizedDescriptionKey: "Missing email for reauthentication."]))
                return
            }
            let credential = EmailAuthProvider.credential(withEmail: email, password: currentPassword)
            currentUser.reauthenticate(with: credential) { _, error in
                if let error {
                    finish(error)
                } else {
                    runUpdates()
                }
            }
        } else {
            runUpdates()
        }
    }
}
