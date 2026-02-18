import Foundation
import SwiftUI
import Combine
import UIKit
import AVKit
import FirebaseFirestore
import FirebaseStorage
import FirebaseAuth
import StoreKit
import PhotosUI
import OneSignalFramework
import WebKit
import SafariServices

// NOTE: Preserved legacy block for reference, excluded from compilation to fix parser conflicts.
/*
// Restored UsersView for More tab
struct UsersView: View {
    @EnvironmentObject var store: ProdConnectStore
    var body: some View {
        NavigationView {
            List(store.teamMembers) { user in
                VStack(alignment: .leading) {
                    Text(user.displayName).font(.headline)
                    Text(user.email).font(.subheadline)
                }
            }
            .navigationTitle("Users")
        }
    }
}

// Restored GearTabView for Gear tab
struct GearTabView: View {
        // MARK: - Helper Functions for GearTabView

        func exportGear() {
            guard !filteredGear.isEmpty else { return }
            let csvString = gearToCSV(filteredGear)
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("GearExport.csv")
            do {
                try csvString.write(to: tempURL, atomically: true, encoding: .utf8)
                exportURL = tempURL
                isExporting = false
            } catch {
                // Handle error
                isExporting = false
            }
        }

        func gearToCSV(_ gear: [GearItem]) -> String {
            var csv = "Name,Category,Status,Location,Notes\n"
            for item in gear {
                let row = "\(item.name),\(item.category),\(item.status.rawValue),\(item.location),\(item.maintenanceNotes.replacingOccurrences(of: ",", with: ";"))\n"
                csv += row
            }
            return csv
        }

        func findDuplicateGearGroups() -> [[GearItem]] {
            let grouped = Dictionary(grouping: store.gear) { $0.name.lowercased().trimmingCharacters(in: .whitespaces) }
            return grouped.values.filter { $0.count > 1 }
        }

        func mergeDuplicates() {
            isMerging = true
            let groups = findDuplicateGearGroups()
            var mergedCount = 0
            for group in groups {
                if let merged = mergeGearGroup(group) {
                    store.deleteGear(items: group)
                    store.saveGear(merged)
                    mergedCount += 1
                }
            }
            isMerging = false
            mergeResultMessage = "Merged \(mergedCount) duplicate groups."
            showMergeResult = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                showMergeResult = false
            }
        }

        func mergeGearGroup(_ group: [GearItem]) -> GearItem? {
            guard let first = group.first else { return nil }
            // Merge logic: take non-empty fields from any item
            var merged = first
            for item in group.dropFirst() {
                if merged.category.isEmpty, !item.category.isEmpty { merged.category = item.category }
                if merged.location.isEmpty, !item.location.isEmpty { merged.location = item.location }
                if merged.maintenanceNotes.isEmpty, !item.maintenanceNotes.isEmpty { merged.maintenanceNotes = item.maintenanceNotes }
                if merged.status == .unknown, item.status != .unknown { merged.status = item.status }
            }
            return merged
        }

        // MARK: - Filtering Logic
        var filteredGear: [GearItem] {
            var result = store.gear
            if !searchText.isEmpty {
                result = result.filter { $0.name.localizedCaseInsensitiveContains(searchText) || $0.category.localizedCaseInsensitiveContains(searchText) || $0.location.localizedCaseInsensitiveContains(searchText) }
            }
            if let cat = selectedCategory {
                result = result.filter { $0.category == cat }
            }
            if let stat = selectedStatus {
                result = result.filter { $0.status == stat }
            }
            if let loc = selectedLocation {
                result = result.filter { $0.location == loc }
            }
            return result
        }

        // MARK: - onAppear
        func initializeGearTab() {
            availableCategories = Array(Set(store.gear.map { $0.category })).sorted()
            allGearLocations = Array(Set(store.gear.map { $0.location })).filter { !$0.isEmpty }.sorted()
            statusColor = { status in
                switch status {
                case .available: return .green
                case .checkedOut: return .orange
                case .maintenance: return .yellow
                case .lost: return .red
                case .unknown: return .gray
                case .inUse: return .blue
                case .needsRepair: return .pink
                case .retired: return .gray
                case .missing: return .red
                case .blank: return .gray
            }
        }

        // MARK: - SearchBar View
        struct SearchBar: View {
            @Binding var text: String
            var body: some View {
                HStack {
                    Image(systemName: "magnifyingglass")
                    TextField("Search gear...", text: $text)
                        .textFieldStyle(PlainTextFieldStyle())
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    if !text.isEmpty {
                        Button(action: { text = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                        }
                    }
                }
                .padding(8)
                .background(Color(.systemGray6))
                .cornerRadius(10)
                .padding(.horizontal)
            }
        }

        // MARK: - ShareSheet View
        struct ShareSheet: UIViewControllerRepresentable {
            var items: [Any]
            func makeUIViewController(context: Context) -> UIActivityViewController {
                UIActivityViewController(activityItems: items, applicationActivities: nil)
            }
            func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
        }
    @EnvironmentObject var store: ProdConnectStore
    @State private var showAddGear = false
    @State private var exportURL: URL? = nil
    @State private var isExporting = false
    @State private var mergePreview: [[GearItem]] = []
    @State private var showMergeConfirm = false
    @State private var isMerging = false
    @State private var showMergeResult = false
    @State private var mergeResultMessage: String = ""
    @State private var searchText: String = ""
    @State private var selectedCategory: String? = nil
    @State private var selectedStatus: GearItem.GearStatus? = nil
    @State private var selectedLocation: String? = nil
    @State private var isLoadingMoreGear = false
    @State private var hasMoreGear = false
    @State private var lastGearSnapshot: DocumentSnapshot? = nil
    @State private var gearPageSize: Int = 50
    @State private var isDataFetchInProgress = false
    @State private var isSearchingGear = false
    @State private var isFilteringGear = false
    @State private var searchResults: [GearItem] = []
        var filteredGear: [GearItem] {
            if searchText.isEmpty { return store.gear }
            return store.gear.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
    @State private var allGearLocations: [String] = []
    @State private var availableCategories: [String] = []
    @State private var statusColor: (GearItem.GearStatus) -> Color = { _ in .gray }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SearchBar(text: $searchText)
                HStack(spacing: 12) {
                    Menu {
                        Button("Clear", action: { selectedCategory = nil })
                        Divider()
                        ForEach(availableCategories, id: \.self) { category in
                            Button(category) { selectedCategory = category }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                            Text(selectedCategory ?? "Category").lineLimit(1)
                        }
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(selectedCategory != nil ? Color.blue : Color.gray.opacity(0.3))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    Menu {
                        Button("Clear", action: { selectedStatus = nil })
                        Divider()
                        ForEach(GearItem.GearStatus.allCases, id: \.self) { status in
                            Button(status.rawValue) { selectedStatus = status }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle")
                            Text(selectedStatus?.rawValue ?? "Status").lineLimit(1)
                        }
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(selectedStatus != nil ? Color.blue : Color.gray.opacity(0.3))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    if !allGearLocations.isEmpty {
                        Menu {
                            Button("Clear", action: { selectedLocation = nil })
                            Divider()
                            ForEach(allGearLocations, id: \.self) { location in
                                Button(location) { selectedLocation = location }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "mappin.circle")
                                Text(selectedLocation ?? "Location").lineLimit(1)
                            }
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(selectedLocation != nil ? Color.blue : Color.gray.opacity(0.3))
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                List {
                    ForEach(filteredGear) { item in
                        NavigationLink(destination: GearDetailView(item: item).environmentObject(store)) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(item.name).font(.headline)
                                    Text(item.category).font(.caption).foregroundColor(.secondary)
                                    if !item.location.isEmpty {
                                        Text(item.location).font(.caption2).foregroundColor(.gray)
                                    }
                                }
                                Spacer()
                                Text(item.status.rawValue)
                                    .font(.caption2)
                                    .padding(6)
                                    .background(statusColor(item.status).opacity(0.2))
                                    .foregroundColor(statusColor(item.status))
                                    .cornerRadius(6)
                            }
                        }
                    }
                }
                if isMerging {
                    ProgressView("Merging duplicates...")
                }
                if showMergeResult {
                    Text(mergeResultMessage)
                }
            }
            .navigationTitle("Gear")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button(action: exportGear) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }.disabled(isExporting)
                    Button(action: { showAddGear = true }) {
                        Label("Add", systemImage: "plus")
                    }
                    Button(action: {
                        mergePreview = findDuplicateGearGroups()
                        showMergeConfirm = true
                    }) {
                        Label("Merge", systemImage: "arrow.triangle.merge")
                    }.disabled(isMerging)
                }
            }
            .onAppear {
                initializeGearTab()
            }
            .onChange(of: searchText) { _ in }
            .onChange(of: selectedCategory) { _ in }
            .onChange(of: selectedStatus) { _ in }
            .onChange(of: selectedLocation) { _ in }
        }
        .sheet(isPresented: $showAddGear) {
            AddGearView { newItem in
                store.saveGear(newItem)
                showAddGear = false
            }
        }
        .sheet(isPresented: Binding(get: { exportURL != nil }, set: { if !$0 { exportURL = nil } })) {
            if let url = exportURL {
                ShareSheet(items: [url])
            }
        }
    }
}
*/

struct UsersView: View {
    @EnvironmentObject var store: ProdConnectStore
    private var canManageUsers: Bool { store.user?.isAdmin == true || store.user?.isOwner == true }

