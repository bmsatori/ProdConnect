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
    case tickets
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
        case .gear: return "Assets"
        case .tickets: return "Tickets"
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
        case .tickets: return "ticket"
        case .checklists: return "checklist"
        case .ideas: return "lightbulb"
        case .customize: return "paintbrush"
        case .users: return "person.3"
        case .account: return "person.crop.circle"
        }
    }

}

private func externalTicketFormSlug(from organizationName: String) -> String {
    let trimmed = organizationName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "prodconnect" }

    let lowered = trimmed.lowercased()
    let allowed = CharacterSet.alphanumerics
    var slug = ""
    var previousWasHyphen = false

    for scalar in lowered.unicodeScalars {
        if allowed.contains(scalar) {
            slug.unicodeScalars.append(scalar)
            previousWasHyphen = false
        } else if !previousWasHyphen {
            slug.append("-")
            previousWasHyphen = true
        }
    }

    slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    return slug.isEmpty ? "prodconnect" : slug
}

struct MacRootView: View {
    @EnvironmentObject private var store: ProdConnectStore
    @State private var selectedRoute: MacRoute? = .chat
    @State private var isShowingNotifications = false
    @State private var showsWelcomeScreen = true

    private var sidebarRoutes: [MacRoute] {
        MacRoute.allCases.filter { route in
            switch route {
            case .chat:
                return store.canSeeChat
            case .training:
                return store.canSeeTrainingTab
            case .tickets:
                return store.canUseTickets
            default:
                return true
            }
        }
    }

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

                    if showsWelcomeScreen {
                        MacWelcomeView(
                            userDisplayName: userDisplayName,
                            organizationDisplayName: organizationDisplayName,
                            routes: sidebarRoutes,
                            openRoute: { route in
                                selectedRoute = route
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showsWelcomeScreen = false
                                }
                            }
                        )
                    } else {
                        NavigationSplitView {
                            sidebar
                        } detail: {
                            detail
                        }
                        .navigationSplitViewStyle(.balanced)
                        .toolbar {
                            ToolbarItem(placement: .primaryAction) {
                                Button {
                                    isShowingNotifications = true
                                } label: {
                                    ZStack(alignment: .topTrailing) {
                                        Image(systemName: notificationBadgeCount > 0 ? "bell.badge.fill" : "bell")
                                            .font(.system(size: 16, weight: .semibold))

                                        if notificationBadgeCount > 0 {
                                            Text(notificationBadgeCount > 99 ? "99+" : "\(notificationBadgeCount)")
                                                .font(.system(size: 9, weight: .bold))
                                                .foregroundStyle(.white)
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 2)
                                                .background(Color.red, in: Capsule())
                                                .offset(x: 10, y: -8)
                                        }
                                    }
                                }
                                .help("Notifications")
                            }
                        }
                    }
                }
                .onAppear {
                    if let selectedRoute, !sidebarRoutes.contains(selectedRoute) {
                        self.selectedRoute = sidebarRoutes.first
                    } else if selectedRoute == nil {
                        self.selectedRoute = sidebarRoutes.first
                    }
                }
                .onChange(of: store.user?.id) { newValue in
                    showsWelcomeScreen = newValue != nil
                }
                .sheet(isPresented: $isShowingNotifications) {
                    MacNotificationsView()
                        .environmentObject(store)
                }
            }
        }
        .multilineTextAlignment(.leading)
    }

    private var notificationBadgeCount: Int {
        store.notificationBadgeCount
    }

    private var userDisplayName: String {
        let trimmedName = store.user?.displayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedName.isEmpty {
            return trimmedName
        }

        let fallbackEmail = store.user?.email.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let prefix = fallbackEmail.split(separator: "@").first, !prefix.isEmpty {
            return String(prefix)
        }
        return "User"
    }

    private var organizationDisplayName: String? {
        let trimmedName = store.organizationName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? nil : trimmedName
    }

    private var sidebar: some View {
        List(sidebarRoutes, selection: $selectedRoute) { route in
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
        case .tickets:
            MacTicketsView()
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

private struct MacWelcomeView: View {
    let userDisplayName: String
    let organizationDisplayName: String?
    let routes: [MacRoute]
    let openRoute: (MacRoute) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(red: 0.11, green: 0.55, blue: 0.53).opacity(0.2))
                .frame(width: 320, height: 320)
                .blur(radius: 28)
                .offset(x: -220, y: -170)

            Circle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 260, height: 260)
                .blur(radius: 30)
                .offset(x: 240, y: 200)

            VStack {
                Spacer()

                VStack(spacing: 24) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                            .frame(width: 92, height: 92)

                        Image(systemName: "person.crop.circle.badge.checkmark")
                            .font(.system(size: 36, weight: .semibold))
                            .foregroundStyle(.white)
                    }

                    VStack(spacing: 10) {
                        Text("Welcome")
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.68))

                        Text(userDisplayName)
                            .font(.system(size: 46, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)

                        if let organizationDisplayName, !organizationDisplayName.isEmpty {
                            Text(organizationDisplayName)
                                .font(.system(size: 28, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.82))
                                .multilineTextAlignment(.center)
                        }
                    }

                    Text("You’re signed in and ready to jump back in.")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)

                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(routes) { route in
                            Button {
                                openRoute(route)
                            } label: {
                                VStack(spacing: 10) {
                                    Image(systemName: route.icon)
                                        .font(.system(size: 20, weight: .semibold))
                                    Text(route.title)
                                        .font(.subheadline.weight(.semibold))
                                        .multilineTextAlignment(.center)
                                }
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, minHeight: 88)
                                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 36)
                .padding(.vertical, 38)
                .frame(maxWidth: 560)
                .background(
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 34, style: .continuous)
                                .stroke(Color.white.opacity(0.14), lineWidth: 1)
                        )
                )
                .shadow(color: Color.black.opacity(0.28), radius: 30, x: 0, y: 22)

                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 44)
        .padding(.vertical, 36)
    }
}