    var body: some View {
        NavigationView {
            List(store.teamMembers) { member in
                if canManageUsers {
                    NavigationLink(destination: UserDetailView(user: member).environmentObject(store)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(member.displayName).font(.headline)
                            Text(member.email).font(.subheadline).foregroundColor(.secondary)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(member.displayName).font(.headline)
                        Text(member.email).font(.subheadline).foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Users")
        }
    }
}

struct GearTabView: View {
    @EnvironmentObject var store: ProdConnectStore
    @State private var searchText = ""
    @State private var showAddGear = false
    @State private var exportURL: URL?
    @State private var isExporting = false
    @State private var showMergeConfirm = false
    @State private var isMerging = false
    @State private var mergeResultMessage = ""
    @State private var showMergeResult = false
    @State private var duplicateGearGroupCount = 0

    private var filteredGear: [GearItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return store.gear }
        return store.gear.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
            $0.category.localizedCaseInsensitiveContains(query) ||
            $0.location.localizedCaseInsensitiveContains(query)
        }
    }

    private func statusColor(_ status: GearItem.GearStatus) -> Color {
        switch status {
        case .available: return .green
        case .checkedOut: return .orange
        case .maintenance: return .yellow
        case .lost, .missing: return .red
        case .inUse: return .blue
        case .needsRepair: return .pink
        case .retired, .unknown, .blank: return .gray
        }
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
        var mergedCount = 0

        for group in groups {
            guard var merged = group.first else { continue }
            for item in group.dropFirst() {
                if merged.category.isEmpty, !item.category.isEmpty { merged.category = item.category }
                if merged.location.isEmpty, !item.location.isEmpty { merged.location = item.location }
                if merged.maintenanceNotes.isEmpty, !item.maintenanceNotes.isEmpty { merged.maintenanceNotes = item.maintenanceNotes }
                if merged.status == .unknown, item.status != .unknown { merged.status = item.status }
            }
            store.deleteGear(items: group)
            store.saveGear(merged)
            mergedCount += 1
        }

        isMerging = false
        mergeResultMessage = "Merged \(mergedCount) duplicate group(s)."
        showMergeResult = true
    }

    private func exportGear() {
        guard !filteredGear.isEmpty else { return }
        isExporting = true

        // Spreadsheet-friendly XML that opens in Excel/Numbers; saved with .xlsx per current app expectation.
        var rows = ""
        for item in filteredGear {
            rows += """
            <Row>
            <Cell><Data ss:Type="String">\(item.name.xmlEscaped)</Data></Cell>
            <Cell><Data ss:Type="String">\(item.category.xmlEscaped)</Data></Cell>
            <Cell><Data ss:Type="String">\(item.status.rawValue.xmlEscaped)</Data></Cell>
            <Cell><Data ss:Type="String">\(item.location.xmlEscaped)</Data></Cell>
            <Cell><Data ss:Type="String">\(item.serialNumber.xmlEscaped)</Data></Cell>
            <Cell><Data ss:Type="String">\(item.maintenanceNotes.xmlEscaped)</Data></Cell>
            </Row>
            """
        }

        let xml = """
        <?xml version="1.0"?>
        <?mso-application progid="Excel.Sheet"?>
        <Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet"
         xmlns:o="urn:schemas-microsoft-com:office:office"
         xmlns:x="urn:schemas-microsoft-com:office:excel"
         xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet">
        <Worksheet ss:Name="Gear">
        <Table>
        <Row>
        <Cell><Data ss:Type="String">Name</Data></Cell>
        <Cell><Data ss:Type="String">Category</Data></Cell>
        <Cell><Data ss:Type="String">Status</Data></Cell>
        <Cell><Data ss:Type="String">Location</Data></Cell>
        <Cell><Data ss:Type="String">Serial</Data></Cell>
        <Cell><Data ss:Type="String">Notes</Data></Cell>
        </Row>
        \(rows)
        </Table>
        </Worksheet>
        </Workbook>
        """

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("GearExport.xlsx")
        do {
            try xml.write(to: url, atomically: true, encoding: .utf8)
            exportURL = url
        } catch {
            mergeResultMessage = "Export failed: \(error.localizedDescription)"
            showMergeResult = true
        }
        isExporting = false
    }

    @ViewBuilder
    private func gearRow(for item: GearItem) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(item.name).font(.headline)
                Text(item.category).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Text(item.status.rawValue)
                .font(.caption2)
                .padding(6)
                .background(statusColor(item.status).opacity(0.2))
                .foregroundColor(statusColor(item.status))
                .cornerRadius(6)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SearchBar(text: $searchText)
                List {
                    ForEach(filteredGear) { item in
                        NavigationLink(destination: GearDetailView(item: item).environmentObject(store)) {
                            gearRow(for: item)
                        }
                    }
                }
            }
            .navigationTitle("Gear")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button(action: exportGear) {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .disabled(isExporting || filteredGear.isEmpty)

                    Button(action: { showAddGear = true }) {
                        Label("Add", systemImage: "plus")
                    }

                    Button(action: { showMergeConfirm = true }) {
                        Label("Merge", systemImage: "arrow.triangle.merge")
                    }
                    .disabled(duplicateGearGroupCount == 0 || isMerging)
                }
            }
            .sheet(isPresented: $showAddGear) {
                AddGearView { item in
                    store.saveGear(item)
                    showAddGear = false
                }
                .environmentObject(store)
            }
            .sheet(isPresented: Binding(get: { exportURL != nil }, set: { if !$0 { exportURL = nil } })) {
                if let url = exportURL {
                    ShareSheet(items: [url])
                }
            }
            .alert("Merge Duplicates", isPresented: $showMergeConfirm) {
                Button("Merge", role: .destructive) { mergeDuplicates() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Found \(duplicateGearGroupCount) duplicate group(s). Merge now?")
            }
            .alert("Gear", isPresented: $showMergeResult) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(mergeResultMessage)
            }
            .onAppear {
                refreshDuplicateGroupCount()
            }
            .onReceive(store.$gear) { _ in
                refreshDuplicateGroupCount()
            }
        }
    }
}
// MARK: - ShareSheet for file sharing
import SwiftUI
import Combine
import UIKit
import AVKit
import FirebaseFirestore
import FirebaseStorage
import FirebaseAuth
import StoreKit
import PhotosUI
import OneSignalFramework
// removed extraneous top-level '}'
// MARK: - Main ContentView
struct ContentView: View {
    @StateObject var store = ProdConnectStore.shared
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var autoLoginAttempted = false
    @State private var showAddGear = false
    @State private var exportURL: URL? = nil
    @State private var isExporting = false
    @State private var mergePreview: [[GearItem]] = []
    @State private var showMergeConfirm = false
    @State private var isMerging = false
    @State private var showMergeResult = false
    @State private var mergeResultMessage: String = ""
    @State private var searchText: String = ""
    @State private var selectedCategory: String? = nil
    @State private var selectedStatus: GearItem.GearStatus? = nil
    @State private var selectedLocation: String? = nil
    @State private var isLoadingMoreGear = false
    @State private var hasMoreGear = false
    @State private var lastGearSnapshot: DocumentSnapshot? = nil
    @State private var gearPageSize: Int = 50
    @State private var isDataFetchInProgress = false
    @State private var isSearchingGear = false
    @State private var isFilteringGear = false
    @State private var searchResults: [GearItem] = []
    @State private var uploadVideo: Bool = false
    @State private var showAdd: Bool = false
    @State private var gear: [GearItem] = []
    @State private var patchsheet: [PatchRow] = []
    @State private var ideas: [IdeaCard] = []
    @State private var checklists: [ChecklistTemplate] = []
    @State private var lessons: [TrainingLesson] = []
    @State private var channels: [ChatChannel] = []
    @State private var teamMembers: [UserProfile] = []
    @State private var listenerRegistration: ListenerRegistration? = nil
    @State private var db = Firestore.firestore()
    @State private var user: UserProfile? = nil
    @State private var teamCode: String? = nil
    @State private var availableLocations: [String] = []
    @State private var availableCategories: [String] = []
    @State private var filteredGear: [GearItem] = []
    @State private var filteredResults: [GearItem] = []
    @State private var allGearLocations: [String] = []
    @State private var locations: [String] = []
    @State private var rooms: [String] = []
    @State private var statusColor: (GearItem.GearStatus) -> Color = { _ in .gray }
    @State private var XLSXExportError: Error? = nil
    // Removed invalid top-level property wrappers for StorageReference and StorageMetadata
    // ...existing code...
    private struct MergePreviewGroupRow: View {
        let group: [GearItem]
        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                Text("• " + (group.first?.name ?? "") + " (Serial: " + (group.first?.serialNumber ?? "") + ")")
                    .font(.footnote).bold()
                ForEach(group, id: \.id) { item in
                    Text("    - " + item.category + (item.location.isEmpty ? "" : ", " + item.location))
                        .font(.caption2)
                }
            }
        }
    }
    private var addGearSheetContent: some View {
        AddGearView { newItem in
            store.saveGear(newItem)
            showAddGear = false
        }
        .environmentObject(store)
    }

    private var shareSheetContent: some View {
        Group {
            if let url = exportURL {
                ShareSheet(items: [url])
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarButtons: some ToolbarContent {
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            Button(action: exportGear) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .disabled(isExporting)

            Button(action: { showAddGear = true }) {
                Label("Add", systemImage: "plus")
            }

            Button(action: {
                mergePreview = findDuplicateGearGroups()
                showMergeConfirm = true
            }) {
                Label("Merge", systemImage: "arrow.triangle.merge")
            }
            .disabled(isMerging)
        }
    }

    private var searchBarSection: some View {
        SearchBar(text: $searchText)
            .onChange(of: searchText) { _ in }
    }

    private var mergeProgressSection: some View {
        Group {
            if isMerging {
                ProgressView("Merging duplicates...")
            }
        }
    }

    private var mergeResultSection: some View {
        Group {
            if showMergeResult {
                Text(mergeResultMessage)
            }
        }
    }

    private var filterBar: some View {
        HStack(spacing: 12) {
            categoryMenu
            statusMenu
            if !availableLocations.isEmpty {
                locationMenu
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var categoryMenu: some View {
        Menu {
            Button("Clear", action: { selectedCategory = nil })
            Divider()
            ForEach(availableCategories, id: \.self) { category in
                Button(category) { selectedCategory = category }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                Text(selectedCategory ?? "Category").lineLimit(1)
            }
            .font(.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(selectedCategory != nil ? Color.blue : Color.gray.opacity(0.3))
            .foregroundColor(.white)
            .cornerRadius(8)
        }
    }

    private var statusMenu: some View {
        Menu {
            Button("Clear", action: { selectedStatus = nil })
            Divider()
            ForEach(GearItem.GearStatus.allCases, id: \.self) { status in
                Button(status.rawValue) { selectedStatus = status }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle")
                Text(selectedStatus?.rawValue ?? "Status").lineLimit(1)
            }
            .font(.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(selectedStatus != nil ? Color.blue : Color.gray.opacity(0.3))
            .foregroundColor(.white)
            .cornerRadius(8)
        }
    }

    private var locationMenu: some View {
        Menu {
            Button("Clear", action: { selectedLocation = nil })
            Divider()
            ForEach(availableLocations, id: \.self) { location in
                Button(location) { selectedLocation = location }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "mappin.circle")
                Text(selectedLocation ?? "Location").lineLimit(1)
            }
            .font(.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(selectedLocation != nil ? Color.blue : Color.gray.opacity(0.3))
            .foregroundColor(.white)
            .cornerRadius(8)
        }
    }

    private var gearList: some View {
        List {
            ForEach(filteredGear) { item in
                NavigationLink(destination: GearDetailView(item: item).environmentObject(store)) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(item.name).font(.headline)
                            Text(item.category).font(.caption).foregroundColor(.secondary)
                            if !item.location.isEmpty {
                                Text(item.location).font(.caption2).foregroundColor(.gray)
                            }
                        }
                        Spacer()
                        Text(item.status.rawValue)
                            .font(.caption2)
                            .padding(6)
                            .background(statusColor(item.status).opacity(0.2))
                            .foregroundColor(statusColor(item.status))
                            .cornerRadius(6)
                    }
                }
            }
        }
    }

    var body: some View {
        Group {
            if store.user == nil {
                VStack(spacing: 16) {
                    Text("Sign In").font(.largeTitle)
                    TextField("Email", text: $email)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    SecureField("Password", text: $password)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    Button("Sign In") {
                        store.signIn(email: email, password: password) { result in
                            if case .success = result {
                                KeychainHelper.shared.save(email, for: "prodconnect_email")
                                KeychainHelper.shared.save(password, for: "prodconnect_password")
                            }
                        }
                    }.disabled(email.isEmpty || password.isEmpty)
                }
                .padding()
                .onAppear {
                    if !autoLoginAttempted {
                        let savedEmail = KeychainHelper.shared.read(for: "prodconnect_email") ?? ""
                        let savedPassword = KeychainHelper.shared.read(for: "prodconnect_password") ?? ""
                        if !savedEmail.isEmpty && !savedPassword.isEmpty {
                            email = savedEmail
                            password = savedPassword
                            store.signIn(email: email, password: password) { _ in }
                        }
                        autoLoginAttempted = true
                    }
                }
            } else {
                NavigationStack {
                    VStack(spacing: 0) {
                        searchBarSection
                        filterBar
                        gearList
                        mergeProgressSection
                        mergeResultSection
                    }
                    .navigationTitle("Gear")
                    .toolbar {
                        toolbarButtons
                    }
                }
                .sheet(isPresented: $showAddGear) {
                    addGearSheetContent
                }
                .sheet(isPresented: Binding(get: { exportURL != nil }, set: { if !$0 { exportURL = nil } })) {
                    shareSheetContent
                }
            }
        }
    }

    private func exportGear() {
        // Minimal placeholder to restore compilation; full XLSX export flow can be reconnected after stabilization.
        isExporting = false
    }

    private func findDuplicateGearGroups() -> [[GearItem]] {
        let groups = Dictionary(grouping: store.gear) { item -> String? in
            let nameKey = item.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let serialKey = item.serialNumber.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !nameKey.isEmpty, !serialKey.isEmpty else { return nil }
            return "\(nameKey)|\(serialKey)"
        }
        return groups.compactMap { key, value in
            guard key != nil, value.count > 1 else { return nil }
            return value
        }
    }

    var canEditIdeas: Bool { user != nil }
    var canEditChecklists: Bool { user != nil }

    var canEditTraining: Bool {
        guard let user = user else { return false }
        return user.isAdmin || user.canEditTraining
    }

    var canSeeTrainingTab: Bool {
        guard let user = user else { return false }
        return user.subscriptionTier.lowercased() != "free" || user.isAdmin
    }

    // ...existing code...
    // Configure Firestore settings to prevent WriteStream errors on slow networks
    private func configureFirestoreSettings() {
        let settings = FirestoreSettings()
        settings.cacheSettings = PersistentCacheSettings()  // Updated for deprecation
        Firestore.firestore().settings = settings
        if Auth.auth().currentUser != nil { fetchUserProfile { _ in } }
    }
    // Call configureFirestoreSettings() from your app or view initializer, e.g. in ProdConnectApp or ContentView init/onAppear

    // MARK: - Auth
    func signUp(email: String, password: String, teamCode: String? = nil, isAdmin: Bool = false, completion: @escaping (Result<Void, Error>) -> Void) {
        // If teamCode provided, validate it exists first
        if let code = teamCode, !code.isEmpty {
            self.db.collection("teams").document(code).getDocument { snap, error in
                if error == nil, snap?.exists == true {
                    // Code exists, proceed with signup
                    self.completeSignUp(email: email, password: password, teamCode: code, isAdmin: isAdmin, completion: completion)
                    return
                }

                // Fallback: older teams may only exist in users collection
                self.db.collection("users").whereField("teamCode", isEqualTo: code).limit(to: 1).getDocuments { userSnap, userError in
                    if userError != nil || userSnap?.documents.isEmpty != false {
                        completion(.failure(NSError(domain: "Invalid team code", code: 0, userInfo: [NSLocalizedDescriptionKey: "Team code does not exist"])))
                        return
                    }

                    let creatorEmail = userSnap?.documents.first?.data()["email"] as? String
                    self.db.collection("teams").document(code).setData([
                        "code": code,
                        "createdAt": FieldValue.serverTimestamp(),
                        "createdBy": creatorEmail ?? "",
                        "isActive": true
                    ], merge: true) { _ in
                        self.completeSignUp(email: email, password: password, teamCode: code, isAdmin: isAdmin, completion: completion)
                    }
                }
            }
        } else {
            // No team code provided, create free account with auto-generated hidden code
            completeSignUp(email: email, password: password, teamCode: nil, isAdmin: isAdmin, completion: completion)
        }
    }
    
    private func completeSignUp(email: String, password: String, teamCode: String?, isAdmin: Bool = false, completion: @escaping (Result<Void, Error>) -> Void) {
        Auth.auth().createUser(withEmail: email, password: password) { result, error in
            if let error = error { completion(.failure(error)); return }
            guard let uid = result?.user.uid else { return }
            
            let defaultName = email.components(separatedBy: "@").first ?? "New User"
            let hasTeamCode = teamCode != nil && !teamCode!.isEmpty
            // Basic tier for team members or admin signups; otherwise free
            let subscriptionTier = (hasTeamCode || isAdmin) ? "basic" : "free"
            let finalIsAdmin = isAdmin
            
            // Auto-generate hidden team code for free accounts
            let finalTeamCode = teamCode ?? self.generateTeamCode()

            // Ensure every signup has a team document for discovery/join
            self.db.collection("teams").document(finalTeamCode).setData([
                "code": finalTeamCode,
                "createdAt": FieldValue.serverTimestamp(),
                "createdBy": email,
                "isActive": true
            ], merge: true) { error in
                if let error = error { print("Team registration error:", error) }
            }
            
            let data: [String: Any] = [
                "id": uid,
                "email": email,
                "displayName": defaultName,
                "name": defaultName,
                "teamCode": finalTeamCode,
                "isAdmin": finalIsAdmin,
                "isOwner": false,
                "subscriptionTier": subscriptionTier,
                "canEditPatchsheet": subscriptionTier != "free",
                "canEditTraining": subscriptionTier != "free",
                "canEditGear": subscriptionTier != "free",
                "canEditIdeas": subscriptionTier != "free",
                "canEditChecklists": subscriptionTier != "free",
                "canSeeChat": true,
                "canSeePatchsheet": true,
                "canSeeTraining": true,
                "canSeeGear": true,
                "canSeeIdeas": true,
                "canSeeChecklists": true
            ]
            
            self.db.collection("users").document(uid).setData(data) { error in
                DispatchQueue.main.async {
                    if let error = error {
                        completion(.failure(error))
                    } else {
                        var profile = UserProfile(id: uid, displayName: defaultName, email: email, teamCode: finalTeamCode, isAdmin: finalIsAdmin)
                        profile.subscriptionTier = subscriptionTier
                        profile.canEditPatchsheet = subscriptionTier != "free"
                        profile.canEditTraining = subscriptionTier != "free"
                        profile.canEditGear = subscriptionTier != "free"
                        profile.canEditIdeas = subscriptionTier != "free"
                        profile.canEditChecklists = subscriptionTier != "free"
                        self.user = profile
                        // Set OneSignal external user ID (email)
                        OneSignal.login(profile.email)
                        print("DEBUG: OneSignal logged in with: \(profile.email)")
                        self.listenToTeamData()
                        completion(.success(()))
                    }
                }
            }
        }
    }

    func signIn(email: String, password: String, completion: @escaping (Result<Void, Error>) -> Void) {
        Auth.auth().signIn(withEmail: email, password: password) { _, error in
            if let error = error { completion(.failure(error)); return }
            self.fetchUserProfile { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let profile):
                        self.user = profile
                        // OneSignal login is handled in fetchUserProfile
                        // Check subscription status after sign-in
                        Task {
                            await IAPManager.shared.checkSubscription(for: store)
                        }
                        completion(.success(()))
                    case .failure(let err):
                        completion(.failure(err))
                    }
                }
            }
        }
    }

    func signOut() {
        try? Auth.auth().signOut()
        // Logout from OneSignal (only if a user was actually signed in)
        if user != nil {
            OneSignal.logout()
            print("DEBUG: OneSignal logged out")
        }
        user = nil
        gear = []
        lessons = []
        checklists = []
        ideas = []
        channels = []
        patchsheet = []
        teamMembers = []
        listenerRegistration?.remove()
    }

    private func fetchUserProfile(completion: @escaping (Result<UserProfile, Error>) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else {
            completion(.failure(NSError(domain: "No user", code: 0)))
            return
        }

        db.collection("users").document(uid).getDocument { snap, error in
            if let error = error { completion(.failure(error)); return }
            
            // Check subscription status after fetching profile
            Task {
                await IAPManager.shared.checkSubscription(for: store)
            }
            guard let snap = snap else { completion(.failure(NSError(domain: "No snapshot", code: 0))); return }
            if !snap.exists {
                let email = Auth.auth().currentUser?.email ?? ""
                self.createFreeProfile(uid: uid, email: email, completion: completion)
                return
            }

            do {
                var profile = try snap.data(as: UserProfile.self)
                if profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    profile.displayName = profile.email.components(separatedBy: "@").first ?? "New User"
                }
                if profile.isAdmin && profile.subscriptionTier == "free" {
                    profile.subscriptionTier = "basic"
                    profile.canEditPatchsheet = true
                    profile.canEditTraining = true
                    profile.canEditGear = true
                    profile.canEditIdeas = true
                    profile.canEditChecklists = true
                    self.db.collection("users").document(profile.id).setData([
                        "subscriptionTier": "basic",
                        "canEditPatchsheet": true,
                        "canEditTraining": true,
                        "canEditGear": true,
                        "canEditIdeas": true,
                        "canEditChecklists": true
                    ], merge: true) { error in
                        if let error = error { print("Firestore update error:", error) }
                    }
                }
                if profile.isOwner {
                    var ownerUpdates: [String: Any] = [:]
                    if !profile.isAdmin {
                        profile.isAdmin = true
                        ownerUpdates["isAdmin"] = true
                    }
                    if profile.subscriptionTier == "free" {
                        profile.subscriptionTier = "basic"
                        ownerUpdates["subscriptionTier"] = "basic"
                    }
                    if !ownerUpdates.isEmpty {
                        self.db.collection("users").document(profile.id).setData(ownerUpdates, merge: true) { error in
                            if let error = error { print("Firestore update error:", error) }
                        }
                    }
                }

                self.ensureValidTeamCode(profile) { updatedProfile in
                    self.ensureTeamDocumentExists(updatedProfile)
                    self.user = updatedProfile
                    // Register with OneSignal
                    OneSignal.login(updatedProfile.email)
                    print("DEBUG: OneSignal logged in with: \(updatedProfile.email)")
                    self.listenToTeamData()
                    completion(.success(updatedProfile))
                }
            } catch {
                completion(.failure(error))
            }
        }
    }

    private func createFreeProfile(uid: String, email: String, completion: @escaping (Result<UserProfile, Error>) -> Void) {
        let safeEmail = email.isEmpty ? "unknown@prodconnect" : email
        let defaultName = safeEmail.components(separatedBy: "@").first ?? "User"
        let teamCode = generateTeamCode()

        db.collection("teams").document(teamCode).setData([
            "code": teamCode,
            "createdAt": FieldValue.serverTimestamp(),
            "createdBy": safeEmail,
            "isActive": true
        ], merge: true) { error in
            if let error = error { print("Team registration error:", error) }
        }

        let data: [String: Any] = [
            "id": uid,
            "email": safeEmail,
            "displayName": defaultName,
            "name": defaultName,
            "teamCode": teamCode,
            "isAdmin": false,
            "isOwner": false,
            "subscriptionTier": "free",
            "assignedCampus": "",
            "canEditPatchsheet": false,
            "canEditTraining": false,
            "canEditGear": false,
            "canEditIdeas": false,
            "canEditChecklists": false,
            "canSeeChat": true,
            "canSeePatchsheet": true,
            "canSeeTraining": true,
            "canSeeGear": true,
            "canSeeIdeas": true,
            "canSeeChecklists": true
        ]

        db.collection("users").document(uid).setData(data) { error in
            if let error = error {
                completion(.failure(error))
                return
            }

            var profile = UserProfile(id: uid, displayName: defaultName, email: safeEmail, teamCode: teamCode)
            profile.subscriptionTier = "free"
            profile.assignedCampus = ""
            profile.canEditPatchsheet = false
            profile.canEditTraining = false
            profile.canEditGear = false
            profile.canEditIdeas = false
            profile.canEditChecklists = false

            self.user = profile
            OneSignal.login(profile.email)
            self.listenToTeamData()
            completion(.success(profile))
        }
    }

    private func ensureValidTeamCode(_ profile: UserProfile, completion: @escaping (UserProfile) -> Void) {
        let currentCode = profile.teamCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard currentCode.isEmpty else {
            completion(profile)
            return
        }

        let newCode = generateTeamCode()
        var updated = profile
        updated.teamCode = newCode

        let userDoc = db.collection("users").document(profile.id)
        userDoc.updateData(["teamCode": newCode]) { error in
            if let error = error {
                print("DEBUG: Failed to persist teamCode fallback: \(error.localizedDescription)")
                completion(updated)
                return
            }

            self.db.collection("teams").document(newCode).setData([
                 "createdAt": FieldValue.serverTimestamp()
            ], merge: true) { teamError in
                if let teamError = teamError {
                    print("DEBUG: Failed to create team doc for fallback: \(teamError.localizedDescription)")
                }
                completion(updated)
            }
        }
    }

    private func ensureTeamDocumentExists(_ profile: UserProfile) {
        guard profile.isAdmin else { return }
        let code = profile.teamCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !code.isEmpty else { return }

        db.collection("teams").document(code).getDocument { snap, error in
            if error != nil { return }
            let ownerUpdates: [String: Any]
            if profile.isOwner {
                ownerUpdates = ["ownerId": profile.id, "ownerEmail": profile.email]
            } else {
                ownerUpdates = [:]
            }

            if snap?.exists == true {
                if !ownerUpdates.isEmpty {
                    self.db.collection("teams").document(code).setData(ownerUpdates, merge: true) { err in
                        if let err = err { print("Team owner update error:", err) }
                    }
                }
                return
            }

            var data: [String: Any] = [
                "code": code,
                "createdAt": FieldValue.serverTimestamp(),
                "createdBy": profile.email,
                "isActive": true
            ]
            for (key, value) in ownerUpdates { data[key] = value }
            self.db.collection("teams").document(code).setData(data, merge: true) { err in
                if let err = err { print("Team registration error:", err) }
            }
        }
    }

    // MARK: - Team Data
    func listenToTeamData() {
        guard let code = teamCode, !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        // Prevent multiple simultaneous data fetch requests
        guard !isDataFetchInProgress else { return }
        
        isDataFetchInProgress = true
        
        // LAZY LOAD STRATEGY: Don't load gear/patchsheet at startup
        // These are large collections (15k+ items) that cause WriteStream errors on phones
        // Load them only when user taps the Gear tab
        // This leaves only smaller collections to load at startup
        
        // Load only essential small collections at startup
        // Stagger fetches to prevent network overwhelm on slow phone networks
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.0) {
            self.fetchLessonOnce(teamCode: code)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.fetchChecklistOnce(teamCode: code)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.fetchIdeasOnce(teamCode: code)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.listenToChannels(teamCode: code)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.listenToLocations()
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            self.listenToRooms()
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            self.listenToTeamMembers()
            // Reset the flag after all fetches have started
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.isDataFetchInProgress = false
            }
        }
    }
    
    // Load gear on-demand when user navigates to Gear tab
    func loadGearOnDemand() {
        guard let code = teamCode else { return }
        guard gear.isEmpty else { return } // Only load if empty
        // Load gear immediately, but give a small delay to ensure Firebase is ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.fetchGearOnce(teamCode: code)
        }
    }
    
    // Load patchsheet on-demand when user navigates to Gear tab
    func loadPatchsheetOnDemand() {
        guard let code = teamCode else {
            return
        }
        print("DEBUG: loadPatchsheetOnDemand called for team: \(code)")
        // Always refresh to keep in sync
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            print("DEBUG: calling fetchPatchsheetOnce for team: \(code)")
            self.fetchPatchsheetOnce(teamCode: code)
        }
    }

    func fetchGearAndPatchsheetForExport(completion: @escaping (Result<(gear: [GearItem], patchsheet: [PatchRow]), Error>) -> Void) {
        guard let code = teamCode else {
            completion(.failure(NSError(domain: "Export", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing team code."])))
            return
        }

        let group = DispatchGroup()
        var gearItems: [GearItem] = []
        var patchItems: [PatchRow] = []
        var firstError: Error?

        group.enter()
        var gearQuery: Query = db.collection("gear")
            .whereField("teamCode", isEqualTo: code)
            .limit(to: 10000)

        if let user = user, user.role == .free, let email = Auth.auth().currentUser?.email {
            gearQuery = gearQuery.whereField("createdBy", isEqualTo: email)
        }

        gearQuery.getDocuments { snap, error in
            if let error = error {
                firstError = error
                group.leave()
                return
            }

            let docs = snap?.documents ?? []
            gearItems = docs.compactMap { doc in
                return self.decodeGearItem(from: doc)
            }
            group.leave()
        }

        group.enter()
        db.collection("patchsheet")
            .whereField("teamCode", isEqualTo: code)
            .limit(to: 5000)
            .getDocuments { snap, error in
                if let error = error {
                    firstError = error
                    group.leave()
                    return
                }

                let docs = snap?.documents ?? []
                patchItems = docs.compactMap { doc in
                    return try? doc.data(as: PatchRow.self)
                }
                group.leave()
            }

        group.notify(queue: .main) {
            if let error = firstError {
                completion(.failure(error))
            } else {
                completion(.success((gear: gearItems, patchsheet: patchItems)))
            }
        }
    }

    // Fetch gear with real-time listener for immediate updates
    private func fetchGearOnce(teamCode: String) {
        lastGearSnapshot = nil
        hasMoreGear = true
        
        var query: Query = db.collection("gear")
            .whereField("teamCode", isEqualTo: teamCode)
            .limit(to: gearPageSize)
        
        // Use real-time listener so items appear immediately when added
        query.addSnapshotListener { snap, error in
            
            DispatchQueue.main.async {
                self.isLoadingMoreGear = false
                
                if let error = error {
                    return
                }
                
                let docs = snap?.documents ?? []
                
                var decoded = docs.compactMap { doc -> GearItem? in
                    return self.decodeGearItem(from: doc)
                }
                
                // For free users, filter to only items they created
                if let user = self.user, user.role == .free, let email = Auth.auth().currentUser?.email {
                    decoded = decoded.filter { item in
                        return (item.createdBy ?? "") == email
                    }
                }
                
                if decoded.isEmpty && !self.gear.isEmpty {
                    // Don't clear if we already have items - keep showing what we loaded
                    return
                }
                
                if docs.count < self.gearPageSize {
                    self.hasMoreGear = false
                }
                
                // Save last document for next pagination
                if let lastDoc = docs.last {
                    self.lastGearSnapshot = lastDoc
                }
                
                // Update gear with decoded items
                self.gear = decoded
            }
        }
    }
    
    func loadMoreGear(teamCode: String) {
        guard !isLoadingMoreGear && hasMoreGear else { 
            return 
        }
        
        print("DEBUG: loadMoreGear starting for team: \(teamCode)")
        isLoadingMoreGear = true
        
        var query: Query = db.collection("gear")
            .whereField("teamCode", isEqualTo: teamCode)
        
        // Free users only see items they created
        if let user = user, user.role == .free, let email = Auth.auth().currentUser?.email {
            query = query.whereField("createdBy", isEqualTo: email)
        }
        
        query = query.limit(to: gearPageSize * 2) // Load more than initial for load more button
        
        // If we have a last snapshot, start after it for pagination
        if let lastSnapshot = lastGearSnapshot {
            query = query.start(afterDocument: lastSnapshot)
        }
        
        query.getDocuments { snap, error in
            
            DispatchQueue.main.async {
                self.isLoadingMoreGear = false
                
                if let error = error {
                    print("ERROR fetching more gear: \(error.localizedDescription)")
                    return
                }
                
                let docs = snap?.documents ?? []
                
                if docs.isEmpty {
                    self.hasMoreGear = false
                    return
                }
                
                // If we got fewer than requested, we've reached the end
                if docs.count < self.gearPageSize * 2 {
                    self.hasMoreGear = false
                }
                
                // Save last document for next pagination
                if let lastDoc = docs.last {
                    self.lastGearSnapshot = lastDoc
                }
                
                let decoded = docs.compactMap { doc -> GearItem? in
                    return self.decodeGearItem(from: doc)
                }
                
                // Append to existing gear instead of replacing
                self.gear.append(contentsOf: decoded)
                print("Loaded \(decoded.count) gear items (total: \(self.gear.count), more: \(self.hasMoreGear))")
            }
        }
    }
    
    // Fetch all patchsheet items
    private func fetchPatchsheetOnce(teamCode: String) {
        print("DEBUG: fetchPatchsheetOnce called for teamCode: \(teamCode)")
        db.collection("patchsheet")
            .whereField("teamCode", isEqualTo: teamCode)
            .getDocuments { snap, error in
                
                DispatchQueue.main.async {
                    if let error = error {
                        print("ERROR fetching patchsheet for \(teamCode): \(error.localizedDescription)")
                        return
                    }
                    
                    let docs = snap?.documents ?? []
                    print("DEBUG: Got \(docs.count) patchsheet docs for \(teamCode)")
                    
                    let decoded = docs.compactMap { doc -> PatchRow? in
                        do {
                            let patch = try doc.data(as: PatchRow.self)
                            print("DEBUG: Decoded patch: \(patch.name) (cat: \(patch.category), pos: \(patch.position))")
                            return patch
                        } catch {
                            print("DEBUG: Error decoding patch doc: \(error)")
                            return nil
                        }
                    }
                    
                    self.patchsheet = decoded.sorted { $0.position < $1.position }
                    print("DEBUG: Loaded \(decoded.count) patchsheet items for \(teamCode), now have \(self.patchsheet.count) total")
                }
            }
    }
    
    // Search entire gear database by name, category, location, or serial number
    func searchGear(query: String, teamCode: String) {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            searchResults = []
            return
        }
        
        isSearchingGear = true
        let searchTerm = query.lowercased()
        
        var firestoreQuery: Query = db.collection("gear")
            .whereField("teamCode", isEqualTo: teamCode)
            .limit(to: 10000)  // Safety limit for database reads
        
        firestoreQuery.getDocuments { snap, error in
                
                DispatchQueue.main.async {
                    self.isSearchingGear = false
                    
                    if let error = error {
                        print("ERROR searching gear: \(error.localizedDescription)")
                        return
                    }
                    
                    let docs = snap?.documents ?? []
                    
                    // Filter results locally by search term
                    let decoded = docs.compactMap { doc -> GearItem? in
                        return self.decodeGearItem(from: doc)
                    }
                    
                    // For free users, filter to only items they created
                    var filtered = decoded
                    if let user = self.user, user.role == .free, let email = Auth.auth().currentUser?.email {
                        filtered = filtered.filter { ($0.createdBy ?? "") == email }
                    }
                    
                    // Search across name, category, location, and serial number
                    self.searchResults = filtered.filter { item in
                        item.name.lowercased().contains(searchTerm) ||
                        item.category.lowercased().contains(searchTerm) ||
                        item.location.lowercased().contains(searchTerm) ||
                        item.serialNumber.lowercased().contains(searchTerm)
                    }
                    
                    print("Search found \(self.searchResults.count) matching items for '\(query)'")
                }
            }
    }
    
    func filterGear(category: String?, status: GearItem.GearStatus?, location: String?, teamCode: String) {
        isFilteringGear = true
        
        var query: Query = db.collection("gear").whereField("teamCode", isEqualTo: teamCode)
            .limit(to: 10000)
        
        if let category = category, !category.isEmpty {
            query = query.whereField("category", isEqualTo: category)
        }
        
        if let status = status {
            query = query.whereField("status", isEqualTo: status.rawValue)
        }
        
        if let location = location, !location.isEmpty {
            query = query.whereField("location", isEqualTo: location)
        }
        
        query.getDocuments { snap, error in
            
            DispatchQueue.main.async {
                self.isFilteringGear = false
                
                if let error = error {
                    print("ERROR filtering gear: \(error.localizedDescription)")
                    return
                }
                
                let docs = snap?.documents ?? []
                let decoded = docs.compactMap { doc -> GearItem? in
                    return self.decodeGearItem(from: doc)
                }
                
                // For free users, filter to only items they created
                var filtered = decoded
                if let user = self.user, user.role == .free, let email = Auth.auth().currentUser?.email {
                    filtered = filtered.filter { ($0.createdBy ?? "") == email }
                }
                
                self.filteredResults = filtered
                print("Filter found \(self.filteredResults.count) matching items")
            }
        }
    }
    
    func fetchAllGearLocations(teamCode: String) {
        db.collection("gear")
            .whereField("teamCode", isEqualTo: teamCode)
            .limit(to: 10000)
            .getDocuments { snap, error in
                
                if let error = error {
                    print("ERROR fetching locations: \(error.localizedDescription)")
                    return
                }
                
                let docs = snap?.documents ?? []
                let decoded = docs.compactMap { doc -> GearItem? in
                    return self.decodeGearItem(from: doc)
                }
                
                DispatchQueue.main.async {
                    let locations = Array(Set(decoded.map { $0.location }.filter { !$0.isEmpty })).sorted()
                    self.allGearLocations = locations
                    print("Found \(locations.count) unique locations across all gear")
                }
            }
    }
    
    private func fetchLessonOnce(teamCode: String) {
        db.collection("lessons")
            .whereField("teamCode", isEqualTo: teamCode)
            .limit(to: 500)
            .addSnapshotListener { snap, error in
                if let error = error {
                    print("Error fetching lessons:", error.localizedDescription)
                    return
                }
                let docs = snap?.documents ?? []
                let decoded = docs.compactMap { doc -> TrainingLesson? in
                    do {
                        return try doc.data(as: TrainingLesson.self)
                    } catch {
                        return nil
                    }
                }
                DispatchQueue.main.async {
                        self.lessons = decoded
                    }
                }
    }
    
    private func fetchChecklistOnce(teamCode: String) {
        var query: Query = db.collection("checklists")
            .whereField("teamCode", isEqualTo: teamCode)
        
        // Free users only see items they created
        if let user = user, user.role == .free, let email = Auth.auth().currentUser?.email {
            query = query.whereField("createdBy", isEqualTo: email)
        }
        
        query = query.limit(to: 500)
        
        query.addSnapshotListener { snap, error in
                    if let error = error {
                        print("Error fetching checklists:", error.localizedDescription)
                        return
                    }
                    let docs = snap?.documents ?? []
                    let decoded = docs.compactMap { doc -> ChecklistTemplate? in
                        do {
                            return try doc.data(as: ChecklistTemplate.self)
                        } catch {
                            return nil
                        }
                    }
                    DispatchQueue.main.async {
                        self.checklists = decoded
                    }
                }
    }
    
    private func fetchIdeasOnce(teamCode: String) {
        var query: Query = db.collection("ideas")
            .whereField("teamCode", isEqualTo: teamCode)
        
        // Free users only see items they created
        if let user = user, user.role == .free, let email = Auth.auth().currentUser?.email {
            query = query.whereField("createdBy", isEqualTo: email)
        }
        
        query = query.limit(to: 500)
        
        query.addSnapshotListener { snap, error in
                    if let error = error {
                        print("Error fetching ideas:", error.localizedDescription)
                        return
                    }
                    let docs = snap?.documents ?? []
                    let decoded = docs.compactMap { doc -> IdeaCard? in
                        do {
                            return try doc.data(as: IdeaCard.self)
                        } catch {
                            return nil
                        }
                    }
                    DispatchQueue.main.async {
                        self.ideas = decoded
                    }
                }
    }
    
    private func fetchChannelsOnce(teamCode: String) {
        db.collection("channels")
            .whereField("teamCode", isEqualTo: teamCode)
            .limit(to: 500)
            .getDocuments { snap, error in
                if let error = error {
                    print("Error fetching channels:", error.localizedDescription)
                    return
                }
                let docs = snap?.documents ?? []
                let decoded = docs.compactMap { doc -> ChatChannel? in
                    do {
                        return try doc.data(as: ChatChannel.self)
                    } catch {
                        return nil
                    }
                }
                DispatchQueue.main.async {
                    self.channels = decoded.sorted { lhs, rhs in
                        if lhs.position != rhs.position { return lhs.position < rhs.position }
                        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                    }
                }
            }
    }

    private func listenToChannels(teamCode: String) {
        db.collection("channels")
            .whereField("teamCode", isEqualTo: teamCode)
            .limit(to: 500)
            .addSnapshotListener { snap, error in
                if let error = error {
                    print("Error listening to channels:", error.localizedDescription)
                    return
                }
                let docs = snap?.documents ?? []
                let decoded = docs.compactMap { doc -> ChatChannel? in
                    do {
                        return try doc.data(as: ChatChannel.self)
                    } catch {
                        return nil
                    }
                }
                DispatchQueue.main.async {
                    self.channels = decoded.sorted { lhs, rhs in
                        if lhs.position != rhs.position { return lhs.position < rhs.position }
                        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                    }
                }
            }
    }

    private func listenCollection<T: Codable & Identifiable>(_ collection: String, assignTo keyPath: ReferenceWritableKeyPath<ContentView, [T]>, teamCode: String) {
        // Apply limit for collections with potentially large datasets
        var query: Query = db.collection(collection).whereField("teamCode", isEqualTo: teamCode)
        if collection == "gear" {
            query = query.limit(to: 1000)  // Strictly limit gear to prevent WriteStream transaction size issues
        } else if collection == "patchsheet" {
            query = query.limit(to: 500)  // Strictly limit patchsheet
        }
        query.addSnapshotListener { snap, error in
            if let error = error {
                print("Error loading \(collection):", error.localizedDescription)
                return
            }
            let docs = snap?.documents ?? []
            let decoded = docs.compactMap { doc -> T? in
                do {
                    return try doc.data(as: T.self)
                } catch {
                    return nil
                }
            }
            self[keyPath: keyPath] = decoded
        }
    }
    
    private func listenToLocations() {
        guard let code = teamCode, !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        db.collection("teams").document(code).collection("locations")
            .getDocuments { snapshot, error in
                if let error = error {
                    print("Error fetching locations:", error.localizedDescription)
                    return
                }
                let locations = snapshot?.documents.compactMap { $0.documentID }.sorted() ?? []
                DispatchQueue.main.async {
                    self.locations = locations
                }
            }
    }

    private func listenToRooms() {
        guard let code = teamCode, !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        db.collection("teams").document(code).collection("rooms")
            .getDocuments { snapshot, error in
                if let error = error {
                    print("Error fetching rooms:", error.localizedDescription)
                    return
                }
                let rooms = snapshot?.documents.compactMap { $0.documentID }.sorted() ?? []
                DispatchQueue.main.async {
                    self.rooms = rooms
                }
            }
    }

    func listenToTeamMembers() {
        guard let current = user else { return }
        listenerRegistration?.remove()
        
        // For free accounts, only show themselves
        if current.subscriptionTier == "free" {
            DispatchQueue.main.async {
                self.teamMembers = [current]
            }
            return
        }
        
        self.db.collection("users")
            .whereField("teamCode", isEqualTo: current.teamCode ?? "")
            .getDocuments { snapshot, error in

            if let error = error {
                print("Error fetching team members:", error)
                return
            }

            guard let snapshot = snapshot else { return }

            var members: [UserProfile] = []

            for doc in snapshot.documents {
                let data = doc.data()
                let id = doc.documentID
                let email = data["email"] as? String ?? ""
                    
                // ✅ Fixed displayName logic
                let rawDisplayName = (data["displayName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let displayName: String
                if let name = rawDisplayName, !name.isEmpty {
                    displayName = name
                } else if let legacyName = data["name"] as? String,
                          !legacyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    displayName = legacyName.trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    displayName = email.components(separatedBy: "@").first ?? "User"
                }

                let member = UserProfile(
                    id: id,
                    displayName: displayName,
                        email: email,
                        teamCode: data["teamCode"] as? String ?? current.teamCode,
                        isAdmin: data["isAdmin"] as? Bool ?? false,
                        assignedCampus: data["assignedCampus"] as? String ?? "",
                        canEditPatchsheet: data["canEditPatchsheet"] as? Bool ?? true,
                        canEditTraining: data["canEditTraining"] as? Bool ?? true,
                        canEditGear: data["canEditGear"] as? Bool ?? true,
                        canEditIdeas: data["canEditIdeas"] as? Bool ?? true,
                        canEditChecklists: data["canEditChecklists"] as? Bool ?? true,
                        canSeeChat: data["canSeeChat"] as? Bool ?? true,
                        canSeePatchsheet: data["canSeePatchsheet"] as? Bool ?? true,
                        canSeeTraining: data["canSeeTraining"] as? Bool ?? true,
                        canSeeGear: data["canSeeGear"] as? Bool ?? true,
                        canSeeIdeas: data["canSeeIdeas"] as? Bool ?? true,
                        canSeeChecklists: data["canSeeChecklists"] as? Bool ?? true
                    )

                    members.append(member)
                }

                // Sort alphabetically by displayName
                DispatchQueue.main.async {
                    self.teamMembers = members.sorted { $0.displayName.lowercased() < $1.displayName.lowercased() }
                }
            }
    }

    private func save<T: Encodable>(_ item: T, collection: String) {
        guard let id = (item as? any Identifiable)?.id as? String else { 
            print("Error saving \(item) to \(collection):", "Invalid ID")
            return
        }
        do {
            try db.collection(collection).document(id).setData(from: item, merge: true)
        } catch {
            print("Error saving to \(collection):", error)
        }
    }

    // MARK: - Patchsheet Ordering
    func nextPatchPosition(for category: String) -> Int {
        let positions = patchsheet.filter { $0.category == category }.map { $0.position }
        return (positions.max() ?? -1) + 1
    }

    func updatePatchOrder(category: String, orderedIds: [String]) {
        let batch = db.batch()
        for (idx, id) in orderedIds.enumerated() {
            batch.updateData(["position": idx], forDocument: db.collection("patchsheet").document(id))
        }
        batch.commit { _ in
            DispatchQueue.main.async {
                for (idx, id) in orderedIds.enumerated() {
                    if let i = self.patchsheet.firstIndex(where: { $0.id == id && $0.category == category }) {
                        self.patchsheet[i].position = idx
                    }
                }
            }
        }
    }

    // MARK: - Channel Ordering
    func nextChannelPosition() -> Int {
        let positions = channels.map { $0.position }
        return (positions.max() ?? -1) + 1
    }

    func updateChannelOrder(orderedIds: [String]) {
        let batch = db.batch()
        for (idx, id) in orderedIds.enumerated() {
            batch.updateData(["position": idx], forDocument: db.collection("channels").document(id))
        }
        batch.commit { _ in
            DispatchQueue.main.async {
                for (idx, id) in orderedIds.enumerated() {
                    if let i = self.channels.firstIndex(where: { $0.id == id }) {
                        self.channels[i].position = idx
                    }
                }
                self.channels.sort { lhs, rhs in
                    if lhs.position != rhs.position { return lhs.position < rhs.position }
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
            }
        }
    }

    func saveGear(_ item: GearItem) { 
        save(item, collection: "gear")
    }
    func saveLesson(_ item: TrainingLesson) { save(item, collection: "lessons") }
    func saveChecklist(_ item: ChecklistTemplate) { 
        save(item, collection: "checklists")
    }
    func saveIdea(_ item: IdeaCard) { 
        save(item, collection: "ideas")
    }
    func saveChannel(_ item: ChatChannel) { save(item, collection: "channels") }
    func savePatch(_ item: PatchRow) {
        // Persist to Firestore
        save(item, collection: "patchsheet")
        // Optimistically update local state so UI reflects changes immediately
        DispatchQueue.main.async {
            if let idx = self.patchsheet.firstIndex(where: { $0.id == item.id }) {
                self.patchsheet[idx] = item
            } else {
                self.patchsheet.append(item)
            }
        }
    }

    private func decodeGearItem(from doc: QueryDocumentSnapshot) -> GearItem? {
        if let item = try? doc.data(as: GearItem.self) {
            return item
        }

        let data = doc.data()
        guard let name = data["name"] as? String else { return nil }

        let category = data["category"] as? String ?? ""
        let teamCode = data["teamCode"] as? String ?? ""
        var item = GearItem(name: name, category: category, teamCode: teamCode)

        item.id = data["id"] as? String ?? doc.documentID
        item.status = GearItem.GearStatus(rawValue: data["status"] as? String ?? "") ?? .blank
        item.createdBy = data["createdBy"] as? String
        item.purchaseDate = (data["purchaseDate"] as? Timestamp)?.dateValue() ?? (data["purchaseDate"] as? Date)
        item.purchasedFrom = data["purchasedFrom"] as? String ?? ""
        item.cost = data["cost"] as? Double ?? (data["cost"] as? Int).map(Double.init)
        item.location = data["location"] as? String ?? ""
        item.serialNumber = data["serialNumber"] as? String ?? (data["serial"] as? String ?? "")
        item.campus = data["campus"] as? String ?? ""
        item.assetId = data["assetId"] as? String ?? (data["assetID"] as? String ?? "")
        item.installDate = (data["installDate"] as? Timestamp)?.dateValue() ?? (data["installDate"] as? Date)
        item.maintenanceIssue = data["maintenanceIssue"] as? String ?? ""
        item.maintenanceCost = data["maintenanceCost"] as? Double ?? (data["maintenanceCost"] as? Int).map(Double.init)
        item.maintenanceRepairDate = (data["maintenanceRepairDate"] as? Timestamp)?.dateValue() ?? (data["maintenanceRepairDate"] as? Date)
        item.maintenanceNotes = data["maintenanceNotes"] as? String ?? ""
        item.imageURL = data["imageURL"] as? String ?? (data["imageUrl"] as? String)

        return item
    }

    // MARK: - Gear Merge
    func mergeDuplicateGear(completion: @escaping (Result<(merged: Int, deleted: Int), Error>) -> Void) {
        let groups = Dictionary(grouping: gear) { item -> String? in
            let nameKey = item.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let serialKey = item.serialNumber.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !nameKey.isEmpty, !serialKey.isEmpty else { return nil }
            return "\(nameKey)|\(serialKey)"
        }

        let duplicateGroups = groups.compactMap { $0.value.count > 1 ? $0.value : nil }
        guard !duplicateGroups.isEmpty else {
            completion(.success((merged: 0, deleted: 0)))
            return
        }

        var updateItems: [GearItem] = []
        var deleteIds: [String] = []

        for group in duplicateGroups {
            var merged = group[0]
            for other in group.dropFirst() {
                merged = mergeGearItems(merged, other)
                deleteIds.append(other.id)
            }
            updateItems.append(merged)
        }

        var operations: [(update: GearItem?, delete: String?)] = []
        for item in updateItems { operations.append((update: item, delete: nil)) }
        for id in deleteIds { operations.append((update: nil, delete: id)) }

        func commitBatch(start: Int) {
            if start >= operations.count {
                DispatchQueue.main.async {
                    var updatedGear = self.gear
                    let updateMap = Dictionary(uniqueKeysWithValues: updateItems.map { ($0.id, $0) })
                    for (id, item) in updateMap {
                        if let idx = updatedGear.firstIndex(where: { $0.id == id }) {
                            updatedGear[idx] = item
                        }
                    }
                    updatedGear.removeAll { deleteIds.contains($0.id) }
                    self.gear = updatedGear
                }
                completion(.success((merged: updateItems.count, deleted: deleteIds.count)))
                return
            }

            let batch = self.db.batch()
            let end = min(start + 450, operations.count)
            for idx in start..<end {
                let op = operations[idx]
                if let item = op.update {
                    do {
                        try batch.setData(from: item, forDocument: self.db.collection("gear").document(item.id))
                    } catch {
                        completion(.failure(error))
                        return
                    }
                }
                if let id = op.delete {
                    batch.deleteDocument(self.db.collection("gear").document(id))
                }
            }
            batch.commit { error in
                if let error = error {
                    completion(.failure(error))
                } else {
                    commitBatch(start: end)
                }
            }
        }

        commitBatch(start: 0)
    }

    private func mergeGearItems(_ base: GearItem, _ other: GearItem) -> GearItem {
        var merged = base
        if merged.status == .blank && other.status != .blank { merged.status = other.status }
        if merged.purchaseDate == nil { merged.purchaseDate = other.purchaseDate }
        if merged.cost == nil { merged.cost = other.cost }
        if merged.installDate == nil { merged.installDate = other.installDate }
        if merged.maintenanceCost == nil { merged.maintenanceCost = other.maintenanceCost }
        if merged.maintenanceRepairDate == nil { merged.maintenanceRepairDate = other.maintenanceRepairDate }
        if merged.imageURL == nil { merged.imageURL = other.imageURL }

        if merged.category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { merged.category = other.category }
        if merged.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { merged.location = other.location }
        if merged.campus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { merged.campus = other.campus }
        if merged.serialNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { merged.serialNumber = other.serialNumber }
        if merged.assetId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { merged.assetId = other.assetId }
        if merged.purchasedFrom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { merged.purchasedFrom = other.purchasedFrom }
        if merged.maintenanceIssue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { merged.maintenanceIssue = other.maintenanceIssue }

        let baseNotes = merged.maintenanceNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        let otherNotes = other.maintenanceNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        if baseNotes.isEmpty {
            merged.maintenanceNotes = otherNotes
        } else if !otherNotes.isEmpty && baseNotes != otherNotes {
            merged.maintenanceNotes = baseNotes + "\n---\n" + otherNotes
        }

        return merged
    }

    // MARK: - Notifications
    func sendChatNotification(message: ChatMessage, channelName: String) {
        let senderName = self.teamMembers.first(where: { $0.email == message.author })?.displayName ?? 
                         message.author.components(separatedBy: "@").first ?? message.author
        
        let content = UNMutableNotificationContent()
        content.title = channelName
        content.body = "\(senderName): \(message.text)"
        content.sound = .default
        content.badge = NSNumber(value: UIApplication.shared.applicationIconBadgeNumber + 1)
        
        // Add custom data to route tap to correct channel
        content.userInfo = ["channelName": channelName]
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("DEBUG: Failed to send notification: \(error.localizedDescription)")
            } else {
                print("DEBUG: Notification scheduled for '\(channelName)'")
            }
        }
    }

    func generateTeamCode() -> String { String(UUID().uuidString.prefix(6).uppercased()) }
    
    func saveLocation(_ location: String) {
        guard let tc = teamCode, !tc.isEmpty else { 
            print("DEBUG saveLocation: No valid teamCode")
            return 
        }
        print("DEBUG saveLocation: Saving location '\(location)' for team '\(tc)'")
        db.collection("teams").document(tc).collection("locations").document(location).setData([:]) { error in
            if let error = error {
                print("DEBUG saveLocation: Error saving - \(error.localizedDescription)")
            } else {
                print("DEBUG saveLocation: Successfully saved '\(location)'")
            }
            DispatchQueue.main.async {
                if !self.locations.contains(location) {
                    print("DEBUG saveLocation: Adding to local array")
                    self.locations.append(location)
                    self.locations.sort()
                    print("DEBUG saveLocation: Updated locations array: \(self.locations)")
                }
            }
        }
    }
    
    func deleteLocation(_ location: String) {
        guard let tc = teamCode, !tc.isEmpty else { return }
        db.collection("teams").document(tc).collection("locations").document(location).delete()
        DispatchQueue.main.async {
            self.locations.removeAll { $0 == location }
        }
    }
    
    func saveRoom(_ room: String) {
        guard let tc = teamCode, !tc.isEmpty else {
            print("DEBUG saveRoom: No valid teamCode")
            return
        }
        print("DEBUG saveRoom: Saving room '\(room)' for team '\(tc)'")
        
        // Update local array immediately
        if !self.rooms.contains(room) {
            DispatchQueue.main.async {
                self.rooms.append(room)
                self.rooms.sort()
                print("DEBUG saveRoom: Updated rooms array immediately: \(self.rooms)")
            }
        }
        
        db.collection("teams").document(tc).collection("rooms").document(room).setData([:]) { error in
            if let error = error {
                print("DEBUG saveRoom: Error saving - \(error.localizedDescription)")
            } else {
                print("DEBUG saveRoom: Successfully saved '\(room)' to Firebase")
            }
        }
    }
    
    func deleteRoom(_ room: String) {
        guard let tc = teamCode, !tc.isEmpty else { return }
        db.collection("teams").document(tc).collection("rooms").document(room).delete()
        DispatchQueue.main.async {
            self.rooms.removeAll { $0 == room }
        }
    }
    
    func deleteChannel(_ channelID: String) {
        db.collection("channels").document(channelID).delete()
        DispatchQueue.main.async {
            self.channels.removeAll { $0.id == channelID }
        }
    }
    
    func deleteAllGear() {
        // Split into chunks of 250 to avoid exceeding Firestore batch limits (16MB)
        let chunkSize = 250
        let chunks = stride(from: 0, to: gear.count, by: chunkSize).map {
            Array(gear[$0..<min($0 + chunkSize, gear.count)])
        }
        
        // Commit each chunk asynchronously
        func commitChunk(index: Int) {
            guard index < chunks.count else {
                DispatchQueue.main.async {
                    self.gear.removeAll()
                }
                return
            }
            
            let batch = db.batch()
            for item in chunks[index] {
                batch.deleteDocument(db.collection("gear").document(item.id))
            }
            batch.commit { error in
                if let error = error {
                    print("Error deleting gear batch:", error)
                }
                // Commit next chunk after this one completes
                commitChunk(index: index + 1)
            }
        }
        
        commitChunk(index: 0)
    }
    
    func deletePatchesByCategory(_ category: String) {
        let patchesToDelete = patchsheet.filter { $0.category == category }
        
        // Split into chunks of 250 to avoid exceeding Firestore batch limits (16MB)
        let chunkSize = 250
        let chunks = stride(from: 0, to: patchesToDelete.count, by: chunkSize).map {
            Array(patchesToDelete[$0..<min($0 + chunkSize, patchesToDelete.count)])
        }
        
        // Commit each chunk asynchronously
        func commitChunk(index: Int) {
            guard index < chunks.count else {
                DispatchQueue.main.async {
                    self.patchsheet.removeAll { $0.category == category }
                }
                return
            }
            
            let batch = db.batch()
            for patch in chunks[index] {
                batch.deleteDocument(db.collection("patchsheet").document(patch.id))
            }
            batch.commit { error in
                if let error = error {
                    print("Error deleting patch batch:", error)
                }
                // Commit next chunk after this one completes
                commitChunk(index: index + 1)
            }
        }
        
        commitChunk(index: 0)
    }
    
    func replaceAllGear(_ items: [GearItem]) {
        // Split into chunks of 250 to avoid exceeding Firestore batch limits (16MB)
        let chunkSize = 250
        let chunks = stride(from: 0, to: items.count, by: chunkSize).map {
            Array(items[$0..<min($0 + chunkSize, items.count)])
        }
        
        // Commit each chunk asynchronously, waiting for previous to complete
        func commitChunk(index: Int) {
            guard index < chunks.count else {
                print("Completed writing all \(items.count) gear items")
                return
            }
            
            let batch = db.batch()
            for item in chunks[index] {
                do {
                    try batch.setData(from: item, forDocument: db.collection("gear").document(item.id))
                } catch {
                    print("Error preparing gear item:", error)
                }
            }
            batch.commit { error in
                if let error = error {
                    print("Error committing gear batch \(index + 1)/\(chunks.count):", error)
                } else {
                    print("Completed gear batch \(index + 1)/\(chunks.count)")
                }
                // Commit next chunk after this one completes
                commitChunk(index: index + 1)
            }
        }
        
        commitChunk(index: 0)
    }
    
    func replaceAllPatch(_ rows: [PatchRow]) {
        // Split into chunks of 250 to avoid exceeding Firestore batch limits (16MB)
        let chunkSize = 250
        let chunks = stride(from: 0, to: rows.count, by: chunkSize).map {
            Array(rows[$0..<min($0 + chunkSize, rows.count)])
        }
        
        // Commit each chunk asynchronously, waiting for previous to complete
        func commitChunk(index: Int) {
            guard index < chunks.count else {
                print("Completed writing all \(rows.count) patch items")
                return
            }
            
            let batch = db.batch()
            for row in chunks[index] {
                do {
                    try batch.setData(from: row, forDocument: db.collection("patchsheet").document(row.id))
                } catch {
                    print("Error preparing patch row:", error)
                }
            }
            batch.commit { error in
                if let error = error {
                    print("Error committing patch batch \(index + 1)/\(chunks.count):", error)
                } else {
                    print("Completed patch batch \(index + 1)/\(chunks.count)")
                }
                // Commit next chunk after this one completes
                commitChunk(index: index + 1)
            }
        }
        
        commitChunk(index: 0)
    }
}
// ...existing code...

// MARK: - IAP Manager

@MainActor
class IAPManager: ObservableObject {
    static let shared = IAPManager()
    @Published var product: Product?
    @Published var isAdminActive: Bool = false

    // Replace with your subscription product IDs
    private let adminSubscriptionProductID = "Basic1"
    private let premiumSubscriptionProductID = "Premium1"

    // MARK: - Fetch Products
    func fetchProducts() async {
        do {
            let products = try await Product.products(for: [adminSubscriptionProductID, premiumSubscriptionProductID])
            print("Successfully fetched \(products.count) products: \(products.map { $0.id })")
            product = products.first(where: { $0.id == adminSubscriptionProductID })
            if product == nil {
                print("Error: Basic product not found for ID \(adminSubscriptionProductID)")
            }
        } catch {
            print("Error fetching subscription products for IDs [\(adminSubscriptionProductID), \(premiumSubscriptionProductID)]: \(error)")
        }
    }

    
    func purchaseSubscriptionWithError(for store: ProdConnectStore) async throws {
        if await isOwnerLocked(for: store) {
            throw StoreError.ownerLocked
        }
        guard let product = product else {
            throw StoreError.productNotFound
        }
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await unlockAdmin(for: store)
            await transaction.finish()
            if await canApplySubscription(for: store) == false {
                throw StoreError.ownerLocked
            }
        case .userCancelled:
            throw StoreError.userCancelled
        case .pending:
            throw StoreError.pending
        @unknown default:
            throw StoreError.unknown
        }
    }
    
    func purchasePremiumWithError(productID: String, for store: ProdConnectStore) async throws {
        if await isOwnerLocked(for: store) {
            throw StoreError.ownerLocked
        }
        let products = try await Product.products(for: [productID])
        guard let product = products.first else {
            throw StoreError.productNotFound
        }
        
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await unlockPremium(for: store)
            await transaction.finish()
            if await canApplySubscription(for: store) == false {
                throw StoreError.ownerLocked
            }
        case .userCancelled:
            throw StoreError.userCancelled
        case .pending:
            throw StoreError.pending
        @unknown default:
            throw StoreError.unknown
        }
    }

    // MARK: - Purchase Subscription
    func purchaseSubscription(for store: ProdConnectStore) async {
        guard let product = product else { return }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await unlockAdmin(for: store)
                await transaction.finish()
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            print("Purchase error:", error)
        }
    }
    
    func purchasePremium(productID: String, for store: ProdConnectStore) async {
        do {
            let products = try await Product.products(for: [productID])
            guard let product = products.first else { return }
            
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await unlockPremium(for: store)
                await transaction.finish()
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            print("Premium purchase error:", error)
        }
    }

    // MARK: - Restore Purchases
    func restorePurchases(for store: ProdConnectStore) async {
        do {
            try await AppStore.sync()
            await checkSubscription(for: store)
        } catch {
            print("Restore failed:", error)
        }
    }

    // MARK: - Check Current Subscription Entitlement
    func checkSubscription(for store: ProdConnectStore) async {
        do {
            for try await verification in Transaction.currentEntitlements {
                let transaction = try checkVerified(verification)
                if transaction.productID == adminSubscriptionProductID {
                    // Admin subscription active
                    if await canApplySubscription(for: store) {
                        await unlockAdmin(for: store)
                    }
                    return
                } else if transaction.productID == premiumSubscriptionProductID {
                    // Premium subscription active
                    if await canApplySubscription(for: store) {
                        await unlockPremium(for: store)
                    }
                    return
                }
            }
            // No active subscription found; revoke all premium features
            await revokePremiumFeatures(for: store)
        } catch {
            print("Error checking subscription:", error)
            await revokePremiumFeatures(for: store)
        }
    }

    // MARK: - Unlock / Revoke Admin
    private func unlockAdmin(for store: ProdConnectStore) async {
        guard var user = store.user else { return }
        if !user.isAdmin {
            user.isAdmin = true
            if user.subscriptionTier == "free" {
                user.subscriptionTier = "basic"
            }
            if user.teamCode == nil || user.teamCode?.isEmpty == true {
                // Generate a unique team code
                var teamCode = store.generateTeamCode()
                var isUnique = false
                
                while !isUnique {
                    do {
                        let snapshot = try await store.db.collection("users").whereField("teamCode", isEqualTo: teamCode).getDocuments()
                        isUnique = snapshot.documents.count == 0
                        if !isUnique {
                            teamCode = store.generateTeamCode()
                        }
                    } catch {
                        print("Error checking team code uniqueness: \(error)")
                        break
                    }
                }
                
                user.teamCode = teamCode
                
                // Register the team code in the teams collection so others can join
                store.db.collection("teams").document(teamCode).setData([
                    "code": teamCode,
                    "createdAt": FieldValue.serverTimestamp(),
                    "createdBy": user.email,
                    "isActive": true
                ], merge: true) { error in
                    if let error = error { print("Team registration error:", error) }
                }
            }
            store.user = user

            // ✅ Non-throwing Firestore update
            store.db.collection("users").document(user.id).setData([
                "isAdmin": true,
                "subscriptionTier": user.subscriptionTier,
                "teamCode": user.teamCode ?? ""
            ], merge: true) { error in
                if let error = error { print("Firestore update error:", error) }
            }

            store.listenToTeamData()
        }
        isAdminActive = true
    }

    private func revokeAdmin(for store: ProdConnectStore) async {
        guard var user = store.user else { return }
        if user.isAdmin {
            user.isAdmin = false
            store.user = user

            store.db.collection("users").document(user.id).setData([
                "isAdmin": false
            ], merge: true) { error in
                if let error = error { print("Firestore update error:", error) }
            }

            store.listenToTeamData()
        }
        isAdminActive = false
    }
    
    func unlockPremium(for store: ProdConnectStore) async {
        guard var user = store.user else { return }
        if user.subscriptionTier != "premium" {
            user.subscriptionTier = "premium"
            user.isAdmin = true
            
            // Generate team code if they don't have one
            if user.teamCode == nil || user.teamCode?.isEmpty == true {
                var teamCode = store.generateTeamCode()
                var isUnique = false
                
                while !isUnique {
                    do {
                        let snapshot = try await store.db.collection("users").whereField("teamCode", isEqualTo: teamCode).getDocuments()
                        isUnique = snapshot.documents.count == 0
                        if !isUnique {
                            teamCode = store.generateTeamCode()
                        }
                    } catch {
                        print("Error checking team code uniqueness: \(error)")
                        break
                    }
                }
                
                user.teamCode = teamCode
                
                // Register the team code in the teams collection so others can join
                store.db.collection("teams").document(teamCode).setData([
                    "code": teamCode,
                    "createdAt": FieldValue.serverTimestamp(),
                    "createdBy": user.email,
                    "isActive": true
                ], merge: true) { error in
                    if let error = error { print("Team registration error:", error) }
                }
            }
            
            store.user = user
            
            store.db.collection("users").document(user.id).setData([
                "subscriptionTier": "premium",
                "isAdmin": true,
                "teamCode": user.teamCode ?? ""
            ], merge: true) { error in
                if let error = error { print("Firestore update error:", error) }
            }
            
            // Refresh team data listeners so free user filters are removed
            await MainActor.run {
                store.listenToTeamData()
            }
        }
    }
    
    // MARK: - Set Subscription Tier (Testing)
    func setSubscriptionTier(for store: ProdConnectStore, tier: String) async {
        guard var user = store.user else { 
            print("No user found")
            return 
        }
        
        print("Changing subscription from \(user.subscriptionTier) to \(tier)")
        user.subscriptionTier = tier
        
        await MainActor.run {
            store.objectWillChange.send()
            store.user = user
            print("User updated on main thread. New tier: \(store.user?.subscriptionTier ?? "nil")")
            print("Role: \(store.user?.role ?? .free)")
            print("Can see chat: \(store.canSeeChat)")
            print("Can see training: \(store.canSeeTrainingTab)")
        }
        
        store.db.collection("users").document(user.id).setData([
            "subscriptionTier": tier
        ], merge: true) { error in
            if let error = error { print("Firestore update error:", error) }
            else { print("Firestore updated to: \(tier)") }
        }
    }
    
    // MARK: - Toggle Admin (Testing)
    func toggleAdmin(for store: ProdConnectStore) async {
        guard var user = store.user else { return }
        
        user.isAdmin.toggle()
        if user.isOwner {
            user.isAdmin = true
        }
        if user.isAdmin && user.subscriptionTier == "free" {
            user.subscriptionTier = "basic"
        }
        print("Admin toggled to: \(user.isAdmin)")
        
        await MainActor.run {
            store.objectWillChange.send()
            store.user = user
            print("IsAdmin after toggle: \(store.user?.isAdmin ?? false)")
            print("Subscription tier: \(store.user?.subscriptionTier ?? "nil")")
            print("Role after toggle: \(store.user?.role ?? .free)")
            print("Can see chat: \(store.canSeeChat)")
            print("Can see training: \(store.canSeeTrainingTab)")
        }
        
        store.db.collection("users").document(user.id).setData([
            "isAdmin": user.isAdmin,
            "subscriptionTier": user.subscriptionTier
        ], merge: true) { error in
            if let error = error { print("Firestore update error:", error) }
            else { print("Admin status updated to: \(user.isAdmin)") }
        }
    }
    
    private func revokePremiumFeatures(for store: ProdConnectStore) async {
        guard var user = store.user else { return }
        if user.subscriptionTier == "premium" && !user.isAdmin {
            user.subscriptionTier = "free"
            store.user = user
            
            store.db.collection("users").document(user.id).setData([
                "subscriptionTier": "free"
            ], merge: true) { error in
                if let error = error { print("Firestore update error:", error) }
            }
        }
    }

    private func canApplySubscription(for store: ProdConnectStore) async -> Bool {
        guard var user = store.user else { return false }
        let code = user.teamCode ?? ""
        guard !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }

        do {
            let snap = try await store.db.collection("teams").document(code).getDocument()
            let ownerId = snap.data()?["ownerId"] as? String

            if ownerId == nil || ownerId?.isEmpty == true {
                await assignOwner(user: user, teamCode: code, store: store)
                return true
            }

            if ownerId == user.id {
                if !user.isOwner {
                    user.isOwner = true
                    store.user = user
                    store.db.collection("users").document(user.id)
                        .setData(["isOwner": true], merge: true) { error in
                            if let error = error { print("Firestore update error:", error) }
                        }
                }
                return true
            }

            if user.isOwner {
                user.isOwner = false
                store.user = user
                store.db.collection("users").document(user.id)
                    .setData(["isOwner": false], merge: true) { error in
                        if let error = error { print("Firestore update error:", error) }
                    }
            }
            return false
        } catch {
            print("Owner check failed:", error)
            return false
        }
    }

    private func isOwnerLocked(for store: ProdConnectStore) async -> Bool {
        guard let user = store.user else { return false }
        let code = user.teamCode ?? ""
        guard !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }

        do {
            let snap = try await store.db.collection("teams").document(code).getDocument()
            let ownerId = snap.data()?["ownerId"] as? String
            if let ownerId, !ownerId.isEmpty, ownerId != user.id {
                return true
            }
            return false
        } catch {
            return false
        }
    }

    private func assignOwner(user: UserProfile, teamCode: String, store: ProdConnectStore) async {
        var updated = user
        updated.isOwner = true
        updated.isAdmin = true
        if updated.subscriptionTier == "free" {
            updated.subscriptionTier = "basic"
        }

        await MainActor.run {
            store.user = updated
        }

        store.db.collection("users").document(updated.id).setData([
            "isOwner": true,
            "isAdmin": true,
            "subscriptionTier": updated.subscriptionTier
        ], merge: true) { error in
            if let error = error { print("Firestore update error:", error) }
        }

        store.db.collection("teams").document(teamCode).setData([
            "ownerId": updated.id,
            "ownerEmail": updated.email,
            "code": teamCode,
            "isActive": true
        ], merge: true) { error in
            if let error = error { print("Team owner update error:", error) }
        }
    }

    // MARK: - Verification Helper
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let safe):
            return safe
        }
    }

    enum StoreError: Error {
        case productNotFound
        case userCancelled
        case pending
        case unknown
        case failedVerification
        case ownerLocked
        
        var localizedDescription: String {
            switch self {
            case .productNotFound:
                return "Product not found. Make sure the subscription is set up in App Store Connect and approved."
            case .userCancelled:
                return "Purchase was cancelled."
            case .pending:
                return "Purchase is pending approval."
            case .failedVerification:
                return "Failed to verify the purchase."
            case .unknown:
                return "An unknown error occurred."
            case .ownerLocked:
                return "Only the team owner can change the subscription."
            }
        }
    }
}
// ...existing code...


// MARK: - App Entry

@main
struct ProdConnectApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject var store = ProdConnectStore.shared
    @StateObject var iap = IAPManager.shared

    init() {
        // Firebase configuration is now handled by AppDelegate.swift
        // Global UINavigationBar appearance (visible titles across all tabs)
        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithOpaqueBackground()
        navAppearance.backgroundColor = .black
        // Use dynamic label color to match dark/light automatically
        navAppearance.titleTextAttributes = [.foregroundColor: UIColor.label]
        navAppearance.largeTitleTextAttributes = [.foregroundColor: UIColor.label]

        let navProxy = UINavigationBar.appearance()
        navProxy.standardAppearance = navAppearance
        navProxy.scrollEdgeAppearance = navAppearance
        navProxy.compactAppearance = navAppearance
        if #available(iOS 15.0, *) {
            navProxy.compactScrollEdgeAppearance = navAppearance
        }
        navProxy.prefersLargeTitles = true
        navProxy.isTranslucent = false
        navProxy.tintColor = .systemBlue

        // Global UITabBar appearance
        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithOpaqueBackground()
        tabAppearance.backgroundColor = .black
        let tabProxy = UITabBar.appearance()
        tabProxy.standardAppearance = tabAppearance
        tabProxy.scrollEdgeAppearance = tabAppearance
        tabProxy.tintColor = .systemBlue
        tabProxy.unselectedItemTintColor = .gray

        // Table/List background to avoid blend with transparent bars
        UITableView.appearance().backgroundColor = .black
        UITableViewCell.appearance().backgroundColor = .black
    }

    var body: some Scene {
        WindowGroup {
            if store.user == nil {
                LoginView()
                    .environmentObject(store)
                    .preferredColorScheme(.dark)
            } else {
                MainTabView()
                    .environmentObject(store)
                    .environmentObject(iap)
                    .preferredColorScheme(.dark)
            }
        }
    }
}
// ...existing code...