private struct MacNotificationsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: ProdConnectStore

    var body: some View {
        NavigationStack {
            List {
                if store.notificationIncomingChannels.isEmpty && store.notificationAssignedTickets.isEmpty && store.checklistNotificationNotices.isEmpty {
                    Text("No notifications")
                        .foregroundStyle(.secondary)
                }

                if !store.notificationIncomingChannels.isEmpty {
                    Section("Messages") {
                        ForEach(store.notificationIncomingChannels) { channel in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(channel.name.isEmpty ? "Chat" : channel.name)
                                    .font(.headline)
                                if let last = channel.messages.last {
                                    Text(last.text.isEmpty ? "New attachment" : last.text)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                if !store.notificationAssignedTickets.isEmpty {
                    Section("Assigned Tickets") {
                        ForEach(store.notificationAssignedTickets) { ticket in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(ticket.title.isEmpty ? "Untitled Ticket" : ticket.title)
                                    .font(.headline)
                                Text(ticket.status.rawValue)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                if !store.checklistNotificationNotices.isEmpty {
                    Section("Checklist Assignments") {
                        ForEach(store.checklistNotificationNotices) { notice in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(notice.checklist.title)
                                    .font(.headline)
                                Text(notice.item.text)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .navigationTitle("Notifications")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .frame(minWidth: 480, minHeight: 420)
        .onAppear {
            store.markAllNotificationsSeen()
        }
        .onChange(of: store.notificationBadgeCount) { _, _ in
            store.markAllNotificationsSeen()
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

    private var fallbackGradient: LinearGradient {
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
        ZStack {
            Group {
                if NSImage(named: "BackgroundImage") != nil {
                    Image("BackgroundImage")
                        .resizable()
                        .scaledToFill()
                        .ignoresSafeArea()
                } else {
                    fallbackGradient.ignoresSafeArea()
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

    private var currentEmail: String? {
        store.user?.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var groupChannels: [ChatChannel] {
        store.channels
            .filter { $0.kind == .group }
            .sorted { $0.position < $1.position }
    }

    private var directChannels: [ChatChannel] {
        store.channels
            .filter { $0.kind == .direct }
            .filter { channel in
                guard let currentEmail else { return true }
                let participants = channel.participantEmails.map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                }
                return participants.isEmpty || participants.contains(currentEmail)
            }
            .sorted { lhs, rhs in
                let lhsDate = lhs.lastMessageAt ?? .distantPast
                let rhsDate = rhs.lastMessageAt ?? .distantPast
                if lhsDate == rhsDate {
                    return channelTitle(lhs) < channelTitle(rhs)
                }
                return lhsDate > rhsDate
            }
    }

    private var directMessageUsersToShow: [UserProfile] {
        guard let currentEmail else { return [] }
        let existingOneToOneRecipients = Set(
            directChannels.compactMap { channel -> String? in
                let participants = channel.participantEmails
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                    .filter { !$0.isEmpty }
                guard participants.count == 2, participants.contains(currentEmail) else { return nil }
                return participants.first(where: { $0 != currentEmail })
            }
        )

        return store.teamMembers
            .filter {
                let email = $0.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return email != currentEmail && !existingOneToOneRecipients.contains(email)
            }
            .sorted { lhs, rhs in
                let lhsName = lhs.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                let rhsName = rhs.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !lhsName.isEmpty && !rhsName.isEmpty {
                    return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
                }
                return lhs.email.localizedCaseInsensitiveCompare(rhs.email) == .orderedAscending
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
                            ForEach(directMessageUsersToShow) { member in
                                Button {
                                    openOrCreateDirectMessage(with: [member])
                                } label: {
                                    Text(displayName(for: member.email))
                                }
                                .buttonStyle(.plain)
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
                                            ForEach(Array(channel.messages.enumerated()), id: \.element.id) { index, message in
                                                VStack(alignment: .leading, spacing: 0) {
                                                    if shouldShowDateHeader(for: index, in: channel.messages) {
                                                        Text(dateHeaderText(for: message.timestamp))
                                                            .font(.caption)
                                                            .foregroundStyle(.secondary)
                                                            .padding(.top, index == 0 ? 4 : 14)
                                                            .padding(.bottom, 8)
                                                            .frame(maxWidth: .infinity, alignment: .center)
                                                    }

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
                                        }
                                        .frame(width: scrollProxy.size.width, alignment: .leading)
                                    }
                                    .onAppear {
                                        scrollToLatestMessage(using: reader, in: channel)
                                    }
                                    .onChange(of: channel.messages.count) { _, _ in
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
        .onChange(of: selectedChannelID) { _, _ in
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

    private func openOrCreateDirectMessage(with members: [UserProfile]) {
        guard let teamCode = store.teamCode?.trimmingCharacters(in: .whitespacesAndNewlines), !teamCode.isEmpty else { return }
        guard let currentEmail else { return }

        let recipients = members
            .map { $0.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty && $0 != currentEmail }
        guard !recipients.isEmpty else { return }

        let participants = Array(Set(recipients + [currentEmail])).sorted()
        if let existing = store.channels.first(where: { channel in
            channel.kind == .direct
                && channel.participantEmails.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.sorted() == participants
        }) {
            selectedChannelID = existing.id
            return
        }

        let newChannel = ChatChannel(
            name: "Direct Message",
            teamCode: teamCode,
            position: 0,
            isReadOnly: false,
            isHidden: false,
            readOnlyUserEmails: [],
            hiddenUserEmails: [],
            messages: [],
            kind: .direct,
            participantEmails: participants,
            lastMessageAt: nil
        )
        store.saveChannel(newChannel)
        selectedChannelID = newChannel.id
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

    private func shouldShowDateHeader(for index: Int, in messages: [ChatMessage]) -> Bool {
        guard messages.indices.contains(index) else { return false }
        guard index > 0 else { return true }
        return !Calendar.current.isDate(messages[index].timestamp, inSameDayAs: messages[index - 1].timestamp)
    }

    private func dateHeaderText(for date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return "Today"
        }
        if Calendar.current.isDateInYesterday(date) {
            return "Yesterday"
        }
        return date.formatted(date: .abbreviated, time: .omitted)
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
    @State private var selectedPatch: PatchRow?

    private let categories = ["Audio", "Video", "Lighting"]

    private var filtered: [PatchRow] {
        store.patchsheet
            .filter { $0.category == selectedCategory }
            .sorted(by: PatchRow.autoSort)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Category", selection: $selectedCategory) {
                ForEach(categories, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.segmented)

            List {
                ForEach(filtered) { item in
                    Button {
                        selectedPatch = item
                    } label: {
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
                    .buttonStyle(.plain)
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
        .sheet(item: $selectedPatch) { patch in
            MacEditPatchView(patch: patch)
                .environmentObject(store)
        }
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

private struct MacEditPatchView: View {
    @EnvironmentObject private var store: ProdConnectStore
    @Environment(\.dismiss) private var dismiss
    @State private var patch: PatchRow
    @State private var channelCountText = ""
    @State private var universeText = ""
    @State private var errorMessage: String?
    @State private var showDeleteConfirmation = false
    @State private var isSaving = false

    init(patch: PatchRow) {
        _patch = State(initialValue: patch)
        _channelCountText = State(initialValue: patch.channelCount.map(String.init) ?? "")
        _universeText = State(initialValue: patch.universe ?? "")
    }

    private var canEdit: Bool { store.canEditPatchsheet }

    var body: some View {
        NavigationStack {
            Form {
                Section("Patch Details") {
                    TextField("Name", text: $patch.name).disabled(!canEdit)

                    if patch.category == "Lighting" {
                        TextField("DMX Channel", text: $patch.input).disabled(!canEdit)
                        TextField("Channel Count", text: $channelCountText).disabled(!canEdit)
                        TextField("Universe", text: $universeText).disabled(!canEdit)
                    } else if patch.category == "Video" {
                        TextField("Source", text: $patch.input).disabled(!canEdit)
                        TextField("Destination", text: $patch.output).disabled(!canEdit)
                    } else {
                        TextField("Input", text: $patch.input).disabled(!canEdit)
                        TextField("Output", text: $patch.output).disabled(!canEdit)
                    }

                    if store.locations.isEmpty {
                        TextField("Campus/Location", text: $patch.campus).disabled(!canEdit)
                    } else {
                        Picker("Campus/Location", selection: $patch.campus) {
                            Text("Select campus/location").tag("")
                            ForEach(store.locations.sorted(), id: \.self) { campus in
                                Text(campus).tag(campus)
                            }
                        }
                        .disabled(!canEdit)
                    }

                    if store.rooms.isEmpty {
                        TextField("Room", text: $patch.room).disabled(!canEdit)
                    } else {
                        Picker("Room", selection: $patch.room) {
                            Text("Select room").tag("")
                            ForEach(store.rooms.sorted(), id: \.self) { room in
                                Text(room).tag(room)
                            }
                        }
                        .disabled(!canEdit)
                    }
                }

                if canEdit {
                    Section {
                        Button("Delete Patch", role: .destructive) {
                            showDeleteConfirmation = true
                        }
                        .disabled(isSaving)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Edit Patch")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                if canEdit {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            isSaving = true
                            let trimmed = channelCountText.trimmingCharacters(in: .whitespacesAndNewlines)
                            let parsed = Int(trimmed) ?? 0
                            patch.channelCount = parsed > 0 ? parsed : nil
                            patch.universe = universeText.trimmingCharacters(in: .whitespacesAndNewlines)
                            store.savePatch(patch) { result in
                                switch result {
                                case .success:
                                    isSaving = false
                                    dismiss()
                                case .failure(let error):
                                    isSaving = false
                                    errorMessage = error.localizedDescription
                                }
                            }
                        }
                        .disabled(isSaving)
                    }
                }
            }
            .alert("Delete Patch?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    isSaving = true
                    store.deletePatch(patch) { result in
                        switch result {
                        case .success:
                            isSaving = false
                            dismiss()
                        case .failure(let error):
                            isSaving = false
                            errorMessage = error.localizedDescription
                        }
                    }
                }
            } message: {
                Text("This permanently deletes this patch.")
            }
        }
    }
}

private struct MacTrainingView: View {
    @EnvironmentObject private var store: ProdConnectStore
    @State private var selectedLesson: TrainingLesson?
    @State private var showAddTrainingSheet = false
    @State private var title = ""
    @State private var category = "Audio"
    @State private var urlString = ""

    private let categories = ["Audio", "Video", "Lighting", "Misc"]
    private var canSaveNewLesson: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Group {
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
                    HStack {
                        Spacer()
                        Button {
                            showAddTrainingSheet = true
                        } label: {
                            Label("Add", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                    }

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
                }
                .padding()
                .background(Color.clear)
                .navigationTitle("Training")
            }
        }
        .sheet(isPresented: $showAddTrainingSheet) {
            NavigationStack {
                Form {
                    TextField("Title", text: $title)
                    Picker("Category", selection: $category) {
                        ForEach(categories, id: \.self) { Text($0).tag($0) }
                    }
                    TextField("Video URL (optional)", text: $urlString)
                }
                .navigationTitle("Add Training")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            resetNewLessonForm()
                            showAddTrainingSheet = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            saveNewLesson()
                        }
                        .disabled(!canSaveNewLesson)
                    }
                }
            }
            .frame(minWidth: 420, minHeight: 240)
        }
    }

    private func hasPlayableURL(_ lesson: TrainingLesson) -> Bool {
        let raw = lesson.urlString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !raw.isEmpty && URL(string: raw) != nil
    }

    private func saveNewLesson() {
        store.saveLesson(
            TrainingLesson(
                title: title,
                category: category,
                teamCode: store.teamCode ?? "",
                urlString: urlString.isEmpty ? nil : urlString
            )
        )
        resetNewLessonForm()
        showAddTrainingSheet = false
    }

    private func resetNewLessonForm() {
        title = ""
        category = categories.first ?? "Audio"
        urlString = ""
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
    @State private var showDeleteAssetConfirmation = false
    @State private var deleteAssetErrorMessage: String?
    @State private var isExporting = false
    @State private var showMergeConfirm = false
    @State private var isMerging = false
    @State private var mergeResultMessage = ""
    @State private var showMergeResult = false
    @State private var duplicateGearGroupCount = 0
    @State private var saveErrorMessage: String?

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

                    gearEditor(title: "Edit Asset", buttonTitle: "Save Changes", fullScreen: true)
                }
                .padding()
                .background(Color.clear)
                .navigationTitle(name.isEmpty ? "Edit Asset" : name)
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

                        if store.canEditGear {
                            Button("Delete", role: .destructive) {
                                showDeleteAssetConfirmation = true
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    MacGearDetailView(
                        item: selectedGearItem,
                        statusColor: statusColor(for: selectedGearItem.status)
                    )
                }
                .padding()
                .background(Color.clear)
                .navigationTitle(selectedGearItem.name)
                .alert("Delete Asset?", isPresented: $showDeleteAssetConfirmation) {
                    Button("Cancel", role: .cancel) {}
                    Button("Delete", role: .destructive) {
                        let itemToDelete = selectedGearItem
                        store.deleteGear(items: [itemToDelete]) { result in
                            switch result {
                            case .success:
                                self.selectedGearItem = nil
                            case .failure(let error):
                                deleteAssetErrorMessage = error.localizedDescription
                            }
                        }
                    }
                } message: {
                    Text("This permanently deletes this asset.")
                }
                .alert("Unable to Delete Asset", isPresented: Binding(
                    get: { deleteAssetErrorMessage != nil },
                    set: { if !$0 { deleteAssetErrorMessage = nil } }
                )) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(deleteAssetErrorMessage ?? "")
                }
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
                Button(action: exportGear) {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .disabled(isExporting || filteredGear.isEmpty)

                Button(action: { showMergeConfirm = true }) {
                    Label("Merge", systemImage: "arrow.triangle.merge")
                }
                .buttonStyle(.bordered)
                .disabled(duplicateGearGroupCount == 0 || isMerging)

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

            TextField("Search assets...", text: $searchText)
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
                                let placement = [item.campus, item.location]
                                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                    .filter { !$0.isEmpty }
                                    .joined(separator: " • ")
                                if !placement.isEmpty {
                                    Text(placement).font(.caption2).foregroundStyle(.secondary)
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
                gearEditor(title: "Add Asset", buttonTitle: "Save Asset", fullScreen: false)
            }
        }
        .padding()
        .background(Color.clear)
        .navigationTitle("Assets")
            }
        }
        .alert("Merge Duplicates", isPresented: $showMergeConfirm) {
            Button("Merge", role: .destructive) { mergeDuplicates() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Found \(duplicateGearGroupCount) duplicate group(s). Merge now?")
        }
        .alert("Assets", isPresented: $showMergeResult) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(mergeResultMessage)
        }
        .alert("Unable to Save Asset", isPresented: Binding(
            get: { saveErrorMessage != nil },
            set: { if !$0 { saveErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveErrorMessage ?? "")
        }
        .onAppear {
            refreshDuplicateGroupCount()
        }
        .onReceive(store.$gear) { _ in
            refreshDuplicateGroupCount()
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

    private func findDuplicateGearGroups() -> [[GearItem]] {
        let grouped = Dictionary(grouping: store.gear) { item in
            let name = item.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let serial = item.serialNumber.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(name)|\(serial)"
        }
        return grouped.values.filter { $0.count > 1 }
    }

    private func refreshDuplicateGroupCount() {
        duplicateGearGroupCount = findDuplicateGearGroups().count
    }

    private func mergeDuplicates() {
        isMerging = true
        let groups = findDuplicateGearGroups()
        mergeDuplicateGroups(groups, mergedCount: 0)
    }

    private func mergeDuplicateGroups(_ groups: [[GearItem]], mergedCount: Int) {
        guard let group = groups.first else {
            isMerging = false
            mergeResultMessage = "Merged \(mergedCount) duplicate group(s)."
            showMergeResult = true
            return
        }

        guard var merged = group.first else {
            mergeDuplicateGroups(Array(groups.dropFirst()), mergedCount: mergedCount)
            return
        }

        for item in group.dropFirst() {
            if merged.category.isEmpty, !item.category.isEmpty { merged.category = item.category }
            if merged.location.isEmpty, !item.location.isEmpty { merged.location = item.location }
            if merged.maintenanceNotes.isEmpty, !item.maintenanceNotes.isEmpty { merged.maintenanceNotes = item.maintenanceNotes }
            if merged.status == .unknown, item.status != .unknown { merged.status = item.status }
        }

        let duplicatesToDelete = Array(group.dropFirst())
        store.deleteGear(items: duplicatesToDelete) { result in
            switch result {
            case .success:
                store.saveGear(merged) { saveResult in
                    switch saveResult {
                    case .success:
                        mergeDuplicateGroups(Array(groups.dropFirst()), mergedCount: mergedCount + 1)
                    case .failure(let error):
                        isMerging = false
                        mergeResultMessage = "Merge failed: \(error.localizedDescription)"
                        showMergeResult = true
                    }
                }
            case .failure(let error):
                isMerging = false
                mergeResultMessage = "Merge failed: \(error.localizedDescription)"
                showMergeResult = true
            }
        }
    }

    private func exportGear() {
        guard !filteredGear.isEmpty else { return }
        isExporting = true

        let header = [
            "Name",
            "Category",
            "Status",
            "Campus",
            "Room",
            "Serial Number",
            "Asset ID",
            "Purchased From",
            "Notes"
        ].map(csvEscaped).joined(separator: ",")

        let rows = filteredGear.map { item in
            [
                item.name,
                item.category,
                item.status.rawValue,
                item.campus,
                item.location,
                item.serialNumber,
                item.assetId,
                item.purchasedFrom,
                item.maintenanceNotes
            ].map(csvEscaped).joined(separator: ",")
        }

        let csv = "\u{FEFF}" + ([header] + rows).joined(separator: "\n")
        let savePanel = NSSavePanel()
        savePanel.title = "Export Assets"
        savePanel.nameFieldStringValue = "GearExport.csv"
        savePanel.allowedContentTypes = [.commaSeparatedText]
        savePanel.canCreateDirectories = true

        do {
            guard savePanel.runModal() == .OK, let url = savePanel.url else {
                isExporting = false
                return
            }
            try csv.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            mergeResultMessage = "Export failed: \(error.localizedDescription)"
            showMergeResult = true
        }

        isExporting = false
    }

    private func csvEscaped(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
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
                            if store.rooms.isEmpty {
                                labeledTextField("Room", text: $location)
                            } else {
                                fieldHeader("Room")
                                Picker("Room", selection: $location) {
                                    Text("Select room").tag("")
                                    ForEach(store.rooms.sorted(), id: \.self) { option in
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
                        let gearItem = GearItem(
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
                        store.saveGear(gearItem) { result in
                            switch result {
                            case .success:
                                editingGearID = nil
                                editingImageURL = nil
                                editingCreatedBy = nil
                                resetGearForm()
                                showAddGearForm = false
                            case .failure(let error):
                                saveErrorMessage = error.localizedDescription
                            }
                        }
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
                detailRow("Campus", item.campus)
                detailRow("Room", item.location)
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

            Section("Ticket History") {
                if item.ticketHistory.isEmpty {
                    Text("No tickets linked")
                        .foregroundStyle(.secondary)
                } else {
                    if !item.activeTicketIDs.isEmpty {
                        Text("\(item.activeTicketIDs.count) active ticket(s)")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    ForEach(item.ticketHistory.sorted { $0.updatedAt > $1.updatedAt }) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(entry.ticketTitle)
                                Spacer()
                                Text(entry.status.rawValue)
                                    .font(.caption)
                                    .foregroundStyle(entry.status == .resolved ? .green : .orange)
                            }
                            let locationLine = [entry.campus, entry.room]
                                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                .filter { !$0.isEmpty }
                                .joined(separator: " • ")
                            if !locationLine.isEmpty {
                                Text(locationLine)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Text((entry.resolvedAt ?? entry.updatedAt).formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
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

private struct MacTicketsView: View {
    @EnvironmentObject private var store: ProdConnectStore
    @State private var selectedTicket: SupportTicket?
    @State private var startsEditingSelectedTicket = false
    @State private var isShowingAddTicket = false
    @State private var title = ""
    @State private var detail = ""
    @State private var campus = ""
    @State private var room = ""
    @State private var hasDueDate = false
    @State private var dueDate = Date()
    @State private var attachmentURL: String?
    @State private var attachmentName: String?
    @State private var attachmentKind: TicketAttachmentKind?
    @State private var isUploadingAttachment = false
    @State private var attachmentError: String?
    @State private var locationFilter = ""
    @State private var statusFilter = ""
    @State private var agentFilter = ""
    @State private var externalTicketFormEnabled = false
    @State private var externalTicketFormAccessKey = ""
    @State private var isSavingExternalTicketForm = false
    @State private var externalTicketStatusMessage = ""

    private let unassignedAgentFilter = "__UNASSIGNED__"

    private var canManageExternalTicketForm: Bool {
        (store.user?.isAdmin == true || store.user?.isOwner == true)
            && (store.user?.hasTicketingFeatures == true)
    }

    private var externalTicketFormURLString: String {
        let teamCode = (store.teamCode ?? store.user?.teamCode ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let accessKey = externalTicketFormAccessKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard externalTicketFormEnabled, !teamCode.isEmpty, !accessKey.isEmpty else { return "" }
        let slug = externalTicketFormSlug(from: store.organizationName)
        return "https://prodconnect-1ea3a.web.app/support/\(slug)?team=\(teamCode)&key=\(accessKey)"
    }

    @ViewBuilder
    private var externalTicketFormSection: some View {
        if canManageExternalTicketForm {
            GroupBox("External Ticket Form") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Enable External Form", isOn: $externalTicketFormEnabled)

                    if !externalTicketFormURLString.isEmpty {
                        TextField("Public Link", text: .constant(externalTicketFormURLString))
                            .textFieldStyle(.roundedBorder)

                        HStack {
                            Button("Copy Public Link") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(externalTicketFormURLString, forType: .string)
                                externalTicketStatusMessage = "External ticket form link copied."
                            }
                            .buttonStyle(.bordered)

                            Button("Generate New Link") {
                                externalTicketFormEnabled = true
                                externalTicketFormAccessKey = store.generateExternalTicketAccessKey()
                                externalTicketStatusMessage = "New public link generated. Save to make it active."
                            }
                            .buttonStyle(.bordered)

                            Button {
                                saveExternalTicketForm()
                            } label: {
                                if isSavingExternalTicketForm {
                                    ProgressView()
                                } else {
                                    Text("Save External Form")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isSavingExternalTicketForm)
                        }
                    }

                    if !externalTicketStatusMessage.isEmpty {
                        Text(externalTicketStatusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var selectedTicketContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button {
                startsEditingSelectedTicket = false
                self.selectedTicket = nil
            } label: {
                Label("Back", systemImage: "chevron.left")
            }
            .buttonStyle(.bordered)

            if let selectedTicket {
                MacTicketDetailView(
                    ticket: selectedTicket,
                    startEditing: startsEditingSelectedTicket
                )
            }
        }
        .padding()
        .background(Color.clear)
        .navigationTitle("Ticket")
    }

    private var ticketsListContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !store.canUseTickets {
                ContentUnavailableView(
                    "Ticketing Locked",
                    systemImage: "ticket",
                    description: Text("Upgrade the team to Premium W/Ticketing to enable tickets.")
                )
            } else {
                if isShowingAddTicket {
                    ZStack(alignment: .topTrailing) {
                        VStack {
                            Spacer(minLength: 0)
                            HStack {
                                Spacer(minLength: 0)
                                addTicketSection
                                Spacer(minLength: 0)
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                        HStack(spacing: 10) {
                            Button("Cancel") {
                                isShowingAddTicket = false
                                resetNewTicketForm()
                            }
                            .buttonStyle(.bordered)

                            Button {
                                isShowingAddTicket = false
                                resetNewTicketForm()
                            } label: {
                                Label("Close", systemImage: "xmark")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(.top, 4)
                    }
                } else {
                    HStack {
                        Spacer()
                        Button {
                            resetNewTicketForm()
                            isShowingAddTicket = true
                        } label: {
                            Label("Add", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    HStack(spacing: 12) {
                        ticketLocationMenu
                        ticketStatusMenu
                        ticketAgentMenu
                    }

                    List {
                        if filteredTickets.isEmpty {
                            Text("No matching tickets")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(filteredTickets) { ticket in
                                ticketRow(ticket)
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
        }
        .padding()
        .background(Color.clear)
        .navigationTitle("Tickets")
    }

    private var addTicketSection: some View {
        GroupBox("Add Ticket") {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Title")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField("Issue title", text: $title)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Description")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextEditor(text: $detail)
                        .frame(minHeight: 120)
                        .padding(8)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 12) {
                    GridRow {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Due Date")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Toggle("Set due date", isOn: $hasDueDate)
                            if hasDueDate {
                                DatePicker("Due", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                                    .labelsHidden()
                            }
                        }

                        Color.clear
                    }

                    GridRow {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Campus")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            if store.locations.isEmpty {
                                TextField("Campus", text: $campus)
                                    .textFieldStyle(.roundedBorder)
                            } else {
                                Picker("Campus", selection: $campus) {
                                    Text("Select campus").tag("")
                                    ForEach(store.locations.sorted(), id: \.self) { option in
                                        Text(option).tag(option)
                                    }
                                }
                                .labelsHidden()
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Room")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            if store.rooms.isEmpty {
                                TextField("Room", text: $room)
                                    .textFieldStyle(.roundedBorder)
                            } else {
                                Picker("Room", selection: $room) {
                                    Text("Select room").tag("")
                                    ForEach(store.rooms.sorted(), id: \.self) { option in
                                        Text(option).tag(option)
                                    }
                                }
                                .labelsHidden()
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Attachment")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        Button("Upload Photo") {
                            pickTicketAttachment()
                        }
                        .buttonStyle(.bordered)
                        .disabled(isUploadingAttachment)

                        if attachmentURL != nil {
                            Button("Clear") {
                                attachmentURL = nil
                                attachmentName = nil
                                attachmentKind = nil
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    if isUploadingAttachment {
                        ProgressView("Uploading attachment…")
                    }
                    ticketAttachmentPreview(
                        urlString: attachmentURL,
                        attachmentName: attachmentName,
                        attachmentKind: attachmentKind
                    )
                }

                Button("Save Ticket") {
                    let activeTeamCode = [
                        store.teamCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                        store.user?.teamCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    ].first(where: { !$0.isEmpty }) ?? ""
                    store.saveTicket(
                        SupportTicket(
                            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                            detail: detail.trimmingCharacters(in: .whitespacesAndNewlines),
                            teamCode: activeTeamCode,
                            campus: campus.trimmingCharacters(in: .whitespacesAndNewlines),
                            room: room.trimmingCharacters(in: .whitespacesAndNewlines),
                            status: .new,
                            createdBy: store.user?.email ?? Auth.auth().currentUser?.email,
                            createdByUserID: store.user?.id,
                            dueDate: hasDueDate ? dueDate : nil,
                            lastUpdatedBy: currentUserLabel,
                            attachmentURL: attachmentURL,
                            attachmentName: attachmentName,
                            attachmentKind: attachmentKind,
                            activity: [
                                TicketActivityEntry(
                                    message: "Ticket created",
                                    createdAt: Date(),
                                    author: currentUserLabel
                                )
                            ]
                        )
                    )
                    isShowingAddTicket = false
                    resetNewTicketForm()
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .frame(maxWidth: 760, alignment: .leading)
        }
        .frame(maxWidth: 820)
    }

    private var availableAgents: [UserProfile] {
        store.teamMembers
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private var availableLocations: [String] {
        Array(Set(store.visibleTickets.map { $0.campus.trimmingCharacters(in: .whitespacesAndNewlines) }))
            .filter { !$0.isEmpty }
            .sorted()
    }

    private var filteredTickets: [SupportTicket] {
        store.visibleTickets.filter { ticket in
            let locationMatches = locationFilter.isEmpty
                || ticket.campus.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(locationFilter) == .orderedSame
            let statusMatches = statusFilter.isEmpty
                ? ticket.status != .resolved
                : ticket.status.rawValue == statusFilter
            let agentMatches: Bool
            if agentFilter.isEmpty {
                agentMatches = true
            } else if agentFilter == unassignedAgentFilter {
                agentMatches = (ticket.assignedAgentID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false)
            } else {
                agentMatches = ticket.assignedAgentID?.trimmingCharacters(in: .whitespacesAndNewlines) == agentFilter
            }
            return locationMatches && statusMatches && agentMatches
        }
    }

    var body: some View {
        if let selectedTicket {
            selectedTicketContent
        } else {
            ticketsListContent
        }
    }

    @ViewBuilder
    private func ticketRow(_ ticket: SupportTicket) -> some View {
        Button {
            startsEditingSelectedTicket = false
            selectedTicket = ticket
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(ticket.title)
                        .font(.headline)
                    Spacer()
                    Text(ticket.status.rawValue)
                        .font(.caption2)
                        .foregroundStyle(ticket.status == .resolved ? .green : .orange)
                }
                let locationLine = [ticket.campus, ticket.room]
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: " • ")
                if !locationLine.isEmpty {
                    Text(locationLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let dueDate = ticket.dueDate {
                    Text("Due \(dueDate.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(dueDate < Date() && ticket.status != .resolved ? .red : .secondary)
                }
                HStack {
                    if let linkedGearName = ticket.linkedGearName?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !linkedGearName.isEmpty {
                        Text(linkedGearName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(ticket.updatedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Edit") {
                startsEditingSelectedTicket = true
                selectedTicket = ticket
            }
        }
    }

    private func resetNewTicketForm() {
        title = ""
        detail = ""
        campus = store.user?.assignedCampus.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        room = ""
        hasDueDate = false
        dueDate = Date()
        attachmentURL = nil
        attachmentName = nil
        attachmentKind = nil
        isUploadingAttachment = false
        attachmentError = nil
    }

    private func loadExternalTicketFormState() {
        let settings = store.externalTicketFormIntegration
        externalTicketFormEnabled = settings.isEnabled
        externalTicketFormAccessKey = settings.accessKey
        if externalTicketFormAccessKey.isEmpty, canManageExternalTicketForm {
            externalTicketFormAccessKey = store.generateExternalTicketAccessKey()
        }
    }

    private func saveExternalTicketForm() {
        isSavingExternalTicketForm = true
        externalTicketStatusMessage = ""
        store.saveExternalTicketFormIntegration(
            isEnabled: externalTicketFormEnabled,
            accessKey: externalTicketFormAccessKey
        ) { result in
            isSavingExternalTicketForm = false
            switch result {
            case .success(let settings):
                externalTicketFormEnabled = settings.isEnabled
                externalTicketFormAccessKey = settings.accessKey
                externalTicketStatusMessage = settings.isEnabled ?
                    "External ticket form is live." :
                    "External ticket form is saved but disabled."
            case .failure(let error):
                externalTicketStatusMessage = "Save failed: \(error.localizedDescription)"
            }
        }
    }

    private var currentUserLabel: String {
        let name = store.user?.displayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !name.isEmpty { return name }
        return store.user?.email ?? Auth.auth().currentUser?.email ?? "Unknown User"
    }

    @ViewBuilder
    private func ticketAttachmentPreview(
        urlString: String?,
        attachmentName: String?,
        attachmentKind: TicketAttachmentKind?
    ) -> some View {
        let rawURL = urlString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if rawURL.isEmpty {
            Text("No attachment")
                .foregroundStyle(.secondary)
        } else if let url = URL(string: rawURL) {
            Link(destination: url) {
                Label(
                    attachmentName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                        ? (attachmentName ?? "Open Attachment")
                        : "Open Attachment",
                    systemImage: "paperclip"
                )
            }
        } else {
            Text("Invalid attachment link")
                .foregroundStyle(.secondary)
        }
    }

    @MainActor
    private func pickTicketAttachment() {
        attachmentError = nil

        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]

        let handleSelection: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            uploadTicketAttachment(from: url, kind: inferredTicketAttachmentKind(for: url))
        }

        if let keyWindow = NSApp.keyWindow {
            panel.beginSheetModal(for: keyWindow, completionHandler: handleSelection)
        } else {
            handleSelection(panel.runModal())
        }
    }

    private func uploadTicketAttachment(from localURL: URL, kind: TicketAttachmentKind) {
        attachmentError = nil
        isUploadingAttachment = true

        let safeName = localURL.lastPathComponent.replacingOccurrences(of: " ", with: "_")
        let path = "ticketAttachments/\(UUID().uuidString)/\(UUID().uuidString)-\(safeName)"
        let storageRef = Storage.storage().reference().child(path)
        let metadata = StorageMetadata()
        metadata.contentType = contentType(for: localURL, kind: kind)
        let didAccess = localURL.startAccessingSecurityScopedResource()

        storageRef.putFile(from: localURL, metadata: metadata) { _, error in
            if didAccess {
                localURL.stopAccessingSecurityScopedResource()
            }

            if let error {
                DispatchQueue.main.async {
                    isUploadingAttachment = false
                    attachmentError = "Attachment upload failed: \(error.localizedDescription)"
                }
                return
            }

            storageRef.downloadURL { url, downloadError in
                DispatchQueue.main.async {
                    isUploadingAttachment = false
                    if let downloadError {
                        attachmentError = "Attachment upload failed: \(downloadError.localizedDescription)"
                        return
                    }
                    attachmentURL = url?.absoluteString
                    attachmentName = safeName
                    attachmentKind = kind
                }
            }
        }
    }

    private func contentType(for url: URL, kind: TicketAttachmentKind) -> String {
        if let type = UTType(filenameExtension: url.pathExtension), let mime = type.preferredMIMEType {
            return mime
        }
        switch kind {
        case .image:
            return "image/jpeg"
        case .video:
            return "video/quicktime"
        case .document:
            return "application/octet-stream"
        }
    }

    private func inferredTicketAttachmentKind(for url: URL) -> TicketAttachmentKind {
        if let type = UTType(filenameExtension: url.pathExtension) {
            if type.conforms(to: .image) {
                return .image
            }
            if type.conforms(to: .movie) || type.conforms(to: .video) {
                return .video
            }
        }
        return .document
    }

    private var ticketLocationMenu: some View {
        Menu {
            Button("Clear") { locationFilter = "" }
            Divider()
            ForEach(availableLocations, id: \.self) { option in
                Button(option) { locationFilter = option }
            }
        } label: {
            filterChip(
                title: locationFilter.isEmpty ? "Location" : locationFilter,
                icon: "mappin.circle",
                isActive: !locationFilter.isEmpty
            )
        }
    }

    private var ticketStatusMenu: some View {
        Menu {
            Button("Active") { statusFilter = "" }
            Divider()
            ForEach(TicketStatus.allCases, id: \.self) { option in
                Button(option.rawValue) { statusFilter = option.rawValue }
            }
        } label: {
            filterChip(
                title: statusFilter.isEmpty ? "Active" : statusFilter,
                icon: "checkmark.circle",
                isActive: !statusFilter.isEmpty
            )
        }
    }

    private var ticketAgentMenu: some View {
        Menu {
            Button("Clear") { agentFilter = "" }
            Divider()
            Button("Unassigned") { agentFilter = unassignedAgentFilter }
            if !availableAgents.isEmpty {
                Divider()
                ForEach(availableAgents) { member in
                    Button(member.displayName) { agentFilter = member.id }
                }
            }
        } label: {
            filterChip(
                title: agentFilterTitle,
                icon: "person.crop.circle",
                isActive: !agentFilter.isEmpty
            )
        }
    }

    private var agentFilterTitle: String {
        if agentFilter.isEmpty { return "Agent" }
        if agentFilter == unassignedAgentFilter { return "Unassigned" }
        return availableAgents.first(where: { $0.id == agentFilter })?.displayName ?? "Agent"
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
}

private struct MacTicketDetailView: View {
    @EnvironmentObject private var store: ProdConnectStore
    @State private var ticket: SupportTicket
    @State private var isEditing = false
    @State private var originalTicket: SupportTicket?
    @State private var scheduledStatusSaveWorkItem: DispatchWorkItem?
    @State private var showAssetPicker = false
    @State private var isUploadingAttachment = false
    @State private var attachmentError: String?
    @State private var newPrivateNote = ""

    init(ticket: SupportTicket, startEditing: Bool = false) {
        _ticket = State(initialValue: ticket)
        _isEditing = State(initialValue: startEditing)
        _originalTicket = State(initialValue: startEditing ? ticket : nil)
    }

    private var availableAgents: [UserProfile] {
        store.teamMembers
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private var availableGear: [GearItem] {
        store.gear.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func scheduleStatusSave() {
        scheduledStatusSaveWorkItem?.cancel()
        var ticketToSave = ticket
        ticketToSave.lastUpdatedBy = currentUserLabel
        let workItem = DispatchWorkItem {
            store.saveTicket(ticketToSave)
        }
        scheduledStatusSaveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Spacer()
                if isEditing {
                    Button("Cancel") {
                        if let originalTicket {
                            ticket = originalTicket
                        }
                        originalTicket = nil
                        isEditing = false
                    }
                    .buttonStyle(.bordered)

                    Button("Save") {
                        appendPendingPrivateNoteIfNeeded()
                        ticket.lastUpdatedBy = currentUserLabel
                        store.saveTicket(ticket)
                        originalTicket = nil
                        isEditing = false
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(ticket.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } else {
                    Button("Edit") {
                        originalTicket = ticket
                        isEditing = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            Form {
                Section("Overview") {
                    if isEditing {
                        TextField("Title", text: $ticket.title)
                        TextEditor(text: $ticket.detail)
                            .frame(minHeight: 120)
                    } else {
                        Text(ticket.title)
                        Text(ticket.detail.isEmpty ? "No details" : ticket.detail)
                            .foregroundStyle(ticket.detail.isEmpty ? .secondary : .primary)
                    }
                }

                Section("Status") {
                    Picker(
                        "Status",
                        selection: Binding(
                            get: { ticket.status },
                            set: { newValue in
                                ticket.status = newValue
                                if !isEditing {
                                    scheduleStatusSave()
                                }
                            }
                        )
                    ) {
                        ForEach(TicketStatus.allCases, id: \.self) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                }

                Section("Due Date") {
                    if isEditing {
                        Toggle("Set Due Date", isOn: hasDueDateBinding)
                        if ticket.dueDate != nil {
                            DatePicker("Due", selection: dueDateBinding, displayedComponents: [.date, .hourAndMinute])
                        }
                    } else if let dueDate = ticket.dueDate {
                        Text(dueDate.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(dueDate < Date() && ticket.status != .resolved ? .red : .primary)
                    } else {
                        Text("Not set")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Location") {
                    if isEditing {
                        if store.locations.isEmpty {
                            TextField("Campus", text: $ticket.campus)
                        } else {
                            Picker("Campus", selection: $ticket.campus) {
                                Text("Select campus").tag("")
                                ForEach(store.locations.sorted(), id: \.self) { option in
                                    Text(option).tag(option)
                                }
                            }
                        }
                        if store.rooms.isEmpty {
                            TextField("Room", text: $ticket.room)
                        } else {
                            Picker("Room", selection: $ticket.room) {
                                Text("Select room").tag("")
                                ForEach(store.rooms.sorted(), id: \.self) { option in
                                    Text(option).tag(option)
                                }
                            }
                        }
                    } else {
                        let locationLine = [ticket.campus, ticket.room]
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
                            .joined(separator: " • ")
                        Text(locationLine.isEmpty ? "Not set" : locationLine)
                            .foregroundStyle(locationLine.isEmpty ? .secondary : .primary)
                    }
                }

                Section("Linked Asset") {
                    if isEditing {
                        Button {
                            showAssetPicker = true
                        } label: {
                            HStack {
                                Text("Asset")
                                Spacer()
                                Text(selectedAssetLabel)
                                    .foregroundStyle(selectedAssetName == nil ? .secondary : .primary)
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        if ticket.linkedGearID != nil || ticket.linkedGearName != nil {
                            Button("Clear Asset Link") {
                                ticket.linkedGearID = nil
                                ticket.linkedGearName = nil
                            }
                        }
                    } else {
                        Text((ticket.linkedGearName ?? "").isEmpty ? "None" : (ticket.linkedGearName ?? ""))
                            .foregroundStyle((ticket.linkedGearName ?? "").isEmpty ? .secondary : .primary)
                    }
                }

                Section("Attachment") {
                    if isEditing {
                        HStack(spacing: 10) {
                            Button("Upload Photo") {
                                pickTicketAttachment()
                            }
                            .buttonStyle(.bordered)
                            .disabled(isUploadingAttachment)

                            if ticket.attachmentURL != nil {
                                Button("Clear Attachment") {
                                    ticket.attachmentURL = nil
                                    ticket.attachmentName = nil
                                    ticket.attachmentKind = nil
                                }
                            }
                        }
                        if isUploadingAttachment {
                            ProgressView("Uploading attachment…")
                        }
                        if let attachmentError, !attachmentError.isEmpty {
                            Text(attachmentError)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }

                    ticketAttachmentPreview
                }

                Section("Assignment") {
                    if isEditing && store.canSeeAllTickets {
                        Picker(
                            "Agent",
                            selection: Binding(
                                get: { ticket.assignedAgentID ?? "" },
                                set: { newValue in
                                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if trimmed.isEmpty {
                                        ticket.assignedAgentID = nil
                                        ticket.assignedAgentName = nil
                                    } else if let member = availableAgents.first(where: { $0.id == trimmed }) {
                                        ticket.assignedAgentID = member.id
                                        ticket.assignedAgentName = member.displayName
                                    }
                                }
                            )
                        ) {
                            Text("Unassigned").tag("")
                            ForEach(availableAgents) { member in
                                Text(member.displayName).tag(member.id)
                            }
                        }
                    } else {
                        Text((ticket.assignedAgentName ?? "").isEmpty ? "Unassigned" : (ticket.assignedAgentName ?? ""))
                            .foregroundStyle((ticket.assignedAgentName ?? "").isEmpty ? .secondary : .primary)
                    }
                }

                Section("Requester") {
                    if let requesterName = requesterName {
                        LabeledContent("Name", value: requesterName)
                    }
                    if let requesterEmail = requesterEmail {
                        LabeledContent("Email", value: requesterEmail)
                        Button("Email Requester") {
                            if let url = requesterEmailURL {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    } else {
                        Text("No requester email")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Private Notes") {
                    if isEditing {
                        TextEditor(text: $newPrivateNote)
                            .frame(minHeight: 120)
                            .overlay(alignment: .topLeading) {
                                if newPrivateNote.isEmpty {
                                    Text("Add a private note")
                                        .foregroundStyle(.secondary)
                                        .padding(.top, 8)
                                        .padding(.leading, 5)
                                }
                            }
                    }
                    if ticket.privateNoteEntries.isEmpty {
                        Text("No private notes")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(ticket.privateNoteEntries.sorted { $0.createdAt > $1.createdAt }) { entry in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.message)
                                HStack {
                                    if let author = entry.author?.trimmingCharacters(in: .whitespacesAndNewlines),
                                       !author.isEmpty {
                                        Text(author)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    Text("Visible only inside ProdConnect.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Activity") {
                    if ticket.activity.isEmpty {
                        Text("No updates yet")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(ticket.activity.sorted { $0.createdAt > $1.createdAt }) { entry in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.message)
                                HStack {
                                    if let author = entry.author?.trimmingCharacters(in: .whitespacesAndNewlines),
                                       !author.isEmpty {
                                        Text(author)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
        }
        .navigationTitle("Ticket")
        .sheet(isPresented: $showAssetPicker) {
            MacAssetPickerView(
                selectedAssetID: ticket.linkedGearID,
                onSelect: { item in
                    ticket.linkedGearID = item.id
                    ticket.linkedGearName = item.name
                }
            )
            .environmentObject(store)
        }
        .onAppear {
            newPrivateNote = ""
        }
    }

    private var currentUserLabel: String {
        let name = store.user?.displayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !name.isEmpty { return name }
        return store.user?.email ?? Auth.auth().currentUser?.email ?? "Unknown User"
    }

    private func appendPendingPrivateNoteIfNeeded() {
        let trimmedNote = newPrivateNote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNote.isEmpty else { return }
        ticket.privateNoteEntries.append(
            TicketPrivateNoteEntry(
                message: trimmedNote,
                createdAt: Date(),
                author: currentUserLabel
            )
        )
        newPrivateNote = ""
    }

    private var selectedAssetName: String? {
        let currentName = ticket.linkedGearName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !currentName.isEmpty {
            return currentName
        }
        guard let linkedGearID = ticket.linkedGearID else { return nil }
        return availableGear.first(where: { $0.id == linkedGearID })?.name
    }

    private var selectedAssetLabel: String {
        selectedAssetName ?? "Select Asset"
    }

    private var requesterName: String? {
        let candidates = [
            ticket.externalRequesterName,
            ticket.createdBy?.components(separatedBy: "@").first
        ]
        return candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
    }

    private var requesterEmail: String? {
        let candidates = [
            ticket.externalRequesterEmail,
            ticket.createdBy
        ]
        return candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty && $0.contains("@") })
    }

    private var requesterEmailURL: URL? {
        guard let requesterEmail else { return nil }
        let subject = "Re: \(ticket.title.isEmpty ? "Your Support Ticket" : ticket.title)"
        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "mailto:\(requesterEmail)?subject=\(encodedSubject)")
    }

    private var hasDueDateBinding: Binding<Bool> {
        Binding(
            get: { ticket.dueDate != nil },
            set: { isEnabled in
                ticket.dueDate = isEnabled ? (ticket.dueDate ?? Date()) : nil
            }
        )
    }

    private var dueDateBinding: Binding<Date> {
        Binding(
            get: { ticket.dueDate ?? Date() },
            set: { ticket.dueDate = $0 }
        )
    }

    @ViewBuilder
    private var ticketAttachmentPreview: some View {
        let rawURL = ticket.attachmentURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if rawURL.isEmpty {
            Text("No attachment")
                .foregroundStyle(.secondary)
        } else if let url = URL(string: rawURL) {
            Link(destination: url) {
                Label(
                    ticket.attachmentName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                        ? (ticket.attachmentName ?? "Open Attachment")
                        : "Open Attachment",
                    systemImage: "paperclip"
                )
            }
        } else {
            Text("Invalid attachment link")
                .foregroundStyle(.secondary)
        }
    }

    @MainActor
    private func pickTicketAttachment() {
        attachmentError = nil

        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]

        let handleSelection: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            uploadTicketAttachment(from: url, kind: inferredTicketAttachmentKind(for: url))
        }

        if let keyWindow = NSApp.keyWindow {
            panel.beginSheetModal(for: keyWindow, completionHandler: handleSelection)
        } else {
            handleSelection(panel.runModal())
        }
    }

    private func uploadTicketAttachment(from localURL: URL, kind: TicketAttachmentKind) {
        attachmentError = nil
        isUploadingAttachment = true

        let safeName = localURL.lastPathComponent.replacingOccurrences(of: " ", with: "_")
        let path = "ticketAttachments/\(ticket.id)/\(UUID().uuidString)-\(safeName)"
        let storageRef = Storage.storage().reference().child(path)
        let metadata = StorageMetadata()
        metadata.contentType = contentType(for: localURL, kind: kind)
        let didAccess = localURL.startAccessingSecurityScopedResource()

        storageRef.putFile(from: localURL, metadata: metadata) { _, error in
            if didAccess {
                localURL.stopAccessingSecurityScopedResource()
            }

            if let error {
                DispatchQueue.main.async {
                    isUploadingAttachment = false
                    attachmentError = "Attachment upload failed: \(error.localizedDescription)"
                }
                return
            }

            storageRef.downloadURL { url, downloadError in
                DispatchQueue.main.async {
                    isUploadingAttachment = false
                    if let downloadError {
                        attachmentError = "Attachment upload failed: \(downloadError.localizedDescription)"
                        return
                    }
                    ticket.attachmentURL = url?.absoluteString
                    ticket.attachmentName = safeName
                    ticket.attachmentKind = kind
                }
            }
        }
    }

    private func contentType(for url: URL, kind: TicketAttachmentKind) -> String {
        if let type = UTType(filenameExtension: url.pathExtension), let mime = type.preferredMIMEType {
            return mime
        }
        switch kind {
        case .image:
            return "image/jpeg"
        case .video:
            return "video/quicktime"
        case .document:
            return "application/octet-stream"
        }
    }

    private func inferredTicketAttachmentKind(for url: URL) -> TicketAttachmentKind {
        if let type = UTType(filenameExtension: url.pathExtension) {
            if type.conforms(to: .image) {
                return .image
            }
            if type.conforms(to: .movie) || type.conforms(to: .video) {
                return .video
            }
        }
        return .document
    }
}

private struct MacAssetPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: ProdConnectStore
    @State private var searchText = ""
    @State private var selectedCategory: String?
    @State private var selectedStatus: GearItem.GearStatus?
    @State private var selectedLocation: String?

    let selectedAssetID: String?
    let onSelect: (GearItem) -> Void

    private var availableCategories: [String] {
        Array(Set(store.gear.map(\.category))).filter { !$0.isEmpty }.sorted()
    }

    private var availableLocations: [String] {
        Array(Set(store.gear.map(\.location))).filter { !$0.isEmpty }.sorted()
    }

    private var filteredAssets: [GearItem] {
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
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Select Asset")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
            }

            TextField("Search assets...", text: $searchText)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 12) {
                categoryMenu
                if !availableLocations.isEmpty {
                    locationMenu
                }
                statusMenu
            }

            List {
                if filteredAssets.isEmpty {
                    Text("No assets found")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filteredAssets) { item in
                        Button {
                            onSelect(item)
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.name)
                                        .font(.headline)
                                    Text(item.category)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if !item.location.isEmpty {
                                        Text(item.location)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if item.id == selectedAssetID {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .padding()
        .frame(minWidth: 520, minHeight: 520)
    }

    private var categoryMenu: some View {
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
    }

    private var locationMenu: some View {
        Menu {
            Button("Clear") { selectedLocation = nil }
            Divider()
            ForEach(availableLocations, id: \.self) { option in
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

    private var statusMenu: some View {
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
}

private struct MacChecklistView: View {
    @EnvironmentObject private var store: ProdConnectStore
    @State private var selectedChecklist: ChecklistTemplate?
    @State private var startsEditingSelectedChecklist = false
    @State private var isShowingAddChecklist = false
    @State private var title = ""
    @State private var newChecklistItems = Array(repeating: "", count: 3)
    @State private var hasDueDate = false
    @State private var dueDate = Date()

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
                    startsEditingSelectedChecklist = false
                    self.selectedChecklist = nil
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.bordered)

                MacChecklistDetailView(
                    checklist: selectedChecklist,
                    startEditing: startsEditingSelectedChecklist
                )
            }
            .padding()
            .background(Color.clear)
            .navigationTitle(selectedChecklist.title)
        } else {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Spacer()
                if isShowingAddChecklist {
                    Button("Cancel") {
                        isShowingAddChecklist = false
                        resetNewChecklistForm()
                    }
                    .buttonStyle(.bordered)
                }
                Button {
                    if isShowingAddChecklist {
                        isShowingAddChecklist = false
                        resetNewChecklistForm()
                    } else {
                        resetNewChecklistForm()
                        isShowingAddChecklist = true
                    }
                } label: {
                    Label("Add", systemImage: "plus")
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
                        Toggle("Set due date", isOn: $hasDueDate)
                        if hasDueDate {
                            DatePicker("Due", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                        }
                        Text("Items")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(Array(newChecklistItems.indices), id: \.self) { index in
                            TextField("Item \(index + 1)", text: $newChecklistItems[index])
                        }
                        Button("Add Another Item") {
                            newChecklistItems.append("")
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Button("Save Checklist") {
                            let parsedItems = newChecklistItems.compactMap { item -> ChecklistItem? in
                                let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !trimmed.isEmpty else { return nil }
                                return ChecklistItem(text: trimmed)
                            }
                            let items = parsedItems.isEmpty ? [ChecklistItem(text: "New Item")] : parsedItems
                            var checklist = ChecklistTemplate(
                                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                                teamCode: store.teamCode ?? "",
                                items: items,
                                createdBy: store.user?.email
                            )
                            checklist.dueDate = hasDueDate ? dueDate : nil
                            store.saveChecklist(checklist)
                            resetNewChecklistForm()
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
            startsEditingSelectedChecklist = false
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
            Button("Duplicate") {
                duplicateChecklist(checklist)
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

    private func duplicateChecklist(_ checklist: ChecklistTemplate) {
        var copy = checklist
        copy.id = UUID().uuidString
        copy.title = "\(checklist.title) Copy"
        copy.dueDate = nil
        copy.completedAt = nil
        copy.completedBy = nil
        copy.items = checklist.items.map { item in
            var newItem = item
            newItem.id = UUID().uuidString
            newItem.isDone = false
            newItem.completedAt = nil
            newItem.completedBy = nil
            return newItem
        }
        copy.createdBy = Auth.auth().currentUser?.email
        store.saveChecklist(copy)
    }

    private func resetNewChecklistForm() {
        title = ""
        newChecklistItems = Array(repeating: "", count: 3)
        hasDueDate = false
        dueDate = Date()
    }
}

private struct MacChecklistDetailView: View {
    @EnvironmentObject private var store: ProdConnectStore
    @State private var checklist: ChecklistTemplate
    @State private var isEditing = false
    @State private var originalChecklist: ChecklistTemplate?
    @State private var newItemText = ""
    @State private var newItemNotes = ""

    init(checklist: ChecklistTemplate, startEditing: Bool = false) {
        _checklist = State(initialValue: checklist)
        _isEditing = State(initialValue: startEditing)
        _originalChecklist = State(initialValue: startEditing ? checklist : nil)
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
                        newItemNotes = ""
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
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: 10) {
                                        TextField("Item", text: $checklist.items[index].text)
                                        Button(role: .destructive) {
                                            checklist.items.remove(at: index)
                                        } label: {
                                            Image(systemName: "trash")
                                        }
                                        .buttonStyle(.borderless)
                                    }
                                    TextField("Notes (optional)", text: $checklist.items[index].notes, axis: .vertical)
                                        .lineLimit(2...4)
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            TextField("New Item", text: $newItemText)
                            TextField("Notes (optional)", text: $newItemNotes, axis: .vertical)
                                .lineLimit(2...4)
                            HStack {
                                Spacer()
                                Button("Add Item") {
                                    let trimmed = newItemText.trimmingCharacters(in: .whitespacesAndNewlines)
                                    guard !trimmed.isEmpty else { return }
                                    let trimmedNotes = newItemNotes.trimmingCharacters(in: .whitespacesAndNewlines)
                                    checklist.items.append(ChecklistItem(text: trimmed, notes: trimmedNotes))
                                    newItemText = ""
                                    newItemNotes = ""
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(newItemText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
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
                                            let trimmedNotes = item.notes.trimmingCharacters(in: .whitespacesAndNewlines)
                                            if !trimmedNotes.isEmpty {
                                                Text(trimmedNotes)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
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
            updatedItem.notes = updatedItem.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            return updatedItem
        }
        updateChecklistCompletionMetadata()
        store.saveChecklist(checklist)
        originalChecklist = nil
        newItemText = ""
        newItemNotes = ""
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
    @State private var isShowingAddIdea = false
    @State private var title = ""
    @State private var detail = ""
    @State private var tags = ""
    
    private var canSaveIdea: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Spacer()
                if isShowingAddIdea {
                    Button("Cancel") {
                        resetIdeaForm()
                        isShowingAddIdea = false
                    }
                    .buttonStyle(.bordered)
                }
                Button {
                    if isShowingAddIdea {
                        resetIdeaForm()
                        isShowingAddIdea = false
                    } else {
                        resetIdeaForm()
                        isShowingAddIdea = true
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }

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

            if isShowingAddIdea {
                GroupBox("Add Idea") {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("Title", text: $title)
                        TextEditor(text: $detail)
                            .frame(minHeight: 120)
                        TextField("Tags (comma separated)", text: $tags)
                        Button("Save Idea") {
                            saveIdea()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canSaveIdea)
                    }
                }
            }
        }
        .padding()
        .background(Color.clear)
        .navigationTitle("Ideas")
    }

    private func saveIdea() {
        let parsedTags = tags
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        store.saveIdea(
            IdeaCard(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                detail: detail.trimmingCharacters(in: .whitespacesAndNewlines),
                tags: parsedTags,
                teamCode: store.teamCode ?? "",
                createdBy: store.user?.email
            )
        )
        resetIdeaForm()
        isShowingAddIdea = false
    }

    private func resetIdeaForm() {
        title = ""
        detail = ""
        tags = ""
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
    @State private var freshserviceAPIURL = ""
    @State private var freshserviceAPIKey = ""
    @State private var freshserviceEnabled = false
    @State private var freshserviceSyncMode: ProdConnectStore.FreshserviceSyncMode = .pull
    @State private var isSavingFreshserviceIntegration = false
    @State private var isTestingFreshserviceIntegration = false
    @State private var freshserviceStatusMessage = ""
    @State private var externalTicketFormEnabled = false
    @State private var externalTicketFormAccessKey = ""
    @State private var isSavingExternalTicketForm = false
    @State private var externalTicketStatusMessage = ""
    @State private var bulkOperationMessage = ""
    @State private var isBulkOperationInProgress = false

    private enum ResetAction: String, Identifiable {
        case deleteAllGear
        case deleteAudioPatchsheet
        case deleteVideoPatchsheet
        case deleteLightingPatchsheet

        var id: String { rawValue }

        var title: String {
            switch self {
            case .deleteAllGear: return "Delete All Assets?"
            case .deleteAudioPatchsheet: return "Delete Audio Patchsheet?"
            case .deleteVideoPatchsheet: return "Delete Video Patchsheet?"
            case .deleteLightingPatchsheet: return "Delete Lighting Patchsheet?"
            }
        }

        var message: String {
            switch self {
            case .deleteAllGear:
                return "Are you sure you want to delete all asset items? This cannot be undone."
            case .deleteAudioPatchsheet:
                return "Are you sure you want to delete all audio patches? This cannot be undone."
            case .deleteVideoPatchsheet:
                return "Are you sure you want to delete all video patches? This cannot be undone."
            case .deleteLightingPatchsheet:
                return "Are you sure you want to delete all lighting patches? This cannot be undone."
            }
        }
    }

    private var canManageExternalTicketForm: Bool {
        (store.user?.isAdmin == true || store.user?.isOwner == true)
            && (store.user?.hasTicketingFeatures == true)
    }

    private var externalTicketFormURLString: String {
        let teamCode = (store.teamCode ?? store.user?.teamCode ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let accessKey = externalTicketFormAccessKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard externalTicketFormEnabled, !teamCode.isEmpty, !accessKey.isEmpty else { return "" }
        let slug = externalTicketFormSlug(from: store.organizationName)
        return "https://prodconnect-1ea3a.web.app/support/\(slug)?team=\(teamCode)&key=\(accessKey)"
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
                                Label("Copy Locations from Assets", systemImage: "arrow.triangle.2.circlepath")
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

                        importRow(title: "Assets sheet link", text: $gearSheetLink) {
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

                if canManageIntegrations {
                    GroupBox("Integrations") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Connect Freshservice API")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Toggle("Enable Freshservice", isOn: $freshserviceEnabled)

                            Picker("Sync Mode", selection: $freshserviceSyncMode) {
                                ForEach(ProdConnectStore.FreshserviceSyncMode.allCases, id: \.self) { mode in
                                    Text(mode.title).tag(mode)
                                }
                            }

                            TextField("Freshservice URL", text: $freshserviceAPIURL)
                                .textFieldStyle(.roundedBorder)

                            SecureField("Freshservice API Key", text: $freshserviceAPIKey)
                                .textFieldStyle(.roundedBorder)

                            HStack(spacing: 12) {
                                Button {
                                    saveFreshserviceIntegration()
                                } label: {
                                    if isSavingFreshserviceIntegration {
                                        ProgressView()
                                    } else {
                                        Text("Save Connection")
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(isSavingFreshserviceIntegration || isTestingFreshserviceIntegration)

                                Button {
                                    testFreshserviceConnection()
                                } label: {
                                    if isTestingFreshserviceIntegration {
                                        ProgressView()
                                    } else {
                                        Text("Test Connection")
                                    }
                                }
                                .buttonStyle(.bordered)
                                .disabled(
                                    isSavingFreshserviceIntegration
                                    || isTestingFreshserviceIntegration
                                    || freshserviceAPIURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    || freshserviceAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                )
                            }

                            if !freshserviceStatusMessage.isEmpty {
                                Text(freshserviceStatusMessage)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if canManageExternalTicketForm {
                    GroupBox("External Ticket Form") {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("Enable External Form", isOn: $externalTicketFormEnabled)

                            if !externalTicketFormURLString.isEmpty {
                                TextField("Public Link", text: .constant(externalTicketFormURLString))
                                    .textFieldStyle(.roundedBorder)

                                Button("Copy Public Link") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(externalTicketFormURLString, forType: .string)
                                    externalTicketStatusMessage = "External ticket form link copied."
                                }
                                .buttonStyle(.bordered)
                            }

                            Button {
                                saveCustomizeExternalTicketForm()
                            } label: {
                                if isSavingExternalTicketForm {
                                    ProgressView()
                                } else {
                                    Text("Save External Form")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isSavingExternalTicketForm)

                            if !externalTicketStatusMessage.isEmpty {
                                Text(externalTicketStatusMessage)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                GroupBox("Reset") {
                    VStack(alignment: .leading, spacing: 10) {
                        resetButton("Delete All Assets", action: .deleteAllGear)
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
        .disabled(isBulkOperationInProgress)
        .onAppear(perform: loadFreshserviceIntegrationState)
        .onChange(of: store.freshserviceIntegration) { _, _ in
            loadFreshserviceIntegrationState()
        }
        .onChange(of: store.externalTicketFormIntegration) { _, _ in
            loadExternalTicketFormCustomizeState()
        }
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
        .overlay {
            if isBulkOperationInProgress {
                ZStack {
                    Color.black.opacity(0.25)
                        .ignoresSafeArea()

                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.large)
                        Text(bulkOperationMessage)
                            .font(.headline)
                            .multilineTextAlignment(.center)
                    }
                    .padding(20)
                    .frame(maxWidth: 320)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .shadow(radius: 10)
                }
            }
        }
    }

    private var canManageIntegrations: Bool {
        let isPrivilegedUser = store.user?.isAdmin == true || store.user?.isOwner == true
        return isPrivilegedUser && (store.user?.hasChatAndTrainingFeatures ?? false)
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
        beginBulkOperation("Deleting, please wait")
        switch action {
        case .deleteAllGear:
            store.deleteAllGear { result in
                finishReset(result, successMessage: "All assets have been deleted.")
            }
        case .deleteAudioPatchsheet:
            store.deletePatchesByCategory("Audio") { result in
                finishReset(result, successMessage: "Audio patchsheet has been deleted.")
            }
        case .deleteVideoPatchsheet:
            store.deletePatchesByCategory("Video") { result in
                finishReset(result, successMessage: "Video patchsheet has been deleted.")
            }
        case .deleteLightingPatchsheet:
            store.deletePatchesByCategory("Lighting") { result in
                finishReset(result, successMessage: "Lighting patchsheet has been deleted.")
            }
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

        resultMessage = added == 0 ? "No new locations to copy from Assets." : "Added \(added) location(s) from Assets."
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
                beginBulkOperation("Importing, please wait")
                store.replaceAllGear(gearItems) { result in
                    endBulkOperation()
                    isImporting = false
                    switch result {
                    case .success:
                        gearSheetLink = ""
                        resultMessage = "Imported \(gearItems.count) asset items."
                    case .failure(let error):
                        resultMessage = "Import failed: \(error.localizedDescription)"
                    }
                }
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
                beginBulkOperation("Importing, please wait")
                store.replaceAllPatch(patchRows) { result in
                    endBulkOperation()
                    isImporting = false
                    switch result {
                    case .success:
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
                        resultMessage = "Imported \(patchRows.count) \(category) patches."
                    case .failure(let error):
                        resultMessage = "Import failed: \(error.localizedDescription)"
                    }
                }
            }
        }.resume()
    }

    private func beginBulkOperation(_ message: String) {
        bulkOperationMessage = message
        isBulkOperationInProgress = true
    }

    private func endBulkOperation() {
        isBulkOperationInProgress = false
        bulkOperationMessage = ""
    }

    private func finishReset(_ result: Result<Void, Error>, successMessage: String) {
        endBulkOperation()
        switch result {
        case .success:
            resultMessage = successMessage
        case .failure(let error):
            resultMessage = "Delete failed: \(error.localizedDescription)"
        }
    }

    private func loadFreshserviceIntegrationState() {
        let settings = store.freshserviceIntegration
        freshserviceAPIURL = settings.apiURL
        freshserviceAPIKey = settings.apiKey
        freshserviceEnabled = settings.isEnabled
        freshserviceSyncMode = settings.syncMode
        loadExternalTicketFormCustomizeState()
    }

    private func loadExternalTicketFormCustomizeState() {
        let settings = store.externalTicketFormIntegration
        externalTicketFormEnabled = settings.isEnabled
        externalTicketFormAccessKey = settings.accessKey
        if externalTicketFormAccessKey.isEmpty, canManageExternalTicketForm {
            externalTicketFormAccessKey = store.generateExternalTicketAccessKey()
        }
    }

    private func saveCustomizeExternalTicketForm() {
        isSavingExternalTicketForm = true
        externalTicketStatusMessage = ""
        store.saveExternalTicketFormIntegration(
            isEnabled: externalTicketFormEnabled,
            accessKey: externalTicketFormAccessKey
        ) { result in
            isSavingExternalTicketForm = false
            switch result {
            case .success(let settings):
                externalTicketFormEnabled = settings.isEnabled
                externalTicketFormAccessKey = settings.accessKey
                externalTicketStatusMessage = settings.isEnabled ?
                    "External ticket form is live." :
                    "External ticket form is saved but disabled."
            case .failure(let error):
                externalTicketStatusMessage = "Save failed: \(error.localizedDescription)"
            }
        }
    }

    private func saveFreshserviceIntegration() {
        isSavingFreshserviceIntegration = true
        freshserviceStatusMessage = ""
        store.saveFreshserviceIntegration(
            apiURL: freshserviceAPIURL,
            apiKey: freshserviceAPIKey,
            managedByGroup: "",
            managedByGroupOptions: store.freshserviceIntegration.managedByGroupOptions,
            syncMode: freshserviceSyncMode,
            isEnabled: freshserviceEnabled
        ) { result in
            isSavingFreshserviceIntegration = false
            switch result {
            case .success:
                freshserviceStatusMessage = "Freshservice connection saved."
            case .failure(let error):
                freshserviceStatusMessage = "Save failed: \(error.localizedDescription)"
            }
        }
    }

    private func testFreshserviceConnection() {
        let trimmedURL = freshserviceAPIURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = freshserviceAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty, !trimmedKey.isEmpty else {
            freshserviceStatusMessage = "Enter both the Freshservice URL and API key."
            return
        }

        isTestingFreshserviceIntegration = true
        freshserviceStatusMessage = ""
        let normalizedURL: URL? = {
            let withScheme = trimmedURL.contains("://") ? trimmedURL : "https://\(trimmedURL)"
            guard var components = URLComponents(string: withScheme) else { return nil }
            components.scheme = "https"
            components.user = nil
            components.password = nil
            components.path = "/api/v2/assets"
            components.query = nil
            components.fragment = nil
            return components.url
        }()

        guard let url = normalizedURL else {
            isTestingFreshserviceIntegration = false
            freshserviceStatusMessage = "Connection failed: Invalid Freshservice URL."
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let credentialData = "\(trimmedKey):X".data(using: .utf8) ?? Data()
        request.setValue("Basic \(credentialData.base64EncodedString())", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                isTestingFreshserviceIntegration = false
                if let error {
                    freshserviceStatusMessage = "Connection failed: \(error.localizedDescription)"
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse, let data else {
                    freshserviceStatusMessage = "Connection failed: Freshservice returned an invalid response."
                    return
                }

                if !(200...299).contains(httpResponse.statusCode) {
                    if
                        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                        let message = (json["description"] as? String) ?? (json["message"] as? String),
                        !message.isEmpty
                    {
                        freshserviceStatusMessage = "Connection failed: \(message)"
                    } else {
                        freshserviceStatusMessage = "Connection failed: Freshservice request failed with status \(httpResponse.statusCode)."
                    }
                    return
                }

                let jsonObject = try? JSONSerialization.jsonObject(with: data)
                let assets = (jsonObject as? [String: Any]).flatMap { json in
                    (json["assets"] as? [[String: Any]])
                    ?? (json["config_items"] as? [[String: Any]])
                    ?? (json["cis"] as? [[String: Any]])
                    ?? (json["results"] as? [[String: Any]])
                    ?? (json["data"] as? [[String: Any]])
                } ?? (jsonObject as? [[String: Any]])

                guard let assets else {
                    freshserviceStatusMessage = "Connection failed: Freshservice returned a response in an unsupported format."
                    return
                }

                freshserviceStatusMessage = "Connected to Freshservice. Found \(assets.count) assets."
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
    @State private var selectedUser: UserProfile?

    private var canManageUsers: Bool {
        store.user?.isAdmin == true || store.user?.isOwner == true
    }

    var body: some View {
        List(store.teamMembers.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }) { user in
            userRow(for: user)
        }
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .navigationTitle("Users")
        .sheet(item: $selectedUser) { user in
            NavigationStack {
                MacUserDetailView(user: user)
                    .environmentObject(store)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") {
                                selectedUser = nil
                            }
                        }
                    }
            }
            .frame(minWidth: 520, minHeight: 640)
        }
    }

    @ViewBuilder
    private func userRow(for user: UserProfile) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(user.displayName).font(.headline)
                Text(user.email).font(.caption).foregroundStyle(.secondary)
                if !user.assignedCampus.isEmpty {
                    Text(user.assignedCampus).font(.caption2).foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 12)

            if canManageUsers {
                Button("Edit User") {
                    selectedUser = user
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct MacUserDetailView: View {
    @EnvironmentObject private var store: ProdConnectStore
    @Environment(\.dismiss) private var dismiss
    @State private var user: UserProfile
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showTransferConfirm = false
    @State private var showDeleteConfirm = false

    private var canDeleteUser: Bool {
        guard let currentUser = store.user else { return false }
        return currentUser.canDelete(user)
    }

    init(user: UserProfile) {
        _user = State(initialValue: user)
    }

    var body: some View {
        Form {
            Section("User") {
                LabeledContent("Name", value: user.displayName)
                LabeledContent("Email", value: user.email)
            }

            Section("Role") {
                Toggle("Admin", isOn: $user.isAdmin)
                    .disabled(isSaving || user.isOwner)
                    .onChange(of: user.isAdmin) { _, isAdmin in
                        updateAdminFlag(isAdmin: isAdmin)
                    }
            }

            if store.user?.isOwner == true, user.id != store.user?.id {
                Section("Ownership") {
                    Button("Transfer Ownership") {
                        showTransferConfirm = true
                    }
                    .disabled(isSaving)
                }
            }

            if !user.isAdmin && (store.user?.hasCampusRoomFeatures ?? false) {
                Section("Assigned Campus") {
                    Picker("Campus", selection: $user.assignedCampus) {
                        Text("No campus assigned").tag("")
                        ForEach(store.locations.sorted(), id: \.self) { campus in
                            Text(campus).tag(campus)
                        }
                    }
                    .onChange(of: user.assignedCampus) { _, campus in
                        updateAssignedCampus(campus: campus)
                    }
                }
            }

            Section("Permissions") {
                Toggle("Can edit patchsheet", isOn: $user.canEditPatchsheet)
                    .onChange(of: user.canEditPatchsheet) { _, value in
                        updatePermission(key: "canEditPatchsheet", value: value)
                    }
                Toggle("Can edit training", isOn: $user.canEditTraining)
                    .onChange(of: user.canEditTraining) { _, value in
                        updatePermission(key: "canEditTraining", value: value)
                    }
                Toggle("Can edit assets", isOn: $user.canEditGear)
                    .onChange(of: user.canEditGear) { _, value in
                        updatePermission(key: "canEditGear", value: value)
                    }
                Toggle("Can edit ideas", isOn: $user.canEditIdeas)
                    .onChange(of: user.canEditIdeas) { _, value in
                        updatePermission(key: "canEditIdeas", value: value)
                    }
                Toggle("Can edit checklists", isOn: $user.canEditChecklists)
                    .onChange(of: user.canEditChecklists) { _, value in
                        updatePermission(key: "canEditChecklists", value: value)
                    }
                Toggle("Ticket Agent", isOn: $user.isTicketAgent)
                    .onChange(of: user.isTicketAgent) { _, value in
                        updatePermission(key: "isTicketAgent", value: value)
                    }
            }

            if !user.isAdmin {
                Section("Visible Tabs") {
                    Toggle("Chat", isOn: $user.canSeeChat)
                        .onChange(of: user.canSeeChat) { _, value in
                            updatePermission(key: "canSeeChat", value: value)
                        }
                    Toggle("Patchsheet", isOn: $user.canSeePatchsheet)
                        .onChange(of: user.canSeePatchsheet) { _, value in
                            updatePermission(key: "canSeePatchsheet", value: value)
                        }
                    Toggle("Training", isOn: $user.canSeeTraining)
                        .onChange(of: user.canSeeTraining) { _, value in
                            updatePermission(key: "canSeeTraining", value: value)
                        }
                    Toggle("Assets", isOn: $user.canSeeGear)
                        .onChange(of: user.canSeeGear) { _, value in
                            updatePermission(key: "canSeeGear", value: value)
                        }
                    Toggle("Ideas", isOn: $user.canSeeIdeas)
                        .onChange(of: user.canSeeIdeas) { _, value in
                            updatePermission(key: "canSeeIdeas", value: value)
                        }
                    Toggle("Checklists", isOn: $user.canSeeChecklists)
                        .onChange(of: user.canSeeChecklists) { _, value in
                            updatePermission(key: "canSeeChecklists", value: value)
                        }
                    Toggle("Tickets", isOn: $user.canSeeTickets)
                        .onChange(of: user.canSeeTickets) { _, value in
                            updatePermission(key: "canSeeTickets", value: value)
                        }
                }
            }

            if canDeleteUser {
                Section {
                    Button("Delete User", role: .destructive) {
                        showDeleteConfirm = true
                    }
                    .disabled(isSaving)
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Edit User")
        .alert("Transfer Ownership?", isPresented: $showTransferConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Transfer", role: .destructive) {
                transferOwnership()
            }
        } message: {
            Text("This will move the Owner role and subscription control to this user.")
        }
        .alert("Delete User?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteUser()
            }
        } message: {
            Text("This permanently deletes \(user.displayName)'s user profile.")
        }
        .toolbar {
            if isSaving {
                ToolbarItem {
                    ProgressView()
                }
            }
        }
    }

    private func transferOwnership() {
        guard let currentOwner = store.user, currentOwner.isOwner else { return }
        let teamCode = (currentOwner.teamCode ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !teamCode.isEmpty else {
            errorMessage = "No team code available."
            return
        }

        isSaving = true
        errorMessage = nil

        let batch = store.db.batch()
        let teamRef = store.db.collection("teams").document(teamCode)
        let currentOwnerRef = store.db.collection("users").document(currentOwner.id)
        let newOwnerRef = store.db.collection("users").document(user.id)

        batch.setData([
            "ownerId": user.id,
            "ownerEmail": user.email,
            "code": teamCode,
            "isActive": true
        ], forDocument: teamRef, merge: true)

        batch.setData([
            "isOwner": false
        ], forDocument: currentOwnerRef, merge: true)

        var newOwnerUpdates: [String: Any] = [
            "isOwner": true,
            "isAdmin": true
        ]
        batch.setData(newOwnerUpdates, forDocument: newOwnerRef, merge: true)

        batch.commit { error in
            DispatchQueue.main.async {
                self.isSaving = false
                if let error {
                    self.errorMessage = "Transfer failed: \(error.localizedDescription)"
                    return
                }

                if currentOwner.id == self.store.user?.id {
                    self.store.user?.isOwner = false
                }
                self.user.isOwner = true
                self.user.isAdmin = true
                self.replaceTeamMember()
            }
        }
    }

    private func updateAdminFlag(isAdmin: Bool) {
        isSaving = true
        errorMessage = nil
        store.db.collection("users").document(user.id).updateData(["isAdmin": isAdmin]) { error in
            DispatchQueue.main.async {
                self.isSaving = false
                if let error {
                    self.errorMessage = "Update failed: \(error.localizedDescription)"
                    self.user.isAdmin.toggle()
                    return
                }

                self.replaceTeamMember()
            }
        }
    }

    private func updateAssignedCampus(campus: String) {
        guard !user.id.isEmpty else {
            errorMessage = "Update failed: missing user id"
            return
        }

        isSaving = true
        errorMessage = nil
        store.db.collection("users").document(user.id).setData(["assignedCampus": campus], merge: true) { error in
            DispatchQueue.main.async {
                self.isSaving = false
                if let error {
                    self.errorMessage = "Update failed: \(error.localizedDescription)"
                    return
                }

                self.user.assignedCampus = campus
                self.replaceTeamMember()
            }
        }
    }

    private func updatePermission(key: String, value: Bool) {
        isSaving = true
        errorMessage = nil
        store.db.collection("users").document(user.id).updateData([key: value]) { error in
            DispatchQueue.main.async {
                self.isSaving = false
                if let error {
                    self.errorMessage = "Update failed: \(error.localizedDescription)"
                    return
                }

                switch key {
                case "canEditPatchsheet":
                    self.user.canEditPatchsheet = value
                case "canEditTraining":
                    self.user.canEditTraining = value
                case "canEditGear":
                    self.user.canEditGear = value
                case "canEditIdeas":
                    self.user.canEditIdeas = value
                case "canEditChecklists":
                    self.user.canEditChecklists = value
                case "isTicketAgent":
                    self.user.isTicketAgent = value
                case "canSeeChat":
                    self.user.canSeeChat = value
                case "canSeePatchsheet":
                    self.user.canSeePatchsheet = value
                case "canSeeTraining":
                    self.user.canSeeTraining = value
                case "canSeeGear":
                    self.user.canSeeGear = value
                case "canSeeIdeas":
                    self.user.canSeeIdeas = value
                case "canSeeChecklists":
                    self.user.canSeeChecklists = value
                case "canSeeTickets":
                    self.user.canSeeTickets = value
                default:
                    break
                }

                self.replaceTeamMember()
            }
        }
    }

    private func replaceTeamMember() {
        guard let index = store.teamMembers.firstIndex(where: { $0.id == user.id }) else { return }
        store.teamMembers[index] = user
    }

    private func deleteUser() {
        guard canDeleteUser else { return }

        isSaving = true
        errorMessage = nil

        store.db.collection("users").document(user.id).delete { error in
            DispatchQueue.main.async {
                self.isSaving = false
                if let error {
                    self.errorMessage = "Delete failed: \(error.localizedDescription)"
                    return
                }

                self.store.teamMembers.removeAll { $0.id == self.user.id }
                dismiss()
            }
        }
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
    @State private var organizationName = ""
    @State private var organizationStatusMessage: String?
    private let termsURLString = "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
    private let privacyPolicyURLString = "https://bmsatori.github.io/prodconnect-privacy/"

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

    private var canViewTeamCode: Bool {
        guard let user = store.user else { return false }
        return user.isAdmin || user.isOwner
    }

    private var normalizedSubscriptionTier: String {
        canonicalSubscriptionTier(store.user?.subscriptionTier)
    }

    private var canManageSubscription: Bool {
        guard let user = store.user else { return false }
        if normalizedSubscriptionTier == "free" {
            return true
        }
        return (user.isAdmin || user.isOwner) && normalizedSubscriptionTier != "premium_ticketing"
    }

    private var subscriptionButtonTitle: String {
        normalizedSubscriptionTier == "free" ? "Subscribe" : "Upgrade Subscription"
    }

    private var canEditOrganizationName: Bool {
        store.user?.isAdmin == true || store.user?.isOwner == true
    }

    private var subscriptionTierLabel: String {
        switch normalizedSubscriptionTier {
        case "premium_ticketing", "premium w/ticketing", "premium with ticketing":
            return "Premium W/Ticketing"
        case "premium":
            return "Premium"
        case "basic_ticketing", "basic w/ticketing", "basic with ticketing":
            return "Basic W/Ticketing"
        case "basic":
            return "Basic"
        default:
            return "Free"
        }
    }

    var body: some View {
        Form {
            if let user = store.user {
                LabeledContent("Name", value: user.displayName)
                LabeledContent("Email", value: user.email)
                if canViewTeamCode {
                    LabeledContent("Team Code", value: user.teamCode ?? "None")
                }
                LabeledContent("Subscription", value: subscriptionTierLabel)
                LabeledContent("Role", value: roleLabel)
                if !appVersionText.isEmpty {
                    LabeledContent("App Version", value: appVersionText)
                }
                if !user.assignedCampus.isEmpty {
                    LabeledContent("Campus", value: user.assignedCampus)
                }
            }

            if canEditOrganizationName {
                Section("Organization") {
                    TextField("Organization Name", text: $organizationName)
                    Button("Save Organization Name") {
                        saveOrganizationName()
                    }
                    .buttonStyle(.borderedProminent)
                    if let organizationStatusMessage {
                        Text(organizationStatusMessage)
                            .foregroundStyle(organizationStatusMessage.hasPrefix("Saved") ? .green : .red)
                    }
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
        .task {
            await reconcileSubscriptionState(showNoActiveError: false)
        }
        .onAppear {
            organizationName = store.organizationName
        }
        .onReceive(store.$organizationName) { value in
            organizationName = value
        }
        .task {
            await observeTransactionUpdates()
        }
        .sheet(isPresented: $showEditAccount) {
            MacEditAccountView()
                .environmentObject(store)
        }
        .sheet(isPresented: $showSubscriptionOptions) {
            MacSubscriptionOptionsView(
                currentTier: normalizedSubscriptionTier,
                termsURLString: termsURLString,
                privacyPolicyURLString: privacyPolicyURLString,
                onPurchaseBasic: {
                    await purchaseSubscription(productID: "Basic3", targetTier: "basic")
                },
                onPurchaseBasicTicketing: {
                    await purchaseSubscription(productID: "Basic_Ticketing", targetTier: "basic_ticketing")
                },
                onPurchasePremium: {
                    await purchaseSubscription(productID: "Premium2", targetTier: "premium")
                },
                onPurchasePremiumTicketing: {
                    await purchaseSubscription(productID: "Premium_Ticketing", targetTier: "premium_ticketing")
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

    private func saveOrganizationName() {
        organizationStatusMessage = nil
        store.saveOrganizationName(organizationName) { result in
            switch result {
            case .success:
                organizationStatusMessage = "Saved organization name."
            case .failure(let error):
                organizationStatusMessage = "Save failed: \(error.localizedDescription)"
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
            await reconcileSubscriptionState(showNoActiveError: true)
        } catch {
            subscriptionErrorMessage = error.localizedDescription
        }
    }

    private func applySubscription(targetTier: String) async throws {
        guard var user = store.user else {
            throw MacSubscriptionError.userNotLoaded
        }

        let resolvedTier = canonicalSubscriptionTier(targetTier)
        user.isAdmin = true
        user.subscriptionTier = resolvedTier
        user.canEditPatchsheet = true
        user.canEditTraining = true
        user.canEditGear = true
        user.canEditIdeas = true
        user.canEditChecklists = true
        user.canSeeChat = true
        user.canSeeTraining = true
        user.canSeeTickets = resolvedTier == "basic_ticketing" || resolvedTier == "premium_ticketing"

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
            "canEditChecklists": true,
            "canSeeChat": true,
            "canSeeTraining": true,
            "canSeeTickets": user.canSeeTickets
        ]

        try await store.db.collection("users").document(uid).setData(updates, merge: true)

        store.user = user
        store.teamCode = user.teamCode
        store.listenToTeamData()
        store.listenToTeamMembers()
    }

    private func observeTransactionUpdates() async {
        for await update in Transaction.updates {
            do {
                let transaction = try checkVerified(update)
                await reconcileSubscriptionState(showNoActiveError: false)
                await transaction.finish()
            } catch {
                subscriptionErrorMessage = error.localizedDescription
            }
        }
    }

    private func reconcileSubscriptionState(showNoActiveError: Bool) async {
        do {
            var highestTier: String?
            for try await verification in Transaction.currentEntitlements {
                let transaction = try checkVerified(verification)
                guard let resolvedTier = subscriptionTier(for: transaction.productID) else {
                    continue
                }
                if highestTier == nil || subscriptionTierRank(for: resolvedTier) > subscriptionTierRank(for: highestTier ?? "free") {
                    highestTier = resolvedTier
                }
            }

            if let highestTier {
                try await applySubscription(targetTier: highestTier)
                showSubscriptionOptions = false
            } else if showNoActiveError {
                throw MacSubscriptionError.noActiveSubscription
            }
        } catch {
            if showNoActiveError || (error as? MacSubscriptionError) != .noActiveSubscription {
                subscriptionErrorMessage = error.localizedDescription
            }
        }
    }

    private func revokeSubscriptionEntitlements() async throws {
        guard var user = store.user else {
            throw MacSubscriptionError.userNotLoaded
        }
        guard canonicalSubscriptionTier(user.subscriptionTier) != "free" else { return }

        user.subscriptionTier = "free"
        user.canEditTraining = false
        user.canSeeChat = false
        user.canSeeTraining = false
        user.canSeeTickets = false

        let uid = Auth.auth().currentUser?.uid ?? user.id
        try await store.db.collection("users").document(uid).setData([
            "subscriptionTier": "free",
            "canEditTraining": false,
            "canSeeChat": false,
            "canSeeTraining": false,
            "canSeeTickets": false
        ], merge: true)

        store.user = user
    }

    private func subscriptionTier(for productID: String) -> String? {
        switch productID {
        case "Premium_Ticketing":
            return "premium_ticketing"
        case "Premium2":
            return "premium"
        case "Basic_Ticketing":
            return "basic_ticketing"
        case "Basic3":
            return "basic"
        default:
            return nil
        }
    }

    private func subscriptionTierRank(for tier: String) -> Int {
        switch canonicalSubscriptionTier(tier) {
        case "premium_ticketing":
            return 4
        case "premium":
            return 3
        case "basic_ticketing":
            return 2
        case "basic":
            return 1
        default:
            return 0
        }
    }

    private func canonicalSubscriptionTier(_ rawValue: String?) -> String {
        switch rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "free" {
        case "premium_ticketing", "premium w/ticketing", "premium with ticketing":
            return "premium_ticketing"
        case "basic_ticketing", "basic w/ticketing", "basic with ticketing":
            return "basic_ticketing"
        case "premium":
            return "premium"
        case "basic":
            return "basic"
        default:
            return "free"
        }
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
    @State private var basicTicketingProduct: Product?
    @State private var premiumProduct: Product?
    @State private var premiumTicketingProduct: Product?
    @State private var isLoadingProducts = false
    @State private var isPurchasing = false

    let currentTier: String
    let termsURLString: String
    let privacyPolicyURLString: String
    let onPurchaseBasic: () async -> Void
    let onPurchaseBasicTicketing: () async -> Void
    let onPurchasePremium: () async -> Void
    let onPurchasePremiumTicketing: () async -> Void
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
                        subtitle: "$99.99. Includes chat and training, but hides Locations, Rooms, and Tickets.",
                        price: priceText(for: basicProduct),
                        buttonTitle: currentTier == "basic" ? "Current Plan" : "Choose Basic",
                        isPrimary: true,
                        isDisabled: isPurchasing || currentTier == "basic" || currentTier == "basic_ticketing" || currentTier == "premium" || currentTier == "premium_ticketing"
                    ) {
                        await runPurchase(onPurchaseBasic)
                    }

                    subscriptionCard(
                        title: basicTicketingProduct?.displayName ?? "Basic W/Ticketing",
                        subtitle: "$199.99. Includes chat, training, and Tickets, but hides Locations and Rooms.",
                        price: priceText(for: basicTicketingProduct),
                        buttonTitle: currentTier == "basic_ticketing" ? "Current Plan" : "Choose Basic W/Ticketing",
                        isPrimary: false,
                        isDisabled: isPurchasing || currentTier == "basic_ticketing" || currentTier == "premium" || currentTier == "premium_ticketing"
                    ) {
                        await runPurchase(onPurchaseBasicTicketing)
                    }

                    subscriptionCard(
                        title: premiumProduct?.displayName ?? "Premium",
                        subtitle: "$249.99. Includes everything except Tickets.",
                        price: priceText(for: premiumProduct),
                        buttonTitle: currentTier == "premium" ? "Current Plan" : "Choose Premium",
                        isPrimary: false,
                        isDisabled: isPurchasing || currentTier == "premium" || currentTier == "premium_ticketing"
                    ) {
                        await runPurchase(onPurchasePremium)
                    }

                    subscriptionCard(
                        title: premiumTicketingProduct?.displayName ?? "Premium W/Ticketing",
                        subtitle: "$499.99. Includes every feature.",
                        price: priceText(for: premiumTicketingProduct),
                        buttonTitle: currentTier == "premium_ticketing" ? "Current Plan" : "Choose Premium W/Ticketing",
                        isPrimary: false,
                        isDisabled: isPurchasing || currentTier == "premium_ticketing"
                    ) {
                        await runPurchase(onPurchasePremiumTicketing)
                    }

                    Button(isPurchasing ? "Working..." : "Restore Purchases") {
                        Task {
                            await runPurchase(onRestorePurchases)
                        }
                    }
                    .disabled(isPurchasing)

                    if let termsURL = URL(string: termsURLString) {
                        Link("Terms of Use (EULA)", destination: termsURL)
                            .font(.footnote)
                    }
                    if let privacyURL = URL(string: privacyPolicyURLString) {
                        Link("Privacy Policy", destination: privacyURL)
                            .font(.footnote)
                    }
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
            let products = try await Product.products(for: ["Basic3", "Basic_Ticketing", "Premium2", "Premium_Ticketing"])
            basicProduct = products.first(where: { $0.id == "Basic3" })
            basicTicketingProduct = products.first(where: { $0.id == "Basic_Ticketing" })
            premiumProduct = products.first(where: { $0.id == "Premium2" })
            premiumTicketingProduct = products.first(where: { $0.id == "Premium_Ticketing" })
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
    @FocusState private var focusedField: Field?
    @State private var displayName = ""
    @State private var newEmail = ""
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    private enum Field: Hashable {
        case displayName
        case email
        case currentPassword
        case newPassword
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Display Name") {
                    TextField("Display Name", text: $displayName)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled(true)
                        .focused($focusedField, equals: .displayName)
                }

                Section("Login Email") {
                    TextField("New Email", text: $newEmail)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled(true)
                        .focused($focusedField, equals: .email)
                }

                Section("Password") {
                    SecureField("Current Password", text: $currentPassword)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .currentPassword)
                    SecureField("New Password", text: $newPassword)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .newPassword)
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
                displayName = store.user?.displayName ?? (Auth.auth().currentUser?.email?.components(separatedBy: "@").first ?? "")
                newEmail = ""
                currentPassword = ""
                newPassword = ""
                DispatchQueue.main.async {
                    focusedField = .displayName
                }
            }
            .alert("Account Updated", isPresented: Binding(get: { successMessage != nil }, set: { if !$0 { successMessage = nil } })) {
                Button("OK", role: .cancel) { dismiss() }
            } message: {
                Text(successMessage ?? "")
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
                    self.successMessage = "Your account changes have been saved."
                }
            }
        }

        func updateDisplayNameIfNeeded(completion: @escaping (Error?) -> Void) {
            guard nameChanged, let uid = store.user?.id else {
                completion(nil)
                return
            }
            let changeRequest = currentUser.createProfileChangeRequest()
            changeRequest.displayName = trimmedName
            changeRequest.commitChanges { authError in
                if let authError {
                    completion(authError)
                    return
                }
                store.db.collection("users").document(uid).updateData(["displayName": trimmedName]) { error in
                    if error == nil {
                        DispatchQueue.main.async {
                            store.user?.displayName = trimmedName
                            store.listenToTeamMembers()
                        }
                    }
                    completion(error)
                }
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
                        DispatchQueue.main.async {
                            self.store.user?.email = trimmedEmail
                        }
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