// MARK: - SearchBar Helper
struct SearchBar: View {
    @Binding var text: String

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.gray)
            TextField("Search", text: $text)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}
// ...existing code...

// MARK: - LoginView

struct LoginView: View {
    @EnvironmentObject var store: ProdConnectStore
    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp = false
    @State private var teamCode = ""
    @State private var errorMessage = ""
    @State private var isAuthenticating = false
    @State private var authAttemptID = UUID()
    @State private var showPasswordReset = false
    @State private var resetEmail = ""
    @State private var autoLoginAttempted = false

    var body: some View {
        NavigationStack {
            ZStack {
                Group {
                    if let uiImage = UIImage(named: "BackgroundImage") {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .ignoresSafeArea()
                    } else {
                        Color.black.ignoresSafeArea()
                    }
                }
                VStack(spacing: 16) {
                    Spacer()

                    Text("ProdConnect")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.bottom, 20)

                    Group {
                        TextField("Email", text: $email)
                            .textContentType(.emailAddress)
                            .autocapitalization(.none)
                            .keyboardType(.emailAddress)

                        SecureField("Password", text: $password)
                            .textContentType(.password)

                        if isSignUp {
                            TextField("Team Code (optional)", text: $teamCode)
                        }
                    }
                    .padding()
                    .background(Color.black.opacity(0.8))
                    .cornerRadius(8)
                    .frame(maxWidth: 400)
                    .padding(.horizontal, 24)

                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.footnote)
                    }

                    Button {
                        submitAuth()
                    } label: {
                        Text(isAuthenticating ? "Please wait..." : (isSignUp ? "Create Account" : "Sign In"))
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding()
                            .frame(maxWidth: 400)
                            .background(isAuthenticating ? Color.gray : Color.blue)
                            .cornerRadius(8)
                            .padding(.horizontal, 24)
                    }
                    .disabled(isAuthenticating)

                    if !isSignUp {
                        Button("Forgot Password?") {
                            resetEmail = email
                            showPasswordReset = true
                        }
                        .font(.footnote)
                        .foregroundColor(.white)
                        .padding(.top, 4)
                    }

                    Button(isSignUp ? "Already have an account? Sign In" : "Don't have an account? Sign Up") {
                        withAnimation {
                            isSignUp.toggle()
                            errorMessage = ""
                        }
                    }
                    .font(.footnote)
                    .foregroundColor(.white)
                    .padding(.top, 4)

                    Spacer()
                }
                .padding()
            }
            .alert("Reset Password", isPresented: $showPasswordReset) {
                TextField("Enter your email", text: $resetEmail)
                Button("Send Reset Email") { sendPasswordReset() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Enter your email address to receive a password reset link.")
            }
            .onAppear {
                guard !autoLoginAttempted else { return }
                autoLoginAttempted = true

                let savedEmail = KeychainHelper.shared.read(for: "prodconnect_email") ?? ""
                let savedPassword = KeychainHelper.shared.read(for: "prodconnect_password") ?? ""
                guard !savedEmail.isEmpty, !savedPassword.isEmpty else { return }

                email = savedEmail
                password = savedPassword
                submitAuth()
            }
        }
    }

    private func sendPasswordReset() {
        guard !resetEmail.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Please enter a valid email address."
            return
        }

        Auth.auth().sendPasswordReset(withEmail: resetEmail) { error in
            if let error = error {
                errorMessage = error.localizedDescription
            } else {
                errorMessage = "Password reset email sent! Check your inbox."
            }
        }
    }

    private func submitAuth() {
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanEmail.isEmpty, !cleanPassword.isEmpty else {
            errorMessage = "Enter both email and password."
            return
        }

        errorMessage = ""
        isAuthenticating = true
        let attemptID = UUID()
        authAttemptID = attemptID

        DispatchQueue.main.asyncAfter(deadline: .now() + 12) {
            if isAuthenticating && authAttemptID == attemptID {
                isAuthenticating = false
                errorMessage = "Sign in timed out. Check your connection and try again."
            }
        }

        if isSignUp {
            let cleanTeamCode = teamCode.trimmingCharacters(in: .whitespacesAndNewlines)
            store.signUp(email: cleanEmail, password: cleanPassword, teamCode: cleanTeamCode.isEmpty ? nil : cleanTeamCode) { result in
                guard authAttemptID == attemptID else { return }
                isAuthenticating = false
                switch result {
                case .success:
                    break
                case .failure(let error):
                    let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                    errorMessage = message.isEmpty ? "Sign up failed. Please try again." : message
                }
            }
        } else {
            store.signIn(email: cleanEmail, password: cleanPassword) { result in
                guard authAttemptID == attemptID else { return }
                isAuthenticating = false
                switch result {
                case .success:
                    KeychainHelper.shared.save(cleanEmail, for: "prodconnect_email")
                    KeychainHelper.shared.save(cleanPassword, for: "prodconnect_password")
                    if store.user == nil {
                        errorMessage = "Signed in, but profile did not load. Please try again."
                    }
                case .failure(let error):
                    let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                    errorMessage = message.isEmpty ? "Sign in failed. Please check your credentials and try again." : message
                }
            }
        }
    }
}
// ...existing code...


// MARK: - MainTabView
// MARK: - MainTabView

// MARK: - AccountView

struct AccountView: View {
    @EnvironmentObject var store: ProdConnectStore
    @State private var displayName: String = ""
    @State private var email: String = ""
    @State private var teamCode: String = ""
    @State private var isAdmin: Bool = false
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showJoinTeamAlert = false
    @State private var joinTeamCode = ""
    @State private var isJoiningTeam = false
    @State private var showSubscriptionOptions = false
    @State private var purchaseError: String?
    @State private var showPurchaseError = false
    @State private var showEditAccount = false
    @State private var showDeleteAccountStep1 = false
    @State private var showDeleteAccountStep2 = false
    @State private var deleteConfirmationText = ""
    @State private var isDeletingAccount = false

    private var appVersionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        if !version.isEmpty && !build.isEmpty {
            return "v\(version) (\(build))"
        }
        return version.isEmpty ? "" : "v\(version)"
    }

    private let actionButtonHeight: CGFloat = 40
    private let termsURLString = "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
    // Replace with your app's public privacy policy URL before App Store submission.
    private let privacyPolicyURLString = "https://bmsatori.github.io/prodconnect-privacy/"

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if isLoading {
                    ProgressView("Loading account...")
                } else {
                    VStack(spacing: 8) {
                        Text(displayName)
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        Text(email)
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        
                        if isAdmin {
                            Text("Admin")
                                .font(.caption)
                                .padding(6)
                                .background(Color.blue.opacity(0.2))
                                .cornerRadius(8)
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.top, 20)
                    
                    Divider()
                        .background(Color.gray)
                        .padding(.vertical, 10)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Subscription Level:")
                                .foregroundColor(.white)
                                .fontWeight(.medium)
                            Spacer()
                            Text(store.user?.subscriptionTier.capitalized ?? "Free")
                                .foregroundColor(.white)
                                .fontWeight(.medium)
                        }
                        
                        // Only show Team Code for non-free users
                        if store.user?.subscriptionTier != "free" {
                            HStack {
                                Text("Team Code:")
                                    .foregroundColor(.white)
                                    .fontWeight(.medium)
                                Spacer()
                                Text(teamCode)
                                    .foregroundColor(.white)
                                    .fontWeight(.medium)
                            }
                        }
                        
                        HStack {
                            Text("Role:")
                                .foregroundColor(.white)
                                .fontWeight(.medium)
                            Spacer()
                            let roleLabel = isAdmin ? (store.user?.isOwner == true ? "Owner" : "Admin") : "Basic"
                            Text(roleLabel)
                                .foregroundColor(isAdmin ? .green : .white)
                                .fontWeight(.medium)
                        }

                        if !appVersionText.isEmpty {
                            HStack {
                                Text("App Version:")
                                    .foregroundColor(.white)
                                    .fontWeight(.medium)
                                Spacer()
                                Text(appVersionText)
                                    .foregroundColor(.gray)
                                    .fontWeight(.medium)
                            }
                        }
                    }
                    .padding(.horizontal)

                    Spacer()
                    
                    if store.user?.subscriptionTier == "free" {
                        HStack(spacing: 8) {
                            Button(action: {
                                showJoinTeamAlert = true
                            }) {
                                Text("Join Team")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: actionButtonHeight)
                                    .background(Color.green)
                                    .foregroundColor(.white)
                                    .cornerRadius(10)
                            }
                            
                            Button(action: {
                                showSubscriptionOptions = true
                            }) {
                                Text("Subscribe")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: actionButtonHeight)
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(10)
                            }
                        }
                        .padding(.horizontal)
                    } else if store.user?.subscriptionTier == "basic", store.user?.isAdmin == true {
                        Button(action: {
                            showSubscriptionOptions = true
                        }) {
                            Text("Upgrade Subscription")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: actionButtonHeight)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                        .padding(.horizontal)
                    }

                    HStack(spacing: 8) {
                        Button(action: { showEditAccount = true }) {
                            Text("Edit Account")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: actionButtonHeight)
                                .background(Color.blue.opacity(0.7))
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }

                        NavigationLink {
                            ContactView()
                        } label: {
                            Text("Support")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: actionButtonHeight)
                                .background(Color.gray.opacity(0.25))
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }

                        Button(action: signOut) {
                            Text("Sign Out")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: actionButtonHeight)
                                .background(Color.red)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                    }
                    .padding(.horizontal)

                    Button(action: { showDeleteAccountStep1 = true }) {
                        HStack {
                            if isDeletingAccount {
                                ProgressView()
                                    .progressViewStyle(.circular)
                            }
                            Text(isDeletingAccount ? "Deleting Account..." : "Delete Account")
                                .font(.subheadline.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: actionButtonHeight)
                        .background(Color.red.opacity(0.18))
                        .foregroundColor(.red)
                        .cornerRadius(10)
                    }
                    .disabled(isDeletingAccount)
                    .padding(.horizontal)
                }
                
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .padding()
                }
            }
            .navigationTitle("Account")
            .onAppear {
                loadUserInfo()
                Task {
                    await IAPManager.shared.fetchProducts()
                }
            }
            .alert("Join Team", isPresented: $showJoinTeamAlert) {
                TextField("Team Code", text: $joinTeamCode)
                Button("Cancel", role: .cancel) {
                    joinTeamCode = ""
                }
                Button("Join", action: joinTeam)
                    .disabled(joinTeamCode.trimmingCharacters(in: .whitespaces).isEmpty || isJoiningTeam)
            } message: {
                Text("Enter the team code to join an existing team.")
            }
            .sheet(isPresented: $showSubscriptionOptions) {
                SubscriptionOptionsSheet(
                    termsURLString: termsURLString,
                    privacyPolicyURLString: privacyPolicyURLString,
                    onPurchaseBasic: {
                        do {
                            try await IAPManager.shared.purchaseSubscriptionWithError(for: store)
                            showSubscriptionOptions = false
                        } catch {
                            purchaseError = error.localizedDescription
                            showPurchaseError = true
                        }
                    },
                    onPurchasePremium: {
                        do {
                            try await IAPManager.shared.purchasePremiumWithError(productID: "Premium1", for: store)
                            showSubscriptionOptions = false
                        } catch {
                            purchaseError = error.localizedDescription
                            showPurchaseError = true
                        }
                    }
                )
                .environmentObject(store)
            }
            .alert("Purchase Error", isPresented: $showPurchaseError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(purchaseError ?? "Unknown error")
            }
            .sheet(isPresented: $showEditAccount, onDismiss: loadUserInfo) {
                EditAccountView()
                    .environmentObject(store)
            }
            .confirmationDialog("Delete Account?", isPresented: $showDeleteAccountStep1, titleVisibility: .visible) {
                Button("Continue", role: .destructive) {
                    deleteConfirmationText = ""
                    showDeleteAccountStep2 = true
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This starts account deletion. You will confirm one more time on the next screen.")
            }
            .sheet(isPresented: $showDeleteAccountStep2) {
                NavigationStack {
                    Form {
                        Section("Confirm Deletion") {
                            Text("Type DELETE below to permanently delete your account.")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                            TextField("Type DELETE", text: $deleteConfirmationText)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled(true)
                        }
                        Section {
                            Button("Delete My Account", role: .destructive) {
                                performAccountDeletion()
                            }
                            .disabled(deleteConfirmationText != "DELETE" || isDeletingAccount)
                        }
                    }
                    .navigationTitle("Delete Account")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showDeleteAccountStep2 = false }
                        }
                    }
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
    }
    
    private func joinTeam() {
        let code = joinTeamCode.trimmingCharacters(in: .whitespaces).uppercased()
        let codeLower = joinTeamCode.trimmingCharacters(in: .whitespaces).lowercased()
        guard !code.isEmpty else { return }
        
        isJoiningTeam = true
        
        func applyJoinUpdates(resolvedCode: String) {
            guard let user = Auth.auth().currentUser else { return }

            let updates: [String: Any] = [
                "teamCode": resolvedCode,
                "subscriptionTier": "basic",
                "isAdmin": false,
                "isOwner": false,
                "canEditPatchsheet": true,
                "canEditTraining": true,
                "canEditGear": true,
                "canEditIdeas": true,
                "canEditChecklists": true
            ]

            self.store.db.collection("users").document(user.uid).updateData(updates) { error in
                DispatchQueue.main.async {
                    self.isJoiningTeam = false

                    if let error = error {
                        self.errorMessage = "Failed to join team: \(error.localizedDescription)"
                    } else {
                        self.teamCode = resolvedCode
                        self.joinTeamCode = ""
                        self.showJoinTeamAlert = false

                        var updated = self.store.user
                        updated?.teamCode = resolvedCode
                        updated?.subscriptionTier = "basic"
                        updated?.isAdmin = false
                        updated?.isOwner = false
                        updated?.canEditPatchsheet = true
                        updated?.canEditTraining = true
                        updated?.canEditGear = true
                        updated?.canEditIdeas = true
                        updated?.canEditChecklists = true
                        self.store.user = updated

                        self.store.listenToTeamData()
                    }
                }
            }
        }

        // Validate team code exists
        store.db.collection("teams").document(code).getDocument { snap, error in
            if error == nil, snap?.exists == true {
                applyJoinUpdates(resolvedCode: code)
                return
            }

            store.db.collection("teams").document(codeLower).getDocument { lowerSnap, lowerError in
                if lowerError == nil, let lowerSnap, lowerSnap.exists {
                    let foundCode = (lowerSnap.data()?["code"] as? String) ?? codeLower
                    applyJoinUpdates(resolvedCode: foundCode.uppercased())
                    return
                }

                store.db.collection("teams")
                    .whereField("code", in: [code, codeLower])
                    .limit(to: 1)
                    .getDocuments { teamSnap, teamError in
                        if teamError == nil, let doc = teamSnap?.documents.first {
                            let foundCode = (doc.data()["code"] as? String) ?? doc.documentID
                            applyJoinUpdates(resolvedCode: foundCode.uppercased())
                            return
                        }

                        DispatchQueue.main.async {
                            self.errorMessage = "Team code does not exist."
                            self.isJoiningTeam = false
                            self.joinTeamCode = ""
                        }
                    }
            }
        }
    }

    private func loadUserInfo() {
        guard let user = Auth.auth().currentUser else {
            errorMessage = "No logged in user."
            isLoading = false
            return
        }

        email = user.email ?? "Unknown"
        
        // Use store's user data if available, otherwise fetch from Firestore
        if let storeUser = store.user {
            displayName = storeUser.displayName ?? email.components(separatedBy: "@").first ?? "User"
            teamCode = storeUser.teamCode ?? "N/A"
            isAdmin = storeUser.isAdmin
            isLoading = false
            return
        }
        
        // Fetch display name from Firestore
        store.db.collection("users").whereField("email", isEqualTo: email).getDocuments { snapshot, error in
            DispatchQueue.main.async {
                if let error = error {
                    self.errorMessage = "Error loading user: \(error.localizedDescription)"
                    self.isLoading = false
                    return
                }

                guard let doc = snapshot?.documents.first else {
                    self.displayName = email.components(separatedBy: "@").first ?? "User"
                    self.teamCode = "N/A"
                    self.isAdmin = false
                    self.isLoading = false
                    return
                }

                let data = doc.data()
                self.displayName = (data["displayName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    ?? (data["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    ?? email.components(separatedBy: "@").first ?? "User"
                self.teamCode = data["teamCode"] as? String ?? "N/A"
                self.isAdmin = data["isAdmin"] as? Bool ?? false
                self.isLoading = false
            }
        }
    }

    private func signOut() {
        do {
            try Auth.auth().signOut()
            store.signOut()
        } catch {
            self.errorMessage = "Sign out failed: \(error.localizedDescription)"
        }
    }

    private func performAccountDeletion() {
        guard let currentUser = Auth.auth().currentUser else {
            errorMessage = "No logged in user."
            showDeleteAccountStep2 = false
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
                        self.errorMessage = "For security, please sign out and sign back in, then try deleting your account again."
                    } else {
                        self.errorMessage = "Account deletion failed: \(deleteError.localizedDescription)"
                    }
                    return
                }

                // Best-effort cleanup of profile data after auth account deletion.
                self.store.db.collection("users").document(uid).delete { _ in
                    DispatchQueue.main.async {
                        self.isDeletingAccount = false
                        self.showDeleteAccountStep2 = false
                        self.store.signOut()
                    }
                }
            }
        }
    }
}

struct SubscriptionOptionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var basicProduct: Product?
    @State private var premiumProduct: Product?
    @State private var isLoadingProducts = false

    let termsURLString: String
    let privacyPolicyURLString: String
    let onPurchaseBasic: () async -> Void
    let onPurchasePremium: () async -> Void
    private let subscriptionProductIDs = ["Basic1", "Premium1"]

    var body: some View {
        NavigationStack {
            Group {
                if #available(iOS 17.0, *) {
                    subscriptionStoreContent
                } else {
                    fallbackSubscriptionContent
                }
            }
            .navigationTitle("Subscribe")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                if #unavailable(iOS 17.0) {
                    ToolbarItemGroup(placement: .navigationBarTrailing) {
                        Button(isLoadingProducts ? "Loading..." : "Basic") {
                            Task { await onPurchaseBasic() }
                        }
                        .disabled(isLoadingProducts)

                        Button(isLoadingProducts ? "Loading..." : "Premium") {
                            Task { await onPurchasePremium() }
                        }
                        .disabled(isLoadingProducts)
                    }
                }
            }
            .task {
                await loadProducts()
            }
        }
    }

    @available(iOS 17.0, *)
    private var subscriptionStoreContent: some View {
        SubscriptionStoreView(productIDs: subscriptionProductIDs) {
            VStack(alignment: .leading, spacing: 8) {
                Text("ProdConnect Subscriptions")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text("Basic and Premium are auto-renewing subscriptions.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
        .subscriptionStoreButtonLabel(.multiline)
        .subscriptionStorePolicyDestination(url: URL(string: termsURLString)!, for: .termsOfService)
        .subscriptionStorePolicyDestination(url: URL(string: privacyPolicyURLString)!, for: .privacyPolicy)
        .storeButton(.visible, for: .restorePurchases)
        .storeButton(.hidden, for: .redeemCode)
    }

    private var fallbackSubscriptionContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("ProdConnect Subscriptions")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text("Choose an auto-renewing subscription plan.")
                    .foregroundColor(.secondary)

                subscriptionCard(
                    title: basicProduct?.displayName ?? "Basic",
                    length: subscriptionLengthText(for: basicProduct),
                    price: priceText(for: basicProduct),
                    details: "Team management, user permissions, and full access to gear, training, checklists, and ideas."
                )

                subscriptionCard(
                    title: premiumProduct?.displayName ?? "Premium",
                    length: subscriptionLengthText(for: premiumProduct),
                    price: priceText(for: premiumProduct),
                    details: "Everything in Basic plus campus/room management, advanced permissions, and priority support."
                )

                if let termsURL = URL(string: termsURLString) {
                    Link("Terms of Use (EULA)", destination: termsURL)
                        .font(.footnote)
                }
                if let privacyURL = URL(string: privacyPolicyURLString) {
                    Link("Privacy Policy", destination: privacyURL)
                        .font(.footnote)
                }

                Text("Subscriptions renew automatically unless canceled at least 24 hours before the end of the current period.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
        }
    }

    @ViewBuilder
    private func subscriptionCard(title: String, length: String, price: String, details: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text("Length: \(length)").font(.subheadline)
            Text("Price: \(price)").font(.subheadline)
            Text(details)
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func loadProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            let products = try await Product.products(for: ["Basic1", "Premium1"])
            basicProduct = products.first(where: { $0.id == "Basic1" })
            premiumProduct = products.first(where: { $0.id == "Premium1" })
        } catch {
            // Keep fallback copy visible even if products fail to load.
        }
    }

    private func subscriptionLengthText(for product: Product?) -> String {
        guard let period = product?.subscription?.subscriptionPeriod else { return "Auto-renewing subscription period" }
        let unit: String
        switch period.unit {
        case .day: unit = period.value == 1 ? "day" : "days"
        case .week: unit = period.value == 1 ? "week" : "weeks"
        case .month: unit = period.value == 1 ? "month" : "months"
        case .year: unit = period.value == 1 ? "year" : "years"
        @unknown default: unit = "period"
        }
        return "\(period.value) \(unit) (auto-renewing)"
    }

    private func priceText(for product: Product?) -> String {
        guard let product else { return "See App Store pricing" }
        return product.displayPrice
    }
}
// ...existing code...

// MARK: - EditAccountView

struct EditAccountView: View {
    @EnvironmentObject var store: ProdConnectStore
    @Environment(\.dismiss) var dismiss
    @State private var displayName = ""
    @State private var newEmail = ""
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Display Name") {
                    TextField("Display Name", text: $displayName)
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled(true)
                }

                Section("Login Email") {
                    TextField("New Email", text: $newEmail)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
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

                if let errorMessage = errorMessage {
                    Section { Text(errorMessage).foregroundColor(.red) }
                }
            }
            .navigationTitle("Edit Account")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if isSaving {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        ProgressView()
                    }
                }
            }
            .onAppear {
                displayName = store.user?.displayName ?? (Auth.auth().currentUser?.email?.components(separatedBy: "@").first ?? "")
                newEmail = ""
                currentPassword = ""
                newPassword = ""
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

        func updateDisplayNameIfNeeded(completion: @escaping (Result<Void, Error>) -> Void) {
            guard nameChanged else { completion(.success(())); return }
            guard let uid = store.user?.id else { completion(.success(())); return }
            store.db.collection("users").document(uid).updateData(["displayName": trimmedName]) { error in
                if let error = error { completion(.failure(error)); return }
                store.user?.displayName = trimmedName
                store.listenToTeamMembers()
                completion(.success(()))
            }
        }

        func updateEmailIfNeeded(completion: @escaping (Result<Void, Error>) -> Void) {
            guard emailChanged else { completion(.success(())); return }
            currentUser.updateEmail(to: trimmedEmail) { error in
                if let error = error { completion(.failure(error)); return }
                store.db.collection("users").document(currentUser.uid).updateData(["email": trimmedEmail]) { err in
                    if let err = err { completion(.failure(err)); return }
                    store.user?.email = trimmedEmail
                    OneSignal.login(trimmedEmail)
                    completion(.success(()))
                }
            }
        }

        func updatePasswordIfNeeded(completion: @escaping (Result<Void, Error>) -> Void) {
            guard passwordChanged else { completion(.success(())); return }
            currentUser.updatePassword(to: trimmedPassword) { error in
                if let error = error { completion(.failure(error)); return }
                completion(.success(()))
            }
        }

        func runUpdates() {
            updateEmailIfNeeded { result in
                switch result {
                case .failure(let error):
                    finishWithError(error)
                case .success:
                    updatePasswordIfNeeded { pwdResult in
                        switch pwdResult {
                        case .failure(let error):
                            finishWithError(error)
                        case .success:
                            updateDisplayNameIfNeeded { nameResult in
                                switch nameResult {
                                case .failure(let error):
                                    finishWithError(error)
                                case .success:
                                    finishWithSuccess()
                                }
                            }
                        }
                    }
                }
            }
        }

        func finishWithError(_ error: Error) {
            DispatchQueue.main.async {
                isSaving = false
                errorMessage = error.localizedDescription
            }
        }

        func finishWithSuccess() {
            DispatchQueue.main.async {
                isSaving = false
                successMessage = "Your account was updated."
            }
        }

        if needsReauth {
            guard let email = currentUser.email else {
                finishWithError(NSError(domain: "Auth", code: 0, userInfo: [NSLocalizedDescriptionKey: "Missing email for reauthentication."]))
                return
            }
            let credential = EmailAuthProvider.credential(withEmail: email, password: currentPassword)
            currentUser.reauthenticate(with: credential) { _, error in
                if let error = error {
                    finishWithError(error)
                } else {
                    runUpdates()
                }
            }
        } else {
            runUpdates()
        }
    }
}
// ...existing code...

// MARK: - ContactView

struct ContactView: View {
    private let supportEmail = "prodconnectapp@gmail.com"

    var body: some View {
        NavigationStack {
            Form {
                Section("Support") {
                    Text("Need help with ProdConnect?")
                    Link("Email Support", destination: URL(string: "mailto:\(supportEmail)")!)
                }
            }
            .navigationTitle("Contact")
        }
    }
}

// MARK: - CustomizeView (Admin Only)
struct CustomizeView: View {
    @EnvironmentObject var store: ProdConnectStore
    @State private var newCampus = ""
    @State private var newRoom = ""
    @State private var gearSheetLink = ""
    @State private var audioPatchSheetLink = ""
    @State private var videoPatchSheetLink = ""
    @State private var lightingPatchSheetLink = ""
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isImporting = false
    @State private var showDeleteAllConfirmation = false
    @State private var showDeleteAudioConfirmation = false
    @State private var showDeleteLightingConfirmation = false
    @State private var showDeleteVideoConfirmation = false
    @State private var showImportHelp = false

    var body: some View {
        NavigationStack {
            Form {
            if store.user?.hasCampusRoomFeatures ?? false {
                // Campus Management
                Section {
                    HStack {
                        TextField("Add new campus", text: $newCampus)
                            .textFieldStyle(.roundedBorder)
                        Button(action: addCampus) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundColor(.blue)
                        }
                        .disabled(newCampus.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .listRowBackground(Color.black)
                    
                    if !store.locations.isEmpty {
                        ForEach(store.locations.sorted(), id: \.self) { campus in
                            HStack {
                                Image(systemName: "building.2")
                                    .foregroundColor(.blue)
                                    .frame(width: 24)
                                Text(campus)
                                    .foregroundColor(.white)
                                Spacer()
                            }
                            .listRowBackground(Color.black)
                        }
                        .onDelete { indexSet in
                            let sorted = store.locations.sorted()
                            for index in indexSet {
                                store.deleteLocation(sorted[index])
                            }
                        }
                    } else {
                        Text("No campuses added yet")
                            .foregroundColor(.gray)
                            .font(.caption)
                            .listRowBackground(Color.black)
                    }
                } header: {
                    Text("Campus Locations")
                } footer: {
                    Text("Swipe left on a campus to delete it")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                // Rooms Management
                Section {
                    HStack {
                        TextField("Add new room", text: $newRoom)
                            .textFieldStyle(.roundedBorder)
                        Button(action: addRoom) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundColor(.blue)
                        }
                        .disabled(newRoom.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .listRowBackground(Color.black)
                    
                    if !store.rooms.isEmpty {
                        ForEach(store.rooms.sorted(), id: \.self) { room in
                            HStack {
                                Image(systemName: "door.left.hand.open")
                                    .foregroundColor(.blue)
                                    .frame(width: 24)
                                Text(room)
                                    .foregroundColor(.white)
                                Spacer()
                            }
                            .listRowBackground(Color.black)
                        }
                        .onDelete { indexSet in
                            let sorted = store.rooms.sorted()
                            for index in indexSet {
                                store.deleteRoom(sorted[index])
                            }
                        }
                    } else {
                        Text("No rooms added yet")
                            .foregroundColor(.gray)
                            .font(.caption)
                            .listRowBackground(Color.black)
                    }
                } header: {
                    Text("Room Names")
                } footer: {
                    Text("Swipe left on a room to delete it")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            } else {
                Section {
                    HStack {
                        Text("Campus & Rooms management")
                        Spacer()
                        Text("Premium")
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue)
                            .cornerRadius(4)
                    }
                }
            }
            
            Section(header:
                HStack {
                    Text("Import from Google Sheets")
                    Spacer()
                    Button(action: { showImportHelp = true }) {
                        HStack(spacing: 4) {
                            Image(systemName: "questionmark.circle")
                            Text("Help")
                        }
                        .font(.caption)
                        .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                }
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Paste your Google Sheet share link and tap Import")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        TextField("Gear sheet link", text: $gearSheetLink)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        Button(action: importGearData) {
                            if isImporting {
                                ProgressView()
                            } else {
                                Image(systemName: "arrow.down.doc")
                            }
                        }
                        .disabled(gearSheetLink.isEmpty || isImporting)
                    }
                    
                    HStack {
                        TextField("Audio patchsheet link", text: $audioPatchSheetLink)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        Button(action: { importPatchData(category: "Audio", link: audioPatchSheetLink) }) {
                            if isImporting {
                                ProgressView()
                            } else {
                                Image(systemName: "arrow.down.doc")
                            }
                        }
                        .disabled(audioPatchSheetLink.isEmpty || isImporting)
                    }
                    
                    HStack {
                        TextField("Video patchsheet link", text: $videoPatchSheetLink)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        Button(action: { importPatchData(category: "Video", link: videoPatchSheetLink) }) {
                            if isImporting {
                                ProgressView()
                            } else {
                                Image(systemName: "arrow.down.doc")
                            }
                        }
                        .disabled(videoPatchSheetLink.isEmpty || isImporting)
                    }
                    
                    HStack {
                        TextField("Lighting patchsheet link", text: $lightingPatchSheetLink)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        Button(action: { importPatchData(category: "Lighting", link: lightingPatchSheetLink) }) {
                            if isImporting {
                                ProgressView()
                            } else {
                                Image(systemName: "arrow.down.doc")
                            }
                        }
                        .disabled(lightingPatchSheetLink.isEmpty || isImporting)
                    }
                }
            }
            
            Section(header: Text("Reset")) {
                Button(action: { showDeleteAllConfirmation = true }) {
                    HStack {
                        Image(systemName: "trash.fill")
                            .foregroundColor(.red)
                        Text("Delete All Gear")
                            .foregroundColor(.red)
                    }
                }
                Button(action: { showDeleteAudioConfirmation = true }) {
                    HStack {
                        Image(systemName: "trash.fill")
                            .foregroundColor(.red)
                        Text("Delete Audio Patchsheet")
                            .foregroundColor(.red)
                    }
                }
                Button(action: { showDeleteVideoConfirmation = true }) {
                    HStack {
                        Image(systemName: "trash.fill")
                            .foregroundColor(.red)
                        Text("Delete Video Patchsheet")
                            .foregroundColor(.red)
                    }
                }
                Button(action: { showDeleteLightingConfirmation = true }) {
                    HStack {
                        Image(systemName: "trash.fill")
                            .foregroundColor(.red)
                        Text("Delete Lighting Patchsheet")
                            .foregroundColor(.red)
                    }
                }
            }
        }
        .navigationTitle("Customize")
        .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .sheet(isPresented: $showImportHelp) {
            ImportHelpView()
        }
        .alert("Delete All Gear?", isPresented: $showDeleteAllConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete All", role: .destructive) {
                store.deleteAllGear()
                errorMessage = "✓ All gear has been deleted"
                showError = true
            }
        } message: {
            Text("Are you sure you want to delete all gear items? This cannot be undone.")
        }
        .alert("Delete Audio Patchsheet?", isPresented: $showDeleteAudioConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                store.deletePatchesByCategory("Audio")
                errorMessage = "✓ Audio patchsheet has been deleted"
                showError = true
            }
        } message: {
            Text("Are you sure you want to delete all audio patches? This cannot be undone.")
        }
        .alert("Delete Lighting Patchsheet?", isPresented: $showDeleteLightingConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                store.deletePatchesByCategory("Lighting")
                errorMessage = "✓ Lighting patchsheet has been deleted"
                showError = true
            }
        } message: {
            Text("Are you sure you want to delete all lighting patches? This cannot be undone.")
        }
        .alert("Delete Video Patchsheet?", isPresented: $showDeleteVideoConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                store.deletePatchesByCategory("Video")
                errorMessage = "✓ Video patchsheet has been deleted"
                showError = true
            }
        } message: {
            Text("Are you sure you want to delete all video patches? This cannot be undone.")
        }
        .alert(errorMessage.hasPrefix("✓") ? "Success" : "Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }

    private func addCampus() {
        let trimmed = newCampus.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            errorMessage = "Campus name cannot be empty"
            showError = true
            return
        }
        if store.locations.contains(trimmed) {
            errorMessage = "This campus already exists"
            showError = true
            return
        }
        print("DEBUG: Adding campus '\(trimmed)' for team \(store.teamCode ?? "NO_TEAM_CODE")")
        store.saveLocation(trimmed)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            print("DEBUG: After save, locations count = \(store.locations.count), locations = \(store.locations)")
            errorMessage = "✓ Campus '\(trimmed)' added successfully"
            showError = true
        }
        newCampus = ""
    }
    
    private func addRoom() {
        let trimmed = newRoom.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            errorMessage = "Room name cannot be empty"
            showError = true
            return
        }
        if store.rooms.contains(trimmed) {
            errorMessage = "This room already exists"
            showError = true
            return
        }
        print("DEBUG: Adding room '\(trimmed)' for team \(store.teamCode ?? "NO_TEAM_CODE")")
        store.saveRoom(trimmed)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            print("DEBUG: After save, rooms count = \(store.rooms.count), rooms = \(store.rooms)")
            errorMessage = "✓ Room '\(trimmed)' added successfully"
            showError = true
        }
        newRoom = ""
    }

    private func importGearData() {
        isImporting = true
        let csvURL = convertGoogleSheetLinkToCSV(gearSheetLink)
        
        URLSession.shared.dataTask(with: csvURL) { data, _, error in
            defer { DispatchQueue.main.async { isImporting = false } }
            
            guard let data = data, error == nil else {
                DispatchQueue.main.async {
                    errorMessage = "Failed to fetch sheet: \(error?.localizedDescription ?? "Unknown error")"
                    showError = true
                }
                return
            }
            
            guard let csvString = String(data: data, encoding: .utf8) else { return }
            let gearItems = parseGearCSV(csvString)
            
            DispatchQueue.main.async {
                store.replaceAllGear(gearItems)
                gearSheetLink = ""
                errorMessage = "✓ Imported \(gearItems.count) gear items"
                showError = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    showError = false
                }
            }
        }.resume()
    }
    
    private func importPatchData(category: String, link: String) {
        isImporting = true
        let csvURL = convertGoogleSheetLinkToCSV(link)
        
        URLSession.shared.dataTask(with: csvURL) { data, _, error in
            defer { DispatchQueue.main.async { isImporting = false } }
            
            guard let data = data, error == nil else {
                DispatchQueue.main.async {
                    errorMessage = "Failed to fetch sheet: \(error?.localizedDescription ?? "Unknown error")"
                    showError = true
                }
                return
            }
            
            guard let csvString = String(data: data, encoding: .utf8) else { return }
            var patchRows = parsePatchCSV(csvString)
            
            // Filter or set category for imported patches
            patchRows = patchRows.map { var row = $0; row.category = category; return row }
            
            DispatchQueue.main.async {
                store.replaceAllPatch(patchRows)
                // Clear the appropriate field
                if category == "Audio" { audioPatchSheetLink = "" }
                else if category == "Video" { videoPatchSheetLink = "" }
                else if category == "Lighting" { lightingPatchSheetLink = "" }
                
                errorMessage = "✓ Imported \(patchRows.count) \(category) patches"
                showError = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    showError = false
                }
            }
        }.resume()
    }
    
    private func convertGoogleSheetLinkToCSV(_ link: String) -> URL {
        let cleanLink = link.trimmingCharacters(in: .whitespaces)
        if let spreadsheetID = extractSpreadsheetID(from: cleanLink) {
            return URL(string: "https://docs.google.com/spreadsheets/d/\(spreadsheetID)/export?format=csv")!
        }
        return URL(string: cleanLink)!
    }
    
    private func extractSpreadsheetID(from link: String) -> String? {
        if let range = link.range(of: "/d/") {
            let afterD = link[range.upperBound...]
            if let slashRange = afterD.range(of: "/") {
                return String(afterD[..<slashRange.lowerBound])
            } else {
                return String(afterD)
            }
        }
        return nil
    }
    
    private func parseGearCSV(_ csv: String) -> [GearItem] {
        let lines = csv.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard lines.count > 1 else { return [] }
        
        var items: [GearItem] = []
        let headers = lines[0].components(separatedBy: ",")
        
        for i in 1..<lines.count {
            let values = lines[i].components(separatedBy: ",")
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
        
        for i in 1..<lines.count {
            let values = lines[i].components(separatedBy: ",")
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

// MARK: - Import Help

struct ImportHelpView: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    helpCard(title: "Before You Import", bullets: [
                        "Use Google Sheets and share the sheet with anyone who has the link.",
                        "Headers must match ProdConnect fields exactly (case-insensitive).",
                        "Dates must be formatted as YYYY-MM-DD.",
                        "If a field is optional, you can leave it blank."
                    ])

                    helpCard(title: "Importing Inventory", bullets: [
                        "Supported headers: name, category, location, campus, serial, serialNumber, status, assetId, asset id, purchased, purchasedate, purchasedFrom, purchased from, cost, installDate, install date, maintenanceIssue, maintenance issue, maintenanceCost, maintenance cost, maintenanceRepairDate, maintenance repair date, maintenanceNotes, maintenance notes, imageURL, image url.",
                        "Status values recognized: In Stock, In Use, Needs Repair, Retired, Missing.",
                        "Cost should be a number (no currency symbols)."
                    ])

                    helpCard(title: "Importing Patchsheet", bullets: [
                        "Supported headers: name, input, output, category, campus, room.",
                        "Category can be Audio, Video, or Lighting.",
                        "Lighting rows can leave output blank."
                    ])

                    helpCard(title: "Link Tips", bullets: [
                        "Use the Google Sheet share link or a direct CSV export link.",
                        "If import fails, double-check the link and try again."
                    ])
                }
                .padding()
            }
            .navigationTitle("Import Help")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .background(Color.black.ignoresSafeArea())
        }
        .presentationDetents([.medium, .large])
    }

    private func helpCard(title: String, bullets: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundColor(.white)

            ForEach(bullets, id: \.self) { bullet in
                HStack(alignment: .top, spacing: 8) {
                    Text("•")
                        .foregroundColor(.blue)
                    Text(bullet)
                        .foregroundColor(.gray)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .background(Color(white: 0.12))
        .cornerRadius(12)
    }
}

// MARK: - UserDetailView (Admin Only)
struct UserDetailView: View {
    @EnvironmentObject var store: ProdConnectStore
    @Environment(\.dismiss) var dismiss
    @State var user: UserProfile
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showTransferConfirm = false

    var body: some View {
        Form {
            Section(header: Text("User")) {
                Text(user.displayName)
                Text("Email: \(user.email)")
            }

            Section(header: Text("Role")) {
                Toggle("Admin", isOn: $user.isAdmin)
                    .disabled(isSaving || user.isOwner)
                    .onChange(of: user.isAdmin) { newValue in
                        updateAdminFlag(isAdmin: newValue)
                    }
            }

            if store.user?.isOwner == true, user.id != store.user?.id {
                Section(header: Text("Ownership")) {
                    Button("Transfer Ownership") {
                        showTransferConfirm = true
                    }
                    .disabled(isSaving)
                }
            }
            
            if !user.isAdmin && (store.user?.hasCampusRoomFeatures ?? false) {
                Section(header: Text("Assigned Campus")) {
                    Picker("Campus", selection: $user.assignedCampus) {
                        Text("No campus assigned").tag("")
                        ForEach(store.locations.sorted(), id: \.self) { campus in
                            Text(campus).tag(campus)
                        }
                    }
                    .onChange(of: user.assignedCampus) { newValue in
                        updateAssignedCampus(campus: newValue)
                    }
                }
            }

            Section(header: Text("Permissions")) {
                Toggle("Can edit patchsheet", isOn: $user.canEditPatchsheet)
                    .onChange(of: user.canEditPatchsheet) { newValue in
                        updatePermission(key: "canEditPatchsheet", value: newValue)
                    }
                Toggle("Can edit training", isOn: $user.canEditTraining)
                    .onChange(of: user.canEditTraining) { newValue in
                        updatePermission(key: "canEditTraining", value: newValue)
                    }
                Toggle("Can edit gear", isOn: $user.canEditGear)
                    .onChange(of: user.canEditGear) { newValue in
                        updatePermission(key: "canEditGear", value: newValue)
                    }
                Toggle("Can edit ideas", isOn: $user.canEditIdeas)
                    .onChange(of: user.canEditIdeas) { newValue in
                        updatePermission(key: "canEditIdeas", value: newValue)
                    }
                Toggle("Can edit checklists", isOn: $user.canEditChecklists)
                    .onChange(of: user.canEditChecklists) { newValue in
                        updatePermission(key: "canEditChecklists", value: newValue)
                    }
            }

            if !user.isAdmin {
                Section(header: Text("Visible Tabs")) {
                    Toggle("Chat", isOn: $user.canSeeChat)
                        .onChange(of: user.canSeeChat) { newValue in
                            updatePermission(key: "canSeeChat", value: newValue)
                        }
                    Toggle("Patchsheet", isOn: $user.canSeePatchsheet)
                        .onChange(of: user.canSeePatchsheet) { newValue in
                            updatePermission(key: "canSeePatchsheet", value: newValue)
                        }
                    Toggle("Training", isOn: $user.canSeeTraining)
                        .onChange(of: user.canSeeTraining) { newValue in
                            updatePermission(key: "canSeeTraining", value: newValue)
                        }
                    Toggle("Gear", isOn: $user.canSeeGear)
                        .onChange(of: user.canSeeGear) { newValue in
                            updatePermission(key: "canSeeGear", value: newValue)
                        }
                    Toggle("Ideas", isOn: $user.canSeeIdeas)
                        .onChange(of: user.canSeeIdeas) { newValue in
                            updatePermission(key: "canSeeIdeas", value: newValue)
                        }
                    Toggle("Checklists", isOn: $user.canSeeChecklists)
                        .onChange(of: user.canSeeChecklists) { newValue in
                            updatePermission(key: "canSeeChecklists", value: newValue)
                        }
                }
            }

            if let err = errorMessage {
                Section { Text(err).foregroundColor(.red) }
            }
        }
        .navigationTitle("Edit User")
        .toolbar {
            if isSaving {
                ToolbarItem(placement: .navigationBarTrailing) {
                    ProgressView()
                }
            }
        }
        .confirmationDialog("Transfer Ownership?", isPresented: $showTransferConfirm, titleVisibility: .visible) {
            Button("Transfer to \(user.displayName)") {
                transferOwnership()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will move the Owner role and subscription control to this user.")
        }
    }

    private func transferOwnership() {
        guard let currentOwner = store.user, currentOwner.isOwner else { return }
        let teamCode = currentOwner.teamCode ?? ""
        guard !teamCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
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
        if user.subscriptionTier == "free" {
            newOwnerUpdates["subscriptionTier"] = "basic"
        }
        batch.setData(newOwnerUpdates, forDocument: newOwnerRef, merge: true)

        batch.commit { error in
            DispatchQueue.main.async {
                self.isSaving = false
                if let error = error {
                    self.errorMessage = "Transfer failed: \(error.localizedDescription)"
                    return
                }

                if currentOwner.id == self.store.user?.id {
                    self.store.user?.isOwner = false
                }
                self.user.isOwner = true
                self.user.isAdmin = true
                if self.user.subscriptionTier == "free" {
                    self.user.subscriptionTier = "basic"
                }
            }
        }
    }

    private func updateAdminFlag(isAdmin: Bool) {
        isSaving = true
        errorMessage = nil
        store.db.collection("users").document(user.id).updateData(["isAdmin": isAdmin]) { error in
            DispatchQueue.main.async {
                self.isSaving = false
                if let error = error {
                    self.errorMessage = "Update failed: \(error.localizedDescription)"
                    self.user.isAdmin.toggle() // revert on failure
                } else {
                    if let idx = store.teamMembers.firstIndex(where: { $0.id == user.id }) {
                        store.teamMembers[idx].isAdmin = isAdmin
                    }
                }
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
        print("DEBUG: Updating campus to '\(campus)' for user \(user.id)")

        store.db.collection("users").document(user.id).setData(["assignedCampus": campus], merge: true) { error in
            DispatchQueue.main.async {
                self.isSaving = false
                if let error = error {
                    print("DEBUG: Campus update error: \(error.localizedDescription)")
                    self.errorMessage = "Update failed: \(error.localizedDescription)"
                } else {
                    print("DEBUG: Campus updated successfully to '\(campus)'")
                    self.user.assignedCampus = campus
                    if let idx = store.teamMembers.firstIndex(where: { $0.id == user.id }) {
                        store.teamMembers[idx].assignedCampus = campus
                    }
                }
            }
        }
    }
    
    private func updatePermission(key: String, value: Bool) {
        isSaving = true
        errorMessage = nil
        store.db.collection("users").document(user.id).updateData([key: value]) { error in
            DispatchQueue.main.async {
                self.isSaving = false
                if let error = error {
                    self.errorMessage = "Update failed: \(error.localizedDescription)"
                } else {
                    if let idx = store.teamMembers.firstIndex(where: { $0.id == user.id }) {
                        switch key {
                        case "canEditPatchsheet":
                            store.teamMembers[idx].canEditPatchsheet = value
                        case "canEditTraining":
                            store.teamMembers[idx].canEditTraining = value
                        case "canEditGear":
                            store.teamMembers[idx].canEditGear = value
                        case "canEditIdeas":
                            store.teamMembers[idx].canEditIdeas = value
                        case "canEditChecklists":
                            store.teamMembers[idx].canEditChecklists = value
                        case "canSeeChat":
                            store.teamMembers[idx].canSeeChat = value
                        case "canSeePatchsheet":
                            store.teamMembers[idx].canSeePatchsheet = value
                        case "canSeeTraining":
                            store.teamMembers[idx].canSeeTraining = value
                        case "canSeeGear":
                            store.teamMembers[idx].canSeeGear = value
                        case "canSeeIdeas":
                            store.teamMembers[idx].canSeeIdeas = value
                        case "canSeeChecklists":
                            store.teamMembers[idx].canSeeChecklists = value
                        default:
                            break
                        }
                    }
                }
            }
        }
    }
}

    // ...existing code...

// MARK: - Edit Patch View

struct EditPatchView: View {
    @EnvironmentObject var store: ProdConnectStore
    @Environment(\.dismiss) var dismiss
    @State var patch: PatchRow
    @State private var isSaving = false
    @State private var editChannelCountText = ""
    
    var canEdit: Bool { store.canEditPatchsheet }
    
    var body: some View {
        Form {
            Section("Patch Details") {
                TextField("Name", text: $patch.name).disabled(!canEdit)
                
                if patch.category == "Lighting" {
                    TextField("DMX Channel", text: $patch.input).disabled(!canEdit)
                    TextField("Channel Count", text: $editChannelCountText).keyboardType(.numberPad).disabled(!canEdit)
                } else if patch.category == "Video" {
                    TextField("Source", text: $patch.input).disabled(!canEdit)
                    TextField("Destination", text: $patch.output).disabled(!canEdit)
                } else {
                    TextField("Input", text: $patch.input).disabled(!canEdit)
                    TextField("Output", text: $patch.output).disabled(!canEdit)
                }
                
                TextField("Campus", text: $patch.campus).disabled(!canEdit)
                TextField("Room", text: $patch.room).disabled(!canEdit)
            }
        }
        .navigationTitle("Edit Patch")
        .onAppear {
            if let count = patch.channelCount, count > 0 {
                editChannelCountText = String(count)
            } else {
                editChannelCountText = ""
            }
        }
        .toolbar {
            if canEdit {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        isSaving = true
                        let trimmed = editChannelCountText.trimmingCharacters(in: .whitespaces)
                        let parsed = Int(trimmed) ?? 0
                        patch.channelCount = parsed > 0 ? parsed : nil
                        // Use central savePatch to persist and update local state
                        store.savePatch(patch)
                        DispatchQueue.main.async {
                            isSaving = false
                            dismiss()
                        }
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { UIApplication.shared.endEditing() }
                }
            }
        }
    }
}


// MARK: - Training Views (Updated for completion tracking)

// ...existing code...
struct TrainingListView: View {
    @EnvironmentObject var store: ProdConnectStore
    @State private var showAdd = false
    @State private var showAddVideo = false
    @State private var selectedFilter = "All"
    @State private var searchText = ""
    var canEdit: Bool { store.user?.isAdmin == true || store.user?.canEditTraining == true }

    // Only allowed categories
    let categories = ["All", "Audio", "Video", "Lighting", "Misc"]

    // Filtered lessons based on selection and search
    var filteredLessons: [TrainingLesson] {
        var lessons = store.lessons
        
        if selectedFilter != "All" {
            lessons = lessons.filter { $0.category == selectedFilter }
        }
        
        if !searchText.isEmpty {
            lessons = lessons.filter { $0.title.localizedCaseInsensitiveContains(searchText) || $0.category.localizedCaseInsensitiveContains(searchText) }
        }
        
        return lessons
    }

    var body: some View {
        NavigationStack {
            VStack {
                SearchBar(text: $searchText)

                Picker("Category", selection: $selectedFilter) {
                    ForEach(categories, id: \.self) { Text($0) }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)

                List {
                    ForEach(filteredLessons) { lesson in
                        NavigationLink(destination: TrainingDetailView(lesson: lesson).environmentObject(store)) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(lesson.title).font(.headline)
                                    Text(lesson.category).font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                if lesson.isCompleted {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                }
                            }
                        }
                    }
                    .onDelete { idx in
                        guard canEdit else { return }
                        for i in idx {
                            let id = filteredLessons[i].id
                            store.db.collection("lessons").document(id).delete()
                        }
                    }
                }
            }
            .navigationTitle("Training")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showAdd) {
                AddTrainingView { new in
                    store.saveLesson(new)
                }
                .environmentObject(store)
            }
            .sheet(isPresented: $showAddVideo) {
                AddTrainingView { new in
                    store.saveLesson(new)
                }
                .environmentObject(store)
            }
        }
    }

    // Helper to get YouTube thumbnail
    private func getYouTubeThumbnailURL(from url: String) -> String {
        if let videoID = url.components(separatedBy: "v=").last?.components(separatedBy: "&").first {
            return "https://img.youtube.com/vi/\(videoID)/hqdefault.jpg"
        } else if let videoID = url.components(separatedBy: "/").last {
            return "https://img.youtube.com/vi/\(videoID)/hqdefault.jpg"
        }
        return ""
    }
}

private extension String {
    var xmlEscaped: String {
        self
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

// ...existing code...

struct TrainingDetailView: View {
    @EnvironmentObject var store: ProdConnectStore
    @State var lesson: TrainingLesson
    @State private var player: AVPlayer? = nil
    
    var body: some View {
        VStack {
            if let urlString = lesson.urlString, !urlString.isEmpty {
                if let youtubeURL = YouTubeURLHelper.watchURL(from: urlString) {
                    InAppSafariView(url: youtubeURL)
                        .frame(height: 320)
                } else if let url = URL(string: urlString) {
                    // Local video
                    VideoPlayer(player: player)
                        .frame(height: 250)
                        .onAppear {
                            player = AVPlayer(url: url)
                            // Observe playback end
                            NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player?.currentItem, queue: .main) { _ in
                                markCompleted()
                            }
                        }
                        .onDisappear {
                            player?.pause()
                            NotificationCenter.default.removeObserver(self)
                        }
                } else {
                    Text("Invalid video URL")
                        .foregroundColor(.red)
                }
            } else {
                Text("No video attached")
            }

            Form {
                Section("Details") {
                    Text(lesson.title).font(.headline)
                    Text(lesson.category).font(.subheadline).foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle(lesson.title)
        .onDisappear {
            // If it's a YouTube video, mark completed when leaving the view
            if lesson.urlString?.contains("youtube.com") == true || lesson.urlString?.contains("youtu.be") == true {
                markCompleted()
            }
        }
    }

    private func markCompleted() {
        guard !lesson.isCompleted else { return }
        lesson.isCompleted = true
        store.saveLesson(lesson)
    }
}

struct AddTrainingView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var store: ProdConnectStore

    @State private var title = ""
    @State private var category = "Audio" // Default selection
    @State private var videoSource: String = "local" // "local" or "youtube"
    @State private var youtubeLink = ""
    @State private var selectedVideoItem: PhotosPickerItem?
    @State private var localVideoURL: URL?
    @State private var isUploading = false
    @State private var uploadProgress: Double = 0
    @State private var errorMsg: String?

    var onSave: (TrainingLesson) -> Void

    // Only allowed categories
    let categories = ["Audio", "Video", "Lighting", "Misc"]

    private func uploadVideo(localURL: URL, completion: @escaping (Result<String, Error>) -> Void) {
        let filename = "\(UUID().uuidString).mov"
        let storageRef = Storage.storage().reference().child("trainingVideos/\(filename)")

        let uploadTask = storageRef.putFile(from: localURL)
        uploadTask.observe(.progress) { snapshot in
            if let fraction = snapshot.progress?.fractionCompleted {
                uploadProgress = fraction
            }
        }
        uploadTask.observe(.success) { _ in
            storageRef.downloadURL { url, error in
                if let error { completion(.failure(error)); return }
                completion(.success(url?.absoluteString ?? ""))
            }
        }
        uploadTask.observe(.failure) { snapshot in
            completion(.failure(snapshot.error ?? NSError(domain: "Upload", code: 1)))
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Title", text: $title)
                    Picker("Category", selection: $category) {
                        ForEach(categories, id: \.self) { Text($0) }
                    }
                    .pickerStyle(MenuPickerStyle())
                }
                Section("Video Options") {
                    Picker("Video Source", selection: $videoSource) {
                        Text("Camera Roll").tag("local")
                        Text("YouTube Link").tag("youtube")
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    if videoSource == "local" {
                        PhotosPicker(
                            selection: $selectedVideoItem,
                            matching: .videos,
                            photoLibrary: .shared()) {
                                Text(localVideoURL == nil ? "Select Video" : "Change Video")
                            }
                            .onChange(of: selectedVideoItem) { newItem in
                                Task {
                                    if let item = newItem {
                                        if let data = try? await item.loadTransferable(type: Data.self) {
                                            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
                                            try? data.write(to: tempURL)
                                            localVideoURL = tempURL
                                            youtubeLink = ""
                                        }
                                    }
                                }
                            }
                        if let url = localVideoURL {
                            Text("Selected: \(url.lastPathComponent)").font(.caption)
                        }
                    } else if videoSource == "youtube" {
                        TextField("YouTube URL", text: $youtubeLink)
                            .keyboardType(.URL)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .onChange(of: youtubeLink) { _ in localVideoURL = nil }
                    }
                }
                if isUploading {
                    ProgressView(value: uploadProgress)
                }
                if let errorMsg = errorMsg {
                    Text(errorMsg).foregroundColor(.red)
                }
                Section {
                    Button("Create") {
                        if videoSource == "local" {
                            guard let localURL = localVideoURL else { return }
                            isUploading = true
                            errorMsg = nil
                            uploadVideo(localURL: localURL) { result in
                                DispatchQueue.main.async {
                                    isUploading = false
                                    switch result {
                                    case .success(let urlString):
                                        let lesson = TrainingLesson(
                                            title: title.isEmpty ? "Untitled" : title,
                                            category: category,
                                            teamCode: store.teamCode ?? "",
                                            durationSeconds: 0,
                                            urlString: urlString
                                        )
                                        onSave(lesson)
                                        dismiss()
                                    case .failure(let error):
                                        errorMsg = "Upload failed: \(error.localizedDescription)"
                                    }
                                }
                            }
                    } else {
                        guard let normalizedYouTubeURL = YouTubeURLHelper.normalizedWatchURLString(from: youtubeLink) else {
                            errorMsg = "Enter a valid YouTube video URL."
                            return
                        }
                        let lesson = TrainingLesson(
                            title: title.isEmpty ? "Untitled" : title,
                            category: category,
                            teamCode: store.teamCode ?? "",
                            durationSeconds: 0,
                            urlString: normalizedYouTubeURL
                        )
                        onSave(lesson)
                        dismiss()
                    }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty ||
                              (videoSource == "local" && localVideoURL == nil) ||
                              (videoSource == "youtube" && youtubeLink.trimmingCharacters(in: .whitespaces).isEmpty) || isUploading)
                }
            }
            .navigationTitle("New Lesson")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
    // ...existing code...

}

// MARK: - Gear Detail View
// ...existing code...
struct GearDetailView: View {
    @EnvironmentObject var store: ProdConnectStore
    @Environment(\.dismiss) var dismiss
    @State var item: GearItem
    @State private var selectedImageItem: PhotosPickerItem?
    @State private var isUploadingImage = false
    @State private var uploadProgress: Double = 0
    @State private var imageError: String?

    var canEdit: Bool { store.canEditGear }

    var body: some View {
        Form {
            Section("Details") {
                TextField("Name", text: $item.name).disabled(!canEdit)
                TextField("Serial Number", text: $item.serialNumber).disabled(!canEdit)
                TextField("Asset ID", text: $item.assetId).disabled(!canEdit)
                Picker("Category", selection: $item.category) {
                    ForEach(["Audio","Video","Lighting","Network","Misc"], id: \.self) { Text($0) }
                }.pickerStyle(.menu).disabled(!canEdit)
                if store.locations.isEmpty {
                    TextField("Location/Campus", text: $item.location).disabled(!canEdit)
                } else {
                    Picker("Location/Campus", selection: $item.location) {
                        Text("Select location").tag("")
                        ForEach(store.locations, id: \.self) { loc in
                            Text(loc).tag(loc)
                        }
                    }
                    .disabled(!canEdit)
                }
                Picker("Status", selection: $item.status) {
                    ForEach(GearItem.GearStatus.allCases, id: \.self) { status in
                        Text(status.rawValue).tag(status)
                    }
                }
                .disabled(!canEdit)
            }

            Section("Install Info") {
                DatePicker("Install Date", selection: Binding(
                    get: { item.installDate ?? Date() },
                    set: { item.installDate = $0 }
                ), displayedComponents: .date).disabled(!canEdit)
            }

            Section("Purchase Info") {
                DatePicker("Purchase Date", selection: Binding(
                    get: { item.purchaseDate ?? Date() },
                    set: { item.purchaseDate = $0 }
                ), displayedComponents: .date).disabled(!canEdit)
                
                TextField("Purchased From", text: Binding(
                    get: { item.purchasedFrom },
                    set: { item.purchasedFrom = $0 }
                )).disabled(!canEdit)
                
                TextField("Cost", value: Binding(
                    get: { item.cost ?? 0 },
                    set: { item.cost = $0 }
                ), format: .currency(code: Locale.current.currencyCode ?? "USD"))
                .keyboardType(.decimalPad)
                .disabled(!canEdit)
            }

            Section("Maintenance") {
                TextField("Issue", text: $item.maintenanceIssue).disabled(!canEdit)
                TextField("Cost", value: Binding(
                    get: { item.maintenanceCost ?? 0 },
                    set: { item.maintenanceCost = $0 }
                ), format: .currency(code: Locale.current.currencyCode ?? "USD"))
                .keyboardType(.decimalPad)
                .disabled(!canEdit)

                DatePicker("Repair Date", selection: Binding(
                    get: { item.maintenanceRepairDate ?? Date() },
                    set: { item.maintenanceRepairDate = $0 }
                ), displayedComponents: .date).disabled(!canEdit)

                TextEditor(text: $item.maintenanceNotes)
                    .frame(minHeight: 120)
                    .disabled(!canEdit)
            }

            Section("Image") {
                if let urlString = item.imageURL, let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 220)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        case .failure:
                            Text("Image failed to load")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        @unknown default:
                            EmptyView()
                        }
                    }
                } else {
                    Text("No image")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                PhotosPicker(selection: $selectedImageItem, matching: .images) {
                    Text("Change Image")
                }
                .disabled(!canEdit || isUploadingImage)

                if isUploadingImage {
                    ProgressView(value: uploadProgress)
                }
                if let imageError = imageError {
                    Text(imageError)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }

            Section {
                Button("Save Changes") {
                    store.saveGear(item)
                    dismiss() // <-- automatically go back
                }
                .disabled(!canEdit)
            }
        }
        .navigationTitle(item.name)
        .onChange(of: selectedImageItem) { newValue in
            guard let newValue, canEdit else { return }
            Task { await loadAndUploadImage(from: newValue) }
        }
    }

    private func loadAndUploadImage(from item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        isUploadingImage = true
        imageError = nil

        uploadGearImage(data: data) { result in
            DispatchQueue.main.async {
                isUploadingImage = false
                switch result {
                case .success(let urlString):
                    self.item.imageURL = urlString
                case .failure(let error):
                    self.imageError = "Image upload failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func uploadGearImage(data: Data, completion: @escaping (Result<String, Error>) -> Void) {
        let storageRef = Storage.storage().reference().child("gearImages/\(UUID().uuidString).jpg")
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        let uploadTask = storageRef.putData(data, metadata: metadata)

        uploadTask.observe(.progress) { snapshot in
            if let fraction = snapshot.progress?.fractionCompleted {
                uploadProgress = fraction
            }
        }

        uploadTask.observe(.success) { _ in
            storageRef.downloadURL { url, error in
                if let url = url { completion(.success(url.absoluteString)) }
                else if let error = error { completion(.failure(error)) }
            }
        }

        uploadTask.observe(.failure) { snapshot in
            if let error = snapshot.error {
                completion(.failure(error))
            }
        }
    }
}

// MARK: - Add Gear View
// ...existing code...
struct AddGearView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var store: ProdConnectStore

    @State private var name = ""
    @State private var category = "Audio"
    @State private var status: GearItem.GearStatus = .available
    @State private var location = ""
    @State private var campus = ""
    @State private var purchaseDate = Date()
    @State private var purchasedFrom = ""
    @State private var cost: Double = 0
    @State private var serialNumber = ""
    @State private var assetId = ""
    @State private var installDate = Date()
    @State private var maintenanceIssue = ""
    @State private var maintenanceCost: Double = 0
    @State private var maintenanceRepairDate = Date()
    @State private var maintenanceNotes = ""
    @State private var selectedImageItem: PhotosPickerItem?
    @State private var selectedImageData: Data?
    @State private var isUploadingImage = false
    @State private var uploadProgress: Double = 0
    @State private var imageError: String?

    var onSave: (GearItem) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Name", text: $name)
                    TextField("Serial Number", text: $serialNumber)
                    TextField("Asset ID", text: $assetId)
                    Picker("Category", selection: $category) {
                        ForEach(["Audio","Video","Lighting","Network","Misc"], id: \.self) { Text($0) }
                    }
                    if store.locations.isEmpty {
                        TextField("Location", text: $location)
                    } else {
                        Picker("Location", selection: $location) {
                            Text("Select location").tag("")
                            ForEach(store.locations, id: \.self) { loc in
                                Text(loc).tag(loc)
                            }
                        }
                    }
                    TextField("Campus", text: $campus)
                    Picker("Status", selection: $status) {
                        ForEach(GearItem.GearStatus.allCases, id: \.self) { status in
                            Text(status.rawValue).tag(status)
                        }
                    }
                }
                Section("Install Info") {
                    DatePicker("Install Date", selection: $installDate, displayedComponents: .date)
                }
                Section("Purchase Info") {
                    DatePicker("Purchase Date", selection: $purchaseDate, displayedComponents: .date)
                    TextField("Purchased From", text: $purchasedFrom)
                    TextField("Cost", value: $cost, format: .currency(code: Locale.current.currencyCode ?? "USD"))
                        .keyboardType(.decimalPad)
                }
                Section("Maintenance") {
                    TextField("Issue", text: $maintenanceIssue)
                    TextField("Cost", value: $maintenanceCost, format: .currency(code: Locale.current.currencyCode ?? "USD"))
                        .keyboardType(.decimalPad)
                    DatePicker("Repair Date", selection: $maintenanceRepairDate, displayedComponents: .date)
                    TextEditor(text: $maintenanceNotes)
                        .frame(minHeight: 120)
                }
                Section("Image") {
                    if let data = selectedImageData, let uiImage = UIImage(data: data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        Text("No image selected")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    PhotosPicker(selection: $selectedImageItem, matching: .images) {
                        Text("Select Image")
                    }
                    .disabled(isUploadingImage)

                    if isUploadingImage {
                        ProgressView(value: uploadProgress)
                    }
                    if let imageError = imageError {
                        Text(imageError)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Add Gear")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        let createItem: (String?) -> GearItem = { imageURL in
                            var new = GearItem(
                                name: name.trimmingCharacters(in: .whitespaces),
                                category: category,
                                status: status,
                                teamCode: store.teamCode ?? "",
                                purchaseDate: purchaseDate,
                                purchasedFrom: purchasedFrom,
                                cost: cost,
                                location: location.trimmingCharacters(in: .whitespaces),
                                serialNumber: serialNumber.trimmingCharacters(in: .whitespaces),
                                campus: campus.trimmingCharacters(in: .whitespaces)
                            )
                            new.createdBy = Auth.auth().currentUser?.email
                            new.assetId = assetId.trimmingCharacters(in: .whitespaces)
                            new.installDate = installDate
                            new.maintenanceIssue = maintenanceIssue.trimmingCharacters(in: .whitespaces)
                            new.maintenanceCost = maintenanceCost
                            new.maintenanceRepairDate = maintenanceRepairDate
                            new.maintenanceNotes = maintenanceNotes.trimmingCharacters(in: .whitespaces)
                            new.imageURL = imageURL
                            return new
                        }

                        if let data = selectedImageData {
                            isUploadingImage = true
                            imageError = nil
                            uploadGearImage(data: data) { result in
                                DispatchQueue.main.async {
                                    isUploadingImage = false
                                    switch result {
                                    case .success(let urlString):
                                        onSave(createItem(urlString))
                                        dismiss()
                                    case .failure(let error):
                                        imageError = "Image upload failed: \(error.localizedDescription)"
                                    }
                                }
                            }
                        } else {
                            onSave(createItem(nil))
                            dismiss()
                        }
                    }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isUploadingImage)
                }
            }
            .onChange(of: selectedImageItem) { newValue in
                guard let newValue else { return }
                Task { await loadImageData(from: newValue) }
            }
        }
    }

    private func loadImageData(from item: PhotosPickerItem) async {
        if let data = try? await item.loadTransferable(type: Data.self) {
            DispatchQueue.main.async {
                self.selectedImageData = data
            }
        }
    }

    private func uploadGearImage(data: Data, completion: @escaping (Result<String, Error>) -> Void) {
        let storageRef = Storage.storage().reference().child("gearImages/\(UUID().uuidString).jpg")
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        let uploadTask = storageRef.putData(data, metadata: metadata)

        uploadTask.observe(.progress) { snapshot in
            if let fraction = snapshot.progress?.fractionCompleted {
                uploadProgress = fraction
            }
        }

        uploadTask.observe(.success) { _ in
            storageRef.downloadURL { url, error in
                if let url = url { completion(.success(url.absoluteString)) }
                else if let error = error { completion(.failure(error)) }
            }
        }

        uploadTask.observe(.failure) { snapshot in
            if let error = snapshot.error {
                completion(.failure(error))
            }
        }
    }
}

// MARK: - Ideas Views

// ...existing code...
struct IdeasListView: View {
    @EnvironmentObject var store: ProdConnectStore
    @State private var showCreate = false

    var canEdit: Bool { store.canEditIdeas }
    var activeIdeas: [IdeaCard] { store.ideas.filter { !$0.implemented } }
    var completedIdeas: [IdeaCard] { store.ideas.filter { $0.implemented }.sorted { ($0.completedAt ?? Date()) > ($1.completedAt ?? Date()) } }

    var body: some View {
        NavigationStack {
            VStack {
                List {
                    if !activeIdeas.isEmpty {
                        Section("Not Completed") {
                            ForEach(activeIdeas) { idea in
                                NavigationLink { IdeaDetailView(idea: idea) } label: {
                                    VStack(alignment: .leading) {
                                        Text(idea.title).font(.headline)
                                        Text(idea.tags.joined(separator: ", ")).font(.caption).foregroundColor(.secondary)
                                    }
                                }
                            }
                            .onDelete { idx in
                                guard canEdit else { return }
                                for i in idx { store.db.collection("ideas").document(activeIdeas[i].id).delete() }
                            }
                        }
                    }
                    
                    if !completedIdeas.isEmpty {
                        Section("Completed") {
                            ForEach(completedIdeas) { idea in
                                NavigationLink { IdeaDetailView(idea: idea) } label: {
                                    VStack(alignment: .leading) {
                                        Text(idea.title).font(.headline)
                                        Text(idea.tags.joined(separator: ", ")).font(.caption).foregroundColor(.secondary)
                                        if let completedAt = idea.completedAt {
                                            Text("Completed: \(completedAt.formatted(date: .abbreviated, time: .shortened))").font(.caption2).foregroundColor(.secondary)
                                        }
                                    }
                                }
                            }
                            .onDelete { idx in
                                guard canEdit else { return }
                                for i in idx { store.db.collection("ideas").document(completedIdeas[i].id).delete() }
                            }
                        }
                    }
                }
                .toolbar {
                    if canEdit {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button { showCreate = true } label: { Image(systemName: "plus") }
                        }
                    }
                }
                .sheet(isPresented: $showCreate) {
                    CreateIdeaView { new in store.saveIdea(new) }
                }
            }
            .navigationTitle("Ideas")
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}

struct IdeaDetailView: View {
    @EnvironmentObject var store: ProdConnectStore
    @State var idea: IdeaCard
    var canEdit: Bool { store.user?.isAdmin == true || store.user?.canEditIdeas == true }
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                Text(idea.title).font(.title2)
                Text(idea.detail)
            }

            Section {
                let userID = store.user?.id ?? ""
                let isLiked = idea.likedBy.contains(userID)
                Button(action: toggleLike) {
                    HStack {
                        Image(systemName: isLiked ? "heart.fill" : "heart")
                        Text("Like (\(idea.likedBy.count))")
                    }
                    .foregroundColor(isLiked ? .red : .blue)
                }
            }

            Section {
                Button(idea.implemented ? "Marked Implemented" : "Mark Implemented") {
                    if !idea.implemented {
                        idea.implemented = true
                        idea.completedAt = Date()
                    }
                    store.saveIdea(idea)
                }.disabled(idea.implemented)
            }
        }
        .navigationTitle(idea.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Ensure the system-provided back affordance is hidden and any left items removed
            // Unconditional diagnostic to ensure we see a log entry when this view appears
            DispatchQueue.main.async {
                NSLog("[DIAG] IdeaDetailView onAppear fired")
            }
        }
    }

    func toggleLike() {
        guard let userID = store.user?.id else { return }
        if idea.likedBy.contains(userID) {
            idea.likedBy.removeAll { $0 == userID }
        } else {
            idea.likedBy.append(userID)
        }
        store.saveIdea(idea)
    }
}

struct CreateIdeaView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var store: ProdConnectStore
    @State private var title = ""
    @State private var detail = ""
    @State private var tags = ""
    var onSave: (IdeaCard) -> Void

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $title)
                TextEditor(text: $detail).frame(minHeight: 120)
                TextField("Tags (comma separated)", text: $tags)
            }
            .navigationTitle("New Idea")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Create") {
                        var new = IdeaCard(title: title.isEmpty ? "Untitled" : title,
                                           detail: detail,
                                           tags: tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) },
                                           teamCode: store.teamCode ?? "")
                        new.id = UUID().uuidString
                        new.createdBy = Auth.auth().currentUser?.email
                        onSave(new)
                        dismiss()
                    }.disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: - Checklists Views

// ...existing code...
struct ChecklistsListView: View {
    @EnvironmentObject var store: ProdConnectStore
    @State private var showCreate = false

    var canEdit: Bool { store.canEditChecklists }
    var activeChecklists: [ChecklistTemplate] {
        store.checklists
            .filter { !isChecklistCompleted($0) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }
    var completedChecklists: [ChecklistTemplate] {
        store.checklists
            .filter { isChecklistCompleted($0) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            VStack {
                List {
                    if !activeChecklists.isEmpty {
                        Section("Not Completed") {
                            ForEach(activeChecklists) { template in
                                checklistRow(template)
                            }
                            .onDelete { idx in
                                guard canEdit else { return }
                                for i in idx {
                                    deleteChecklist(activeChecklists[i])
                                }
                            }
                        }
                    }

                    if !completedChecklists.isEmpty {
                        Section("Completed") {
                            ForEach(completedChecklists) { template in
                                checklistRow(template)
                            }
                            .onDelete { idx in
                                guard canEdit else { return }
                                for i in idx {
                                    deleteChecklist(completedChecklists[i])
                                }
                            }
                        }
                    }
                }
                .toolbar {
                    if canEdit {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button { showCreate = true } label: { Image(systemName: "plus") }
                        }
                    }
                }
                .sheet(isPresented: $showCreate) {
                    CreateChecklistView { newChecklist in
                        store.saveChecklist(newChecklist)
                    }
                }
            }
            .navigationTitle("Checklists")
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    @ViewBuilder
    private func checklistRow(_ template: ChecklistTemplate) -> some View {
        NavigationLink { ChecklistRunView(template: template) } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(template.title).font(.headline)
                if let dueDate = template.dueDate {
                    Text("Due: \(dueDate.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2)
                        .foregroundColor(isChecklistCompleted(template) ? .secondary : (dueDate < Date() ? .red : .secondary))
                }
                if isChecklistCompleted(template) {
                    if let completedAt = template.completedAt {
                        let by = template.completedBy?.trimmingCharacters(in: .whitespacesAndNewlines)
                        if let by, !by.isEmpty {
                            Text("Completed by \(by) on \(completedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        } else {
                            Text("Completed on \(completedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Text("Completed")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .contextMenu {
            if canEdit {
                Button("Duplicate") {
                    duplicateChecklist(template)
                }
                Button(role: .destructive) {
                    deleteChecklist(template)
                } label: {
                    Text("Delete")
                }
            }
        }
    }

    private func isChecklistCompleted(_ template: ChecklistTemplate) -> Bool {
        !template.items.isEmpty && template.items.allSatisfy(\.isDone)
    }

    private func duplicateChecklist(_ template: ChecklistTemplate) {
        guard canEdit else { return }
        var copy = template
        copy.id = UUID().uuidString
        copy.title = "\(template.title) Copy"
        copy.dueDate = nil
        copy.completedAt = nil
        copy.completedBy = nil
        copy.items = template.items.map { item in
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

    private func deleteChecklist(_ template: ChecklistTemplate) {
        guard canEdit else { return }
        store.db.collection("checklists").document(template.id).delete()
    }
}

struct ChecklistRunView: View {
    @EnvironmentObject var store: ProdConnectStore
    @State var template: ChecklistTemplate
    @Environment(\.dismiss) private var dismiss
    @State private var hasDueDate = false
    @State private var draftDueDate = Date()
    @State private var isEditingChecklist = false
    @State private var newChecklistItemText = ""
    var canEdit: Bool { store.canEditChecklists }

    var body: some View {
        Form {
            Section(header: Text("Title")) {
                if canEdit && isEditingChecklist {
                    TextField("Checklist title", text: $template.title)
                } else {
                    Text(template.title)
                }
            }
            Section(header: Text("Progress")) {
                ProgressView(value: progress)
            }
            Section(header: Text("Due Date")) {
                if canEdit && isEditingChecklist {
                    Toggle("Set due date", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("Due", selection: $draftDueDate, displayedComponents: [.date, .hourAndMinute])
                    }
                } else if let dueDate = template.dueDate {
                    Text("Due: \(dueDate.formatted(date: .abbreviated, time: .shortened))")
                        .foregroundColor(.secondary)
                } else {
                    Text("No due date")
                        .foregroundColor(.secondary)
                }
            }
            if let completedAt = template.completedAt {
                Section(header: Text("Checklist Completion")) {
                    if let completedBy = template.completedBy?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !completedBy.isEmpty {
                        Text("Completed by \(completedBy)")
                    }
                    Text("Completed on \(completedAt.formatted(date: .abbreviated, time: .shortened))")
                }
            }
            Section {
                ForEach($template.items) { $item in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Button(action: { toggleItem(&item) }) {
                                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(item.isDone ? .green : .secondary)
                            }
                            .buttonStyle(.plain)
                            .disabled(!canEdit || !isEditingChecklist)
                            if canEdit && isEditingChecklist {
                                TextField("Checklist item", text: $item.text)
                            } else {
                                Text(item.text)
                            }
                            if canEdit && isEditingChecklist {
                                Button(role: .destructive) {
                                    deleteChecklistItem(id: item.id)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        if item.isDone, let completedAt = item.completedAt {
                            let by = item.completedBy?.trimmingCharacters(in: .whitespacesAndNewlines)
                            if let by, !by.isEmpty {
                                Text("Checked by \(by) on \(completedAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            } else {
                                Text("Checked on \(completedAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            if canEdit && isEditingChecklist {
                Section(header: Text("Add Item")) {
                    HStack {
                        TextField("New checklist item", text: $newChecklistItemText)
                        Button("Add") {
                            let trimmed = newChecklistItemText.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            template.items.append(ChecklistItem(text: trimmed))
                            newChecklistItemText = ""
                        }
                        .disabled(newChecklistItemText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            Section {
                Button(canEdit && isEditingChecklist ? "Save & Close" : "Close") {
                    if canEdit && isEditingChecklist {
                        template.dueDate = hasDueDate ? draftDueDate : nil
                        updateChecklistCompletionMetadata()
                        store.saveChecklist(template)
                    }
                    dismiss()
                }.buttonStyle(.borderedProminent)
            }
        }
        .navigationTitle(template.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if canEdit {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isEditingChecklist ? "Done" : "Edit") {
                        isEditingChecklist.toggle()
                    }
                }
            }
        }
        .onAppear {
            // Ensure the system-provided back affordance is hidden and any left items removed
            // Unconditional diagnostic to ensure we see a log entry when this view appears
            DispatchQueue.main.async {
                NSLog("[DIAG] ChecklistRunView onAppear fired")
            }
            isEditingChecklist = false
            if let dueDate = template.dueDate {
                hasDueDate = true
                draftDueDate = dueDate
            } else {
                hasDueDate = false
                draftDueDate = Date()
            }
            newChecklistItemText = ""
        }
    }

    private func toggleItem(_ item: inout ChecklistItem) {
        item.isDone.toggle()
        if item.isDone {
            item.completedAt = Date()
            item.completedBy = completionUserLabel
        } else {
            item.completedAt = nil
            item.completedBy = nil
        }
    }

    private func updateChecklistCompletionMetadata() {
        if template.items.isEmpty {
            template.completedAt = nil
            template.completedBy = nil
            return
        }

        if template.items.allSatisfy(\.isDone) {
            if template.completedAt == nil {
                template.completedAt = Date()
            }
            if (template.completedBy ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                template.completedBy = completionUserLabel
            }
        } else {
            template.completedAt = nil
            template.completedBy = nil
        }
    }

    private var completionUserLabel: String {
        let displayName = store.user?.displayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !displayName.isEmpty { return displayName }
        return store.user?.email ?? Auth.auth().currentUser?.email ?? "Unknown User"
    }

    private func deleteChecklistItem(id: String) {
        template.items.removeAll { $0.id == id }
    }

    var progress: Double {
        guard !template.items.isEmpty else { return 0 }
        return Double(template.items.filter { $0.isDone }.count) / Double(template.items.count)
    }
}

struct CreateChecklistView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var store: ProdConnectStore
    @State private var title = ""
    @State private var itemsText = "Item 1\nItem 2"
    @State private var hasDueDate = false
    @State private var dueDate = Date()

    var onSave: (ChecklistTemplate) -> Void

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $title)
                Section("Due Date") {
                    Toggle("Set due date", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("Due", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                    }
                }
                Section("Items (one per line)") {
                    TextEditor(text: $itemsText).frame(minHeight: 120)
                }
                Section {
                    Button("Create") {
                        let items = itemsText
                            .split(separator: "\n")
                            .map { ChecklistItem(text: String($0)) }

                        var template = ChecklistTemplate(
                            title: title.isEmpty ? "New Checklist" : title,
                            teamCode: store.teamCode ?? "",
                            items: items
                        )
                        template.createdBy = Auth.auth().currentUser?.email
                        template.dueDate = hasDueDate ? dueDate : nil

                        onSave(template)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .navigationTitle("New Checklist")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Chat Views

// ...existing code...
struct ChatListView: View {
    @EnvironmentObject var store: ProdConnectStore
    @State private var showCreate = false
    var isAdmin: Bool { store.user?.isAdmin == true }
    private var channelsToShow: [ChatChannel] {
        if isAdmin { return store.channels }
        guard let email = store.user?.email else { return [] }
        return store.channels.filter { !$0.isHidden && !$0.hiddenUserEmails.contains(email) }
    }

    var body: some View {
        NavigationStack {
            VStack {
                List {
                    Section {
                        ForEach(channelsToShow) { channel in
                            NavigationLink {
                                ChatChannelDetailView(channel: channel)
                            } label: {
                                Text(channel.name)
                                    .font(.headline)
                            }
                        }
                        .onMove { indices, newOffset in
                            guard isAdmin else { return }
                            store.channels.move(fromOffsets: indices, toOffset: newOffset)
                            let orderedIds = store.channels.map { $0.id }
                            store.updateChannelOrder(orderedIds: orderedIds)
                        }
                        .onDelete { idx in
                            guard isAdmin else { return }
                            for i in idx {
                                let id = store.channels[i].id
                                store.db.collection("channels").document(id).delete()
                            }
                        }
                        .moveDisabled(!isAdmin)
                    } header: {
                        Text("Channels")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                            .textCase(nil)
                    }
                }
                .toolbar {
                    if isAdmin {
                        ToolbarItem(placement: .navigationBarLeading) {
                            EditButton()
                        }
                    }
                    if isAdmin {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button { showCreate = true } label: { Image(systemName: "plus") }
                        }
                    }
                }
                .sheet(isPresented: $showCreate) {
                    CreateChannelView()
                }
            }
            .navigationTitle("Chat")
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}

// MARK: - Chat Channel Detail
struct ChatChannelDetailView: View {
    @EnvironmentObject var store: ProdConnectStore
    @State var channel: ChatChannel
    @State private var newMessage = ""
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var pendingAttachmentURL: URL?
    @State private var pendingAttachmentName: String?
    @State private var pendingAttachmentKind: ChatAttachmentKind?
    @State private var pendingAttachmentData: Data?
    @State private var showFilePicker = false
    @State private var isUploadingAttachment = false
    @State private var uploadProgress: Double = 0
    @State private var attachmentError: String?
    @State private var messageToEdit: ChatMessage?
    @State private var messageToDelete: ChatMessage?
    @State private var showSettings = false

    private let maxAttachmentBytes = 100 * 1024 * 1024

    private var isAdmin: Bool { store.user?.isAdmin == true }
    private var canSendMessages: Bool {
        if isAdmin { return true }
        guard let email = store.user?.email else { return false }
        if channel.isReadOnly { return false }
        return !channel.readOnlyUserEmails.contains(email)
    }

    var body: some View {
        VStack {
            ScrollViewReader { proxy in
                List {
                    ForEach(channel.messages) { msg in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Text(userName(for: msg.author))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                ForEach(userTags(for: msg.author), id: \.self) { tag in
                                    Text(tag)
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.secondary.opacity(0.15))
                                        .clipShape(Capsule())
                                }
                                if msg.editedAt != nil {
                                    Text("edited")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            if !msg.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(msg.text)
                            }
                            attachmentView(for: msg)
                        }
                        .contextMenu {
                            if canEdit(msg) {
                                Button("Edit") {
                                    messageToEdit = msg
                                    newMessage = msg.text
                                    clearPendingAttachment()
                                }
                                Button(role: .destructive) { messageToDelete = msg } label: {
                                    Text("Delete")
                                }
                            } else if isAdmin {
                                Button(role: .destructive) { messageToDelete = msg } label: {
                                    Text("Delete")
                                }
                            }
                        }
                        .id(msg.id)
                    }
                }
                .onChange(of: channel.messages.count) { _ in
                    if let lastMsg = channel.messages.last {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            proxy.scrollTo(lastMsg.id, anchor: .bottom)
                        }
                    }
                }
                .onAppear {
                    if let lastMsg = channel.messages.last {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            proxy.scrollTo(lastMsg.id, anchor: .bottom)
                        }
                    }
                    // Clear badge count when opening chat
                    UIApplication.shared.applicationIconBadgeNumber = 0
                    UNUserNotificationCenter.current().removeAllDeliveredNotifications()
                    store.listenToTeamMembers()
                }
            }
            HStack {
                if let pendingName = pendingAttachmentName {
                    HStack(spacing: 6) {
                        Image(systemName: pendingAttachmentKind == .image ? "photo" : "doc")
                            .foregroundColor(.secondary)
                        Text(pendingName)
                            .font(.caption)
                            .lineLimit(1)
                        Button(role: .destructive) {
                            clearPendingAttachment()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                    }
                }
            }
            .padding(.horizontal)
            HStack(spacing: 8) {
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Image(systemName: "photo.on.rectangle")
                }
                .buttonStyle(.plain)
                .disabled(!canSendMessages || isUploadingAttachment || messageToEdit != nil)
                Button {
                    showFilePicker = true
                } label: {
                    Image(systemName: "paperclip")
                }
                .buttonStyle(.plain)
                .disabled(!canSendMessages || isUploadingAttachment || messageToEdit != nil)
                TextField("Message", text: $newMessage)
                    .textFieldStyle(.roundedBorder)
                if messageToEdit != nil {
                    Button("Cancel") {
                        messageToEdit = nil
                        newMessage = ""
                    }
                    .buttonStyle(.borderless)
                }
                Button(messageToEdit == nil ? "Send" : "Save") {
                    sendMessage()
                }
                .disabled(!canSendMessages || isUploadingAttachment || newMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
            if isUploadingAttachment {
                ProgressView(value: uploadProgress)
                    .padding(.horizontal)
            }
            if let attachmentError = attachmentError {
                Text(attachmentError)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }
            if !canSendMessages {
                Text("Read-only channel. Only admins can post.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 6)
            }
        }
        .navigationTitle(channel.name)
        .toolbar {
            if isAdmin {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                }
            }
        }
        .onChange(of: selectedPhotoItem) { newValue in
            guard let newValue else { return }
            Task { await loadPhotoAttachment(from: newValue) }
        }
        .onReceive(store.$channels) { updated in
            if let refreshed = updated.first(where: { $0.id == channel.id }) {
                channel = refreshed
            }
        }
        .alert("Delete message?", isPresented: Binding(get: { messageToDelete != nil }, set: { if !$0 { messageToDelete = nil } })) {
            Button("Delete", role: .destructive) {
                if let msg = messageToDelete {
                    deleteMessage(msg)
                }
                messageToDelete = nil
            }
            Button("Cancel", role: .cancel) { messageToDelete = nil }
        } message: {
            Text("This action cannot be undone.")
        }
        .sheet(isPresented: $showSettings) {
            ChannelSettingsView(channel: $channel)
        }
        .sheet(isPresented: $showFilePicker) {
            ChatFilePicker { url in
                setPendingAttachment(url: url, kind: .file)
            }
        }
    }

    // MARK: - Send message
    func sendMessage() {
        guard let author = store.user?.email else { return }
        let trimmedText = newMessage.trimmingCharacters(in: .whitespacesAndNewlines)

        if let editingMessage = messageToEdit {
            guard !trimmedText.isEmpty else { return }
            updateMessage(editingMessage, newText: trimmedText)
            messageToEdit = nil
            newMessage = ""
            return
        }

        if let pendingName = pendingAttachmentName,
           let pendingKind = pendingAttachmentKind {
            isUploadingAttachment = true
            attachmentError = nil
            let upload: (@escaping (Result<String, Error>) -> Void) -> Void
            if pendingKind == .image, let data = pendingAttachmentData {
                if data.count > maxAttachmentBytes {
                    isUploadingAttachment = false
                    attachmentError = "Attachment is too large. Max size is 100 MB."
                    return
                }
                upload = { completion in
                    uploadChatImage(data: data, filename: pendingName, completion: completion)
                }
            } else if let pendingURL = pendingAttachmentURL {
                if let size = try? pendingURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                   size > maxAttachmentBytes {
                    isUploadingAttachment = false
                    attachmentError = "Attachment is too large. Max size is 100 MB."
                    return
                }
                upload = { completion in
                    uploadChatAttachment(localURL: pendingURL, filename: pendingName, completion: completion)
                }
            } else {
                isUploadingAttachment = false
                attachmentError = "Attachment upload failed: Missing file data."
                return
            }

            upload { result in
                DispatchQueue.main.async {
                    isUploadingAttachment = false
                    switch result {
                    case .success(let urlString):
                        let msg = ChatMessage(
                            author: author,
                            text: trimmedText,
                            timestamp: Date(),
                            editedAt: nil,
                            attachmentURL: urlString,
                            attachmentName: pendingName,
                            attachmentKind: pendingKind
                        )
                        appendMessage(msg) { result in
                            switch result {
                            case .success:
                                newMessage = ""
                                clearPendingAttachment()
                            case .failure(let error):
                                attachmentError = "Message send failed: \(error.localizedDescription)"
                            }
                        }
                    case .failure(let error):
                        attachmentError = "Attachment upload failed: \(error.localizedDescription)"
                    }
                }
            }
            return
        }

        guard !trimmedText.isEmpty else { return }
        let msg = ChatMessage(author: author, text: trimmedText, timestamp: Date())
        appendMessage(msg) { result in
            switch result {
            case .success:
                newMessage = ""
            case .failure(let error):
                attachmentError = "Message send failed: \(error.localizedDescription)"
            }
        }
    }

    private func appendMessage(_ msg: ChatMessage, completion: @escaping (Result<Void, Error>) -> Void) {
        let updatedMessages = channel.messages + [msg]
        persistMessages(updatedMessages) { result in
            switch result {
            case .success:
                channel.messages = updatedMessages
                if let idx = store.channels.firstIndex(where: { $0.id == channel.id }) {
                    store.channels[idx] = channel
                }
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private func updateMessage(_ msg: ChatMessage, newText: String) {
        guard let index = channel.messages.firstIndex(where: { $0.id == msg.id }) else { return }
        var updatedMessages = channel.messages
        updatedMessages[index].text = newText
        updatedMessages[index].editedAt = Date()
        persistMessages(updatedMessages) { result in
            switch result {
            case .success:
                channel.messages = updatedMessages
                if let idx = store.channels.firstIndex(where: { $0.id == channel.id }) {
                    store.channels[idx] = channel
                }
            case .failure(let error):
                attachmentError = "Update failed: \(error.localizedDescription)"
            }
        }
    }

    private func deleteMessage(_ msg: ChatMessage) {
        let updatedMessages = channel.messages.filter { $0.id != msg.id }
        persistMessages(updatedMessages) { result in
            switch result {
            case .success:
                channel.messages = updatedMessages
                if let idx = store.channels.firstIndex(where: { $0.id == channel.id }) {
                    store.channels[idx] = channel
                }
            case .failure(let error):
                attachmentError = "Delete failed: \(error.localizedDescription)"
            }
        }
    }

    private func canEdit(_ msg: ChatMessage) -> Bool {
        guard let email = store.user?.email else { return false }
        return isAdmin || msg.author == email
    }

    private func setPendingAttachment(url: URL, kind: ChatAttachmentKind) {
        pendingAttachmentURL = url
        pendingAttachmentName = url.lastPathComponent
        pendingAttachmentKind = kind
    }

    private func clearPendingAttachment() {
        pendingAttachmentURL = nil
        pendingAttachmentName = nil
        pendingAttachmentKind = nil
        pendingAttachmentData = nil
    }

    private func persistMessages(_ messages: [ChatMessage], completion: @escaping (Result<Void, Error>) -> Void) {
        let payload = messages.map(messageDictionary)
        store.db.collection("channels").document(channel.id).setData(["messages": payload], merge: true) { error in
            if let error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }

    private func messageDictionary(_ msg: ChatMessage) -> [String: Any] {
        var dict: [String: Any] = [
            "id": msg.id,
            "author": msg.author,
            "text": msg.text,
            "timestamp": Timestamp(date: msg.timestamp)
        ]
        if let editedAt = msg.editedAt {
            dict["editedAt"] = Timestamp(date: editedAt)
        }
        if let attachmentURL = msg.attachmentURL, !attachmentURL.isEmpty {
            dict["attachmentURL"] = attachmentURL
        }
        if let attachmentName = msg.attachmentName, !attachmentName.isEmpty {
            dict["attachmentName"] = attachmentName
        }
        if let attachmentKind = msg.attachmentKind {
            dict["attachmentKind"] = attachmentKind.rawValue
        }
        return dict
    }

    private func loadPhotoAttachment(from item: PhotosPickerItem) async {
        if let data = try? await item.loadTransferable(type: Data.self) {
            if data.count > maxAttachmentBytes {
                DispatchQueue.main.async {
                    attachmentError = "Attachment is too large. Max size is 100 MB."
                }
                return
            }
            DispatchQueue.main.async {
                pendingAttachmentData = data
                pendingAttachmentName = "Photo.jpg"
                pendingAttachmentKind = .image
            }
        } else {
            DispatchQueue.main.async {
                attachmentError = "Unable to prepare image attachment."
            }
        }
    }

    private func uploadChatAttachment(localURL: URL, filename: String, completion: @escaping (Result<String, Error>) -> Void) {
        let safeName = filename.replacingOccurrences(of: " ", with: "_")
        let path = "chatAttachments/\(channel.id)/\(UUID().uuidString)-\(safeName)"
        let storageRef = Storage.storage().reference().child(path)
        let uploadTask = storageRef.putFile(from: localURL, metadata: nil)

        uploadTask.observe(.progress) { snapshot in
            if let fraction = snapshot.progress?.fractionCompleted {
                uploadProgress = fraction
            }
        }

        uploadTask.observe(.success) { _ in
            storageRef.downloadURL { url, error in
                if let url = url { completion(.success(url.absoluteString)) }
                else if let error = error { completion(.failure(error)) }
            }
        }

        uploadTask.observe(.failure) { snapshot in
            if let error = snapshot.error {
                completion(.failure(error))
            }
        }
    }

    private func uploadChatImage(data: Data, filename: String, completion: @escaping (Result<String, Error>) -> Void) {
        let safeName = filename.replacingOccurrences(of: " ", with: "_")
        let path = "chatAttachments/\(channel.id)/\(UUID().uuidString)-\(safeName)"
        let storageRef = Storage.storage().reference().child(path)
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        let uploadTask = storageRef.putData(data, metadata: metadata)

        uploadTask.observe(.progress) { snapshot in
            if let fraction = snapshot.progress?.fractionCompleted {
                uploadProgress = fraction
            }
        }

        uploadTask.observe(.success) { _ in
            storageRef.downloadURL { url, error in
                if let url = url { completion(.success(url.absoluteString)) }
                else if let error = error { completion(.failure(error)) }
            }
        }

        uploadTask.observe(.failure) { snapshot in
            if let error = snapshot.error {
                completion(.failure(error))
            }
        }
    }

    // MARK: - Display name helper
    func userName(for email: String) -> String {
        if let current = store.user, current.email == email {
            if !current.displayName.trimmingCharacters(in: .whitespaces).isEmpty {
                return current.displayName
            }
        }
        if let member = store.teamMembers.first(where: { $0.email == email }) {
            if !member.displayName.trimmingCharacters(in: .whitespaces).isEmpty {
                return member.displayName
            }
        }
        // fallback: show first part of email
        return email.components(separatedBy: "@").first ?? email
    }

    private func userTags(for email: String) -> [String] {
        if let current = store.user, current.email == email {
            var tags: [String] = []
            if current.isAdmin { tags.append("ADMIN") }
            let campus = current.assignedCampus.trimmingCharacters(in: .whitespacesAndNewlines)
            if !campus.isEmpty { tags.append(campus) }
            return tags
        }
        guard let member = store.teamMembers.first(where: { $0.email == email }) else { return [] }
        var tags: [String] = []
        if member.isAdmin { tags.append("ADMIN") }
        let campus = member.assignedCampus.trimmingCharacters(in: .whitespacesAndNewlines)
        if !campus.isEmpty { tags.append(campus) }
        return tags
    }

    @ViewBuilder
    private func attachmentView(for msg: ChatMessage) -> some View {
        if let urlString = msg.attachmentURL,
           let url = URL(string: urlString) {
            if msg.attachmentKind == .image {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    case .failure:
                        Text("Image failed to load")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    @unknown default:
                        EmptyView()
                    }
                }
            } else {
                Link(destination: url) {
                    HStack(spacing: 6) {
                        Image(systemName: "doc")
                        Text(msg.attachmentName ?? "Attachment")
                            .lineLimit(1)
                    }
                    .font(.caption)
                }
            }
        }
    }
}

struct ChannelSettingsView: View {
    @EnvironmentObject var store: ProdConnectStore
    @Environment(\.dismiss) var dismiss
    @Binding var channel: ChatChannel

    var body: some View {
        NavigationStack {
            Form {
                Section("Permissions") {
                    Toggle("Read-only for non-admins", isOn: $channel.isReadOnly)
                    Toggle("Hidden from non-admins", isOn: $channel.isHidden)
                }
                Section("Read-only users") {
                    ForEach(store.teamMembers) { member in
                        Toggle(isOn: Binding(get: {
                            channel.readOnlyUserEmails.contains(member.email)
                        }, set: { isOn in
                            if isOn {
                                if !channel.readOnlyUserEmails.contains(member.email) {
                                    channel.readOnlyUserEmails.append(member.email)
                                }
                            } else {
                                channel.readOnlyUserEmails.removeAll { $0 == member.email }
                            }
                        })) {
                            Text(member.displayName)
                        }
                    }
                }
                Section("Hidden users") {
                    ForEach(store.teamMembers) { member in
                        Toggle(isOn: Binding(get: {
                            channel.hiddenUserEmails.contains(member.email)
                        }, set: { isOn in
                            if isOn {
                                if !channel.hiddenUserEmails.contains(member.email) {
                                    channel.hiddenUserEmails.append(member.email)
                                }
                            } else {
                                channel.hiddenUserEmails.removeAll { $0 == member.email }
                            }
                        })) {
                            Text(member.displayName)
                        }
                    }
                }
                Section {
                    Button("Save") {
                        store.saveChannel(channel)
                        dismiss()
                    }
                }
            }
            .navigationTitle("Channel Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

struct ChatFilePicker: UIViewControllerRepresentable {
    var onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.item], asCopy: true)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onPick: (URL) -> Void

        init(onPick: @escaping (URL) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPick(url)
        }
    }
}



// MARK: - Create Channel View
struct CreateChannelView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var store: ProdConnectStore
    @State private var name = ""
    @State private var isReadOnly = false
    @State private var isHidden = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Channel Name") {
                    TextField("Enter name", text: $name)
                }
                Section("Permissions") {
                    Toggle("Read-only for non-admins", isOn: $isReadOnly)
                    Toggle("Hidden from non-admins", isOn: $isHidden)
                }
                Section {
                    Button("Create") {
                        let position = store.nextChannelPosition()
                        let newChannel = ChatChannel(
                            name: name.trimmingCharacters(in: .whitespaces),
                            teamCode: store.teamCode ?? "",
                            position: position,
                            isReadOnly: isReadOnly,
                            isHidden: isHidden
                        )
                        store.saveChannel(newChannel)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .navigationTitle("New Channel")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}


// MARK: - Helpers / Preview

#if DEBUG
struct ProdConnect_Previews: PreviewProvider {
    static var previews: some View {
        let store = ProdConnectStore.shared
        MainTabView().environmentObject(store)
    }
}

#endif


struct PatchRow: Identifiable, Codable {
    var id: String = UUID().uuidString
    var name: String
    var input: String
    var output: String
    var teamCode: String
    var category: String
    var campus: String
    var room: String
    var channelCount: Int?
    var position: Int = 0
}

struct UserProfile: Identifiable, Codable {
    var id: String = UUID().uuidString
    var displayName: String
    var email: String
    var teamCode: String?
    var isAdmin: Bool = false
    var isOwner: Bool = false
    var subscriptionTier: String = "free"
    var assignedCampus: String = ""
    var canEditPatchsheet: Bool = false
    var canEditTraining: Bool = false
    var canEditGear: Bool = false
    var canEditIdeas: Bool = false
    var canEditChecklists: Bool = false
    var canSeeChat: Bool = true
    var canSeePatchsheet: Bool = true
    var canSeeTraining: Bool = true
    var canSeeGear: Bool = true
    var canSeeIdeas: Bool = true
    var canSeeChecklists: Bool = true
    // Add other fields as needed

    enum Role {
        case free
        case basic
        case premium
        case admin
    }

    var role: Role {
        if isAdmin { return .admin }
        switch subscriptionTier.lowercased() {
        case "premium": return .premium
        case "basic": return .basic
        default: return .free
        }
    }

    var hasCampusRoomFeatures: Bool {
        role == .premium || role == .admin
    }
}

struct TrainingLesson: Identifiable, Codable {
    var id: String = UUID().uuidString
    var title: String
    var category: String
    var teamCode: String
    var durationSeconds: Int = 0
    var urlString: String? = nil
    var isCompleted: Bool = false
}

struct ChecklistItem: Identifiable, Codable {
    var id: String = UUID().uuidString
    var text: String
    var isDone: Bool = false
    var completedAt: Date? = nil
    var completedBy: String? = nil
}

struct ChecklistTemplate: Identifiable, Codable {
    var id: String = UUID().uuidString
    var title: String
    var teamCode: String
    var items: [ChecklistItem] = []
    var createdBy: String? = nil
    var dueDate: Date? = nil
    var completedAt: Date? = nil
    var completedBy: String? = nil
}

struct IdeaCard: Identifiable, Codable {
    var id: String = UUID().uuidString
    var title: String
    var detail: String = ""
    var tags: [String] = []
    var teamCode: String
    var createdBy: String? = nil
    var implemented: Bool = false
    var completedAt: Date? = nil
    var likedBy: [String] = []
}

struct ChatChannel: Identifiable, Codable {
    var id: String = UUID().uuidString
    var name: String
    var teamCode: String
    var position: Int = 0
    var isReadOnly: Bool = false
    var isHidden: Bool = false
    var readOnlyUserEmails: [String] = []
    var hiddenUserEmails: [String] = []
    var messages: [ChatMessage] = []
}

struct ChatMessage: Identifiable, Codable {
    var id: String = UUID().uuidString
    var author: String
    var text: String
    var timestamp: Date
    var editedAt: Date? = nil
    var attachmentURL: String? = nil
    var attachmentName: String? = nil
    var attachmentKind: ChatAttachmentKind? = nil
}

enum ChatAttachmentKind: String, Codable {
    case image
    case file
}

// MARK: - Views


// MARK: - View Stubs for Missing Views

struct ShareSheet: UIViewControllerRepresentable {
    var items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct MainTabView: View {
    // Restored ChatChannelListView wrapper
    struct ChatChannelListView: View {
        @EnvironmentObject var store: ProdConnectStore
        var body: some View {
            NavigationView {
                List(store.channels) { channel in
                    NavigationLink(destination: ChatChannelDetailView(channel: channel)) {
                        Text(channel.name)
                    }
                }
                .navigationTitle("Channels")
            }
        }
    }

    // Restored PatchsheetView with Audio, Video, and Lighting tabs and text fields
    struct PatchsheetView: View {
        @EnvironmentObject var store: ProdConnectStore
        @State private var selectedTab = 0
        @State private var field1 = ""
        @State private var field2 = ""
        @State private var field3 = ""
        @State private var selectedCampus: String = ""
        private let categories = ["Audio", "Video", "Lighting"]
        
        private var assignedCampus: String {
            store.user?.assignedCampus.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        
        private var canSelectCampus: Bool {
            guard let user = store.user else { return false }
            let isPremium = user.subscriptionTier.lowercased() == "premium"
            return isPremium && (user.isAdmin || user.isOwner) && assignedCampus.isEmpty
        }
        
        private var effectiveCampusFilter: String {
            if !assignedCampus.isEmpty { return assignedCampus }
            return selectedCampus
        }

        var body: some View {
            NavigationView {
                VStack(spacing: 0) {
                    HStack {
                        Picker("Category", selection: $selectedTab) {
                            ForEach(0..<categories.count, id: \ .self) { idx in
                                Text(categories[idx])
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        Spacer()
                        if canSelectCampus {
                            Menu {
                                ForEach(store.locations, id: \.self) { campus in
                                    Button(campus) { selectedCampus = campus }
                                }
                            } label: {
                                HStack {
                                    Text(selectedCampus.isEmpty ? "Campus" : selectedCampus)
                                    Image(systemName: "chevron.down")
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.blue.opacity(0.2))
                                .cornerRadius(8)
                            }
                        } else if !assignedCampus.isEmpty {
                            HStack {
                                Image(systemName: "building.2")
                                Text(assignedCampus)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.blue.opacity(0.2))
                            .cornerRadius(8)
                        }
                    }
                    .padding([.horizontal, .top])
                    List(filteredPatches) { patch in
                        NavigationLink(destination: PatchDetailView(patch: patch)) {
                            VStack(alignment: .leading) {
                                Text(patch.name).font(.headline)
                                HStack {
                                    Text("Input: \(patch.input)")
                                    Text("Output: \(patch.output)")
                                }.font(.caption)
                                if !patch.campus.isEmpty {
                                    Text("Campus: \(patch.campus)").font(.caption2)
                                }
                                if !patch.room.isEmpty {
                                    Text("Room: \(patch.room)").font(.caption2)
                                }
                            }
                        }
                    }
                    Spacer()
                    VStack(spacing: 8) {
                        TextField(categories[selectedTab] == "Lighting" ? "Fixture" : "Name", text: $field1)
                            .textFieldStyle(RoundedBorderTextFieldStyle())

                        HStack(spacing: 8) {
                            TextField(
                                categories[selectedTab] == "Video" ? "Source" : (categories[selectedTab] == "Lighting" ? "DMX Channel" : "Input"),
                                text: $field2
                            )
                            TextField(
                                categories[selectedTab] == "Video" ? "Destination" : (categories[selectedTab] == "Lighting" ? "Channel Count" : "Output"),
                                text: $field3
                            )
                        }
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    Button {
                        let patch = PatchRow(
                            name: categories[selectedTab] == "Lighting" ? field1 : field1,
                            input: categories[selectedTab] == "Lighting" ? field2 : (categories[selectedTab] == "Video" ? field2 : field2),
                            output: categories[selectedTab] == "Lighting" ? field3 : (categories[selectedTab] == "Video" ? field3 : field3),
                            teamCode: store.teamCode ?? "",
                            category: categories[selectedTab],
                            campus: effectiveCampusFilter,
                            room: ""
                        )
                        store.savePatch(patch)
                        field1 = ""
                        field2 = ""
                        field3 = ""
                    } label: {
                        Label("Add Patch", systemImage: "plus.rectangle.on.rectangle")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!addPatchEnabled)
                    .padding(.horizontal)
                    .padding(.bottom, 16)
                }
                .navigationTitle("Patchsheet")
            }
        }
        private var addPatchEnabled: Bool {
            if categories[selectedTab] == "Audio" {
                return !field1.isEmpty && (!field2.isEmpty || !field3.isEmpty)
            } else if categories[selectedTab] == "Video" {
                return !field1.isEmpty && (!field2.isEmpty || !field3.isEmpty)
            } else {
                return !field1.isEmpty && (!field2.isEmpty || !field3.isEmpty)
            }
        }
            // Fix Chat Add Channel button
            struct LegacyChatListView: View {
                @EnvironmentObject var store: ProdConnectStore
                @State private var newChannelName = ""
                var body: some View {
                    NavigationView {
                        VStack {
                            List(store.channels) { channel in
                                NavigationLink(destination: ChatChannelDetailView(channel: channel)) {
                                    Text(channel.name)
                                }
                            }
                            HStack {
                                TextField("New Channel Name", text: $newChannelName)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                Button("Add Channel") {
                                    let channel = ChatChannel(id: UUID().uuidString, name: newChannelName, teamCode: store.teamCode ?? "")
                                    store.saveChannel(channel)
                                    newChannelName = ""
                                }.disabled(newChannelName.isEmpty)
                            }
                            .padding()
                        }
                        .navigationTitle("Channels")
                    }
                }
            }
            // Restore Export, Merge, Add buttons for Gear
            struct LegacyGearTabView: View {
                @EnvironmentObject var store: ProdConnectStore
                @State private var showAddGear = false
                @State private var exportURL: URL? = nil
                @State private var isExporting = false
                @State private var mergePreview: [[GearItem]] = []
                @State private var showMergeConfirm = false
                @State private var isMerging = false
                @State private var showMergeResult = false
                @State private var mergeResultMessage: String = ""
                @State private var searchText: String = ""
                @State private var selectedCategory: String? = nil
                @State private var selectedStatus: GearItem.GearStatus? = nil
                @State private var selectedLocation: String? = nil
                @State private var allGearLocations: [String] = []
                @State private var availableCategories: [String] = []
                @State private var statusColor: (GearItem.GearStatus) -> Color = { _ in .gray }

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
                    return result
                }

                private func exportGear() {
                    guard !filteredGear.isEmpty else { return }
                    let header = "Name,Category,Status,Location,Notes\n"
                    let rows = filteredGear.map { item in
                        let notes = item.maintenanceNotes.replacingOccurrences(of: ",", with: ";")
                        return "\(item.name),\(item.category),\(item.status.rawValue),\(item.location),\(notes)"
                    }
                    let csv = header + rows.joined(separator: "\n")
                    let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("GearExport.csv")
                    do {
                        try csv.write(to: fileURL, atomically: true, encoding: .utf8)
                        exportURL = fileURL
                    } catch {
                        // keep UI responsive even if export fails
                    }
                    isExporting = false
                }

                private func findDuplicateGearGroups() -> [[GearItem]] {
                    let grouped = Dictionary(grouping: store.gear) { item in
                        "\(item.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines))|\(item.serialNumber.lowercased().trimmingCharacters(in: .whitespacesAndNewlines))"
                    }
                    return grouped.values.filter { $0.count > 1 }
                }

                var body: some View {
                    NavigationStack {
                        VStack(spacing: 0) {
                            SearchBar(text: $searchText)
                            HStack(spacing: 12) {
                                Menu {
                                    Button("Clear", action: { selectedCategory = nil })
                                    Divider()
                                    ForEach(availableCategories, id: \ .self) { category in
                                        Button(category) { selectedCategory = category }
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "line.3.horizontal.decrease.circle")
                                        Text(selectedCategory ?? "Category").lineLimit(1)
                                    }
                                    .font(.caption)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(selectedCategory != nil ? Color.blue : Color.gray.opacity(0.3))
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                                }
                                Menu {
                                    Button("Clear", action: { selectedStatus = nil })
                                    Divider()
                                    ForEach(GearItem.GearStatus.allCases, id: \ .self) { status in
                                        Button(status.rawValue) { selectedStatus = status }
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "checkmark.circle")
                                        Text(selectedStatus?.rawValue ?? "Status").lineLimit(1)
                                    }
                                    .font(.caption)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(selectedStatus != nil ? Color.blue : Color.gray.opacity(0.3))
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                                }
                                if !allGearLocations.isEmpty {
                                    Menu {
                                        Button("Clear", action: { selectedLocation = nil })
                                        Divider()
                                        ForEach(allGearLocations, id: \ .self) { location in
                                            Button(location) { selectedLocation = location }
                                        }
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "mappin.circle")
                                            Text(selectedLocation ?? "Location").lineLimit(1)
                                        }
                                        .font(.caption)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(selectedLocation != nil ? Color.blue : Color.gray.opacity(0.3))
                                        .foregroundColor(.white)
                                        .cornerRadius(8)
                                    }
                                }
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                            List {
                                ForEach(filteredGear) { item in
                                    NavigationLink(destination: GearDetailView(item: item).environmentObject(store)) {
                                        HStack {
                                            VStack(alignment: .leading) {
                                                Text(item.name).font(.headline)
                                                Text(item.category).font(.caption).foregroundColor(.secondary)
                                                if !item.location.isEmpty {
                                                    Text(item.location).font(.caption2).foregroundColor(.gray)
                                                }
                                            }
                                            Spacer()
                                            Text(item.status.rawValue)
                                                .font(.caption2)
                                                .padding(6)
                                                .background(statusColor(item.status).opacity(0.2))
                                                .foregroundColor(statusColor(item.status))
                                                .cornerRadius(6)
                                        }
                                    }
                                }
                            }
                            .navigationTitle("Gear")
                            .toolbar {
                                ToolbarItemGroup(placement: .navigationBarTrailing) {
                                    Button(action: exportGear) {
                                        Label("Share", systemImage: "square.and.arrow.up")
                                    }.disabled(isExporting)
                                    Button(action: { showAddGear = true }) {
                                        Label("Add", systemImage: "plus")
                                    }
                                    Button(action: {
                                        mergePreview = findDuplicateGearGroups()
                                        showMergeConfirm = true
                                    }) {
                                        Label("Merge", systemImage: "arrow.triangle.merge")
                                    }.disabled(isMerging)
                                }
                            }
                        }
                    }
                    .sheet(isPresented: $showAddGear) {
                        AddGearView { newItem in
                            store.saveGear(newItem)
                            showAddGear = false
                        }
                    }
                    .sheet(isPresented: Binding(get: { exportURL != nil }, set: { if !$0 { exportURL = nil } })) {
                        if let url = exportURL {
                            ShareSheet(items: [url])
                        }
                    }
                }
                // ...existing helper functions for export, merge, filter, etc...
            }
            // Add Video button for Training
            struct LegacyTrainingListView: View {
                @EnvironmentObject var store: ProdConnectStore
                @State private var showAdd = false
                @State private var showAddVideo = false
                @State private var selectedFilter = "All"
                @State private var searchText = ""
                let categories = ["All", "Audio", "Video", "Lighting", "Misc"]
                var body: some View {
                    VStack {
                        SearchBar(text: $searchText)
                        Picker("Category", selection: $selectedFilter) {
                            ForEach(categories, id: \ .self) { Text($0) }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .padding(.horizontal)
                        List {
                            ForEach(filteredLessons) { lesson in
                                NavigationLink(destination: TrainingDetailView(lesson: lesson)) {
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(lesson.title).font(.headline)
                                            Text(lesson.category).font(.caption).foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        if lesson.isCompleted {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.green)
                                        }
                                    }
                                }
                            }
                        }
                        HStack {
                            Button("Add Training") { showAdd = true }
                            Button("Add Video") { showAddVideo = true }
                        }
                        .padding()
                    }
                    .navigationTitle("Training")
                    .sheet(isPresented: $showAdd) {
                        AddTrainingView { new in
                            store.saveLesson(new)
                        }
                    }
                    .sheet(isPresented: $showAddVideo) {
                        AddTrainingView { new in
                            store.saveLesson(new)
                        }
                    }
                }
                private var filteredLessons: [TrainingLesson] {
                    var lessons = store.lessons
                    if selectedFilter != "All" {
                        lessons = lessons.filter { $0.category == selectedFilter }
                    }
                    if !searchText.isEmpty {
                        lessons = lessons.filter { $0.title.localizedCaseInsensitiveContains(searchText) || $0.category.localizedCaseInsensitiveContains(searchText) }
                    }
                    return lessons
            }
        }
        private var filteredPatches: [PatchRow] {
            store.patchsheet.filter { $0.category == categories[selectedTab] && (effectiveCampusFilter.isEmpty || $0.campus == effectiveCampusFilter) }
        }
        struct PatchDetailView: View {
            var patch: PatchRow
            var body: some View {
                Form {
                    Section(header: Text("Patch Info")) {
                        TextField("Name", text: .constant(patch.name)).disabled(true)
                        TextField("Input", text: .constant(patch.input)).disabled(true)
                        TextField("Output", text: .constant(patch.output)).disabled(true)
                        TextField("Campus", text: .constant(patch.campus)).disabled(true)
                        TextField("Room", text: .constant(patch.room)).disabled(true)
                    }
                }
                .navigationTitle(patch.name)
            }
        }
    }
    var body: some View {
        TabView {
            ChatListView()
                .tabItem {
                    Label("Chat", systemImage: "message")
                }
            PatchsheetView()
                .tabItem {
                    Label("Patchsheet", systemImage: "square.grid.3x2")
                }
            TrainingListView()
                .tabItem {
                    Label("Training", systemImage: "graduationcap")
                }
            GearTabView()
                .tabItem {
                    Label("Gear", systemImage: "shippingbox")
                }
            MoreTabView()
                .tabItem {
                    Label("More", systemImage: "ellipsis")
                }
        }
    }
}

struct MoreTabView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    ChecklistsListView()
                } label: {
                    Text("Checklist")
                }
                NavigationLink {
                    IdeasListView()
                } label: {
                    Text("Ideas")
                }
                NavigationLink {
                    CustomizeView()
                } label: {
                    Text("Customize")
                }
                NavigationLink {
                    AccountView()
                } label: {
                    Text("Account")
                }
                NavigationLink {
                    UsersView()
                } label: {
                    Text("Users")
                }
            }
            .navigationTitle("More")
        }
    }
}


struct YouTubeWebView: UIViewRepresentable {
    var urlString: String

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        if #available(iOS 10.0, *) {
            config.mediaTypesRequiringUserActionForPlayback = []
        }

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.navigationDelegate = context.coordinator
        loadVideo(into: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        loadVideo(into: webView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private func loadVideo(into webView: WKWebView) {
        guard let videoID = YouTubeURLHelper.extractVideoID(from: urlString) else {
            let html = """
            <html><body style="margin:0;background:#000;color:#fff;font-family:-apple-system">
            <div style="padding:16px">Invalid YouTube URL</div>
            </body></html>
            """
            webView.loadHTMLString(html, baseURL: nil)
            return
        }

        let html = """
        <!doctype html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
          <style>
            html, body { margin:0; padding:0; background:#000; height:100%; overflow:hidden; }
            iframe { position:absolute; inset:0; width:100%; height:100%; border:0; }
          </style>
        </head>
        <body>
          <iframe
            src="https://www.youtube.com/embed/\(videoID)?playsinline=1&rel=0&modestbranding=1"
            allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"
            allowfullscreen>
          </iframe>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: URL(string: "https://www.youtube.com"))
    }

    final class Coordinator: NSObject, WKNavigationDelegate {}
}

struct InAppSafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.preferredControlTintColor = .systemBlue
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

enum YouTubeURLHelper {
    static func extractVideoID(from value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let components = URLComponents(string: trimmed) else { return nil }
        let host = components.host?.lowercased() ?? ""

        if host.contains("youtu.be") {
            let id = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return sanitizeVideoID(id)
        }

        if host.contains("youtube.com") {
            if let videoID = components.queryItems?.first(where: { $0.name == "v" })?.value {
                return sanitizeVideoID(videoID)
            }
            let parts = components.path.split(separator: "/")
            if let embedIndex = parts.firstIndex(of: "embed"), parts.indices.contains(embedIndex + 1) {
                return sanitizeVideoID(String(parts[embedIndex + 1]))
            }
            if let shortsIndex = parts.firstIndex(of: "shorts"), parts.indices.contains(shortsIndex + 1) {
                return sanitizeVideoID(String(parts[shortsIndex + 1]))
            }
        }

        return nil
    }

    static func watchURL(from value: String) -> URL? {
        guard let id = extractVideoID(from: value) else { return nil }
        return URL(string: "https://www.youtube.com/watch?v=\(id)")
    }

    static func normalizedWatchURLString(from value: String) -> String? {
        watchURL(from: value)?.absoluteString
    }

    private static func sanitizeVideoID(_ value: String) -> String? {
        let id = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return nil }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
        guard id.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        guard id.count >= 10 && id.count <= 15 else { return nil }
        return id
    }
}

private extension TrainingDetailView {
    func isYouTubeURL(_ value: String) -> Bool {
        value.contains("youtube.com") || value.contains("youtu.be")
    }
}

private extension UIApplication {
    func endEditing() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
