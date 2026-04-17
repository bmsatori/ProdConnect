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
import UniformTypeIdentifiers
import OneSignalFramework
import WebKit
import SafariServices
import AVFoundation
import Vision

private func currentCurrencyIdentifier() -> String {
    if #available(iOS 16.0, macOS 13.0, *) {
        return Locale.current.currency?.identifier ?? "USD"
    } else {
        return Locale.current.currencyCode ?? "USD"
    }
}

private func jsonSafeFirestoreValue(_ value: Any) -> Any {
    switch value {
    case let timestamp as Timestamp:
        return timestamp.dateValue().timeIntervalSinceReferenceDate
    case let date as Date:
        return date.timeIntervalSinceReferenceDate
    case let dict as [String: Any]:
        return dict.mapValues { jsonSafeFirestoreValue($0) }
    case let array as [Any]:
        return array.map { jsonSafeFirestoreValue($0) }
    default:
        return value
    }
}

private func decodeFirestoreDocument<T: Decodable>(_ data: [String: Any], as type: T.Type) -> T? {
    do {
        let safeData = jsonSafeFirestoreValue(data)
        guard JSONSerialization.isValidJSONObject(safeData) else { return nil }
        let json = try JSONSerialization.data(withJSONObject: safeData, options: [])
        return try JSONDecoder().decode(type, from: json)
    } catch {
        return nil
    }
}

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
                    TextField("Search assets...", text: $text)
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
            .navigationTitle("Assets")
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
            AddGearView { _ in
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
    @State private var selectedCategory: String? = nil
    @State private var selectedStatus: GearItem.GearStatus? = nil
    @State private var selectedLocation: String? = nil
    @State private var showAddGear = false
    @State private var exportURL: URL?
    @State private var isExporting = false
    @State private var showMergeConfirm = false
    @State private var isMerging = false
    @State private var mergeResultMessage = ""
    @State private var showMergeResult = false
    @State private var duplicateGearGroupCount = 0
    @State private var showSerialScanner = false
    @State private var isRecognizingSerial = false
    @State private var showScanAlert = false
    @State private var scanAlertMessage = ""

    private var availableCategories: [String] {
        Array(Set(store.gear.map { $0.category.trimmingCharacters(in: .whitespacesAndNewlines) }))
            .filter { !$0.isEmpty }
            .sorted()
    }

    private var availableLocations: [String] {
        Array(Set(store.gear.map { $0.location.trimmingCharacters(in: .whitespacesAndNewlines) }))
            .filter { !$0.isEmpty }
            .sorted()
    }

    private var filteredGear: [GearItem] {
        var result = store.gear
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            let normalizedQuery = query.lowercased()
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(query) ||
                $0.category.localizedCaseInsensitiveContains(query) ||
                $0.location.localizedCaseInsensitiveContains(query) ||
                $0.serialNumber.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedQuery ||
                $0.assetId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedQuery
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
            "Location",
            "Campus",
            "Serial Number",
            "Asset ID",
            "Purchased From",
            "Notes"
        ].map(\.csvEscaped).joined(separator: ",")

        let rows = filteredGear.map { item in
            [
                item.name,
                item.category,
                item.status.rawValue,
                item.location,
                item.campus,
                item.serialNumber,
                item.assetId,
                item.purchasedFrom,
                item.maintenanceNotes
            ].map(\.csvEscaped).joined(separator: ",")
        }

        // Add UTF-8 BOM so Excel reliably detects UTF-8.
        let csv = "\u{FEFF}" + ([header] + rows).joined(separator: "\n")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("GearExport.csv")
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
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

    private var searchControls: some View {
        HStack(spacing: 8) {
            SearchBar(text: $searchText)

            Button(action: requestCameraAccessAndPresentScanner) {
                Image(systemName: "camera.viewfinder")
                    .font(.headline)
                    .frame(width: 40, height: 40)
                    .background(Color.blue.opacity(0.15))
                    .foregroundColor(.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .accessibilityLabel("Scan serial number")
        }
        .padding(.trailing)
    }

    private var filterBar: some View {
        HStack(spacing: 12) {
            categoryMenu
            statusMenu
            locationMenu
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var categoryMenu: some View {
        Menu {
            Button("Clear") { selectedCategory = nil }
            Divider()
            if availableCategories.isEmpty {
                Text("No categories")
            } else {
                ForEach(availableCategories, id: \.self) { category in
                    Button(category) { selectedCategory = category }
                }
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
            Button("Clear") { selectedStatus = nil }
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
            Button("Clear") { selectedLocation = nil }
            Divider()
            if availableLocations.isEmpty {
                Text("No locations")
            } else {
                ForEach(availableLocations, id: \.self) { location in
                    Button(location) { selectedLocation = location }
                }
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

    private func requestCameraAccessAndPresentScanner() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            scanAlertMessage = "Camera is not available on this device."
            showScanAlert = true
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showSerialScanner = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        showSerialScanner = true
                    } else {
                        scanAlertMessage = "Camera access is required to scan serial numbers."
                        showScanAlert = true
                    }
                }
            }
        case .denied, .restricted:
            scanAlertMessage = "Camera access is off. Enable it in Settings to scan serial numbers."
            showScanAlert = true
        @unknown default:
            scanAlertMessage = "Unable to access camera right now."
            showScanAlert = true
        }
    }

    private func recognizeSerial(from image: UIImage, scanAreaInPreview: CGRect, previewSize: CGSize) {
        guard let croppedImage = croppedImage(
            from: image,
            normalizedRectInPreview: scanAreaInPreview,
            previewSize: previewSize
        ),
              let cgImage = croppedImage.cgImage else {
            scanAlertMessage = "Could not read the captured image."
            showScanAlert = true
            return
        }

        isRecognizingSerial = true
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false

        DispatchQueue.global(qos: .userInitiated).async {
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
                let observations = request.results ?? []
                let textLines = observations.compactMap { $0.topCandidates(1).first?.string }
                let bestCandidate = bestSerialCandidate(from: textLines)

                DispatchQueue.main.async {
                    isRecognizingSerial = false
                    if let serial = bestCandidate {
                        searchText = serial
                    } else {
                        scanAlertMessage = "No serial number text was detected. Try again with better lighting."
                        showScanAlert = true
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    isRecognizingSerial = false
                    scanAlertMessage = "Scan failed: \(error.localizedDescription)"
                    showScanAlert = true
                }
            }
        }
    }

    private func normalizedImage(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        image.draw(in: CGRect(origin: .zero, size: image.size))
        let normalized = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return normalized ?? image
    }

    private func croppedImage(
        from image: UIImage,
        normalizedRectInPreview: CGRect,
        previewSize: CGSize
    ) -> UIImage? {
        let uprightImage = normalizedImage(image)
        guard let cgImage = uprightImage.cgImage else { return nil }
        guard previewSize.width > 0, previewSize.height > 0 else { return nil }

        let imageSize = CGSize(width: CGFloat(cgImage.width), height: CGFloat(cgImage.height))
        let scale = max(previewSize.width / imageSize.width, previewSize.height / imageSize.height)
        let displayedSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let displayedOrigin = CGPoint(
            x: (previewSize.width - displayedSize.width) / 2,
            y: (previewSize.height - displayedSize.height) / 2
        )

        let scanRectInPreview = CGRect(
            x: normalizedRectInPreview.origin.x * previewSize.width,
            y: normalizedRectInPreview.origin.y * previewSize.height,
            width: normalizedRectInPreview.size.width * previewSize.width,
            height: normalizedRectInPreview.size.height * previewSize.height
        )

        let scanRectInImage = CGRect(
            x: (scanRectInPreview.origin.x - displayedOrigin.x) / scale,
            y: (scanRectInPreview.origin.y - displayedOrigin.y) / scale,
            width: scanRectInPreview.size.width / scale,
            height: scanRectInPreview.size.height / scale
        )
        let fullRect = CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
        let cropRect = CGRect(
            x: scanRectInImage.origin.x,
            y: scanRectInImage.origin.y,
            width: scanRectInImage.size.width,
            height: scanRectInImage.size.height
        )
        .integral
        .intersection(fullRect)

        guard cropRect.width > 1, cropRect.height > 1,
              let cropped = cgImage.cropping(to: cropRect) else { return nil }

        return UIImage(cgImage: cropped, scale: uprightImage.scale, orientation: .up)
    }

    private func bestSerialCandidate(from lines: [String]) -> String? {
        let tokens = lines
            .flatMap { $0.components(separatedBy: .whitespacesAndNewlines) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .map { token in
                token.replacingOccurrences(
                    of: "[^A-Za-z0-9\\-_.]",
                    with: "",
                    options: .regularExpression
                )
            }
            .filter { token in
                token.count >= 4 && token.rangeOfCharacter(from: .decimalDigits) != nil
            }

        if let bestToken = tokens.max(by: { $0.count < $1.count }) {
            return bestToken
        }

        return lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && $0.rangeOfCharacter(from: .decimalDigits) != nil }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchControls
                filterBar
                List {
                    ForEach(filteredGear) { item in
                        NavigationLink(destination: GearDetailView(item: item).environmentObject(store)) {
                            gearRow(for: item)
                        }
                    }
                }
            }
            .navigationTitle("Assets")
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
                AddGearView { _ in
                    showAddGear = false
                }
                .environmentObject(store)
            }
            .sheet(isPresented: $showSerialScanner) {
                SerialCameraCaptureView { image, scanAreaInPreview, previewSize in
                    showSerialScanner = false
                    recognizeSerial(from: image, scanAreaInPreview: scanAreaInPreview, previewSize: previewSize)
                } onCancel: {
                    showSerialScanner = false
                }
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
            .alert("Assets", isPresented: $showMergeResult) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(mergeResultMessage)
            }
            .alert("Serial Scan", isPresented: $showScanAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(scanAlertMessage)
            }
            .overlay {
                if isRecognizingSerial {
                    ZStack {
                        Color.black.opacity(0.25).ignoresSafeArea()
                        ProgressView("Reading serial number...")
                            .padding(16)
                            .background(Color(.systemBackground))
                            .cornerRadius(12)
                    }
                }
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

struct SerialCameraCaptureView: UIViewControllerRepresentable {
    private let defaultScanArea = CGRect(x: 0.08, y: 0.40, width: 0.84, height: 0.20)
    let onCapture: (UIImage, CGRect, CGSize) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> ScannerHostViewController {
        ScannerHostViewController(
            scanAreaNormalized: defaultScanArea,
            onCapture: onCapture,
            onCancel: onCancel
        )
    }

    func updateUIViewController(_ uiViewController: ScannerHostViewController, context: Context) {}
}

final class ScannerHostViewController: UIViewController, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    private let scanAreaNormalized: CGRect
    private let onCapture: (UIImage, CGRect, CGSize) -> Void
    private let onCancel: () -> Void

    private let picker = UIImagePickerController()
    private let maskLayer = CAShapeLayer()
    private let boxLayer = CAShapeLayer()
    private let guideLineLayer = CAShapeLayer()
    private let instructionLabel = UILabel()
    private let captureButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)
    private var isCapturing = false

    init(
        scanAreaNormalized: CGRect,
        onCapture: @escaping (UIImage, CGRect, CGSize) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.scanAreaNormalized = scanAreaNormalized
        self.onCapture = onCapture
        self.onCancel = onCancel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.showsCameraControls = false
        picker.allowsEditing = false
        picker.delegate = self

        addChild(picker)
        picker.view.frame = view.bounds
        picker.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(picker.view)
        picker.didMove(toParent: self)

        maskLayer.fillRule = .evenOdd
        maskLayer.fillColor = UIColor.black.withAlphaComponent(0.45).cgColor
        view.layer.addSublayer(maskLayer)

        boxLayer.strokeColor = UIColor.systemYellow.cgColor
        boxLayer.fillColor = UIColor.clear.cgColor
        boxLayer.lineWidth = 2
        boxLayer.lineDashPattern = [8, 6]
        view.layer.addSublayer(boxLayer)

        guideLineLayer.strokeColor = UIColor.systemYellow.withAlphaComponent(0.9).cgColor
        guideLineLayer.lineWidth = 1.5
        view.layer.addSublayer(guideLineLayer)

        instructionLabel.text = "Align serial number inside the box"
        instructionLabel.textColor = .white
        instructionLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        instructionLabel.textAlignment = .center
        view.addSubview(instructionLabel)

        captureButton.setTitle("Capture", for: .normal)
        captureButton.setTitleColor(.black, for: .normal)
        captureButton.titleLabel?.font = .systemFont(ofSize: 18, weight: .bold)
        captureButton.backgroundColor = UIColor.white.withAlphaComponent(0.95)
        captureButton.layer.cornerRadius = 28
        captureButton.layer.borderWidth = 2
        captureButton.layer.borderColor = UIColor.black.withAlphaComponent(0.18).cgColor
        captureButton.addTarget(self, action: #selector(capturePressed), for: .touchUpInside)
        view.addSubview(captureButton)

        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.setTitleColor(.white, for: .normal)
        cancelButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        cancelButton.addTarget(self, action: #selector(cancelPressed), for: .touchUpInside)
        view.addSubview(cancelButton)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        picker.view.frame = view.bounds

        let layoutBounds = view.bounds
        let scanUIBounds = CGRect(
            x: 0,
            y: 0,
            width: layoutBounds.width,
            height: max(layoutBounds.height - 190, layoutBounds.height * 0.72)
        )
        let scanRect = CGRect(
            x: scanUIBounds.width * scanAreaNormalized.origin.x,
            y: scanUIBounds.height * scanAreaNormalized.origin.y,
            width: scanUIBounds.width * scanAreaNormalized.size.width,
            height: scanUIBounds.height * scanAreaNormalized.size.height
        )

        let outerPath = UIBezierPath(rect: scanUIBounds)
        outerPath.append(UIBezierPath(roundedRect: scanRect, cornerRadius: 14))
        maskLayer.path = outerPath.cgPath
        boxLayer.path = UIBezierPath(roundedRect: scanRect, cornerRadius: 14).cgPath

        let linePath = UIBezierPath()
        linePath.move(to: CGPoint(x: scanRect.minX + 12, y: scanRect.midY))
        linePath.addLine(to: CGPoint(x: scanRect.maxX - 12, y: scanRect.midY))
        guideLineLayer.path = linePath.cgPath

        instructionLabel.frame = CGRect(x: 24, y: scanRect.minY - 42, width: scanUIBounds.width - 48, height: 24)
        captureButton.frame = CGRect(x: (layoutBounds.width - 150) / 2, y: layoutBounds.height - 92, width: 150, height: 56)
        cancelButton.frame = CGRect(x: 18, y: 52, width: 80, height: 36)
    }

    @objc private func capturePressed() {
        guard !isCapturing else { return }
        isCapturing = true
        captureButton.isEnabled = false
        captureButton.alpha = 0.55
        picker.takePicture()
    }

    @objc private func cancelPressed() {
        onCancel()
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        onCancel()
    }

    func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]
    ) {
        isCapturing = false
        captureButton.isEnabled = true
        captureButton.alpha = 1.0
        if let image = info[.originalImage] as? UIImage {
            onCapture(image, scanAreaNormalized, view.bounds.size)
        } else {
            onCancel()
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
    @State private var lessonAssignedToCurrentUserIDs: Set<String> = []
    @State private var hasPrimedLessonAssignmentState = false
    @State private var checklistMentionedItemState: [String: Set<String>] = [:]
    @State private var hasPrimedChecklistMentionState = false
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
        AddGearView { _ in
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
            if !availableLocations.isEmpty {
                locationMenu
            }
            statusMenu
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
                    .navigationTitle("Assets")
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

    var canEditIdeas: Bool {
        guard let user = user else { return false }
        return user.isAdmin || user.isOwner || user.canEditIdeas
    }
    var canEditChecklists: Bool {
        guard let user = user else { return false }
        return user.isAdmin || user.isOwner || user.canEditChecklists
    }

    var canEditTraining: Bool {
        guard let user = user else { return false }
        return user.isAdmin || user.canEditTraining
    }

    var canSeeTrainingTab: Bool {
        guard let user = user else { return false }
        return user.isAdmin || user.isOwner || user.canSeeTraining
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
            let subscriptionTier = "free"
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
                "canEditPatchsheet": true,
                "canEditTraining": false,
                "canEditGear": true,
                "canEditIdeas": true,
                "canEditChecklists": true,
                "canSeeChat": false,
                "canSeePatchsheet": true,
                "canSeeTraining": false,
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
                        profile.canEditPatchsheet = true
                        profile.canEditTraining = false
                        profile.canEditGear = true
                        profile.canEditIdeas = true
                        profile.canEditChecklists = true
                        profile.canSeeChat = false
                        profile.canSeeTraining = false
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
        lessonAssignedToCurrentUserIDs = []
        hasPrimedLessonAssignmentState = false
        checklistMentionedItemState = [:]
        hasPrimedChecklistMentionState = false
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

            Task { @MainActor in
                do {
                    guard let data = snap.data(), var profile = decodeFirestoreDocument(data, as: UserProfile.self) else {
                        throw NSError(domain: "ProfileDecode", code: 0, userInfo: [NSLocalizedDescriptionKey: "Unable to decode user profile."])
                    }
                    if profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        profile.displayName = profile.email.components(separatedBy: "@").first ?? "New User"
                    }
                    if profile.isOwner {
                        var ownerUpdates: [String: Any] = [:]
                        if !profile.isAdmin {
                            profile.isAdmin = true
                            ownerUpdates["isAdmin"] = true
                        }
                        if !ownerUpdates.isEmpty {
                            Task {
                                do {
                                    try await self.db.collection("users").document(profile.id).setData(ownerUpdates, merge: true)
                                } catch {
                                    print("Firestore update error:", error)
                                }
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
            "canEditPatchsheet": true,
            "canEditTraining": false,
            "canEditGear": true,
            "canEditIdeas": true,
            "canEditChecklists": true,
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
            profile.canEditPatchsheet = true
            profile.canEditTraining = false
            profile.canEditGear = true
            profile.canEditIdeas = true
            profile.canEditChecklists = true

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
                Task { @MainActor in
                    patchItems = docs.compactMap { doc in
                        decodeFirestoreDocument(doc.data(), as: PatchRow.self)
                    }
                    group.leave()
                }
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
        
        let query: Query = db.collection("gear")
            .whereField("teamCode", isEqualTo: teamCode)
            .limit(to: gearPageSize)
        
        // Use real-time listener so items appear immediately when added
        query.addSnapshotListener { snap, _ in
            
            DispatchQueue.main.async {
                self.isLoadingMoreGear = false
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
                        guard let patch = decodeFirestoreDocument(doc.data(), as: PatchRow.self) else {
                            return nil
                        }
                        print("DEBUG: Decoded patch: \(patch.name) (cat: \(patch.category), pos: \(patch.position))")
                        return patch
                    }
                    
                    self.patchsheet = decoded.sorted(by: PatchRow.autoSort)
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
        
        let firestoreQuery: Query = db.collection("gear")
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
                let decoded = docs.compactMap { doc in
                    decodeFirestoreDocument(doc.data(), as: TrainingLesson.self)
                }
                DispatchQueue.main.async {
                    self.processLessonAssignmentNotifications(with: decoded)
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
                    let decoded = docs.compactMap { doc in
                        decodeFirestoreDocument(doc.data(), as: ChecklistTemplate.self)
                    }
                    DispatchQueue.main.async {
                        self.processChecklistMentionNotifications(with: decoded)
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
                    let decoded = docs.compactMap { doc in
                        decodeFirestoreDocument(doc.data(), as: IdeaCard.self)
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
                Task { @MainActor in
                    let decoded = docs.compactMap { doc in
                        decodeFirestoreDocument(doc.data(), as: ChatChannel.self)
                    }
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
                let decoded = docs.compactMap { doc in
                    decodeFirestoreDocument(doc.data(), as: ChatChannel.self)
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
            let decoded = docs.compactMap { doc in
                decodeFirestoreDocument(doc.data(), as: T.self)
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
        let location = item.location.trimmingCharacters(in: .whitespacesAndNewlines)
        if !location.isEmpty { saveLocation(location) }
        let campus = item.campus.trimmingCharacters(in: .whitespacesAndNewlines)
        if !campus.isEmpty { saveLocation(campus) }
        let room = item.room.trimmingCharacters(in: .whitespacesAndNewlines)
        if !room.isEmpty { saveRoom(room) }
    }
    func saveLesson(_ item: TrainingLesson) { save(item, collection: "lessons") }
    func saveChecklist(_ item: ChecklistTemplate) { 
        save(item, collection: "checklists")
    }
    func saveIdea(_ item: IdeaCard) { 
        save(item, collection: "ideas")
    }
    func saveChannel(_ item: ChatChannel) { save(item, collection: "channels") }
    func savePatch(_ item: PatchRow, completion: ((Result<Void, Error>) -> Void)? = nil) {
        var patch = item
        let resolvedTeamCode = (
            user?.teamCode?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? user?.teamCode
                : teamCode
        )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !resolvedTeamCode.isEmpty else {
            let error = NSError(
                domain: "ProdConnect",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No valid team code is available for this patch."]
            )
            completion?(.failure(error))
            return
        }

        patch.teamCode = resolvedTeamCode

        do {
            try db.collection("patchsheet").document(patch.id).setData(from: patch, merge: true) { error in
                DispatchQueue.main.async {
                    if let error {
                        print("Error saving patch:", error.localizedDescription)
                        completion?(.failure(error))
                        return
                    }

                    let campus = patch.campus.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !campus.isEmpty { self.saveLocation(campus) }

                    if let idx = self.patchsheet.firstIndex(where: { $0.id == patch.id }) {
                        self.patchsheet[idx] = patch
                    } else {
                        self.patchsheet.append(patch)
                    }

                    completion?(.success(()))
                }
            }
        } catch {
            completion?(.failure(error))
        }
    }

    private func decodeGearItem(from doc: QueryDocumentSnapshot) -> GearItem? {
        if let item = decodeFirestoreDocument(doc.data(), as: GearItem.self) {
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
        item.room = data["room"] as? String ?? ""
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

    private func processLessonAssignmentNotifications(with lessons: [TrainingLesson]) {
        guard user != nil else { return }
        let currentAssignedIDs = Set(lessons.filter { isLessonAssignedToCurrentUser($0) }.map { $0.id })

        guard hasPrimedLessonAssignmentState else {
            lessonAssignedToCurrentUserIDs = currentAssignedIDs
            hasPrimedLessonAssignmentState = true
            return
        }

        let newlyAssigned = currentAssignedIDs.subtracting(lessonAssignedToCurrentUserIDs)
        for lessonID in newlyAssigned {
            guard let lesson = lessons.first(where: { $0.id == lessonID }) else { continue }
            scheduleAssignmentNotification(
                identifier: "lesson-assigned-\(lessonID)",
                title: "New Training Assignment",
                body: "\"\(lesson.title)\" was assigned to you."
            )
        }
        lessonAssignedToCurrentUserIDs = currentAssignedIDs
    }

    private func processChecklistMentionNotifications(with checklists: [ChecklistTemplate]) {
        guard user != nil else { return }
        var newState: [String: Set<String>] = [:]
        for checklist in checklists {
            let mentionedItemIDs = Set(
                checklist.items
                    .filter { isChecklistItemMentioningCurrentUser($0) }
                    .map { $0.id }
            )
            newState[checklist.id] = mentionedItemIDs
        }

        guard hasPrimedChecklistMentionState else {
            checklistMentionedItemState = newState
            hasPrimedChecklistMentionState = true
            return
        }

        for checklist in checklists {
            let oldSet = checklistMentionedItemState[checklist.id] ?? []
            let newSet = newState[checklist.id] ?? []
            let newlyMentionedItemIDs = newSet.subtracting(oldSet)
            for itemID in newlyMentionedItemIDs {
                guard let item = checklist.items.first(where: { $0.id == itemID }) else { continue }
                let preview = checklistItemPreviewText(item.text)
                let body: String
                if preview.isEmpty {
                    body = "You were tagged in \"\(checklist.title)\"."
                } else {
                    body = "You were tagged in \"\(checklist.title)\": \(preview)"
                }
                scheduleAssignmentNotification(
                    identifier: "checklist-tag-\(checklist.id)-\(itemID)",
                    title: "Checklist Assignment",
                    body: body
                )
            }
        }

        checklistMentionedItemState = newState
    }

    private func scheduleAssignmentNotification(identifier: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("DEBUG: Failed to schedule assignment notification: \(error.localizedDescription)")
            }
        }
    }

    private func isLessonAssignedToCurrentUser(_ lesson: TrainingLesson) -> Bool {
        guard let currentUser = user else { return false }
        let currentID = currentUser.id.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentEmail = currentUser.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let assignedID = lesson.assignedToUserID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let assignedEmail = lesson.assignedToUserEmail?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if !assignedID.isEmpty && assignedID == currentID { return true }
        if !assignedEmail.isEmpty && assignedEmail == currentEmail { return true }
        return false
    }

    private func checklistItemPreviewText(_ text: String) -> String {
        let pattern = "(?<!\\S)@[A-Za-z0-9._-]+"
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var cleaned = regex.stringByReplacingMatches(in: text, options: [], range: fullRange, withTemplate: "")
        cleaned = cleaned.replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func mentionTokens(in text: String) -> Set<String> {
        let pattern = "(?<!\\S)@([A-Za-z0-9._-]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        let matches = regex.matches(in: text, options: [], range: range)
        var tokens: Set<String> = []
        for match in matches where match.numberOfRanges > 1 {
            let token = nsText.substring(with: match.range(at: 1))
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            if !token.isEmpty { tokens.insert(token) }
        }
        return tokens
    }

    private func mentionMatchTokens(for user: UserProfile) -> Set<String> {
        let email = user.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var tokens: Set<String> = []
        if !email.isEmpty {
            tokens.insert(email)
            if let localPart = email.split(separator: "@").first, !localPart.isEmpty {
                tokens.insert(String(localPart))
            }
        }
        let displayName = user.displayName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if !displayName.isEmpty {
            tokens.insert(displayName)
            tokens.insert(displayName.replacingOccurrences(of: " ", with: ""))
            tokens.insert(displayName.replacingOccurrences(of: " ", with: "."))
            tokens.insert(displayName.replacingOccurrences(of: " ", with: "_"))
            tokens.insert(displayName.replacingOccurrences(of: " ", with: "-"))
        }
        return tokens
    }

    private func isChecklistItemMentioningCurrentUser(_ item: ChecklistItem) -> Bool {
        guard let currentUser = user else { return false }
        let tags = mentionTokens(in: item.text)
        if tags.isEmpty { return false }
        return !mentionMatchTokens(for: currentUser).isDisjoint(with: tags)
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
        if let channel = channels.first(where: { $0.id == channelID }) {
            for message in channel.messages {
                if let raw = message.attachmentURL?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !raw.isEmpty,
                   (raw.hasPrefix("gs://") || raw.contains("firebasestorage.googleapis.com") || raw.contains("storage.googleapis.com")) {
                    Storage.storage().reference(forURL: raw).delete { error in
                        if let error {
                            print("Error deleting channel attachment:", error.localizedDescription)
                        }
                    }
                }
            }
        }
        db.collection("channels").document(channelID).delete()
        DispatchQueue.main.async {
            self.channels.removeAll { $0.id == channelID }
        }
    }
    
    func deleteAllGear(completion: ((Result<Void, Error>) -> Void)? = nil) {
        // Split into chunks of 250 to avoid exceeding Firestore batch limits (16MB)
        let chunkSize = 250
        let chunks = stride(from: 0, to: gear.count, by: chunkSize).map {
            Array(gear[$0..<min($0 + chunkSize, gear.count)])
        }
        var firstError: Error?

        guard !chunks.isEmpty else {
            completion?(.success(()))
            return
        }
        
        // Commit each chunk asynchronously
        func commitChunk(index: Int) {
            guard index < chunks.count else {
                DispatchQueue.main.async {
                    self.gear.removeAll()
                    if let firstError {
                        completion?(.failure(firstError))
                    } else {
                        completion?(.success(()))
                    }
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
                    if firstError == nil {
                        firstError = error
                    }
                }
                // Commit next chunk after this one completes
                commitChunk(index: index + 1)
            }
        }
        
        commitChunk(index: 0)
    }
    
    func deletePatchesByCategory(_ category: String, completion: ((Result<Void, Error>) -> Void)? = nil) {
        let patchesToDelete = patchsheet.filter { $0.category == category }
        
        // Split into chunks of 250 to avoid exceeding Firestore batch limits (16MB)
        let chunkSize = 250
        let chunks = stride(from: 0, to: patchesToDelete.count, by: chunkSize).map {
            Array(patchesToDelete[$0..<min($0 + chunkSize, patchesToDelete.count)])
        }
        var firstError: Error?

        guard !chunks.isEmpty else {
            completion?(.success(()))
            return
        }
        
        // Commit each chunk asynchronously
        func commitChunk(index: Int) {
            guard index < chunks.count else {
                DispatchQueue.main.async {
                    self.patchsheet.removeAll { $0.category == category }
                    if let firstError {
                        completion?(.failure(firstError))
                    } else {
                        completion?(.success(()))
                    }
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
                    if firstError == nil {
                        firstError = error
                    }
                }
                // Commit next chunk after this one completes
                commitChunk(index: index + 1)
            }
        }
        
        commitChunk(index: 0)
    }
    
    func replaceAllGear(_ items: [GearItem], completion: ((Result<Void, Error>) -> Void)? = nil) {
        // Split into chunks of 250 to avoid exceeding Firestore batch limits (16MB)
        let chunkSize = 250
        let chunks = stride(from: 0, to: items.count, by: chunkSize).map {
            Array(items[$0..<min($0 + chunkSize, items.count)])
        }
        var firstError: Error?

        guard !chunks.isEmpty else {
            completion?(.success(()))
            return
        }
        
        // Commit each chunk asynchronously, waiting for previous to complete
        func commitChunk(index: Int) {
            guard index < chunks.count else {
                print("Completed writing all \(items.count) gear items")
                DispatchQueue.main.async {
                    if let firstError {
                        completion?(.failure(firstError))
                    } else {
                        completion?(.success(()))
                    }
                }
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
                    if firstError == nil {
                        firstError = error
                    }
                } else {
                    print("Completed gear batch \(index + 1)/\(chunks.count)")
                }
                // Commit next chunk after this one completes
                commitChunk(index: index + 1)
            }
        }
        
        commitChunk(index: 0)
    }
    
    func replaceAllPatch(_ rows: [PatchRow], completion: ((Result<Void, Error>) -> Void)? = nil) {
        // Split into chunks of 250 to avoid exceeding Firestore batch limits (16MB)
        let chunkSize = 250
        let chunks = stride(from: 0, to: rows.count, by: chunkSize).map {
            Array(rows[$0..<min($0 + chunkSize, rows.count)])
        }
        var firstError: Error?

        guard !chunks.isEmpty else {
            completion?(.success(()))
            return
        }
        
        // Commit each chunk asynchronously, waiting for previous to complete
        func commitChunk(index: Int) {
            guard index < chunks.count else {
                print("Completed writing all \(rows.count) patch items")
                DispatchQueue.main.async {
                    if let firstError {
                        completion?(.failure(firstError))
                    } else {
                        completion?(.success(()))
                    }
                }
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
                    if firstError == nil {
                        firstError = error
                    }
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
    private var transactionListenerTask: Task<Void, Never>?

    // Replace with your subscription product IDs
    private let basicSubscriptionProductID = "Basic1"
    private let basicTicketingSubscriptionProductID = "Basic_Ticketing"
    private let premiumSubscriptionProductID = "Premium1"
    private let premiumTicketingSubscriptionProductID = "Premium_Ticketing"

    // MARK: - Fetch Products
    func fetchProducts() async {
        do {
            let products = try await Product.products(for: [
                basicSubscriptionProductID,
                basicTicketingSubscriptionProductID,
                premiumSubscriptionProductID,
                premiumTicketingSubscriptionProductID
            ])
            print("Successfully fetched \(products.count) products: \(products.map { $0.id })")
            product = products.first(where: { $0.id == basicSubscriptionProductID })
            if product == nil {
                print("Error: Basic product not found for ID \(basicSubscriptionProductID)")
            }
        } catch {
            print("Error fetching subscription products: \(error)")
        }
    }

    func startObservingTransactions(for store: ProdConnectStore) {
        guard transactionListenerTask == nil else { return }

        transactionListenerTask = Task {
            await reconcileSubscriptionState(for: store)

            for await update in Transaction.updates {
                do {
                    let transaction = try checkVerified(update)
                    await reconcileSubscriptionState(for: store)
                    await transaction.finish()
                } catch {
                    print("Transaction update handling failed:", error)
                }
            }
        }
    }

    
    func purchaseSubscriptionWithError(for store: ProdConnectStore) async throws {
        try await purchaseTierWithError(productID: basicSubscriptionProductID, targetTier: "basic", for: store)
    }
    
    func purchasePremiumWithError(productID: String, for store: ProdConnectStore) async throws {
        try await purchaseTierWithError(productID: productID, targetTier: "premium", for: store)
    }

    func purchaseTierWithError(productID: String, targetTier: String, for store: ProdConnectStore) async throws {
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
            await applySubscriptionTier(targetTier, for: store)
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
            await reconcileSubscriptionState(for: store)
        } catch {
            print("Restore failed:", error)
        }
    }

    // MARK: - Check Current Subscription Entitlement
    func checkSubscription(for store: ProdConnectStore) async {
        await reconcileSubscriptionState(for: store)
    }

    private func reconcileSubscriptionState(for store: ProdConnectStore) async {
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
                await applySubscriptionTier(highestTier, for: store)
            }
        } catch {
            print("Error checking subscription:", error)
        }
    }

    // MARK: - Unlock / Revoke Admin
    private func unlockAdmin(for store: ProdConnectStore) async {
        await applySubscriptionTier("basic", for: store)
        isAdminActive = true
    }

    private func revokeAdmin(for store: ProdConnectStore) async {
        guard var user = store.user else { return }
        if user.isAdmin {
            user.isAdmin = false
            store.user = user

            do {
                try await store.db.collection("users").document(user.id).setData([
                    "isAdmin": false
                ], merge: true)
            } catch {
                print("Firestore update error:", error)
            }

            store.listenToTeamData()
        }
        isAdminActive = false
    }
    
    func unlockPremium(for store: ProdConnectStore) async {
        await applySubscriptionTier("premium", for: store)
    }

    private func applySubscriptionTier(_ targetTier: String, for store: ProdConnectStore) async {
        guard var user = store.user else { return }
        let normalizedTier = canonicalSubscriptionTier(targetTier)
        if canonicalSubscriptionTier(user.subscriptionTier) == normalizedTier,
           user.isAdmin,
           user.canEditTraining,
           user.canSeeChat,
           user.canSeeTraining {
            return
        }

        user.subscriptionTier = normalizedTier
        user.isAdmin = true
        user.canEditTraining = normalizedTier != "free"
        user.canSeeChat = normalizedTier != "free"
        user.canSeeTraining = normalizedTier != "free"
        user.canSeeTickets = user.hasTicketingFeatures

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

            do {
                try await store.db.collection("teams").document(teamCode).setData([
                    "code": teamCode,
                    "createdAt": FieldValue.serverTimestamp(),
                    "createdBy": user.email,
                    "isActive": true
                ], merge: true)
            } catch {
                print("Team registration error:", error)
            }
        }

        store.user = user

        do {
            try await store.db.collection("users").document(user.id).setData([
                "subscriptionTier": user.subscriptionTier,
                "isAdmin": true,
                "teamCode": user.teamCode ?? "",
                "canEditTraining": user.canEditTraining,
                "canSeeChat": user.canSeeChat,
                "canSeeTraining": user.canSeeTraining,
                "canSeeTickets": user.canSeeTickets
            ], merge: true)
        } catch {
            print("Firestore update error:", error)
        }

        await MainActor.run {
            store.listenToTeamData()
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
        
        do {
            try await store.db.collection("users").document(user.id).setData([
                "subscriptionTier": tier
            ], merge: true)
            print("Firestore updated to: \(tier)")
        } catch {
            print("Firestore update error:", error)
        }
    }
    
    // MARK: - Toggle Admin (Testing)
    func toggleAdmin(for store: ProdConnectStore) async {
        guard var user = store.user else { return }
        
        user.isAdmin.toggle()
        if user.isOwner {
            user.isAdmin = true
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
        
        do {
            try await store.db.collection("users").document(user.id).setData([
                "isAdmin": user.isAdmin,
                "subscriptionTier": user.subscriptionTier
            ], merge: true)
            print("Admin status updated to: \(user.isAdmin)")
        } catch {
            print("Firestore update error:", error)
        }
    }
    
    private func revokeSubscriptionEntitlements(for store: ProdConnectStore) async {
        guard var user = store.user else { return }
        guard canonicalSubscriptionTier(user.subscriptionTier) != "free" else { return }

        user.subscriptionTier = "free"
        user.canEditTraining = false
        user.canSeeChat = false
        user.canSeeTraining = false
        user.canSeeTickets = false
        store.user = user

        do {
            try await store.db.collection("users").document(user.id).setData([
                "subscriptionTier": "free",
                "canEditTraining": false,
                "canSeeChat": false,
                "canSeeTraining": false,
                "canSeeTickets": false
            ], merge: true)
        } catch {
            print("Firestore update error:", error)
        }
    }

    private func subscriptionTier(for productID: String) -> String? {
        switch productID {
        case basicSubscriptionProductID:
            return "basic"
        case basicTicketingSubscriptionProductID:
            return "basic_ticketing"
        case premiumSubscriptionProductID:
            return "premium"
        case premiumTicketingSubscriptionProductID:
            return "premium_ticketing"
        default:
            return nil
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
                    do {
                        try await store.db.collection("users").document(user.id)
                            .setData(["isOwner": true], merge: true)
                    } catch {
                        print("Firestore update error:", error)
                    }
                }
                return true
            }

            if user.isOwner {
                user.isOwner = false
                store.user = user
                do {
                    try await store.db.collection("users").document(user.id)
                        .setData(["isOwner": false], merge: true)
                } catch {
                    print("Firestore update error:", error)
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

        await MainActor.run {
            store.user = updated
        }

        do {
            try await store.db.collection("users").document(updated.id).setData([
                "isOwner": true,
                "isAdmin": true
            ], merge: true)
        } catch {
            print("Firestore update error:", error)
        }

        do {
            try await store.db.collection("teams").document(teamCode).setData([
                "ownerId": updated.id,
                "ownerEmail": updated.email,
                "code": teamCode,
                "isActive": true
            ], merge: true)
        } catch {
            print("Team owner update error:", error)
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
                    .task {
                        iap.startObservingTransactions(for: store)
                    }
            } else {
                iOSLaunchWelcomeContainer()
                    .environmentObject(store)
                    .environmentObject(iap)
                    .preferredColorScheme(.dark)
                    .task {
                        iap.startObservingTransactions(for: store)
                    }
            }
        }
    }
}

private struct iOSLaunchWelcomeContainer: View {
    @EnvironmentObject private var store: ProdConnectStore
    @AppStorage(preferredMainTabSectionsStorageKey) private var preferredMainTabSections = ""
    @State private var showsWelcomeScreen = true
    @State private var selectedLaunchSection: MainAppSection?
    @State private var shouldOpenMoreTab = false

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

    private var availableSections: [MainAppSection] {
        availableMainAppSections(for: store)
    }

    private var featuredSections: [MainAppSection] {
        resolvedPreferredMainTabSections(
            storedValue: preferredMainTabSections,
            availableSections: availableSections
        )
    }

    private var hasNotificationsShortcut: Bool {
        availableSections.contains(.notifications)
    }

    private var hasMoreShortcut: Bool {
        availableSections.contains { !featuredSections.contains($0) }
    }

    var body: some View {
        Group {
            if showsWelcomeScreen {
                iOSWelcomeView(
                    userDisplayName: userDisplayName,
                    organizationDisplayName: organizationDisplayName,
                    sections: featuredSections,
                    showsNotificationsShortcut: hasNotificationsShortcut,
                    showsMoreShortcut: hasMoreShortcut,
                    openSection: { section in
                        selectedLaunchSection = section
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showsWelcomeScreen = false
                        }
                    },
                    openMore: {
                        shouldOpenMoreTab = true
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showsWelcomeScreen = false
                        }
                    }
                )
            } else {
                MainTabView(
                    selectedLaunchSection: $selectedLaunchSection,
                    shouldOpenMoreTab: $shouldOpenMoreTab
                )
            }
        }
        .onChange(of: store.user?.id) { newValue in
            showsWelcomeScreen = newValue != nil
            if newValue == nil {
                selectedLaunchSection = nil
                shouldOpenMoreTab = false
            }
        }
    }
}

private struct iOSWelcomeView: View {
    let userDisplayName: String
    let organizationDisplayName: String?
    let sections: [MainAppSection]
    let showsNotificationsShortcut: Bool
    let showsMoreShortcut: Bool
    let openSection: (MainAppSection) -> Void
    let openMore: () -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.03, green: 0.07, blue: 0.11),
                    Color(red: 0.05, green: 0.12, blue: 0.24),
                    Color(red: 0.01, green: 0.02, blue: 0.04)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color(red: 0.2, green: 0.45, blue: 0.92).opacity(0.24))
                .frame(width: 280, height: 280)
                .blur(radius: 20)
                .offset(x: -130, y: -250)

            Circle()
                .fill(Color.white.opacity(0.09))
                .frame(width: 240, height: 240)
                .blur(radius: 28)
                .offset(x: 150, y: 260)

            GeometryReader { proxy in
                let compactHeight = proxy.size.height < 760
                let veryCompactHeight = proxy.size.height < 700
                let compactWidth = proxy.size.width < 390
                let iconBoxSize: CGFloat = veryCompactHeight ? 64 : (compactHeight ? 72 : 86)
                let iconSize: CGFloat = veryCompactHeight ? 26 : (compactHeight ? 30 : 34)
                let titleSize: CGFloat = veryCompactHeight ? 30 : (compactHeight ? 34 : 40)
                let orgSize: CGFloat = veryCompactHeight ? 19 : (compactHeight ? 21 : 24)
                let sectionSpacing: CGFloat = veryCompactHeight ? 14 : (compactHeight ? 18 : 24)
                let tileHeight: CGFloat = veryCompactHeight ? 62 : (compactHeight ? 72 : 86)
                let tileSpacing: CGFloat = veryCompactHeight ? 8 : (compactHeight ? 10 : 14)
                let horizontalPadding: CGFloat = compactWidth ? 20 : 28
                let verticalPadding: CGFloat = veryCompactHeight ? 18 : (compactHeight ? 24 : 34)

                VStack {
                    VStack(spacing: sectionSpacing) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                                .frame(width: iconBoxSize, height: iconBoxSize)

                            Image(systemName: "person.crop.circle.badge.checkmark")
                                .font(.system(size: iconSize, weight: .semibold))
                                .foregroundColor(.white)
                        }

                        VStack(spacing: compactHeight ? 8 : 10) {
                            Text("Welcome")
                                .font(.system(size: veryCompactHeight ? 15 : (compactHeight ? 16 : 18), weight: .semibold, design: .rounded))
                                .foregroundColor(.white.opacity(0.68))

                            Text(userDisplayName)
                                .font(.system(size: titleSize, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .minimumScaleFactor(0.6)
                                .allowsTightening(true)

                            if let organizationDisplayName, !organizationDisplayName.isEmpty {
                                Text(organizationDisplayName)
                                    .font(.system(size: orgSize, weight: .medium, design: .rounded))
                                    .foregroundColor(Color.white.opacity(0.82))
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.65)
                                    .allowsTightening(true)
                            }
                        }

                        LazyVGrid(columns: columns, spacing: tileSpacing) {
                            ForEach(sections) { section in
                                Button {
                                    openSection(section)
                                } label: {
                                    VStack(spacing: compactHeight ? 8 : 10) {
                                        Image(systemName: section.icon)
                                            .font(.system(size: veryCompactHeight ? 16 : (compactHeight ? 18 : 20), weight: .semibold))
                                        Text(section.title)
                                            .font(.system(size: veryCompactHeight ? 13 : (compactHeight ? 14 : 15), weight: .semibold))
                                            .multilineTextAlignment(.center)
                                            .lineLimit(2)
                                            .minimumScaleFactor(0.8)
                                    }
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity, minHeight: tileHeight)
                                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }

                            if showsNotificationsShortcut {
                                Button {
                                    openSection(.notifications)
                                } label: {
                                    VStack(spacing: compactHeight ? 8 : 10) {
                                        Image(systemName: MainAppSection.notifications.icon)
                                            .font(.system(size: veryCompactHeight ? 16 : (compactHeight ? 18 : 20), weight: .semibold))
                                        Text(MainAppSection.notifications.title)
                                            .font(.system(size: veryCompactHeight ? 13 : (compactHeight ? 14 : 15), weight: .semibold))
                                            .multilineTextAlignment(.center)
                                            .lineLimit(2)
                                            .minimumScaleFactor(0.8)
                                    }
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity, minHeight: tileHeight)
                                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }

                            if showsMoreShortcut {
                                Button(action: openMore) {
                                    VStack(spacing: compactHeight ? 8 : 10) {
                                        Image(systemName: "ellipsis")
                                            .font(.system(size: veryCompactHeight ? 16 : (compactHeight ? 18 : 20), weight: .semibold))
                                        Text("More")
                                            .font(.system(size: veryCompactHeight ? 13 : (compactHeight ? 14 : 15), weight: .semibold))
                                            .multilineTextAlignment(.center)
                                            .lineLimit(2)
                                            .minimumScaleFactor(0.8)
                                    }
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity, minHeight: tileHeight)
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
                    .padding(.horizontal, horizontalPadding)
                    .padding(.vertical, verticalPadding)
                    .frame(maxWidth: 460)
                    .background(
                        RoundedRectangle(cornerRadius: 34, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 34, style: .continuous)
                                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
                            )
                    )
                    .shadow(color: Color.black.opacity(0.28), radius: 28, x: 0, y: 20)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, compactWidth ? 16 : 24)
                .padding(.vertical, veryCompactHeight ? 14 : (compactHeight ? 20 : 32))
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
                    if let uiImage = UIImage(named: "Background") {
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
    @State private var organizationName = ""
    @State private var organizationStatusMessage: String?

    private var appVersionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        if !version.isEmpty && !build.isEmpty {
            return "v\(version) (\(build))"
        }
        return version.isEmpty ? "" : "v\(version)"
    }

    private let actionButtonHeight: CGFloat = 34
    private let termsURLString = "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
    // Replace with your app's public privacy policy URL before App Store submission.
    private let privacyPolicyURLString = "https://bmsatori.github.io/prodconnect-privacy/"

    private var effectiveSubscriptionTierLabel: String {
        switch effectiveSubscriptionTier {
        case "premium_ticketing":
            return "Premium W/Ticketing"
        case "premium":
            return "Premium"
        case "basic_ticketing":
            return "Basic W/Ticketing"
        case "basic":
            return "Basic"
        default:
            return "Free"
        }
    }
    
    private var effectiveSubscriptionTier: String {
        let ownTier = canonicalSubscriptionTier(store.user?.subscriptionTier)
        let teamCode = store.user?.teamCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !teamCode.isEmpty else { return ownTier }
        guard !store.teamMembers.isEmpty else { return ownTier }

        let teamMembers = store.teamMembers.filter {
            ($0.teamCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") == teamCode
        }
        let highestRank = teamMembers
            .map(\.subscriptionTierRank)
            .reduce(subscriptionTierRank(for: ownTier), max)
        return subscriptionTierName(for: highestRank)
    }

    private var canUpgradeSubscription: Bool {
        (store.user?.isAdmin == true || store.user?.isOwner == true) && effectiveSubscriptionTier != "premium_ticketing"
    }

    private var canEditOrganizationName: Bool {
        store.user?.isAdmin == true || store.user?.isOwner == true
    }

    var body: some View {
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
                        Text(effectiveSubscriptionTierLabel)
                            .foregroundColor(.white)
                            .fontWeight(.medium)
                    }

                    // Only show Team Code for non-free users
                    if effectiveSubscriptionTier != "free" {
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

                    if canEditOrganizationName {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Organization Name")
                                .foregroundColor(.white)
                                .fontWeight(.medium)
                            TextField("Organization Name", text: $organizationName)
                                .textFieldStyle(.roundedBorder)
                            Button("Save Organization Name") {
                                saveOrganizationName()
                            }
                            .buttonStyle(.borderedProminent)
                            if let organizationStatusMessage {
                                Text(organizationStatusMessage)
                                    .font(.caption)
                                    .foregroundColor(organizationStatusMessage.hasPrefix("Saved") ? .green : .red)
                            }
                        }
                    }
                }
                .padding(.horizontal)

                Spacer()

                if effectiveSubscriptionTier == "free" {
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
                } else if canUpgradeSubscription {
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

                HStack(spacing: 8) {
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

                    Button(action: { showDeleteAccountStep1 = true }) {
                        HStack(spacing: 6) {
                            if isDeletingAccount {
                                ProgressView()
                                    .progressViewStyle(.circular)
                            }
                            Text(isDeletingAccount ? "Deleting..." : "Delete")
                                .font(.subheadline.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: actionButtonHeight)
                        .background(Color.red.opacity(0.18))
                        .foregroundColor(.red)
                        .cornerRadius(10)
                    }
                    .disabled(isDeletingAccount)
                }
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
            organizationName = store.organizationName
        }
        .onReceive(store.$user) { user in
            applyAccountState(from: user)
        }
        .onReceive(store.$organizationName) { value in
            organizationName = value
        }
        .sheet(isPresented: $showJoinTeamAlert) {
            NavigationStack {
                Form {
                    Section("Join Team") {
                        Text("Enter the team code to join an existing team.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                        TextField("Team Code", text: $joinTeamCode)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled(true)
                    }
                    Section {
                        Button("Join") {
                            joinTeam()
                        }
                        .disabled(joinTeamCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isJoiningTeam)
                    }
                }
                .navigationTitle("Join Team")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            joinTeamCode = ""
                            showJoinTeamAlert = false
                        }
                    }
                    if isJoiningTeam {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            ProgressView()
                        }
                    }
                }
            }
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
                onPurchaseBasicTicketing: {
                    do {
                        try await IAPManager.shared.purchaseTierWithError(
                            productID: "Basic_Ticketing",
                            targetTier: "basic_ticketing",
                            for: store
                        )
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
                },
                onPurchasePremiumTicketing: {
                    do {
                        try await IAPManager.shared.purchaseTierWithError(
                            productID: "Premium_Ticketing",
                            targetTier: "premium_ticketing",
                            for: store
                        )
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
                "subscriptionTier": "free",
                "isAdmin": false,
                "isOwner": false,
                "canEditPatchsheet": true,
                "canEditTraining": false,
                "canEditGear": true,
                "canEditIdeas": true,
                "canEditChecklists": true,
                "canSeeChat": false,
                "canSeeTraining": false,
                "canSeeTickets": false
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
                        updated?.subscriptionTier = "free"
                        updated?.isAdmin = false
                        updated?.isOwner = false
                        updated?.canEditPatchsheet = true
                        updated?.canEditTraining = false
                        updated?.canEditGear = true
                        updated?.canEditIdeas = true
                        updated?.canEditChecklists = true
                        updated?.canSeeChat = false
                        updated?.canSeeTraining = false
                        updated?.canSeeTickets = false
                        self.store.user = updated

                        self.store.listenToTeamData()
                    }
                }
            }
        }

        let db = store.db

        // Validate team code exists
        db.collection("teams").document(code).getDocument { snap, error in
            if error == nil, snap?.exists == true {
                DispatchQueue.main.async {
                    applyJoinUpdates(resolvedCode: code)
                }
                return
            }

            db.collection("teams").document(codeLower).getDocument { lowerSnap, lowerError in
                if lowerError == nil, let lowerSnap, lowerSnap.exists {
                    let foundCode = (lowerSnap.data()?["code"] as? String) ?? codeLower
                    DispatchQueue.main.async {
                        applyJoinUpdates(resolvedCode: foundCode.uppercased())
                    }
                    return
                }

                db.collection("teams")
                    .whereField("code", in: [code, codeLower])
                    .limit(to: 1)
                    .getDocuments { teamSnap, teamError in
                        if teamError == nil, let doc = teamSnap?.documents.first {
                            let foundCode = (doc.data()["code"] as? String) ?? doc.documentID
                            DispatchQueue.main.async {
                                applyJoinUpdates(resolvedCode: foundCode.uppercased())
                            }
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

    private func subscriptionTierRank(for tier: String) -> Int {
        switch tier {
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

    private func subscriptionTierName(for rank: Int) -> String {
        switch rank {
        case 4:
            return "premium_ticketing"
        case 3:
            return "premium"
        case 2:
            return "basic_ticketing"
        case 1:
            return "basic"
        default:
            return "free"
        }
    }

    private func loadUserInfo() {
        guard let user = Auth.auth().currentUser else {
            errorMessage = "No logged in user."
            isLoading = false
            return
        }

        NSLog("[DIAG] AccountView loadUserInfo start uid=%@", user.uid)
        email = user.email ?? "Unknown"

        let fallbackDisplayName = email.components(separatedBy: "@").first ?? "User"
        let fallbackTeamCode = "N/A"

        if let storeUser = store.user {
            applyAccountState(from: storeUser)
            NSLog("[DIAG] AccountView loadUserInfo using store.user")
            return
        }

        displayName = fallbackDisplayName
        teamCode = fallbackTeamCode
        isAdmin = false
        isLoading = false

        // Fetch profile directly by uid to avoid slow/blocked query paths.
        store.db.collection("users").document(user.uid).getDocument { snapshot, error in
            DispatchQueue.main.async {
                if let error = error {
                    NSLog("[DIAG] AccountView loadUserInfo firestore error: %@", error.localizedDescription)
                    self.errorMessage = "Error loading user: \(error.localizedDescription)"
                    self.displayName = fallbackDisplayName
                    self.teamCode = fallbackTeamCode
                    self.isAdmin = false
                    self.isLoading = false
                    return
                }

                guard let data = snapshot?.data() else {
                    NSLog("[DIAG] AccountView loadUserInfo missing user doc")
                    return
                }

                self.displayName = (data["displayName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    ?? (data["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    ?? fallbackDisplayName
                self.teamCode = data["teamCode"] as? String ?? fallbackTeamCode
                self.isAdmin = data["isAdmin"] as? Bool ?? false
                self.isLoading = false
                NSLog("[DIAG] AccountView loadUserInfo completed")
            }
        }
    }

    private func applyAccountState(from user: UserProfile?) {
        guard let user else { return }
        displayName = user.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (user.email.components(separatedBy: "@").first ?? "User")
            : user.displayName
        email = user.email
        teamCode = user.teamCode?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? (user.teamCode ?? "N/A") : "N/A"
        isAdmin = user.isAdmin
        organizationName = store.organizationName
        isLoading = false
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
    @EnvironmentObject private var store: ProdConnectStore
    @Environment(\.dismiss) private var dismiss
    @State private var basicProduct: Product?
    @State private var basicTicketingProduct: Product?
    @State private var premiumProduct: Product?
    @State private var premiumTicketingProduct: Product?
    @State private var isLoadingProducts = false

    let termsURLString: String
    let privacyPolicyURLString: String
    let onPurchaseBasic: () async -> Void
    let onPurchaseBasicTicketing: () async -> Void
    let onPurchasePremium: () async -> Void
    let onPurchasePremiumTicketing: () async -> Void
    private let subscriptionProductIDs = ["Basic1", "Basic_Ticketing", "Premium1", "Premium_Ticketing"]

    private var shouldHighlightIntroOffer: Bool {
        guard subscriptionTierKey(store.user?.subscriptionTier) == "free" else { return false }
        guard let user = store.user else { return false }
        let distinctMemberIDs = Set(store.teamMembers.map(\.id))
        return distinctMemberIDs.isEmpty || distinctMemberIDs == [user.id]
    }

    var body: some View {
        NavigationStack {
            fallbackSubscriptionContent
            .navigationTitle("Subscribe")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task {
                await loadProducts()
            }
        }
    }

    private var fallbackSubscriptionContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("ProdConnect Subscriptions")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text("Choose an auto-renewing subscription plan.")
                    .foregroundColor(.secondary)

                if shouldHighlightIntroOffer {
                    Text("Start with a 7-day free trial on any plan.")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)

                    Text("Available for new individual subscriptions. Team members on someone else’s account are not eligible.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                subscriptionCard(
                    title: basicProduct?.displayName ?? "Basic",
                    length: subscriptionLengthText(for: basicProduct),
                    price: priceText(for: basicProduct),
                    offerText: introductoryOfferText(for: basicProduct),
                    details: "Includes chat and training, but hides Locations, Rooms, and Tickets.",
                    buttonTitle: "Choose Basic",
                    action: onPurchaseBasic
                )

                subscriptionCard(
                    title: basicTicketingProduct?.displayName ?? "Basic W/Ticketing",
                    length: subscriptionLengthText(for: basicTicketingProduct),
                    price: priceText(for: basicTicketingProduct, fallback: "$199.99"),
                    offerText: introductoryOfferText(for: basicTicketingProduct),
                    details: "Includes chat, training, and Tickets, but hides Locations and Rooms.",
                    buttonTitle: "Choose Basic W/Ticketing",
                    action: onPurchaseBasicTicketing
                )

                subscriptionCard(
                    title: premiumProduct?.displayName ?? "Premium",
                    length: subscriptionLengthText(for: premiumProduct),
                    price: priceText(for: premiumProduct),
                    offerText: introductoryOfferText(for: premiumProduct),
                    details: "Includes everything except Tickets.",
                    buttonTitle: "Choose Premium",
                    action: onPurchasePremium
                )

                subscriptionCard(
                    title: premiumTicketingProduct?.displayName ?? "Premium W/Ticketing",
                    length: subscriptionLengthText(for: premiumTicketingProduct),
                    price: priceText(for: premiumTicketingProduct, fallback: "$499.99"),
                    offerText: introductoryOfferText(for: premiumTicketingProduct),
                    details: "Includes every feature.",
                    buttonTitle: "Choose Premium W/Ticketing",
                    action: onPurchasePremiumTicketing
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

                Button("Restore Purchases") {
                    Task {
                        await IAPManager.shared.restorePurchases(for: store)
                    }
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
    }

    @ViewBuilder
    private func subscriptionCard(
        title: String,
        length: String,
        price: String,
        offerText: String?,
        details: String,
        buttonTitle: String,
        action: @escaping () async -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text("Length: \(length)").font(.subheadline)
            Text("Price: \(price)").font(.subheadline)
            if let offerText {
                Text(offerText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
            }
            Text(details)
                .font(.footnote)
                .foregroundColor(.secondary)
            Button(buttonTitle) {
                Task {
                    await action()
                }
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 6)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func loadProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            let products = try await Product.products(for: subscriptionProductIDs)
            basicProduct = products.first(where: { $0.id == "Basic1" })
            basicTicketingProduct = products.first(where: { $0.id == "Basic_Ticketing" })
            premiumProduct = products.first(where: { $0.id == "Premium1" })
            premiumTicketingProduct = products.first(where: { $0.id == "Premium_Ticketing" })
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

    private func priceText(for product: Product?, fallback: String = "See App Store pricing") -> String {
        guard let product else { return fallback }
        return product.displayPrice
    }

    private func introductoryOfferText(for product: Product?) -> String? {
        guard shouldHighlightIntroOffer else { return nil }
        guard let offer = product?.subscription?.introductoryOffer else {
            return "Includes a 7-day free trial for new subscribers."
        }

        let periodText = subscriptionPeriodText(value: offer.period.value, unit: offer.period.unit)
        switch offer.paymentMode {
        case .freeTrial:
            return "Includes \(periodText) free trial for new subscribers."
        case .payAsYouGo:
            return "Intro offer: \(offer.displayPrice) for \(periodText)."
        case .payUpFront:
            return "Intro offer: \(offer.displayPrice) upfront for \(periodText)."
        default:
            return "Intro offer available for new subscribers."
        }
    }

    private func subscriptionPeriodText(value: Int, unit: Product.SubscriptionPeriod.Unit) -> String {
        let resolvedUnit: String
        switch unit {
        case .day:
            resolvedUnit = value == 1 ? "day" : "days"
        case .week:
            resolvedUnit = value == 1 ? "week" : "weeks"
        case .month:
            resolvedUnit = value == 1 ? "month" : "months"
        case .year:
            resolvedUnit = value == 1 ? "year" : "years"
        @unknown default:
            resolvedUnit = "period"
        }
        return "\(value) \(resolvedUnit)"
    }

    private func subscriptionTierKey(_ rawValue: String?) -> String {
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
        var emailVerificationPending = false

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
                DispatchQueue.main.async {
                    store.user?.displayName = trimmedName
                    store.listenToTeamMembers()
                    completion(.success(()))
                }
            }
        }

        func updateEmailIfNeeded(completion: @escaping (Result<Void, Error>) -> Void) {
            guard emailChanged else { completion(.success(())); return }
            currentUser.sendEmailVerification(beforeUpdatingEmail: trimmedEmail) { error in
                if let error = error { completion(.failure(error)); return }
                emailVerificationPending = true
                completion(.success(()))
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
                successMessage = emailVerificationPending
                    ? "Your changes were saved. Check your new email to verify the address change."
                    : "Your account was updated."
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
    @AppStorage(preferredMainTabSectionsStorageKey) private var preferredMainTabSections = ""
    @State private var newCampus = ""
    @State private var newRoom = ""
    @State private var newTicketCategory = ""
    @State private var newTicketSubcategory = ""
    @State private var gearSheetLink = ""
    @State private var audioPatchSheetLink = ""
    @State private var videoPatchSheetLink = ""
    @State private var lightingPatchSheetLink = ""
    private struct ResultAlertData: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    @State private var resultAlert: ResultAlertData? = nil
    @State private var isImporting = false
    @State private var showDeleteAllConfirmation = false
    @State private var showDeleteAudioConfirmation = false
    @State private var showDeleteLightingConfirmation = false
    @State private var showDeleteVideoConfirmation = false
    @State private var showImportHelp = false
    @State private var showEditCampusSheet = false
    @State private var editingCampusOriginal = ""
    @State private var editingCampusName = ""
    @State private var isRenamingCampus = false
    @State private var freshserviceAPIURL = ""
    @State private var freshserviceAPIKey = ""
    @State private var freshserviceEnabled = false
    @State private var isSavingFreshserviceIntegration = false
    @State private var isTestingFreshserviceIntegration = false
    @State private var freshserviceStatusMessage = ""
    @State private var externalTicketFormEnabled = false
    @State private var externalTicketFormAccessKey = ""
    @State private var isSavingExternalTicketForm = false
    @State private var externalTicketStatusMessage = ""
    @State private var bulkOperationMessage = ""
    @State private var isBulkOperationInProgress = false

    private var availableSections: [MainAppSection] {
        availableMainAppSections(for: store)
    }

    private var isPrivilegedUser: Bool {
        store.user?.isAdmin == true || store.user?.isOwner == true
    }

    private var canManageIntegrations: Bool {
        isPrivilegedUser && (store.user?.hasChatAndTrainingFeatures ?? false)
    }

    private var canManageExternalTicketForm: Bool {
        isPrivilegedUser && (store.user?.hasTicketingFeatures == true)
    }

    private var externalTicketFormURLString: String {
        let teamCode = (store.teamCode ?? store.user?.teamCode ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let accessKey = externalTicketFormAccessKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard externalTicketFormEnabled, !teamCode.isEmpty, !accessKey.isEmpty else { return "" }
        let slug = externalTicketFormSlug(from: store.organizationName)
        return "https://prodconnect-1ea3a.web.app/support/\(slug)?team=\(teamCode)&key=\(accessKey)"
    }

    private var featuredSections: [MainAppSection] {
        resolvedPreferredMainTabSections(
            storedValue: preferredMainTabSections,
            availableSections: availableSections
        )
    }

    private var overflowSections: [MainAppSection] {
        availableSections.filter { !featuredSections.contains($0) }
    }

    private func presentResultAlert(_ message: String, delay: TimeInterval = 0.2) {
        let title = message.hasPrefix("✓") ? "Success" : "Error"
        resultAlert = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            resultAlert = ResultAlertData(title: title, message: message)
        }
    }

    @ViewBuilder
    private var resultOverlay: some View {
        if let alert = resultAlert {
            ZStack {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()

                VStack(spacing: 12) {
                    Text(alert.title)
                        .font(.headline)
                    Text(alert.message)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                    Button("OK") {
                        resultAlert = nil
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(16)
                .frame(maxWidth: 320)
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .shadow(radius: 10)
                .padding(.horizontal, 24)
            }
        }
    }

    @ViewBuilder
    private var progressOverlay: some View {
        if isBulkOperationInProgress {
            ZStack {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()

                VStack(spacing: 12) {
                    ProgressView()
                    Text(bulkOperationMessage)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                }
                .padding(20)
                .frame(maxWidth: 320)
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .shadow(radius: 10)
                .padding(.horizontal, 24)
            }
        }
    }

    @ViewBuilder
    private var campusAndRoomsSection: some View {
        if store.user?.hasCampusRoomFeatures ?? false {
            campusSection
            roomsSection
        } else {
            premiumCampusSection
        }
    }

    private var ticketCategoriesSection: some View {
        Section {
            HStack {
                TextField("Add new category", text: $newTicketCategory)
                    .textFieldStyle(.roundedBorder)
                Button(action: addTicketCategory) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(.blue)
                }
                .disabled(newTicketCategory.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .listRowBackground(Color.black)

            if !store.ticketCategories.isEmpty {
                ForEach(store.ticketCategories.sorted(), id: \.self) { category in
                    HStack {
                        Image(systemName: "square.grid.2x2")
                            .foregroundColor(.blue)
                            .frame(width: 24)
                        Text(category)
                            .foregroundColor(.white)
                        Spacer()
                    }
                    .listRowBackground(Color.black)
                }
                .onDelete { indexSet in
                    let sorted = store.ticketCategories.sorted()
                    for index in indexSet {
                        store.deleteTicketCategory(sorted[index])
                    }
                }
            } else {
                Text("No custom categories added yet")
                    .foregroundColor(.gray)
                    .font(.caption)
                    .listRowBackground(Color.black)
            }
        } header: {
            Text("Ticket Categories")
        } footer: {
            Text("Swipe left on a category to delete it")
                .font(.caption)
                .foregroundColor(.gray)
        }
    }

    private var ticketSubcategoriesSection: some View {
        Section {
            HStack {
                TextField("Add new subcategory", text: $newTicketSubcategory)
                    .textFieldStyle(.roundedBorder)
                Button(action: addTicketSubcategory) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(.blue)
                }
                .disabled(newTicketSubcategory.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .listRowBackground(Color.black)

            if !store.ticketSubcategories.isEmpty {
                ForEach(store.ticketSubcategories.sorted(), id: \.self) { subcategory in
                    HStack {
                        Image(systemName: "tag")
                            .foregroundColor(.blue)
                            .frame(width: 24)
                        Text(subcategory)
                            .foregroundColor(.white)
                        Spacer()
                    }
                    .listRowBackground(Color.black)
                }
                .onDelete { indexSet in
                    let sorted = store.ticketSubcategories.sorted()
                    for index in indexSet {
                        store.deleteTicketSubcategory(sorted[index])
                    }
                }
            } else {
                Text("No custom subcategories added yet")
                    .foregroundColor(.gray)
                    .font(.caption)
                    .listRowBackground(Color.black)
            }
        } header: {
            Text("Ticket Subcategories")
        } footer: {
            Text("Swipe left on a subcategory to delete it")
                .font(.caption)
                .foregroundColor(.gray)
        }
    }

    private var tabCustomizationSection: some View {
        Section {
            ForEach(Array(featuredSections.enumerated()), id: \.element) { index, section in
                HStack(spacing: 12) {
                    Label(section.title, systemImage: section.icon)
                    Spacer()
                    Button {
                        moveFeaturedSection(from: index, to: index - 1)
                    } label: {
                        Image(systemName: "arrow.up")
                    }
                    .buttonStyle(.borderless)
                    .disabled(index == 0)

                    Button {
                        moveFeaturedSection(from: index, to: index + 1)
                    } label: {
                        Image(systemName: "arrow.down")
                    }
                    .buttonStyle(.borderless)
                    .disabled(index == featuredSections.count - 1)

                    Button("More") {
                        removeFeaturedSection(section)
                    }
                    .buttonStyle(.borderless)
                    .disabled(featuredSections.count <= 1)
                }
            }

            if !overflowSections.isEmpty {
                ForEach(overflowSections) { section in
                    HStack {
                        Label(section.title, systemImage: section.icon)
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("Add") {
                            addFeaturedSection(section)
                        }
                        .buttonStyle(.borderless)
                        .disabled(featuredSections.count >= 4)
                    }
                }
            }
        } header: {
            Text("Bottom Tab Bar")
        } footer: {
            Text("Choose up to 4 tabs for the bottom bar on this device. Everything else stays in More.")
                .font(.caption)
                .foregroundColor(.gray)
        }
    }

    private var campusSection: some View {
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

            Button(action: syncGearLocationsToCampuses) {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("Copy Locations from Assets")
                }
            }
            .listRowBackground(Color.black)

            if !store.locations.isEmpty {
                ForEach(store.locations.sorted(), id: \.self) { campus in
                    Button {
                        editingCampusOriginal = campus
                        editingCampusName = campus
                        showEditCampusSheet = true
                    } label: {
                        HStack {
                            Image(systemName: "building.2")
                                .foregroundColor(.blue)
                                .frame(width: 24)
                            Text(campus)
                                .foregroundColor(.white)
                            Spacer()
                            Image(systemName: "pencil")
                                .foregroundColor(.gray)
                        }
                    }
                    .buttonStyle(.plain)
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
    }

    private var roomsSection: some View {
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
    }

    private var premiumCampusSection: some View {
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

    private var importSection: some View {
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
                    TextField("Assets sheet link", text: $gearSheetLink)
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
    }

    private var integrationsSection: some View {
        Section("Integrations") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Connect Freshservice for API-based asset linking.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Toggle("Enable Freshservice", isOn: $freshserviceEnabled)

                TextField("Freshservice URL", text: $freshserviceAPIURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                SecureField("Freshservice API Key", text: $freshserviceAPIKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                HStack {
                    Button {
                        saveFreshserviceIntegration()
                    } label: {
                        if isSavingFreshserviceIntegration {
                            ProgressView()
                        } else {
                            Text("Save Connection")
                        }
                    }
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
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var externalTicketFormSection: some View {
        Section {
            Toggle("Enable External Form", isOn: $externalTicketFormEnabled)

            if !externalTicketFormURLString.isEmpty {
                TextField("Public Link", text: .constant(externalTicketFormURLString))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Button("Copy Public Link") {
                    UIPasteboard.general.string = externalTicketFormURLString
                    externalTicketStatusMessage = "External ticket form link copied."
                }
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
            .disabled(isSavingExternalTicketForm)

            if !externalTicketStatusMessage.isEmpty {
                Text(externalTicketStatusMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        } header: {
            Text("External Ticket Form")
        } footer: {
            Text("Anyone with this link can submit a ticket to your team.")
                .font(.caption)
                .foregroundColor(.gray)
        }
    }

    private var resetSection: some View {
        Section(header: Text("Reset")) {
            Button(action: { showDeleteAllConfirmation = true }) {
                HStack {
                    Image(systemName: "trash.fill")
                        .foregroundColor(.red)
                    Text("Delete All Assets")
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

    private var customizeBaseView: some View {
        NavigationStack {
            Form {
                tabCustomizationSection
                if isPrivilegedUser {
                    campusAndRoomsSection
                    ticketCategoriesSection
                    ticketSubcategoriesSection
                    if canManageIntegrations {
                        integrationsSection
                    }
                    if canManageExternalTicketForm {
                        externalTicketFormSection
                    }
                    importSection
                    resetSection
                }
            }
            .navigationTitle("Customize")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .disabled(isBulkOperationInProgress)
            .onAppear(perform: loadFreshserviceIntegrationState)
            .onReceive(store.$freshserviceIntegration) { _ in
                loadFreshserviceIntegrationState()
            }
            .onReceive(store.$externalTicketFormIntegration) { _ in
                loadExternalTicketFormCustomizeState()
            }
        }
    }

    private var customizeSheetedView: some View {
        customizeBaseView
        .sheet(isPresented: $showImportHelp) {
            ImportHelpView()
        }
        .sheet(isPresented: $showEditCampusSheet) {
            editCampusSheetContent
        }
    }

    private var editCampusSheetContent: some View {
        NavigationStack {
            Form {
                Section("Campus Name") {
                    TextField("Campus", text: $editingCampusName)
                }
            }
            .navigationTitle("Edit Campus")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showEditCampusSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: saveCampusRename)
                        .disabled(isRenamingCampus)
                }
            }
            .overlay {
                if isRenamingCampus {
                    ZStack {
                        Color.black.opacity(0.2).ignoresSafeArea()
                        ProgressView("Saving...")
                            .padding()
                            .background(Color(.systemBackground))
                            .cornerRadius(10)
                    }
                }
            }
        }
    }

    private var customizeFinalView: some View {
        customizeSheetedView
        .alert("Delete All Assets?", isPresented: $showDeleteAllConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete All", role: .destructive) {
                beginBulkOperation("Deleting, please wait")
                store.deleteAllGear { result in
                    endBulkOperation()
                    switch result {
                    case .success:
                        presentResultAlert("✓ All assets have been deleted")
                    case .failure(let error):
                        presentResultAlert("Delete failed: \(error.localizedDescription)", delay: 0)
                    }
                }
            }
        } message: {
            Text("Are you sure you want to delete all asset items? This cannot be undone.")
        }
        .alert("Delete Audio Patchsheet?", isPresented: $showDeleteAudioConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                beginBulkOperation("Deleting, please wait")
                store.deletePatchesByCategory("Audio") { result in
                    endBulkOperation()
                    switch result {
                    case .success:
                        presentResultAlert("✓ Audio patchsheet has been deleted")
                    case .failure(let error):
                        presentResultAlert("Delete failed: \(error.localizedDescription)", delay: 0)
                    }
                }
            }
        } message: {
            Text("Are you sure you want to delete all audio patches? This cannot be undone.")
        }
        .alert("Delete Lighting Patchsheet?", isPresented: $showDeleteLightingConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                beginBulkOperation("Deleting, please wait")
                store.deletePatchesByCategory("Lighting") { result in
                    endBulkOperation()
                    switch result {
                    case .success:
                        presentResultAlert("✓ Lighting patchsheet has been deleted")
                    case .failure(let error):
                        presentResultAlert("Delete failed: \(error.localizedDescription)", delay: 0)
                    }
                }
            }
        } message: {
            Text("Are you sure you want to delete all lighting patches? This cannot be undone.")
        }
        .alert("Delete Video Patchsheet?", isPresented: $showDeleteVideoConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                beginBulkOperation("Deleting, please wait")
                store.deletePatchesByCategory("Video") { result in
                    endBulkOperation()
                    switch result {
                    case .success:
                        presentResultAlert("✓ Video patchsheet has been deleted")
                    case .failure(let error):
                        presentResultAlert("Delete failed: \(error.localizedDescription)", delay: 0)
                    }
                }
            }
        } message: {
            Text("Are you sure you want to delete all video patches? This cannot be undone.")
        }
        .overlay(resultOverlay)
        .overlay(progressOverlay)
    }

    var body: some View {
        customizeFinalView
    }

    private func saveFeaturedSections(_ sections: [MainAppSection]) {
        preferredMainTabSections = encodePreferredMainTabSections(Array(sections.prefix(4)))
    }

    private func addFeaturedSection(_ section: MainAppSection) {
        guard !featuredSections.contains(section) else { return }
        saveFeaturedSections(featuredSections + [section])
    }

    private func removeFeaturedSection(_ section: MainAppSection) {
        saveFeaturedSections(featuredSections.filter { $0 != section })
    }

    private func moveFeaturedSection(from sourceIndex: Int, to destinationIndex: Int) {
        guard featuredSections.indices.contains(sourceIndex),
              featuredSections.indices.contains(destinationIndex),
              sourceIndex != destinationIndex else { return }
        var updated = featuredSections
        let moved = updated.remove(at: sourceIndex)
        updated.insert(moved, at: destinationIndex)
        saveFeaturedSections(updated)
    }

    private func saveCampusRename() {
        let updated = editingCampusName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !updated.isEmpty else {
            presentResultAlert("Campus name cannot be empty.", delay: 0)
            return
        }
        guard updated.caseInsensitiveCompare(editingCampusOriginal) != .orderedSame else {
            showEditCampusSheet = false
            return
        }
        isRenamingCampus = true
        store.renameLocation(editingCampusOriginal, to: updated) { result in
            DispatchQueue.main.async {
                isRenamingCampus = false
                switch result {
                case .success:
                    showEditCampusSheet = false
                    presentResultAlert("✓ Campus renamed to '\(updated)'.", delay: 0)
                case .failure(let error):
                    presentResultAlert("Rename failed: \(error.localizedDescription)", delay: 0)
                }
            }
        }
    }

    private func addCampus() {
        let trimmed = newCampus.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            presentResultAlert("Campus name cannot be empty", delay: 0)
            return
        }
        if store.locations.contains(trimmed) {
            presentResultAlert("This campus already exists", delay: 0)
            return
        }
        print("DEBUG: Adding campus '\(trimmed)' for team \(store.teamCode ?? "NO_TEAM_CODE")")
        store.saveLocation(trimmed)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            print("DEBUG: After save, locations count = \(store.locations.count), locations = \(store.locations)")
            presentResultAlert("✓ Campus '\(trimmed)' added successfully", delay: 0)
        }
        newCampus = ""
    }
    
    private func addRoom() {
        let trimmed = newRoom.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            presentResultAlert("Room name cannot be empty", delay: 0)
            return
        }
        if store.rooms.contains(trimmed) {
            presentResultAlert("This room already exists", delay: 0)
            return
        }
        print("DEBUG: Adding room '\(trimmed)' for team \(store.teamCode ?? "NO_TEAM_CODE")")
        store.saveRoom(trimmed)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            print("DEBUG: After save, rooms count = \(store.rooms.count), rooms = \(store.rooms)")
            presentResultAlert("✓ Room '\(trimmed)' added successfully", delay: 0)
        }
        newRoom = ""
    }

    private func addTicketCategory() {
        let trimmed = newTicketCategory.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            presentResultAlert("Category name cannot be empty", delay: 0)
            return
        }
        if store.ticketCategories.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            presentResultAlert("This category already exists", delay: 0)
            return
        }
        store.saveTicketCategory(trimmed)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            presentResultAlert("✓ Category '\(trimmed)' added successfully", delay: 0)
        }
        newTicketCategory = ""
    }

    private func addTicketSubcategory() {
        let trimmed = newTicketSubcategory.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            presentResultAlert("Subcategory name cannot be empty", delay: 0)
            return
        }
        if store.ticketSubcategories.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            presentResultAlert("This subcategory already exists", delay: 0)
            return
        }
        store.saveTicketSubcategory(trimmed)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            presentResultAlert("✓ Subcategory '\(trimmed)' added successfully", delay: 0)
        }
        newTicketSubcategory = ""
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

        if added == 0 {
            presentResultAlert("No new locations to copy from Assets.", delay: 0)
        } else {
            presentResultAlert("✓ Added \(added) location(s) from Assets.", delay: 0)
        }
    }

    private func importGearData() {
        isImporting = true
        let csvURL = convertGoogleSheetLinkToCSV(gearSheetLink)
        
        URLSession.shared.dataTask(with: csvURL) { data, _, error in
            guard let data = data, error == nil else {
                DispatchQueue.main.async {
                    isImporting = false
                    presentResultAlert("Failed to fetch sheet: \(error?.localizedDescription ?? "Unknown error")", delay: 0)
                }
                return
            }
            
            guard let csvString = String(data: data, encoding: .utf8) else {
                DispatchQueue.main.async {
                    isImporting = false
                    presentResultAlert("Failed to decode CSV response.", delay: 0)
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
                        presentResultAlert("✓ Imported \(gearItems.count) asset items", delay: 0)
                    case .failure(let error):
                        presentResultAlert("Import failed: \(error.localizedDescription)", delay: 0)
                    }
                }
            }
        }.resume()
    }
    
    private func importPatchData(category: String, link: String) {
        isImporting = true
        let csvURL = convertGoogleSheetLinkToCSV(link)
        
        URLSession.shared.dataTask(with: csvURL) { data, _, error in
            guard let data = data, error == nil else {
                DispatchQueue.main.async {
                    isImporting = false
                    presentResultAlert("Failed to fetch sheet: \(error?.localizedDescription ?? "Unknown error")", delay: 0)
                }
                return
            }
            
            guard let csvString = String(data: data, encoding: .utf8) else {
                DispatchQueue.main.async {
                    isImporting = false
                    presentResultAlert("Failed to decode CSV response.", delay: 0)
                }
                return
            }
            var patchRows = parsePatchCSV(csvString)
            
            // Filter or set category for imported patches
            patchRows = patchRows.map { var row = $0; row.category = category; return row }
            
            DispatchQueue.main.async {
                beginBulkOperation("Importing, please wait")
                store.replaceAllPatch(patchRows) { result in
                    endBulkOperation()
                    isImporting = false
                    switch result {
                    case .success:
                        if category == "Audio" { audioPatchSheetLink = "" }
                        else if category == "Video" { videoPatchSheetLink = "" }
                        else if category == "Lighting" { lightingPatchSheetLink = "" }
                        presentResultAlert("✓ Imported \(patchRows.count) \(category) patches", delay: 0)
                    case .failure(let error):
                        presentResultAlert("Import failed: \(error.localizedDescription)", delay: 0)
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

    private func loadFreshserviceIntegrationState() {
        let settings = store.freshserviceIntegration
        freshserviceAPIURL = settings.apiURL
        freshserviceAPIKey = settings.apiKey
        freshserviceEnabled = settings.isEnabled
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
            syncMode: store.freshserviceIntegration.syncMode,
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
        FreshserviceAPI.fetchAssetsWithAPIKey(apiKey: trimmedKey, apiUrl: trimmedURL) { result in
            DispatchQueue.main.async {
                isTestingFreshserviceIntegration = false
                switch result {
                case .success(let assets):
                    freshserviceStatusMessage = "Connected to Freshservice. Found \(assets.count) assets."
                case .failure(let error):
                    freshserviceStatusMessage = "Connection failed: \(error.localizedDescription)"
                }
            }
        }
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
        let rows = parseCSVRows(csv)
        guard rows.count > 1 else { return [] }

        var items: [GearItem] = []
        let headers = rows[0]

        for values in rows.dropFirst() {
            var item = GearItem(name: "", category: "", teamCode: store.teamCode ?? "")

            for (index, header) in headers.enumerated() {
                guard index < values.count else { continue }
                let value = values[index].trimmingCharacters(in: .whitespacesAndNewlines)

                switch normalizedCSVHeader(header) {
                case "name": item.name = value
                case "category": item.category = value
                case "location": item.location = value
                case "room": item.room = value
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
        let parsedRows = parseCSVRows(csv)
        guard parsedRows.count > 1 else { return [] }

        var rows: [PatchRow] = []
        let headers = parsedRows[0]

        for values in parsedRows.dropFirst() {
            var row = PatchRow(name: "", input: "", output: "", teamCode: store.teamCode ?? "", category: "", campus: "", room: "")

            for (index, header) in headers.enumerated() {
                guard index < values.count else { continue }
                let value = values[index].trimmingCharacters(in: .whitespacesAndNewlines)

                switch normalizedCSVHeader(header) {
                case "name": row.name = value
                case "input": row.input = value
                case "output": row.output = value
                case "notes", "note", "comments", "comment": row.notes = value
                case "category": row.category = value
                case "campus": row.campus = value
                case "room": row.room = value
                case "universe": row.universe = value
                default: break
                }
            }

            if !row.name.isEmpty {
                row.position = rows.count
                rows.append(row)
            }
        }

        return rows
    }

    private func normalizedCSVHeader(_ header: String) -> String {
        header
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
    }

    private func parseCSVRows(_ csv: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var isInsideQuotes = false

        let characters = Array(csv)
        var index = 0

        while index < characters.count {
            let character = characters[index]
            switch character {
            case "\"":
                if isInsideQuotes, index + 1 < characters.count, characters[index + 1] == "\"" {
                    field.append("\"")
                    index += 1
                } else {
                    isInsideQuotes.toggle()
                }
            case "," where !isInsideQuotes:
                row.append(cleanCSVField(field))
                field = ""
            case "\n" where !isInsideQuotes:
                row.append(cleanCSVField(field))
                if !row.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                    rows.append(row)
                }
                row = []
                field = ""
            case "\r" where !isInsideQuotes:
                row.append(cleanCSVField(field))
                if !row.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                    rows.append(row)
                }
                row = []
                field = ""
                if index + 1 < characters.count, characters[index + 1] == "\n" {
                    index += 1
                }
            default:
                field.append(character)
            }
            index += 1
        }

        if !field.isEmpty || !row.isEmpty {
            row.append(cleanCSVField(field))
            if !row.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                rows.append(row)
            }
        }

        return rows
    }

    private func cleanCSVField(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2, trimmed.hasPrefix("\""), trimmed.hasSuffix("\"") else {
            return trimmed
        }
        let inner = String(trimmed.dropFirst().dropLast())
        return inner.replacingOccurrences(of: "\"\"", with: "\"")
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
                        "Supported headers: name, input, output, category, campus, room, universe.",
                        "Category can be Audio, Video, or Lighting.",
                        "Lighting rows can leave output blank and may include universe."
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
    @State private var showDeleteConfirm = false

    private var canDeleteUser: Bool {
        guard let currentUser = store.user else { return false }
        return currentUser.canDelete(user)
    }

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
                Toggle("Can edit run of show", isOn: $user.canEditRunOfShow)
                    .onChange(of: user.canEditRunOfShow) { newValue in
                        updatePermission(key: "canEditRunOfShow", value: newValue)
                    }
                Toggle("Can edit assets", isOn: $user.canEditGear)
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
                Toggle("Ticket Agent", isOn: $user.isTicketAgent)
                    .onChange(of: user.isTicketAgent) { newValue in
                        updatePermission(key: "isTicketAgent", value: newValue)
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
                    Toggle("Run of Show", isOn: $user.canSeeRunOfShow)
                        .onChange(of: user.canSeeRunOfShow) { newValue in
                            updatePermission(key: "canSeeRunOfShow", value: newValue)
                        }
                    Toggle("Assets", isOn: $user.canSeeGear)
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
                    Toggle("Tickets", isOn: $user.canSeeTickets)
                        .onChange(of: user.canSeeTickets) { newValue in
                            updatePermission(key: "canSeeTickets", value: newValue)
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
        .alert("Delete User?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteUser()
            }
        } message: {
            Text("This permanently deletes \(user.displayName)'s user profile.")
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

        let newOwnerUpdates: [String: Any] = [
            "isOwner": true,
            "isAdmin": true
        ]
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
                        case "canEditRunOfShow":
                            store.teamMembers[idx].canEditRunOfShow = value
                        case "canEditGear":
                            store.teamMembers[idx].canEditGear = value
                        case "canEditIdeas":
                            store.teamMembers[idx].canEditIdeas = value
                        case "canEditChecklists":
                            store.teamMembers[idx].canEditChecklists = value
                        case "isTicketAgent":
                            store.teamMembers[idx].isTicketAgent = value
                        case "canSeeChat":
                            store.teamMembers[idx].canSeeChat = value
                        case "canSeePatchsheet":
                            store.teamMembers[idx].canSeePatchsheet = value
                        case "canSeeTraining":
                            store.teamMembers[idx].canSeeTraining = value
                        case "canSeeRunOfShow":
                            store.teamMembers[idx].canSeeRunOfShow = value
                        case "canSeeGear":
                            store.teamMembers[idx].canSeeGear = value
                        case "canSeeIdeas":
                            store.teamMembers[idx].canSeeIdeas = value
                        case "canSeeChecklists":
                            store.teamMembers[idx].canSeeChecklists = value
                        case "canSeeTickets":
                            store.teamMembers[idx].canSeeTickets = value
                        default:
                            break
                        }
                    }
                }
            }
        }
    }

    private func deleteUser() {
        guard canDeleteUser else { return }

        isSaving = true
        errorMessage = nil

        store.db.collection("users").document(user.id).delete { error in
            DispatchQueue.main.async {
                self.isSaving = false
                if let error = error {
                    self.errorMessage = "Delete failed: \(error.localizedDescription)"
                    return
                }

                self.store.teamMembers.removeAll { $0.id == self.user.id }
                dismiss()
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
    @State private var editUniverseText = ""
    @State private var saveErrorMessage: String?
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false
    
    var canEdit: Bool { store.canEditPatchsheet }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 0) {
                    editorField("Name") {
                        TextField("Name", text: $patch.name)
                            .disabled(!canEdit)
                    }

                    if patch.category == "Lighting" {
                        editorField("DMX Channel") {
                            TextField("DMX Channel", text: $patch.input)
                                .disabled(!canEdit)
                        }
                        editorField("Channel Count") {
                            TextField("Channel Count", text: $editChannelCountText)
                                .keyboardType(.numberPad)
                                .disabled(!canEdit)
                        }
                        editorField("Universe", isLast: false) {
                            TextField("Universe", text: $editUniverseText)
                                .disabled(!canEdit)
                        }
                    } else if patch.category == "Video" {
                        editorField("Source") {
                            TextField("Source", text: $patch.input)
                                .disabled(!canEdit)
                        }
                        editorField("Destination") {
                            TextField("Destination", text: $patch.output)
                                .disabled(!canEdit)
                        }
                    } else {
                        editorField("Input") {
                            TextField("Input", text: $patch.input)
                                .disabled(!canEdit)
                        }
                        editorField("Output") {
                            TextField("Output", text: $patch.output)
                                .disabled(!canEdit)
                        }
                    }

                    editorField("Notes") {
                        TextField("Notes", text: $patch.notes, axis: .vertical)
                            .lineLimit(2...6)
                            .disabled(!canEdit)
                    }

                    if store.locations.isEmpty {
                        editorField("Campus/Location") {
                            TextField("Campus/Location", text: $patch.campus)
                                .disabled(!canEdit)
                        }
                    } else {
                        editorField("Campus/Location") {
                            Picker("Campus/Location", selection: $patch.campus) {
                                Text("Select campus/location").tag("")
                                ForEach(store.locations.sorted(), id: \.self) { campus in
                                    Text(campus).tag(campus)
                                }
                            }
                            .disabled(!canEdit)
                        }
                    }

                    if store.rooms.isEmpty {
                        editorField("Room", isLast: true) {
                            TextField("Room", text: $patch.room)
                                .disabled(!canEdit)
                        }
                    } else {
                        editorField("Room", isLast: true) {
                            Picker("Room", selection: $patch.room) {
                                Text("Select room").tag("")
                                ForEach(store.rooms.sorted(), id: \.self) { room in
                                    Text(room).tag(room)
                                }
                            }
                            .disabled(!canEdit)
                        }
                    }
                }
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                if canEdit {
                    Button("Delete Patch", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .disabled(isSaving || isDeleting)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 60)
            .padding(.bottom, 32)
        }
        .navigationTitle("Edit Patch")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let count = patch.channelCount, count > 0 {
                editChannelCountText = String(count)
            } else {
                editChannelCountText = ""
            }
            editUniverseText = patch.universe ?? ""
        }
        .toolbar {
            if canEdit {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        isSaving = true
                        let trimmed = editChannelCountText.trimmingCharacters(in: .whitespaces)
                        let parsed = Int(trimmed) ?? 0
                        patch.channelCount = parsed > 0 ? parsed : nil
                        patch.universe = editUniverseText.trimmingCharacters(in: .whitespacesAndNewlines)
                        store.savePatch(patch) { result in
                            DispatchQueue.main.async {
                                isSaving = false
                                switch result {
                                case .success:
                                    dismiss()
                                case .failure(let error):
                                    saveErrorMessage = error.localizedDescription
                                }
                            }
                        }
                    }
                }
            }
        }
        .alert("Unable to Save Patch", isPresented: Binding(
            get: { saveErrorMessage != nil },
            set: { if !$0 { saveErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveErrorMessage ?? "")
        }
        .alert("Delete Patch?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                isDeleting = true
                store.deletePatch(patch) { result in
                    DispatchQueue.main.async {
                        isDeleting = false
                        switch result {
                        case .success:
                            dismiss()
                        case .failure(let error):
                            saveErrorMessage = error.localizedDescription
                        }
                    }
                }
            }
        } message: {
            Text("This permanently deletes this patch.")
        }
    }

    @ViewBuilder
    private func editorField<Content: View>(_ title: String, isLast: Bool = false, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            if !isLast {
                Divider()
                    .padding(.horizontal, 16)
            }
        }
    }
}


// MARK: - Training Views (Updated for completion tracking)

// ...existing code...
struct TrainingListView: View {
    private enum AssignmentFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case assigned = "Assigned"
        case unassigned = "Unassigned"

        var id: String { rawValue }
    }

    private enum CompletionFilter: String, CaseIterable, Identifiable {
        case all = "All Status"
        case incomplete = "Incomplete"
        case completed = "Completed"

        var id: String { rawValue }
    }

    @EnvironmentObject var store: ProdConnectStore
    @State private var showAdd = false
    @State private var showAddVideo = false
    @State private var selectedFilter = "All"
    @State private var assignmentFilter: AssignmentFilter = .all
    @State private var completionFilter: CompletionFilter = .all
    @State private var searchText = ""
    var canEdit: Bool { store.user?.isAdmin == true || store.user?.canEditTraining == true }

    // Only allowed categories
    let categories = ["All", "Audio", "Video", "Lighting", "Misc"]

    // Filtered lessons based on selection and search
    var filteredLessons: [TrainingLesson] {
        var lessons = visibleLessons
        
        if selectedFilter != "All" {
            lessons = lessons.filter { $0.category == selectedFilter }
        }

        switch assignmentFilter {
        case .all:
            break
        case .assigned:
            lessons = lessons.filter(isLessonAssigned)
        case .unassigned:
            lessons = lessons.filter { !isLessonAssigned($0) }
        }

        switch completionFilter {
        case .all:
            break
        case .incomplete:
            lessons = lessons.filter { !$0.isCompleted }
        case .completed:
            lessons = lessons.filter(\.isCompleted)
        }

        if !searchText.isEmpty {
            lessons = lessons.filter { lesson in
                trainingSearchTokens(for: lesson).contains {
                    $0.localizedCaseInsensitiveContains(searchText)
                }
            }
        }
        
        return lessons
    }
    private var groupedLessons: [(group: String, items: [TrainingLesson])] {
        let grouped = Dictionary(grouping: filteredLessons) { trainingGroupTitle(for: $0) }
        return grouped.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }.map { key in
            let items = (grouped[key] ?? []).sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
            return (group: key, items: items)
        }
    }

    private var visibleLessons: [TrainingLesson] {
        guard let currentUser = store.user else { return [] }
        if currentUser.isAdmin || currentUser.isOwner {
            return store.lessons
        }

        let currentUserID = currentUser.id.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentUserEmail = currentUser.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return store.lessons.filter { lesson in
            let assignedID = lesson.assignedToUserID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let assignedEmail = lesson.assignedToUserEmail?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            if assignedID.isEmpty && assignedEmail.isEmpty { return true }
            if !assignedID.isEmpty && assignedID == currentUserID { return true }
            if !assignedEmail.isEmpty && assignedEmail == currentUserEmail { return true }
            return false
        }
    }

    private func assignmentLabel(for lesson: TrainingLesson) -> String? {
        let assignedID = lesson.assignedToUserID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let assignedEmail = lesson.assignedToUserEmail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if assignedID.isEmpty && assignedEmail.isEmpty { return nil }
        if let member = store.teamMembers.first(where: { $0.id == assignedID }) {
            let name = member.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { return "Assigned: \(name)" }
            return "Assigned: \(member.email)"
        }
        return assignedEmail.isEmpty ? "Assigned" : "Assigned: \(assignedEmail)"
    }

    private func isLessonAssigned(_ lesson: TrainingLesson) -> Bool {
        let assignedID = lesson.assignedToUserID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let assignedEmail = lesson.assignedToUserEmail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !assignedID.isEmpty || !assignedEmail.isEmpty
    }

    private func trainingSearchTokens(for lesson: TrainingLesson) -> [String] {
        var tokens = [
            lesson.title,
            lesson.category,
            trainingGroupTitle(for: lesson)
        ]
        if let assignmentLabel = assignmentLabel(for: lesson) {
            tokens.append(assignmentLabel)
        }
        if lesson.isCompleted {
            tokens.append("Completed")
        } else {
            tokens.append("Incomplete")
        }
        return tokens
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

                Picker("Assignment", selection: $assignmentFilter) {
                    ForEach(AssignmentFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)

                Picker("Status", selection: $completionFilter) {
                    ForEach(CompletionFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)

                List {
                    ForEach(groupedLessons, id: \.group) { section in
                        Section(section.group) {
                            ForEach(section.items) { lesson in
                                NavigationLink(destination: TrainingDetailView(lesson: lesson).environmentObject(store)) {
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(lesson.title).font(.headline)
                                            Text(lesson.category).font(.caption).foregroundColor(.secondary)
                                            if let label = assignmentLabel(for: lesson) {
                                                Text(label).font(.caption2).foregroundColor(.blue)
                                            }
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
                                    store.deleteLesson(section.items[i])
                                }
                            }
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

    private func trainingGroupTitle(for lesson: TrainingLesson) -> String {
        let trimmed = lesson.groupName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Ungrouped" : trimmed
    }
}

private extension String {
    var csvEscaped: String {
        let escaped = self.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

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
    @State private var selectedAssignedUserID: String = ""

    private var canAssignLesson: Bool {
        store.user?.isAdmin == true || store.user?.isOwner == true
    }

    private var assignableMembers: [UserProfile] {
        store.teamMembers.sorted { lhs, rhs in
            lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }
    
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

                if canAssignLesson {
                    Section("Assignment") {
                        Picker("Assigned To", selection: $selectedAssignedUserID) {
                            Text("Unassigned").tag("")
                            ForEach(assignableMembers) { member in
                                let displayName = member.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                                Text(displayName.isEmpty ? member.email : displayName).tag(member.id)
                            }
                        }
                        .onChange(of: selectedAssignedUserID) { newValue in
                            applyAssignment(for: newValue)
                        }
                    }
                } else if let assignedTo = assignmentTextForCurrentLesson() {
                    Section("Assignment") {
                        Text(assignedTo).font(.subheadline)
                    }
                }
            }
        }
        .navigationTitle(lesson.title)
        .onAppear {
            selectedAssignedUserID = lesson.assignedToUserID ?? ""
        }
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

    private func applyAssignment(for userID: String) {
        let trimmedID = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentID = lesson.assignedToUserID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let currentEmail = lesson.assignedToUserEmail?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if trimmedID.isEmpty {
            if currentID.isEmpty && currentEmail.isEmpty { return }
            lesson.assignedToUserID = nil
            lesson.assignedToUserEmail = nil
            store.saveLesson(lesson)
            return
        }

        guard let user = assignableMembers.first(where: { $0.id == trimmedID }) else { return }
        let normalizedEmail = user.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if currentID == user.id && currentEmail == normalizedEmail { return }
        lesson.assignedToUserID = user.id
        lesson.assignedToUserEmail = normalizedEmail
        store.saveLesson(lesson)
    }

    private func assignmentTextForCurrentLesson() -> String? {
        let assignedID = lesson.assignedToUserID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let assignedEmail = lesson.assignedToUserEmail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if assignedID.isEmpty && assignedEmail.isEmpty { return nil }
        if let member = assignableMembers.first(where: { $0.id == assignedID }) {
            let displayName = member.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !displayName.isEmpty { return "Assigned to \(displayName)" }
            return "Assigned to \(member.email)"
        }
        return assignedEmail.isEmpty ? "Assigned" : "Assigned to \(assignedEmail)"
    }
}

struct AddTrainingView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var store: ProdConnectStore

    @State private var title = ""
    @State private var category = "Audio" // Default selection
    @State private var videoSource: String = "local" // "local" or "youtube"
    @State private var youtubeLink = ""
    @State private var groupName = ""
    @State private var selectedVideoItem: PhotosPickerItem?
    @State private var localVideoURL: URL?
    @State private var isUploading = false
    @State private var uploadProgress: Double = 0
    @State private var errorMsg: String?
    @State private var selectedAssignedUserID: String = ""

    var onSave: (TrainingLesson) -> Void

    // Only allowed categories
    let categories = ["Audio", "Video", "Lighting", "Misc"]

    private var canAssignLesson: Bool {
        store.user?.isAdmin == true || store.user?.isOwner == true
    }

    private var assignableMembers: [UserProfile] {
        store.teamMembers.sorted { lhs, rhs in
            lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    private var selectedAssignedUser: UserProfile? {
        let trimmed = selectedAssignedUserID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return assignableMembers.first(where: { $0.id == trimmed })
    }

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
                    TextField("Group", text: $groupName)

                    if canAssignLesson {
                        Picker("Assign To", selection: $selectedAssignedUserID) {
                            Text("Unassigned").tag("")
                            ForEach(assignableMembers) { member in
                                let displayName = member.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                                Text(displayName.isEmpty ? member.email : displayName).tag(member.id)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                    }
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
                                            groupName: normalizedTrainingGroupName(groupName),
                                            teamCode: store.teamCode ?? "",
                                            durationSeconds: 0,
                                            urlString: urlString,
                                            assignedToUserID: selectedAssignedUser?.id,
                                            assignedToUserEmail: selectedAssignedUser?.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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
                            groupName: normalizedTrainingGroupName(groupName),
                            teamCode: store.teamCode ?? "",
                            durationSeconds: 0,
                            urlString: normalizedYouTubeURL,
                            assignedToUserID: selectedAssignedUser?.id,
                            assignedToUserEmail: selectedAssignedUser?.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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

private func normalizedTrainingGroupName(_ value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
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
    @State private var pendingAutoSave: DispatchWorkItem?
    @State private var showDeleteConfirmation = false
    @State private var deleteErrorMessage: String?
    @State private var didDeleteAsset = false
    @State private var saveErrorMessage: String?

    var canEdit: Bool { store.canEditGear }
    private var categoryOptions: [String] {
        let current = item.category.trimmingCharacters(in: .whitespacesAndNewlines)
        var options = ProdConnectStore.defaultGearCategories
        let existing = store.gear.map(\.category).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        for option in existing where !options.contains(where: { $0.caseInsensitiveCompare(option) == .orderedSame }) {
            options.append(option)
        }
        if !current.isEmpty && !options.contains(where: { $0.caseInsensitiveCompare(current) == .orderedSame }) {
            options.append(current)
        }
        return options.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var body: some View {
        Form {
            Section("Details") {
                TextField("Name", text: $item.name).disabled(!canEdit)
                TextField("Serial Number", text: $item.serialNumber).disabled(!canEdit)
                TextField("Asset ID", text: $item.assetId).disabled(!canEdit)
                Picker("Category", selection: $item.category) {
                    ForEach(categoryOptions, id: \.self) { Text($0) }
                }.pickerStyle(.menu).disabled(!canEdit)
                if store.locations.isEmpty {
                    TextField("Location", text: $item.location).disabled(!canEdit)
                } else {
                    Picker("Location", selection: $item.location) {
                        Text("Select location").tag("")
                        ForEach(store.locations, id: \.self) { loc in
                            Text(loc).tag(loc)
                        }
                    }
                    .disabled(!canEdit)
                }
                if store.rooms.isEmpty {
                    TextField("Room", text: $item.room).disabled(!canEdit)
                } else {
                    Picker("Room", selection: $item.room) {
                        Text("Select room").tag("")
                        ForEach(store.rooms, id: \.self) { room in
                            Text(room).tag(room)
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
                ), format: .currency(code: currentCurrencyIdentifier()))
                .keyboardType(.decimalPad)
                .disabled(!canEdit)
            }

            Section("Maintenance") {
                TextField("Issue", text: $item.maintenanceIssue).disabled(!canEdit)
                TextField("Cost", value: Binding(
                    get: { item.maintenanceCost ?? 0 },
                    set: { item.maintenanceCost = $0 }
                ), format: .currency(code: currentCurrencyIdentifier()))
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

            Section("Ticket History") {
                if item.ticketHistory.isEmpty {
                    Text("No tickets linked")
                        .foregroundColor(.secondary)
                } else {
                    if !item.activeTicketIDs.isEmpty {
                        Text("\(item.activeTicketIDs.count) active ticket(s)")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    ForEach(item.ticketHistory.sorted { $0.updatedAt > $1.updatedAt }) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(entry.ticketTitle)
                                Spacer()
                                Text(entry.status.rawValue)
                                    .font(.caption)
                                    .foregroundColor(entry.status == .resolved ? .green : .orange)
                            }
                            let locationLine = [entry.campus, entry.room]
                                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                .filter { !$0.isEmpty }
                                .joined(separator: " • ")
                            if !locationLine.isEmpty {
                                Text(locationLine)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Text((entry.resolvedAt ?? entry.updatedAt).formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
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
                if canEdit {
                    Text("Changes auto-save")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if canEdit {
                    Button("Delete Asset", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                }
                Button("Done") {
                    dismiss()
                }
            }
        }
        .navigationTitle(item.name)
        .onChange(of: selectedImageItem) { newValue in
            guard let newValue, canEdit else { return }
            Task { await loadAndUploadImage(from: newValue) }
        }
        .onChange(of: item.name) { _ in scheduleAutoSave() }
        .onChange(of: item.serialNumber) { _ in scheduleAutoSave() }
        .onChange(of: item.assetId) { _ in scheduleAutoSave() }
        .onChange(of: item.category) { _ in scheduleAutoSave() }
        .onChange(of: item.location) { _ in scheduleAutoSave() }
        .onChange(of: item.room) { _ in scheduleAutoSave() }
        .onChange(of: item.status) { _ in scheduleAutoSave() }
        .onChange(of: item.installDate) { _ in scheduleAutoSave() }
        .onChange(of: item.purchaseDate) { _ in scheduleAutoSave() }
        .onChange(of: item.purchasedFrom) { _ in scheduleAutoSave() }
        .onChange(of: item.cost) { _ in scheduleAutoSave() }
        .onChange(of: item.maintenanceIssue) { _ in scheduleAutoSave() }
        .onChange(of: item.maintenanceCost) { _ in scheduleAutoSave() }
        .onChange(of: item.maintenanceRepairDate) { _ in scheduleAutoSave() }
        .onChange(of: item.maintenanceNotes) { _ in scheduleAutoSave() }
        .onChange(of: item.imageURL) { _ in scheduleAutoSave() }
        .onDisappear {
            guard canEdit, !didDeleteAsset else { return }
            pendingAutoSave?.cancel()
            persistGear(item)
        }
        .alert("Delete Asset?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                pendingAutoSave?.cancel()
                store.deleteGear(items: [item]) { result in
                    switch result {
                    case .success:
                        didDeleteAsset = true
                        dismiss()
                    case .failure(let error):
                        deleteErrorMessage = error.localizedDescription
                    }
                }
            }
        } message: {
            Text("This permanently deletes this asset.")
        }
        .alert("Unable to Delete Asset", isPresented: Binding(
            get: { deleteErrorMessage != nil },
            set: { if !$0 { deleteErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteErrorMessage ?? "")
        }
        .alert("Unable to Save Asset", isPresented: Binding(
            get: { saveErrorMessage != nil },
            set: { if !$0 { saveErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveErrorMessage ?? "")
        }
    }

    private func scheduleAutoSave() {
        guard canEdit else { return }
        pendingAutoSave?.cancel()
        let snapshot = item
        let work = DispatchWorkItem {
            persistGear(snapshot)
        }
        pendingAutoSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    private func persistGear(_ snapshot: GearItem) {
        store.saveGear(snapshot) { result in
            switch result {
            case .success:
                item = snapshot
            case .failure(let error):
                saveErrorMessage = error.localizedDescription
                if let persisted = store.gear.first(where: { $0.id == snapshot.id }) {
                    item = persisted
                }
            }
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
    @State private var room = ""
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
    @State private var serialValidationMessage: String?

    var onSave: (GearItem) -> Void
    private var categoryOptions: [String] {
        let existing = store.gear.map(\.category).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return Array(Set(ProdConnectStore.defaultGearCategories + existing))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Name", text: $name)
                    TextField("Serial Number", text: $serialNumber)
                    TextField("Asset ID", text: $assetId)
                    Picker("Category", selection: $category) {
                        ForEach(categoryOptions, id: \.self) { Text($0) }
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
                    if store.rooms.isEmpty {
                        TextField("Room", text: $room)
                    } else {
                        Picker("Room", selection: $room) {
                            Text("Select room").tag("")
                            ForEach(store.rooms.sorted(), id: \.self) { room in
                                Text(room).tag(room)
                            }
                        }
                    }
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
                    TextField("Cost", value: $cost, format: .currency(code: currentCurrencyIdentifier()))
                        .keyboardType(.decimalPad)
                }
                Section("Maintenance") {
                    TextField("Issue", text: $maintenanceIssue)
                    TextField("Cost", value: $maintenanceCost, format: .currency(code: currentCurrencyIdentifier()))
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
            .navigationTitle("Add Asset")
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
                                room: room.trimmingCharacters(in: .whitespaces),
                                serialNumber: serialNumber.trimmingCharacters(in: .whitespaces),
                                campus: ""
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
                                        let newItem = createItem(urlString)
                                        store.saveGear(newItem) { saveResult in
                                            switch saveResult {
                                            case .success:
                                                onSave(newItem)
                                                dismiss()
                                            case .failure(let error):
                                                serialValidationMessage = error.localizedDescription
                                            }
                                        }
                                    case .failure(let error):
                                        imageError = "Image upload failed: \(error.localizedDescription)"
                                    }
                                }
                            }
                        } else {
                            let newItem = createItem(nil)
                            store.saveGear(newItem) { saveResult in
                                switch saveResult {
                                case .success:
                                    onSave(newItem)
                                    dismiss()
                                case .failure(let error):
                                    serialValidationMessage = error.localizedDescription
                                }
                            }
                        }
                    }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isUploadingImage)
                }
            }
            .onChange(of: selectedImageItem) { newValue in
                guard let newValue else { return }
                Task { await loadImageData(from: newValue) }
            }
            .alert("Unable to Save Asset", isPresented: Binding(
                get: { serialValidationMessage != nil },
                set: { if !$0 { serialValidationMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(serialValidationMessage ?? "")
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

// MARK: - Tickets Views

struct TicketsListView: View {
    @EnvironmentObject var store: ProdConnectStore
    @State private var showSubmitForm = false
    @State private var locationFilter = ""
    @State private var statusFilter = ""
    @State private var agentFilter = ""

    private let unassignedAgentFilter = "__UNASSIGNED__"

    private var availableLocations: [String] {
        Array(Set(store.visibleTickets.map { $0.campus.trimmingCharacters(in: .whitespacesAndNewlines) }))
            .filter { !$0.isEmpty }
            .sorted()
    }

    private var availableAssignees: [UserProfile] {
        store.teamMembers
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
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
        NavigationStack {
            Group {
                if !store.canUseTickets {
                    VStack(spacing: 12) {
                        Text("Ticketing is available on Premium W/Ticketing.")
                            .font(.headline)
                        Text("Upgrade the team subscription to enable campus ticket tracking.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    VStack(spacing: 0) {
                        ticketFilterBar

                        List {
                            if filteredTickets.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("No matching tickets")
                                        .foregroundColor(.secondary)
                                    Button("Submit Ticket") {
                                        showSubmitForm = true
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                            } else {
                                ForEach(filteredTickets) { ticket in
                                    NavigationLink {
                                        TicketDetailView(ticket: ticket)
                                    } label: {
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack(alignment: .firstTextBaseline) {
                                                Text(ticket.title)
                                                    .font(.headline)
                                                Spacer()
                                                Text(ticket.status.rawValue)
                                                    .font(.caption2)
                                                    .foregroundColor(ticket.status == .resolved ? .green : .orange)
                                            }
                                            let locationLine = [ticket.campus, ticket.room]
                                                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                                .filter { !$0.isEmpty }
                                                .joined(separator: " • ")
                                            if !locationLine.isEmpty {
                                                Text(locationLine)
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                            if let dueDate = ticket.dueDate {
                                                Text("Due \(dueDate.formatted(date: .abbreviated, time: .shortened))")
                                                    .font(.caption2)
                                                    .foregroundColor(dueDate < Date() && ticket.status != .resolved ? .red : .secondary)
                                            }
                                            HStack {
                                                if let assetName = ticket.linkedGearName?.trimmingCharacters(in: .whitespacesAndNewlines),
                                                   !assetName.isEmpty {
                                                    Text(assetName)
                                                        .font(.caption2)
                                                        .foregroundColor(.secondary)
                                                }
                                                Spacer()
                                                Text(ticket.updatedAt.formatted(date: .abbreviated, time: .shortened))
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Tickets")
            .toolbar {
                if store.canUseTickets {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            showSubmitForm = true
                        } label: {
                            Label("Submit Ticket", systemImage: "plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $showSubmitForm) {
                SubmitTicketView { ticket in
                    store.saveTicket(ticket)
                }
            }
        }
    }

    private var ticketFilterBar: some View {
        HStack(spacing: 12) {
            ticketLocationMenu
            ticketStatusMenu
            ticketAgentMenu
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var ticketLocationMenu: some View {
        Menu {
            Button("Clear") { locationFilter = "" }
            Divider()
            if availableLocations.isEmpty {
                Text("No locations")
            } else {
                ForEach(availableLocations, id: \.self) { location in
                    Button(location) { locationFilter = location }
                }
            }
        } label: {
            ticketFilterChip(
                title: locationFilter.isEmpty ? "Location" : locationFilter,
                icon: "mappin.circle",
                isActive: !locationFilter.isEmpty
            )
        }
        .frame(maxWidth: .infinity)
    }

    private var ticketStatusMenu: some View {
        Menu {
            Button("Active") { statusFilter = "" }
            Divider()
            ForEach(TicketStatus.allCases, id: \.self) { status in
                Button(status.rawValue) { statusFilter = status.rawValue }
            }
        } label: {
            ticketFilterChip(
                title: statusFilter.isEmpty ? "Active" : statusFilter,
                icon: "checkmark.circle",
                isActive: !statusFilter.isEmpty
            )
        }
        .frame(maxWidth: .infinity)
    }

    private var ticketAgentMenu: some View {
        Menu {
            Button("Clear") { agentFilter = "" }
            Divider()
            Button("Unassigned") { agentFilter = unassignedAgentFilter }
            if !availableAssignees.isEmpty {
                Divider()
                ForEach(availableAssignees) { agent in
                    Button(agent.displayName) { agentFilter = agent.id }
                }
            }
        } label: {
            ticketFilterChip(
                title: agentFilterTitle,
                icon: "person.crop.circle",
                isActive: !agentFilter.isEmpty
            )
        }
        .frame(maxWidth: .infinity)
    }

    private var agentFilterTitle: String {
        if agentFilter.isEmpty { return "Agent" }
        if agentFilter == unassignedAgentFilter { return "Unassigned" }
        return availableAssignees.first(where: { $0.id == agentFilter })?.displayName ?? "Agent"
    }

    private func ticketFilterChip(title: String, icon: String, isActive: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(title)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isActive ? Color.blue : Color.gray.opacity(0.3))
        .foregroundColor(.white)
        .cornerRadius(8)
    }
}

struct TicketDetailView: View {
    @EnvironmentObject var store: ProdConnectStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var ticket: SupportTicket
    @State private var isEditing = false
    @State private var originalTicket: SupportTicket?
    @State private var selectedAgentID = ""
    @State private var showAssetPicker = false
    @State private var newPrivateNote = ""
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var pendingAttachmentData: Data?
    @State private var pendingAttachmentName: String?
    @State private var isUploadingAttachment = false
    @State private var attachmentError: String?

    init(ticket: SupportTicket) {
        _ticket = State(initialValue: ticket)
        _selectedAgentID = State(initialValue: ticket.assignedAgentID ?? "")
    }

    private var canAssignAgents: Bool {
        store.canSeeAllTickets
    }

    private var availableAssignees: [UserProfile] {
        store.teamMembers
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private var availableGear: [GearItem] {
        store.gear.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private let maxAttachmentBytes = 100 * 1024 * 1024

    var body: some View {
        Form {
            Section("Overview") {
                if isEditing {
                    TextField("Title", text: $ticket.title)
                    TextEditor(text: $ticket.detail)
                        .frame(minHeight: 120)
                } else {
                    Text(ticket.title)
                        .font(.title3)
                    Text(ticket.detail.isEmpty ? "No details" : ticket.detail)
                        .foregroundColor(ticket.detail.isEmpty ? .secondary : .primary)
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
                                ticket.lastUpdatedBy = currentUserLabel
                                store.saveTicket(ticket)
                            }
                        }
                    )
                ) {
                    ForEach(TicketStatus.allCases, id: \.self) { status in
                        Text(status.rawValue).tag(status)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("Due Date") {
                if isEditing {
                    Toggle("Set Due Date", isOn: hasDueDateBinding)
                    if ticket.dueDate != nil {
                        DatePicker("Due", selection: dueDateBinding, displayedComponents: [.date, .hourAndMinute])
                    }
                } else if let dueDate = ticket.dueDate {
                    Text(dueDate.formatted(date: .abbreviated, time: .shortened))
                        .foregroundColor(dueDate < Date() && ticket.status != .resolved ? .red : .primary)
                } else {
                    Text("Not set")
                        .foregroundColor(.secondary)
                }
            }

            Section("Category") {
                if isEditing {
                    if ticketCategoryOptions.isEmpty {
                        TextField("Category", text: $ticket.category)
                        TextField("Subcategory", text: $ticket.subcategory)
                    } else {
                        Picker("Category", selection: $ticket.category) {
                            Text("Select category").tag("")
                            ForEach(ticketCategoryOptions, id: \.self) { option in
                                Text(option).tag(option)
                            }
                        }
                        if ticketSubcategoryOptions.isEmpty {
                            TextField("Subcategory", text: $ticket.subcategory)
                        } else {
                            Picker("Subcategory", selection: $ticket.subcategory) {
                                Text("Select subcategory").tag("")
                                ForEach(ticketSubcategoryOptions, id: \.self) { option in
                                    Text(option).tag(option)
                                }
                            }
                        }
                    }
                } else {
                    let categoryLine = [ticket.category, ticket.subcategory]
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                        .joined(separator: " • ")
                    Text(categoryLine.isEmpty ? "Not set" : categoryLine)
                        .foregroundColor(categoryLine.isEmpty ? .secondary : .primary)
                }
            }

            Section("Location") {
                if isEditing {
                    if store.locations.isEmpty {
                        TextField("Campus", text: $ticket.campus)
                    } else {
                        Picker("Campus", selection: $ticket.campus) {
                            Text("Select campus").tag("")
                            ForEach(store.locations.sorted(), id: \.self) { campus in
                                Text(campus).tag(campus)
                            }
                        }
                    }
                    if store.rooms.isEmpty {
                        TextField("Room", text: $ticket.room)
                    } else {
                        Picker("Room", selection: $ticket.room) {
                            Text("Select room").tag("")
                            ForEach(store.rooms.sorted(), id: \.self) { room in
                                Text(room).tag(room)
                            }
                        }
                    }
                } else {
                    let locationLine = [ticket.campus, ticket.room]
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                        .joined(separator: " • ")
                    Text(locationLine.isEmpty ? "Not set" : locationLine)
                        .foregroundColor(locationLine.isEmpty ? .secondary : .primary)
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
                                .foregroundColor(selectedAssetName == nil ? .secondary : .primary)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    if ticket.linkedGearID != nil || ticket.linkedGearName != nil {
                        Button("Clear Asset Link", role: .destructive) {
                            ticket.linkedGearID = nil
                            ticket.linkedGearName = nil
                        }
                    }
                } else {
                    Text(ticket.linkedGearName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? (ticket.linkedGearName ?? "") : "None")
                        .foregroundColor((ticket.linkedGearName ?? "").isEmpty ? .secondary : .primary)
                }
            }

            Section("Attachment") {
                if isEditing {
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Label(
                            pendingAttachmentData == nil ? "Choose Photo" : "Replace Photo",
                            systemImage: "photo.on.rectangle"
                        )
                    }
                    if isUploadingAttachment {
                        ProgressView()
                    }
                    if hasAttachmentToClear {
                        Button("Clear Attachment", role: .destructive) {
                            clearPendingTicketAttachment()
                            ticket.attachmentURL = nil
                            ticket.attachmentName = nil
                            ticket.attachmentKind = nil
                        }
                    }
                    if let attachmentError {
                        Text(attachmentError)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }

                ticketAttachmentPreview
            }

            Section("Agent") {
                if isEditing, canAssignAgents {
                    Picker(
                        "Agent",
                        selection: $selectedAgentID
                    ) {
                        Text("Unassigned").tag("")
                        ForEach(availableAssignees) { member in
                            Text(displayName(for: member)).tag(member.id)
                        }
                    }
                    .pickerStyle(.menu)
                } else {
                    Text(ticket.assignedAgentName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? (ticket.assignedAgentName ?? "") : "Unassigned")
                        .foregroundColor((ticket.assignedAgentName ?? "").isEmpty ? .secondary : .primary)
                }

                if !isEditing, let currentUser = store.user, ticket.assignedAgentID != currentUser.id {
                    Button("Assign to Me") {
                        selectedAgentID = currentUser.id
                        applySelectedAgent()
                        ticket.lastUpdatedBy = currentUserLabel
                        store.saveTicket(ticket)
                    }
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
                            openURL(url)
                        }
                    }
                } else {
                    Text("No requester email")
                        .foregroundColor(.secondary)
                }
            }

            Section("Private Notes") {
                if isEditing {
                    TextEditor(text: $newPrivateNote)
                        .frame(minHeight: 120)
                        .overlay(alignment: .topLeading) {
                            if newPrivateNote.isEmpty {
                                Text("Add a private note")
                                    .foregroundColor(.secondary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                            }
                        }
                }
                if ticket.privateNoteEntries.isEmpty {
                    Text("No private notes")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(ticket.privateNoteEntries.sorted { $0.createdAt > $1.createdAt }) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.message)
                            HStack {
                                if let author = entry.author?.trimmingCharacters(in: .whitespacesAndNewlines), !author.isEmpty {
                                    Text(author)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                Text("Visible only inside ProdConnect.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Activity") {
                if ticket.activity.isEmpty {
                    Text("No updates yet")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(ticket.activity.sorted { $0.createdAt > $1.createdAt }) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.message)
                            HStack {
                                if let author = entry.author?.trimmingCharacters(in: .whitespacesAndNewlines), !author.isEmpty {
                                    Text(author)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }

            Section {
                Button(isEditing ? "Save" : "Close") {
                    if isEditing {
                        saveEditedTicket()
                        return
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isUploadingAttachment)
            }
        }
        .navigationTitle("Ticket")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAssetPicker) {
            AssetTicketPickerView(
                selectedAssetID: ticket.linkedGearID,
                onSelect: { item in
                    ticket.linkedGearID = item.id
                    ticket.linkedGearName = item.name
                }
            )
            .environmentObject(store)
        }
        .toolbar {
            if store.canUseTickets {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if isEditing {
                        Button("Cancel", action: cancelEditing)
                    }
                    Button(isEditing ? "Done" : "Edit") {
                        if isEditing {
                            saveEditedTicket()
                        } else {
                            originalTicket = ticket
                            selectedAgentID = ticket.assignedAgentID ?? ""
                            isEditing = true
                        }
                    }
                }
            }
        }
        .onChange(of: selectedPhotoItem) { newValue in
            guard let newValue else { return }
            Task { await loadTicketPhotoAttachment(from: newValue) }
        }
        .onAppear {
            selectedAgentID = ticket.assignedAgentID ?? ""
            newPrivateNote = ""
        }
    }

    private var currentUserLabel: String {
        let name = store.user?.displayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !name.isEmpty { return name }
        return store.user?.email ?? Auth.auth().currentUser?.email ?? "Unknown User"
    }

    private var ticketCategoryOptions: [String] {
        let current = ticket.category.trimmingCharacters(in: .whitespacesAndNewlines)
        var options = store.availableTicketCategories
        if !current.isEmpty && !options.contains(where: { $0.caseInsensitiveCompare(current) == .orderedSame }) {
            options.append(current)
        }
        return options.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var ticketSubcategoryOptions: [String] {
        let current = ticket.subcategory.trimmingCharacters(in: .whitespacesAndNewlines)
        var options = store.availableTicketSubcategories
        if !current.isEmpty && !options.contains(where: { $0.caseInsensitiveCompare(current) == .orderedSame }) {
            options.append(current)
        }
        return options.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
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

    private func cancelEditing() {
        if let originalTicket {
            ticket = originalTicket
            selectedAgentID = originalTicket.assignedAgentID ?? ""
        }
        clearPendingTicketAttachment()
        isEditing = false
        originalTicket = nil
    }

    private func saveEditedTicket() {
        attachmentError = nil
        applySelectedAgent()
        appendPendingPrivateNoteIfNeeded()
        ticket.lastUpdatedBy = currentUserLabel

        guard let pendingAttachmentData else {
            store.saveTicket(ticket)
            dismiss()
            return
        }

        isUploadingAttachment = true
        uploadTicketImage(data: pendingAttachmentData, filename: pendingAttachmentName ?? "Photo.jpg") { result in
            DispatchQueue.main.async {
                isUploadingAttachment = false
                switch result {
                case .success(let urlString):
                    ticket.attachmentURL = urlString
                    ticket.attachmentName = pendingAttachmentName ?? "Photo.jpg"
                    ticket.attachmentKind = .image
                    clearPendingTicketAttachment()
                    store.saveTicket(ticket)
                    dismiss()
                case .failure(let error):
                    attachmentError = "Attachment upload failed: \(error.localizedDescription)"
                }
            }
        }
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

    private func applySelectedAgent() {
        let trimmed = selectedAgentID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            ticket.assignedAgentID = nil
            ticket.assignedAgentName = nil
            return
        }

        guard let member = availableAssignees.first(where: { $0.id == trimmed }) else {
            ticket.assignedAgentID = nil
            ticket.assignedAgentName = nil
            return
        }

        ticket.assignedAgentID = member.id
        ticket.assignedAgentName = displayName(for: member)
    }

    private func displayName(for member: UserProfile) -> String {
        let trimmed = member.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return member.email.components(separatedBy: "@").first ?? member.email
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
        if pendingAttachmentData != nil {
            Label(
                pendingAttachmentName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                    ? (pendingAttachmentName ?? "Selected Photo")
                    : "Selected Photo",
                systemImage: "photo"
            )
        } else {
            let rawURL = ticket.attachmentURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if rawURL.isEmpty {
                Text("No attachment")
                    .foregroundColor(.secondary)
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
                    .foregroundColor(.secondary)
            }
        }
    }

    private var hasAttachmentToClear: Bool {
        pendingAttachmentData != nil || !(ticket.attachmentURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    private func clearPendingTicketAttachment() {
        selectedPhotoItem = nil
        pendingAttachmentData = nil
        pendingAttachmentName = nil
        attachmentError = nil
    }

    private func loadTicketPhotoAttachment(from item: PhotosPickerItem) async {
        if let data = try? await item.loadTransferable(type: Data.self) {
            if data.count > maxAttachmentBytes {
                DispatchQueue.main.async {
                    selectedPhotoItem = nil
                    pendingAttachmentData = nil
                    pendingAttachmentName = nil
                    attachmentError = "Attachment is too large. Max size is 100 MB."
                }
                return
            }
            DispatchQueue.main.async {
                pendingAttachmentData = data
                pendingAttachmentName = "Photo.jpg"
                attachmentError = nil
            }
        } else {
            DispatchQueue.main.async {
                attachmentError = "Unable to prepare image attachment."
            }
        }
    }

    private func uploadTicketImage(data: Data, filename: String, completion: @escaping (Result<String, Error>) -> Void) {
        let safeName = filename.replacingOccurrences(of: " ", with: "_")
        let path = "ticketAttachments/\(ticket.id)/\(UUID().uuidString)-\(safeName)"
        let storageRef = Storage.storage().reference().child(path)
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        storageRef.putData(data, metadata: metadata) { _, error in
            if let error {
                completion(.failure(error))
                return
            }
            storageRef.downloadURL { url, error in
                if let url {
                    completion(.success(url.absoluteString))
                } else if let error {
                    completion(.failure(error))
                }
            }
        }
    }
}

struct SubmitTicketView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: ProdConnectStore
    @State private var title = ""
    @State private var detail = ""
    @State private var category = ""
    @State private var subcategory = ""
    @State private var campus = ""
    @State private var room = ""
    @State private var hasDueDate = false
    @State private var dueDate = Date()
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var attachmentURL: String?
    @State private var attachmentName: String?
    @State private var attachmentKind: TicketAttachmentKind?
    @State private var attachmentData: Data?
    @State private var isUploadingAttachment = false
    @State private var uploadProgress: Double = 0
    @State private var attachmentError: String?

    var onSave: (SupportTicket) -> Void

    private let maxAttachmentBytes = 100 * 1024 * 1024

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var categoryOptions: [String] {
        store.availableTicketCategories
    }

    private var subcategoryOptions: [String] {
        store.availableTicketSubcategories
    }

    var body: some View {
        NavigationStack {
            Form {
                requesterSection
                overviewSection
                categorySection
                dueDateSection
                locationSection
                attachmentSection
                createButtonSection
            }
            .navigationTitle("Submit Ticket")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onChange(of: selectedPhotoItem) { newValue in
                guard let newValue else { return }
                Task { await loadTicketPhotoAttachment(from: newValue) }
            }
            .onAppear {
                let assignedCampus = store.user?.assignedCampus.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if campus.isEmpty {
                    campus = assignedCampus
                }
            }
        }
    }

    private var requesterSection: some View {
        Section("Requester") {
            LabeledContent("Name", value: requesterName)
            LabeledContent("Email", value: requesterEmail)
        }
    }

    private var overviewSection: some View {
        Section {
            TextField("Issue Title", text: $title)
            TextEditor(text: $detail)
                .frame(minHeight: 120)
        } header: {
            Text("Issue")
        } footer: {
            Text("Add enough detail for someone else to understand the issue without following up first.")
        }
    }

    private var dueDateSection: some View {
        Section("Due Date") {
            Toggle("Set Due Date", isOn: $hasDueDate)
            if hasDueDate {
                DatePicker("Due", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
            }
        }
    }

    private var categorySection: some View {
        Section("Category") {
            if categoryOptions.isEmpty {
                TextField("Category", text: $category)
                TextField("Subcategory", text: $subcategory)
            } else {
                Picker("Category", selection: $category) {
                    Text("Select category").tag("")
                    ForEach(categoryOptions, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
                if subcategoryOptions.isEmpty {
                    TextField("Subcategory", text: $subcategory)
                } else {
                    Picker("Subcategory", selection: $subcategory) {
                        Text("Select subcategory").tag("")
                        ForEach(subcategoryOptions, id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }
                }
            }
        }
    }

    private var locationSection: some View {
        Section("Location") {
            if store.locations.isEmpty {
                TextField("Campus", text: $campus)
            } else {
                Picker("Campus", selection: $campus) {
                    Text("Select campus").tag("")
                    ForEach(store.locations.sorted(), id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
            }
            if store.rooms.isEmpty {
                TextField("Room", text: $room)
            } else {
                Picker("Room", selection: $room) {
                    Text("Select room").tag("")
                    ForEach(store.rooms.sorted(), id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
            }
        }
    }

    private var attachmentSection: some View {
        Section("Attachment") {
            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                Label(
                    attachmentData == nil ? "Choose Photo" : "Replace Photo",
                    systemImage: "photo.on.rectangle"
                )
            }
            ticketAttachmentPreview
            if attachmentData != nil {
                Button("Clear Attachment", role: .destructive) {
                    clearPendingTicketAttachment()
                }
            }
            if isUploadingAttachment {
                ProgressView(value: uploadProgress)
            }
            if let attachmentError {
                Text(attachmentError)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
    }

    private var createButtonSection: some View {
        Section {
            Button("Submit Ticket", action: createTicket)
                .buttonStyle(.borderedProminent)
                .disabled(!canSave || isUploadingAttachment)
        }
    }

    private var currentUserLabel: String {
        let name = store.user?.displayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !name.isEmpty { return name }
        return store.user?.email ?? Auth.auth().currentUser?.email ?? "Unknown User"
    }

    @ViewBuilder
    private var ticketAttachmentPreview: some View {
        if attachmentData == nil {
            Text("No attachment")
                .foregroundColor(.secondary)
        } else {
            Label(
                attachmentName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                    ? (attachmentName ?? "Selected Photo")
                    : "Selected Photo",
                systemImage: "photo"
            )
        }
    }

    private func createTicket() {
        attachmentError = nil
        let activeTeamCode = [
            store.teamCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            store.user?.teamCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        ].first(where: { !$0.isEmpty }) ?? ""
        var ticket = SupportTicket(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            detail: detail.trimmingCharacters(in: .whitespacesAndNewlines),
            category: category.trimmingCharacters(in: .whitespacesAndNewlines),
            subcategory: subcategory.trimmingCharacters(in: .whitespacesAndNewlines),
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
            attachmentKind: attachmentKind
        )

        guard let attachmentData else {
            onSave(ticket)
            dismiss()
            return
        }

        isUploadingAttachment = true
        uploadProgress = 0
        uploadTicketImage(data: attachmentData, filename: attachmentName ?? "Photo.jpg") { result in
            DispatchQueue.main.async {
                isUploadingAttachment = false
                switch result {
                case .success(let urlString):
                    ticket.attachmentURL = urlString
                    ticket.attachmentName = attachmentName ?? "Photo.jpg"
                    ticket.attachmentKind = .image
                    onSave(ticket)
                    dismiss()
                case .failure(let error):
                    attachmentError = "Attachment upload failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private var requesterName: String {
        let name = store.user?.displayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !name.isEmpty { return name }
        return "Unknown User"
    }

    private var requesterEmail: String {
        store.user?.email ?? Auth.auth().currentUser?.email ?? "Unknown Email"
    }

    private func clearPendingTicketAttachment() {
        selectedPhotoItem = nil
        attachmentURL = nil
        attachmentName = nil
        attachmentKind = nil
        attachmentData = nil
        attachmentError = nil
        uploadProgress = 0
    }

    private func loadTicketPhotoAttachment(from item: PhotosPickerItem) async {
        if let data = try? await item.loadTransferable(type: Data.self) {
            if data.count > maxAttachmentBytes {
                DispatchQueue.main.async {
                    selectedPhotoItem = nil
                    attachmentURL = nil
                    attachmentName = nil
                    attachmentKind = nil
                    attachmentData = nil
                    uploadProgress = 0
                    attachmentError = "Attachment is too large. Max size is 100 MB."
                }
                return
            }
            DispatchQueue.main.async {
                attachmentData = data
                attachmentName = "Photo.jpg"
                attachmentKind = .image
                attachmentURL = nil
                attachmentError = nil
            }
        } else {
            DispatchQueue.main.async {
                attachmentError = "Unable to prepare image attachment."
            }
        }
    }

    private func uploadTicketImage(data: Data, filename: String, completion: @escaping (Result<String, Error>) -> Void) {
        let safeName = filename.replacingOccurrences(of: " ", with: "_")
        let path = "ticketAttachments/\(UUID().uuidString)/\(UUID().uuidString)-\(safeName)"
        let storageRef = Storage.storage().reference().child(path)
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        let uploadTask = storageRef.putData(data, metadata: metadata)

        uploadTask.observe(.progress) { snapshot in
            if let fraction = snapshot.progress?.fractionCompleted {
                DispatchQueue.main.async {
                    uploadProgress = fraction
                }
            }
        }

        uploadTask.observe(.success) { _ in
            DispatchQueue.main.async {
                uploadProgress = 1
            }
            storageRef.downloadURL { url, error in
                if let url = url {
                    completion(.success(url.absoluteString))
                } else if let error {
                    completion(.failure(error))
                }
            }
        }

        uploadTask.observe(.failure) { snapshot in
            if let error = snapshot.error {
                completion(.failure(error))
            }
        }
    }
}

private struct AssetTicketPickerView: View {
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
        NavigationStack {
            VStack(spacing: 0) {
                SearchBar(text: $searchText)
                filterBar

                List {
                    if filteredAssets.isEmpty {
                        Text("No assets found")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(filteredAssets) { item in
                            Button {
                                onSelect(item)
                                dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.name)
                                            .foregroundColor(.primary)
                                        Text(item.category)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        if !item.location.isEmpty {
                                            Text(item.location)
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    Spacer()
                                    if item.id == selectedAssetID {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Select Asset")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                categoryMenu
                if !availableLocations.isEmpty {
                    locationMenu
                }
                statusMenu
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private var categoryMenu: some View {
        Menu {
            Button("Clear") { selectedCategory = nil }
            Divider()
            if availableCategories.isEmpty {
                Text("No categories")
            } else {
                ForEach(availableCategories, id: \.self) { category in
                    Button(category) { selectedCategory = category }
                }
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
            if availableLocations.isEmpty {
                Text("No locations")
            } else {
                ForEach(availableLocations, id: \.self) { location in
                    Button(location) { selectedLocation = location }
                }
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
            ForEach(GearItem.GearStatus.allCases, id: \.self) { status in
                Button(status.rawValue) { selectedStatus = status }
            }
        } label: {
            filterChip(
                title: selectedStatus?.rawValue ?? "Status",
                icon: "checkmark.circle",
                isActive: selectedStatus != nil
            )
        }
    }

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
        .cornerRadius(8)
    }
}

// MARK: - Checklists Views

// ...existing code...
struct ChecklistsListView: View {
    @EnvironmentObject var store: ProdConnectStore
    @State private var showCreate = false
    @State private var checklistToEdit: ChecklistTemplate?
    @State private var showingAddOptions = false
    @State private var showingAddGroupAlert = false
    @State private var newGroupName = ""
    @State private var collapsedGroups: Set<String> = []

    var canEdit: Bool { store.canEditChecklists }
    private var orderedGroupNames: [String] {
        store.availableChecklistGroups
    }
    private var groupedChecklists: [(group: String, items: [ChecklistTemplate])] {
        let grouped = Dictionary(grouping: store.checklists) { checklistGroupTitle(for: $0) }
        return orderedGroupNames.map { key in
            let items = (grouped[key] ?? []).sorted { lhs, rhs in
                if lhs.position != rhs.position { return lhs.position < rhs.position }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            return (group: key, items: items)
        }
    }

    var body: some View {
        NavigationStack {
            VStack {
                List {
                    ForEach(groupedChecklists, id: \.group) { section in
                        Section {
                            if !collapsedGroups.contains(section.group) {
                                ForEach(section.items) { template in
                                    checklistRow(template)
                                }
                                .onDelete { idx in
                                    guard canEdit else { return }
                                    for i in idx {
                                        deleteChecklist(section.items[i])
                                    }
                                }
                            } else if section.items.isEmpty {
                                EmptyView()
                            }
                        } header: {
                            Button {
                                toggleGroup(section.group)
                            } label: {
                                HStack {
                                    Image(systemName: collapsedGroups.contains(section.group) ? "chevron.right" : "chevron.down")
                                        .font(.caption.weight(.semibold))
                                    Text(section.group)
                                }
                            }
                            .buttonStyle(.plain)
                            .draggable(store.canPersistChecklistGroupOrder ? dragTokenForGroup(section.group) : "")
                            .dropDestination(for: String.self) { items, _ in
                                handleDroppedGroupToken(items.first, before: section.group)
                            }
                        }
                    }
                }
                .toolbar {
                    if canEdit {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button { showingAddOptions = true } label: { Image(systemName: "plus") }
                        }
                    }
                }
                .sheet(isPresented: $showCreate) {
                    CreateChecklistView { newChecklist in
                        store.saveChecklist(newChecklist)
                    }
                }
                .sheet(item: $checklistToEdit) { checklist in
                    NavigationStack {
                        ChecklistRunView(template: checklist, startsEditing: true)
                    }
                }
                .confirmationDialog("Add", isPresented: $showingAddOptions, titleVisibility: .visible) {
                    Button("Add Group") {
                        newGroupName = ""
                        showingAddGroupAlert = true
                    }
                    Button("Add Checklist") {
                        showCreate = true
                    }
                    Button("Cancel", role: .cancel) {}
                }
                .alert("Add Group", isPresented: $showingAddGroupAlert) {
                    TextField("Group name", text: $newGroupName)
                    Button("Cancel", role: .cancel) {}
                    Button("Save") {
                        store.addChecklistGroup(newGroupName)
                    }
                } message: {
                    Text("Create a checklist group.")
                }
            }
            .navigationTitle("Checklists")
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    @ViewBuilder
    private func checklistRow(_ template: ChecklistTemplate) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                toggleChecklistCompletion(template)
            } label: {
                Image(systemName: isChecklistCompleted(template) ? "checkmark.circle.fill" : "checkmark.circle")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(isChecklistCompleted(template) ? .green : .secondary)
                    .padding(.top, 2)
            }
            .buttonStyle(.plain)

            NavigationLink { ChecklistRunView(template: template) } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(template.title)
                        .font(.headline)
                    Spacer(minLength: 8)
                    Text(checklistProgressLabel(for: template))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isChecklistCompleted(template) ? .green : .blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background((isChecklistCompleted(template) ? Color.green : Color.blue).opacity(0.12))
                        .clipShape(Capsule())
                }
                ProgressView(value: checklistCompletionFraction(for: template))
                    .tint(isChecklistCompleted(template) ? .green : .blue)
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
        }
        .contextMenu {
            if canEdit {
                Button("Edit") {
                    checklistToEdit = template
                }
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
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if canEdit {
                Button("Edit") {
                    checklistToEdit = template
                }
                .tint(.blue)
            }
        }
        .draggable(dragTokenForChecklist(template))
        .dropDestination(for: String.self) { items, _ in
            handleDroppedChecklistToken(items.first, before: template)
        }
    }

    private func isChecklistCompleted(_ template: ChecklistTemplate) -> Bool {
        !template.items.isEmpty && template.items.allSatisfy(\.isDone)
    }

    private func checklistCompletionFraction(for template: ChecklistTemplate) -> Double {
        guard !template.items.isEmpty else { return 0 }
        let completedCount = template.items.filter(\.isDone).count
        return Double(completedCount) / Double(template.items.count)
    }

    private func checklistProgressLabel(for template: ChecklistTemplate) -> String {
        "\(Int((checklistCompletionFraction(for: template) * 100).rounded()))%"
    }

    private func toggleChecklistCompletion(_ template: ChecklistTemplate) {
        guard !template.items.isEmpty else { return }
        var updated = template
        let shouldComplete = !isChecklistCompleted(template)
        updated.items = updated.items.map { item in
            var next = item
            next.isDone = shouldComplete
            next.completedAt = shouldComplete ? Date() : nil
            next.completedBy = shouldComplete ? completionUserLabel() : nil
            return next
        }
        updated.completedAt = shouldComplete ? Date() : nil
        updated.completedBy = shouldComplete ? completionUserLabel() : nil
        store.saveChecklist(updated)
    }

    private func completionUserLabel() -> String {
        let displayName = store.user?.displayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !displayName.isEmpty { return displayName }
        return store.user?.email ?? Auth.auth().currentUser?.email ?? "Unknown User"
    }

    private func dragTokenForChecklist(_ checklist: ChecklistTemplate) -> String {
        "checklist:\(checklist.id)"
    }

    private func dragTokenForGroup(_ group: String) -> String {
        "group:\(group)"
    }

    private func handleDroppedChecklistToken(_ token: String?, before target: ChecklistTemplate) -> Bool {
        guard let token, token.hasPrefix("checklist:") else { return false }
        let draggedID = String(token.dropFirst("checklist:".count))
        reorderChecklist(draggedID: draggedID, before: target)
        return true
    }

    private func handleDroppedGroupToken(_ token: String?, before targetGroup: String) -> Bool {
        guard store.canPersistChecklistGroupOrder else { return false }
        guard let token, token.hasPrefix("group:") else { return false }
        let draggedGroup = String(token.dropFirst("group:".count))
        var ordered = orderedGroupNames
        guard let sourceIndex = ordered.firstIndex(of: draggedGroup),
              let destinationIndex = ordered.firstIndex(of: targetGroup),
              sourceIndex != destinationIndex else { return false }
        let moved = ordered.remove(at: sourceIndex)
        ordered.insert(moved, at: destinationIndex)
        store.reorderChecklistGroups(ordered)
        return true
    }

    private func reorderChecklist(draggedID: String, before target: ChecklistTemplate) {
        var ordered = store.checklists.sorted {
            if $0.position != $1.position { return $0.position < $1.position }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
        guard let sourceIndex = ordered.firstIndex(where: { $0.id == draggedID }),
              let destinationIndex = ordered.firstIndex(where: { $0.id == target.id }),
              sourceIndex != destinationIndex else { return }
        var moved = ordered.remove(at: sourceIndex)
        moved.groupName = target.groupName
        ordered.insert(moved, at: destinationIndex)
        store.reorderChecklists(ordered)
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

    private func checklistGroupTitle(for template: ChecklistTemplate) -> String {
        let trimmed = template.groupName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Ungrouped" : trimmed
    }

    private func toggleGroup(_ group: String) {
        if collapsedGroups.contains(group) {
            collapsedGroups.remove(group)
        } else {
            collapsedGroups.insert(group)
        }
    }

    private func deleteChecklist(_ template: ChecklistTemplate) {
        guard canEdit else { return }
        store.db.collection("checklists").document(template.id).delete()
    }
}

struct ChecklistRunView: View {
    private enum MentionTarget: Equatable {
        case existingItem(String)
        case newItem
    }

    private struct SelectedTask: Identifiable {
        let id: String
    }

    @EnvironmentObject var store: ProdConnectStore
    @State var template: ChecklistTemplate
    @Environment(\.dismiss) private var dismiss
    private let startsEditing: Bool
    @State private var hasDueDate = false
    @State private var draftDueDate = Date()
    @State private var isEditingChecklist = false
    @State private var draftGroupName = ""
    @State private var newChecklistItemText = ""
    @State private var newChecklistItemNotes = ""
    @State private var newChecklistItemAssignedUserID = ""
    @State private var newChecklistItemHasDueDate = false
    @State private var newChecklistItemDueDate = Date()
    @State private var selectedTask: SelectedTask?
    @State private var activeMentionTarget: MentionTarget? = nil
    @State private var activeMentionQuery: String = ""
    var canEdit: Bool { store.canEditChecklists }
    private var canAssignTasks: Bool { store.canAssignChecklistTasks }
    private var showsAssignmentFeatures: Bool { store.teamHasChecklistTaskAssignmentFeatures }
    private var canManageChecklistDueDate: Bool { store.user?.isAdmin == true || store.user?.isOwner == true }
    private var progressTint: Color { progress >= 1 ? .green : .blue }
    private var assignableMembers: [UserProfile] {
        store.teamMembers.sorted {
            displayName(for: $0).localizedCaseInsensitiveCompare(displayName(for: $1)) == .orderedAscending
        }
    }
    private var todoItems: [ChecklistItem] { template.items.filter { !$0.isDone } }
    private var completedItems: [ChecklistItem] { template.items.filter(\.isDone) }

    init(template: ChecklistTemplate, startsEditing: Bool = false) {
        _template = State(initialValue: template)
        self.startsEditing = startsEditing
    }

    var body: some View {
        Form {
            Section(header: Text("Title")) {
                if canEdit && isEditingChecklist {
                    TextField("Checklist title", text: $template.title)
                } else {
                    Text(template.title)
                }
            }
            Section(header: Text("Group")) {
                if canEdit && isEditingChecklist {
                    TextField("Group", text: $draftGroupName)
                        .textInputAutocapitalization(.words)
                    if !store.availableChecklistGroups.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(store.availableChecklistGroups, id: \.self) { group in
                                    Button(group) {
                                        draftGroupName = group
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                        }
                    }
                } else {
                    Text(template.groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Ungrouped" : template.groupName)
                        .foregroundColor(.secondary)
                }
            }
            Section(header: Text("Assignee")) {
                if canEdit && isEditingChecklist && canAssignTasks {
                    Picker("Assignee", selection: checklistAssignmentSelection) {
                        Text("Unassigned").tag("")
                        ForEach(assignableMembers) { member in
                            Text(displayName(for: member)).tag(member.id)
                        }
                    }
                } else {
                    Text(checklistAssignmentLabel)
                        .foregroundColor(.secondary)
                }
            }
            Section(header: Text("Progress")) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("\(Int((progress * 100).rounded()))% complete")
                            .font(.headline)
                            .foregroundColor(progressTint)
                        Spacer()
                        Text("\(template.items.filter(\.isDone).count)/\(template.items.count)")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.secondary)
                    }

                    ProgressView(value: progress)
                        .tint(progressTint)
                        .scaleEffect(x: 1, y: 1.8, anchor: .center)
                        .padding(.vertical, 4)
                }
            }
            Section(header: Text("Due Date")) {
                if canEdit && isEditingChecklist && canManageChecklistDueDate {
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
            Section(header: Text("To Do")) {
                if todoItems.isEmpty {
                    Text("No open tasks")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(template.items) { item in
                        if !item.isDone {
                            taskRow(item)
                        }
                    }
                }
            }
            if !completedItems.isEmpty {
                Section(header: Text("Completed")) {
                    ForEach(completedItems) { item in
                        taskRow(item)
                    }
                }
            }
            if canEdit {
                Section(header: Text("Add Task")) {
                    TextField("New checklist item", text: Binding(
                        get: { newChecklistItemText },
                        set: { newValue in
                            newChecklistItemText = newValue
                        }
                    ))
                    .onSubmit {
                        addDraftChecklistTask()
                    }
                    if canAssignTasks {
                        Picker("Assigned To", selection: $newChecklistItemAssignedUserID) {
                            Text("Unassigned").tag("")
                            ForEach(assignableMembers) { member in
                                Text(displayName(for: member)).tag(member.id)
                            }
                        }
                    }
                    Toggle("Set task due date", isOn: $newChecklistItemHasDueDate)
                    if newChecklistItemHasDueDate {
                        DatePicker("Task Due", selection: $newChecklistItemDueDate, displayedComponents: [.date, .hourAndMinute])
                    }
                    TextField("Notes (optional)", text: $newChecklistItemNotes, axis: .vertical)
                        .lineLimit(2...4)
                    HStack {
                        Spacer()
                        Button("Add") {
                            addDraftChecklistTask()
                        }
                        .disabled(newChecklistItemText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                if isEditingChecklist {
                    Section {
                    Text(canManageChecklistDueDate
                         ? "Only paid subscriptions include task assignment. Only admins and owners can assign users."
                         : "Only owners and admins can set the overall checklist due date. Only paid subscriptions include task assignment.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }
            }
            Section {
                Button(canEdit && isEditingChecklist ? "Save & Close" : "Close") {
                    if canEdit && isEditingChecklist {
                        template.groupName = draftGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
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
        .sheet(item: $selectedTask) { selection in
            NavigationStack {
                ChecklistTaskDetailView(
                    template: $template,
                    itemID: selection.id,
                    canEdit: canEdit,
                    canAssignTasks: canAssignTasks,
                    showsAssignmentFeatures: showsAssignmentFeatures,
                    canManageChecklistDueDate: canManageChecklistDueDate,
                    assignableMembers: assignableMembers,
                    displayName: displayName(for:),
                    onSave: { persistChecklistDraft() }
                )
            }
        }
        .onAppear {
            // Ensure the system-provided back affordance is hidden and any left items removed
            // Unconditional diagnostic to ensure we see a log entry when this view appears
            DispatchQueue.main.async {
                NSLog("[DIAG] ChecklistRunView onAppear fired")
            }
            store.listenToTeamMembers()
            isEditingChecklist = startsEditing
            if let dueDate = template.dueDate {
                hasDueDate = true
                draftDueDate = dueDate
            } else {
                hasDueDate = false
                draftDueDate = Date()
            }
            newChecklistItemText = ""
            newChecklistItemNotes = ""
            newChecklistItemAssignedUserID = ""
            newChecklistItemHasDueDate = false
            newChecklistItemDueDate = Date()
            draftGroupName = template.groupName.trimmingCharacters(in: .whitespacesAndNewlines)
            selectedTask = nil
            activeMentionTarget = nil
            activeMentionQuery = ""
        }
        .onDisappear {
            if canEdit && isEditingChecklist {
                template.groupName = draftGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
                template.dueDate = hasDueDate ? draftDueDate : nil
                persistChecklistDraft()
            }
        }
    }

    @ViewBuilder
    private func inlineMentionSuggestions(for target: MentionTarget) -> some View {
        if activeMentionTarget == target {
            let suggestions = mentionSuggestions(for: activeMentionQuery)
            if !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(suggestions.prefix(6)) { member in
                        Button {
                            applyMention(member, to: target)
                        } label: {
                            Text(displayName(for: member))
                                .font(.subheadline)
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                        }
                        .buttonStyle(.plain)
                        if member.id != suggestions.prefix(6).last?.id {
                            Divider()
                        }
                    }
                }
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                )
                .padding(.leading, 28)
                .padding(.bottom, 4)
            }
        }
    }

    @ViewBuilder
    private func taskRow(_ item: ChecklistItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Button(action: { toggleItem(itemID: item.id) }) {
                    Image(systemName: item.isDone ? "checkmark.circle.fill" : "checkmark.circle")
                        .foregroundColor(item.isDone ? .green : .secondary)
                }
                .buttonStyle(.plain)

                Button {
                    selectedTask = SelectedTask(id: item.id)
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(displayChecklistText(item.text))
                            .font(.body.weight(.medium))
                            .foregroundColor(.primary)
                        let trimmedNotes = item.notes.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmedNotes.isEmpty {
                            Text(trimmedNotes)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        if showsAssignmentFeatures {
                            taskMetadataRow(item)
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
                .buttonStyle(.plain)

                if canEdit && isEditingChecklist {
                    Button(role: .destructive) {
                        deleteChecklistItem(id: item.id)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(taskRowBackground(for: item))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
        .draggable(dragTokenForTask(item))
        .dropDestination(for: String.self) { items, _ in
            handleDroppedTaskToken(items.first, before: item)
        }
    }

    private func toggleItem(itemID: String) {
        guard let idx = template.items.firstIndex(where: { $0.id == itemID }) else { return }
        template.items[idx].isDone.toggle()
        if template.items[idx].isDone {
            template.items[idx].subtasks = template.items[idx].subtasks.map { subtask in
                var updated = subtask
                updated.isDone = true
                updated.completedAt = updated.completedAt ?? Date()
                updated.completedBy = (updated.completedBy ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? completionUserLabel
                    : updated.completedBy
                return updated
            }
            template.items[idx].completedAt = Date()
            template.items[idx].completedBy = completionUserLabel
        } else {
            template.items[idx].completedAt = nil
            template.items[idx].completedBy = nil
        }
        persistChecklistDraft()
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
        persistChecklistDraft()
    }

    private func dragTokenForTask(_ item: ChecklistItem) -> String {
        "task:\(item.id)"
    }

    private func handleDroppedTaskToken(_ token: String?, before target: ChecklistItem) -> Bool {
        guard let token, token.hasPrefix("task:") else { return false }
        let draggedID = String(token.dropFirst("task:".count))
        reorderTask(draggedID: draggedID, before: target.id)
        return true
    }

    private func reorderTask(draggedID: String, before targetID: String) {
        guard let sourceIndex = template.items.firstIndex(where: { $0.id == draggedID }),
              let destinationIndex = template.items.firstIndex(where: { $0.id == targetID }),
              sourceIndex != destinationIndex else { return }
        let moved = template.items.remove(at: sourceIndex)
        template.items.insert(moved, at: destinationIndex)
        persistChecklistDraft()
    }

    var progress: Double {
        guard !template.items.isEmpty else { return 0 }
        return Double(template.items.filter { $0.isDone }.count) / Double(template.items.count)
    }

    private func displayName(for member: UserProfile) -> String {
        let trimmed = member.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return member.email.components(separatedBy: "@").first ?? member.email
    }

    private func itemTextBinding(for itemID: String) -> Binding<String> {
        Binding(
            get: { template.items.first(where: { $0.id == itemID })?.text ?? "" },
            set: { newValue in
                guard let index = template.items.firstIndex(where: { $0.id == itemID }) else { return }
                template.items[index].text = newValue
                updateMentionContext(for: newValue, target: .existingItem(itemID))
                persistChecklistDraft()
            }
        )
    }

    private var checklistAssignmentSelection: Binding<String> {
        Binding(
            get: { resolvedChecklistAssignmentUserID() },
            set: { newValue in
                let trimmedID = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedID.isEmpty,
                      let member = assignableMembers.first(where: { $0.id == trimmedID }) else {
                    template.assignedUserID = nil
                    template.assignedUserName = nil
                    template.assignedUserEmail = nil
                    return
                }
                template.assignedUserID = member.id
                template.assignedUserName = displayName(for: member)
                template.assignedUserEmail = member.email.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        )
    }

    private var checklistAssignmentLabel: String {
        let assignedName = template.assignedUserName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !assignedName.isEmpty { return assignedName }
        let assignedEmail = template.assignedUserEmail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !assignedEmail.isEmpty {
            return assignedEmail.components(separatedBy: "@").first ?? assignedEmail
        }

        let inferredTaskNames = Array(NSOrderedSet(array: template.items.compactMap { item in
            let storedName = item.assignedUserName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !storedName.isEmpty { return storedName }
            let storedEmail = item.assignedUserEmail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !storedEmail.isEmpty {
                return storedEmail.components(separatedBy: "@").first ?? storedEmail
            }
            return nil
        })) as? [String] ?? []
        if inferredTaskNames.count == 1 {
            return inferredTaskNames[0]
        }

        return "Unassigned"
    }

    private func resolvedChecklistAssignmentUserID() -> String {
        let explicitID = template.assignedUserID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !explicitID.isEmpty {
            return explicitID
        }

        let inferredIDs = Array(NSOrderedSet(array: template.items.compactMap { item in
            let assignedID = item.assignedUserID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return assignedID.isEmpty ? nil : assignedID
        })) as? [String] ?? []
        if inferredIDs.count == 1 {
            return inferredIDs[0]
        }

        let inferredEmails = Array(NSOrderedSet(array: template.items.compactMap { item in
            let assignedEmail = item.assignedUserEmail?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            return assignedEmail.isEmpty ? nil : assignedEmail
        })) as? [String] ?? []
        if inferredEmails.count == 1,
           let member = assignableMembers.first(where: {
               $0.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == inferredEmails[0]
           }) {
            return member.id
        }

        return ""
    }

    private func itemNotesBinding(for itemID: String) -> Binding<String> {
        Binding(
            get: { template.items.first(where: { $0.id == itemID })?.notes ?? "" },
            set: { newValue in
                guard let index = template.items.firstIndex(where: { $0.id == itemID }) else { return }
                template.items[index].notes = newValue
                persistChecklistDraft()
            }
        )
    }

    private func assignmentSelection(for itemID: String) -> Binding<String> {
        Binding(
            get: {
                guard let item = template.items.first(where: { $0.id == itemID }) else { return "" }
                return item.assignedUserID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            },
            set: { newValue in
                guard let index = template.items.firstIndex(where: { $0.id == itemID }) else { return }
                applyAssignment(selectedUserID: newValue, to: index)
                persistChecklistDraft()
            }
        )
    }

    private func itemHasDueDateBinding(for itemID: String) -> Binding<Bool> {
        Binding(
            get: { itemDueDateExists(itemID) },
            set: { shouldSetDueDate in
                guard let index = template.items.firstIndex(where: { $0.id == itemID }) else { return }
                template.items[index].dueDate = shouldSetDueDate ? (template.items[index].dueDate ?? template.dueDate ?? Date()) : nil
                persistChecklistDraft()
            }
        )
    }

    private func itemDueDateBinding(for itemID: String) -> Binding<Date> {
        Binding(
            get: {
                template.items.first(where: { $0.id == itemID })?.dueDate ?? template.dueDate ?? Date()
            },
            set: { newValue in
                guard let index = template.items.firstIndex(where: { $0.id == itemID }) else { return }
                template.items[index].dueDate = newValue
                persistChecklistDraft()
            }
        )
    }

    private func itemDueDateExists(_ itemID: String) -> Bool {
        template.items.first(where: { $0.id == itemID })?.dueDate != nil
    }

    private func makeChecklistItem(text: String, notes: String, assignedUserID: String, dueDate: Date?) -> ChecklistItem {
        var item = ChecklistItem(text: text, notes: notes, dueDate: dueDate)
        applyAssignment(selectedUserID: assignedUserID, to: &item)
        return item
    }

    private func addDraftChecklistTask() {
        let trimmed = newChecklistItemText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let trimmedNotes = newChecklistItemNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        let newItem = makeChecklistItem(
            text: trimmed,
            notes: trimmedNotes,
            assignedUserID: newChecklistItemAssignedUserID,
            dueDate: newChecklistItemHasDueDate ? newChecklistItemDueDate : nil
        )
        template.items.append(newItem)
        newChecklistItemText = ""
        newChecklistItemNotes = ""
        newChecklistItemAssignedUserID = ""
        newChecklistItemHasDueDate = false
        newChecklistItemDueDate = Date()
        persistChecklistDraft()
        selectedTask = SelectedTask(id: newItem.id)
    }

    private func applyAssignment(selectedUserID: String, to index: Int) {
        guard template.items.indices.contains(index) else { return }
        applyAssignment(selectedUserID: selectedUserID, to: &template.items[index])
    }

    private func applyAssignment(selectedUserID: String, to item: inout ChecklistItem) {
        let trimmedID = selectedUserID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty,
              let member = assignableMembers.first(where: { $0.id == trimmedID }) else {
            item.assignedUserID = nil
            item.assignedUserName = nil
            item.assignedUserEmail = nil
            return
        }
        item.assignedUserID = member.id
        item.assignedUserName = displayName(for: member)
        item.assignedUserEmail = member.email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func assignmentLabel(for item: ChecklistItem) -> String? {
        let explicitLabel = explicitAssignmentLabel(for: item)
        return explicitLabel.isEmpty ? nil : explicitLabel
    }

    private func explicitAssignmentLabel(for item: ChecklistItem) -> String {
        if let member = assignedMember(for: item) {
            return displayName(for: member)
        }

        let storedName = item.assignedUserName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !storedName.isEmpty { return storedName }

        let storedEmail = item.assignedUserEmail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !storedEmail.isEmpty {
            return storedEmail.components(separatedBy: "@").first ?? storedEmail
        }

        return ""
    }

    private func assignedMember(for item: ChecklistItem) -> UserProfile? {
        let assignedID = item.assignedUserID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !assignedID.isEmpty,
           let member = assignableMembers.first(where: { $0.id == assignedID }) {
            return member
        }

        let assignedEmail = item.assignedUserEmail?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if !assignedEmail.isEmpty {
            return assignableMembers.first {
                $0.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == assignedEmail
            }
        }

        return nil
    }

    @ViewBuilder
    private func taskMetadataRow(_ item: ChecklistItem) -> some View {
        HStack(spacing: 8) {
            if let assignmentText = assignmentLabel(for: item) {
                Label(assignmentText, systemImage: "person.crop.circle")
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.14))
                    .clipShape(Capsule())
            }
            if let dueDate = item.dueDate {
                Label(dueDateLabel(for: dueDate), systemImage: dueDate < Date() && !item.isDone ? "exclamationmark.circle" : "calendar")
                    .font(.caption2.weight(.medium))
                    .foregroundColor(dueDate < Date() && !item.isDone ? .red : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background((dueDate < Date() && !item.isDone ? Color.red : Color.gray).opacity(0.12))
                    .clipShape(Capsule())
            }
            Spacer(minLength: 0)
        }
    }

    private func dueDateLabel(for dueDate: Date) -> String {
        if Calendar.current.isDateInToday(dueDate) { return "Today" }
        if Calendar.current.isDateInTomorrow(dueDate) { return "Tomorrow" }
        return dueDate.formatted(date: .abbreviated, time: .shortened)
    }

    private func taskRowBackground(for item: ChecklistItem) -> some ShapeStyle {
        if item.isDone {
            return AnyShapeStyle(Color.green.opacity(0.08))
        }
        return AnyShapeStyle(Color.white.opacity(0.04))
    }

    private func mentionTokens(in text: String) -> Set<String> {
        let pattern = "(?<!\\S)@([A-Za-z0-9._-]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        let matches = regex.matches(in: text, options: [], range: range)
        var tokens: Set<String> = []
        for match in matches where match.numberOfRanges > 1 {
            let token = nsText.substring(with: match.range(at: 1))
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            if !token.isEmpty { tokens.insert(token) }
        }
        return tokens
    }

    private func displayChecklistText(_ text: String) -> String {
        let pattern = "(?<!\\S)@[A-Za-z0-9._-]+"
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        var cleaned = regex.stringByReplacingMatches(in: text, options: [], range: fullRange, withTemplate: "")
        cleaned = cleaned.replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func mentionMatchTokens(for member: UserProfile) -> Set<String> {
        let email = member.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var tokens: Set<String> = []
        if !email.isEmpty {
            tokens.insert(email)
            if let localPart = email.split(separator: "@").first, !localPart.isEmpty {
                tokens.insert(String(localPart))
            }
        }
        let name = displayName(for: member)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if !name.isEmpty {
            tokens.insert(name)
            tokens.insert(name.replacingOccurrences(of: " ", with: ""))
            tokens.insert(name.replacingOccurrences(of: " ", with: "."))
            tokens.insert(name.replacingOccurrences(of: " ", with: "_"))
            tokens.insert(name.replacingOccurrences(of: " ", with: "-"))
        }
        return tokens
    }

    private func mentionedMembers(in text: String) -> [UserProfile] {
        let tags = mentionTokens(in: text)
        guard !tags.isEmpty else { return [] }
        var seen: Set<String> = []
        return store.teamMembers
            .filter { member in
                let match = !mentionMatchTokens(for: member).isDisjoint(with: tags)
                if !match { return false }
                let id = member.id.trimmingCharacters(in: .whitespacesAndNewlines)
                if seen.contains(id) { return false }
                seen.insert(id)
                return true
            }
            .sorted { displayName(for: $0).localizedCaseInsensitiveCompare(displayName(for: $1)) == .orderedAscending }
    }

    private func isAssignedToCurrentUser(item: ChecklistItem) -> Bool {
        guard let current = store.user else { return false }
        let assignedID = item.assignedUserID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !assignedID.isEmpty,
           assignedID == current.id.trimmingCharacters(in: .whitespacesAndNewlines) {
            return true
        }
        let assignedEmail = item.assignedUserEmail?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if !assignedEmail.isEmpty,
           assignedEmail == current.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            return true
        }
        let tags = mentionTokens(in: item.text)
        if tags.isEmpty { return false }
        return !mentionMatchTokens(for: current).isDisjoint(with: tags)
    }

    private func mentionSuggestions(for query: String) -> [UserProfile] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return store.teamMembers
            .filter { member in
                let email = member.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if q.isEmpty { return true }
                let name = displayName(for: member).lowercased()
                let localPart = email.split(separator: "@").first.map(String.init) ?? ""
                return name.contains(q) || email.contains(q) || localPart.contains(q)
            }
            .sorted { displayName(for: $0).localizedCaseInsensitiveCompare(displayName(for: $1)) == .orderedAscending }
    }

    private func currentMentionContext(in text: String) -> (range: Range<String.Index>, query: String)? {
        guard let atIndex = text.lastIndex(of: "@") else { return nil }
        if atIndex != text.startIndex {
            let previous = text[text.index(before: atIndex)]
            if !previous.isWhitespace { return nil }
        }
        let queryStart = text.index(after: atIndex)
        let queryPart = text[queryStart...]
        if queryPart.contains(where: { $0.isWhitespace }) { return nil }
        return (atIndex..<text.endIndex, String(queryPart))
    }

    private func updateMentionContext(for text: String, target: MentionTarget) {
        if let context = currentMentionContext(in: text) {
            activeMentionTarget = target
            activeMentionQuery = context.query
        } else if activeMentionTarget == target {
            activeMentionTarget = nil
            activeMentionQuery = ""
        }
    }

    private func mentionToken(for member: UserProfile) -> String {
        let name = displayName(for: member).trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            return name.lowercased().replacingOccurrences(of: " ", with: ".")
        }
        let email = member.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return email.split(separator: "@").first.map(String.init) ?? "user"
    }

    private func applyMention(_ member: UserProfile, to target: MentionTarget) {
        let token = "@\(mentionToken(for: member)) "
        switch target {
        case .newItem:
            guard let context = currentMentionContext(in: newChecklistItemText) else { return }
            newChecklistItemText.replaceSubrange(context.range, with: token)
            updateMentionContext(for: newChecklistItemText, target: .newItem)
        case .existingItem(let id):
            guard let idx = template.items.firstIndex(where: { $0.id == id }) else { return }
            guard let context = currentMentionContext(in: template.items[idx].text) else { return }
            template.items[idx].text.replaceSubrange(context.range, with: token)
            updateMentionContext(for: template.items[idx].text, target: .existingItem(id))
            persistChecklistDraft()
        }
    }

    private func persistChecklistDraft() {
        template.items = template.items.map { item in
            var updatedItem = item
            updatedItem.notes = updatedItem.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            return updatedItem
        }
        updateChecklistCompletionMetadata()
        store.saveChecklist(template)
    }
}

private struct ChecklistTaskDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var template: ChecklistTemplate
    @State private var activeMentionQuery = ""
    @State private var newSubtaskTitle = ""
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showingFileImporter = false
    @State private var isUploadingAttachment = false
    @State private var attachmentError: String?
    let itemID: String
    let canEdit: Bool
    let canAssignTasks: Bool
    let showsAssignmentFeatures: Bool
    let canManageChecklistDueDate: Bool
    let assignableMembers: [UserProfile]
    let displayName: (UserProfile) -> String
    let onSave: () -> Void

    private var itemIndex: Int? {
        template.items.firstIndex(where: { $0.id == itemID })
    }

    private var item: ChecklistItem? {
        guard let itemIndex else { return nil }
        return template.items[itemIndex]
    }

    private var progressTint: Color {
        item?.isDone == true ? .green : .blue
    }

    var body: some View {
        Group {
            if let currentItem = item {
                taskDetailForm(for: currentItem)
                .navigationTitle(displayChecklistText(currentItem.text))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
                .onChange(of: selectedPhotoItem) { newValue in
                    guard let newValue else { return }
                    Task {
                        await uploadPhotoAttachment(from: newValue)
                        await MainActor.run {
                            selectedPhotoItem = nil
                        }
                    }
                }
                .fileImporter(
                    isPresented: $showingFileImporter,
                    allowedContentTypes: [.item],
                    allowsMultipleSelection: false
                ) { result in
                    handleFileImport(result)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary)
                    Text("Task Not Found")
                        .font(.headline)
                        .foregroundColor(.primary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func taskDetailForm(for item: ChecklistItem) -> some View {
        Form {
            completionSection(for: item)
            taskSection(for: item)
            commentSection(for: item)
            detailsSection(for: item)
            subtasksSection
            attachmentsSection

            if showsAssignmentFeatures {
                Section("Status") {
                    taskMetadataRow(item)
                }
            }

            if item.isDone, let completedAt = item.completedAt {
                Section("Completion") {
                    if let by = item.completedBy?.trimmingCharacters(in: .whitespacesAndNewlines), !by.isEmpty {
                        Text("Checked by \(by)")
                    }
                    Text("Completed on \(completedAt.formatted(date: .abbreviated, time: .shortened))")
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func completionSection(for item: ChecklistItem) -> some View {
        Section {
            if item.isDone {
                Button {
                    toggleComplete()
                } label: {
                    Label("Completed", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(BorderedProminentButtonStyle())
                .tint(.green)
            } else {
                Button {
                    toggleComplete()
                } label: {
                    Label("Mark Complete", systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(BorderedButtonStyle())
                .tint(.secondary)
            }
        }
    }

    private func taskSection(for item: ChecklistItem) -> some View {
        Section("Task") {
            if canEdit {
                TextField("Task title", text: itemTextBinding)
            } else {
                Text(displayChecklistText(item.text))
            }
        }
    }

    private func commentSection(for item: ChecklistItem) -> some View {
        Section("Comment") {
            if canEdit {
                VStack(alignment: .leading, spacing: 10) {
                    TextEditor(text: itemNotesBinding)
                        .frame(minHeight: 180)
                    if currentMentionContext(in: item.notes) != nil {
                        mentionSuggestionsList
                    }
                }
            } else {
                let trimmedNotes = item.notes.trimmingCharacters(in: .whitespacesAndNewlines)
                Text(trimmedNotes.isEmpty ? "No comment" : item.notes)
                    .foregroundColor(trimmedNotes.isEmpty ? .secondary : .primary)
            }
        }
    }

    private func detailsSection(for item: ChecklistItem) -> some View {
        Section("Details") {
            if canAssignTasks {
                Picker("Assignee", selection: assignmentSelection) {
                    Text("Unassigned").tag("")
                    ForEach(assignableMembers) { member in
                        Text(displayName(member)).tag(member.id)
                    }
                }
            } else {
                LabeledContent("Assignee", value: assignmentLabel(for: item) ?? "Unassigned")
            }

            if canManageChecklistDueDate {
                Toggle("Set due date", isOn: itemHasDueDateBinding)
                if itemDueDateExists {
                    DatePicker("Task Due", selection: itemDueDateBinding, displayedComponents: [.date, .hourAndMinute])
                }
            } else {
                LabeledContent("Due date", value: item.dueDate.map { dueDateLabel(for: $0) } ?? "No due date")
            }
        }
    }

    private var subtasksSection: some View {
        Section("Subtasks") {
            if let itemIndex {
                if template.items[itemIndex].subtasks.isEmpty {
                    Text("No subtasks")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(Array(template.items[itemIndex].subtasks.indices), id: \.self) { subtaskIndex in
                        subtaskRow(itemIndex: itemIndex, subtaskIndex: subtaskIndex)
                    }
                }

                if canEdit {
                    HStack {
                        TextField("Add subtask", text: $newSubtaskTitle)
                            .onSubmit {
                                addSubtask()
                            }
                        Button("Add") {
                            addSubtask()
                        }
                        .disabled(newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
    }

    private func subtaskRow(itemIndex: Int, subtaskIndex: Int) -> some View {
        let subtask = template.items[itemIndex].subtasks[subtaskIndex]
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Button {
                    toggleSubtask(at: subtaskIndex)
                } label: {
                    Image(systemName: subtask.isDone ? "checkmark.circle.fill" : "checkmark.circle")
                        .foregroundColor(subtask.isDone ? .green : .secondary)
                }
                .buttonStyle(.plain)

                if canEdit {
                    TextField("Subtask", text: subtaskTextBinding(for: subtaskIndex))
                } else {
                    Text(subtask.text)
                        .foregroundColor(.primary)
                }

                if canEdit {
                    Button(role: .destructive) {
                        removeSubtask(at: subtaskIndex)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                }
            }

            if subtask.isDone, let completedAt = subtask.completedAt {
                let completedBy = subtask.completedBy?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                Text(
                    completedBy.isEmpty
                    ? "Completed on \(completedAt.formatted(date: .abbreviated, time: .shortened))"
                    : "Completed by \(completedBy) on \(completedAt.formatted(date: .abbreviated, time: .shortened))"
                )
                .font(.caption2)
                .foregroundColor(.secondary)
            }
        }
    }

    private var attachmentsSection: some View {
        Section("Attachments") {
            if let itemIndex {
                if template.items[itemIndex].attachments.isEmpty {
                    Text("No attachments")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(template.items[itemIndex].attachments) { attachment in
                        attachmentRow(attachment)
                    }
                }
            }

            if canEdit {
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Label("Add Photo", systemImage: "photo")
                }
                Button {
                    showingFileImporter = true
                } label: {
                    Label("Add File", systemImage: "paperclip")
                }
                if isUploadingAttachment {
                    ProgressView("Uploading attachment…")
                }
                if let attachmentError, !attachmentError.isEmpty {
                    Text(attachmentError)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        }
    }

    private func attachmentRow(_ attachment: ChecklistTaskAttachment) -> some View {
        HStack {
            if let url = URL(string: attachment.url.trimmingCharacters(in: .whitespacesAndNewlines)) {
                Link(destination: url) {
                    Label(attachment.name, systemImage: attachmentSystemImage(for: attachment.kind))
                }
            } else {
                Label(attachment.name, systemImage: attachmentSystemImage(for: attachment.kind))
                    .foregroundColor(.secondary)
            }
            Spacer()
            if canEdit {
                Button(role: .destructive) {
                    removeAttachment(id: attachment.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var itemTextBinding: Binding<String> {
        Binding(
            get: { item?.text ?? "" },
            set: { newValue in
                guard let itemIndex else { return }
                template.items[itemIndex].text = newValue
                onSave()
            }
        )
    }

    private var itemNotesBinding: Binding<String> {
        Binding(
            get: { item?.notes ?? "" },
            set: { newValue in
                guard let itemIndex else { return }
                template.items[itemIndex].notes = newValue
                updateMentionContext(for: newValue)
                onSave()
            }
        )
    }

    @ViewBuilder
    private var mentionSuggestionsList: some View {
        let suggestions = mentionSuggestions(for: activeMentionQuery)
        if !suggestions.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(suggestions.prefix(6)) { member in
                    Button {
                        applyMention(member)
                    } label: {
                        Text(displayName(member))
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    if member.id != suggestions.prefix(6).last?.id {
                        Divider()
                    }
                }
            }
        }
    }

    private var assignmentSelection: Binding<String> {
        Binding(
            get: { item?.assignedUserID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" },
            set: { newValue in
                guard let itemIndex else { return }
                applyAssignment(selectedUserID: newValue, to: itemIndex)
                onSave()
            }
        )
    }

    private var itemHasDueDateBinding: Binding<Bool> {
        Binding(
            get: { item?.dueDate != nil },
            set: { shouldSet in
                guard let itemIndex else { return }
                template.items[itemIndex].dueDate = shouldSet ? (template.items[itemIndex].dueDate ?? template.dueDate ?? Date()) : nil
                onSave()
            }
        )
    }

    private var itemDueDateBinding: Binding<Date> {
        Binding(
            get: { item?.dueDate ?? template.dueDate ?? Date() },
            set: { newValue in
                guard let itemIndex else { return }
                template.items[itemIndex].dueDate = newValue
                onSave()
            }
        )
    }

    private var itemDueDateExists: Bool {
        item?.dueDate != nil
    }

    private func subtaskTextBinding(for index: Int) -> Binding<String> {
        Binding(
            get: {
                guard let itemIndex, template.items[itemIndex].subtasks.indices.contains(index) else { return "" }
                return template.items[itemIndex].subtasks[index].text
            },
            set: { newValue in
                guard let itemIndex, template.items[itemIndex].subtasks.indices.contains(index) else { return }
                template.items[itemIndex].subtasks[index].text = newValue
                onSave()
            }
        )
    }

    private func addSubtask() {
        let trimmed = newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let itemIndex else { return }
        template.items[itemIndex].subtasks.append(ChecklistSubtask(text: trimmed))
        newSubtaskTitle = ""
        onSave()
    }

    private func toggleSubtask(at index: Int) {
        guard let itemIndex, template.items[itemIndex].subtasks.indices.contains(index) else { return }
        template.items[itemIndex].subtasks[index].isDone.toggle()
        if template.items[itemIndex].subtasks[index].isDone {
            template.items[itemIndex].subtasks[index].completedAt = Date()
            template.items[itemIndex].subtasks[index].completedBy = completionUserLabel()
        } else {
            template.items[itemIndex].subtasks[index].completedAt = nil
            template.items[itemIndex].subtasks[index].completedBy = nil
        }
        onSave()
    }

    private func removeSubtask(at index: Int) {
        guard let itemIndex, template.items[itemIndex].subtasks.indices.contains(index) else { return }
        template.items[itemIndex].subtasks.remove(at: index)
        onSave()
    }

    private func removeAttachment(id: String) {
        guard let itemIndex else { return }
        template.items[itemIndex].attachments.removeAll { $0.id == id }
        onSave()
    }

    private func attachmentSystemImage(for kind: TicketAttachmentKind) -> String {
        switch kind {
        case .image: return "photo"
        case .video: return "video"
        case .document: return "paperclip"
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            uploadFileAttachment(from: url)
        case .failure(let error):
            attachmentError = "Attachment upload failed: \(error.localizedDescription)"
        }
    }

    private func toggleComplete() {
        guard let itemIndex else { return }
        template.items[itemIndex].isDone.toggle()
        if template.items[itemIndex].isDone {
            template.items[itemIndex].subtasks = template.items[itemIndex].subtasks.map { subtask in
                var updated = subtask
                updated.isDone = true
                updated.completedAt = updated.completedAt ?? Date()
                return updated
            }
            template.items[itemIndex].completedAt = Date()
            template.items[itemIndex].completedBy = completionUserLabel()
        } else {
            template.items[itemIndex].completedAt = nil
            template.items[itemIndex].completedBy = nil
        }
        updateChecklistCompletionMetadata()
        onSave()
    }

    @MainActor
    private func uploadPhotoAttachment(from item: PhotosPickerItem) async {
        guard let itemIndex,
              let data = try? await item.loadTransferable(type: Data.self) else { return }
        isUploadingAttachment = true
        attachmentError = nil
        let filename = "Photo-\(UUID().uuidString.prefix(8)).jpg"
        let path = "checklistTaskAttachments/\(template.id)/\(itemID)/\(UUID().uuidString)-\(filename)"
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        let storageRef = Storage.storage().reference().child(path)
        storageRef.putData(data, metadata: metadata) { _, error in
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
                    guard let urlString = url?.absoluteString else { return }
                    template.items[itemIndex].attachments.append(
                        ChecklistTaskAttachment(url: urlString, name: filename, kind: .image)
                    )
                    onSave()
                }
            }
        }
    }

    private func uploadFileAttachment(from url: URL) {
        guard let itemIndex else { return }
        attachmentError = nil
        isUploadingAttachment = true
        let didAccess = url.startAccessingSecurityScopedResource()
        let safeName = url.lastPathComponent.replacingOccurrences(of: " ", with: "_")
        let kind = inferredAttachmentKind(for: url)
        let path = "checklistTaskAttachments/\(template.id)/\(itemID)/\(UUID().uuidString)-\(safeName)"
        let metadata = StorageMetadata()
        metadata.contentType = contentType(for: url, kind: kind)
        let storageRef = Storage.storage().reference().child(path)
        storageRef.putFile(from: url, metadata: metadata) { _, error in
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
            if let error {
                DispatchQueue.main.async {
                    isUploadingAttachment = false
                    attachmentError = "Attachment upload failed: \(error.localizedDescription)"
                }
                return
            }
            storageRef.downloadURL { downloadURL, downloadError in
                DispatchQueue.main.async {
                    isUploadingAttachment = false
                    if let downloadError {
                        attachmentError = "Attachment upload failed: \(downloadError.localizedDescription)"
                        return
                    }
                    guard let urlString = downloadURL?.absoluteString else { return }
                    template.items[itemIndex].attachments.append(
                        ChecklistTaskAttachment(url: urlString, name: safeName, kind: kind)
                    )
                    onSave()
                }
            }
        }
    }

    private func inferredAttachmentKind(for url: URL) -> TicketAttachmentKind {
        let ext = url.pathExtension.lowercased()
        if ["jpg", "jpeg", "png", "heic", "gif", "webp"].contains(ext) {
            return .image
        }
        if ["mov", "mp4", "m4v", "avi"].contains(ext) {
            return .video
        }
        return .document
    }

    private func contentType(for url: URL, kind: TicketAttachmentKind) -> String {
        if let type = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType {
            return type
        }
        switch kind {
        case .image: return "image/jpeg"
        case .video: return "video/quicktime"
        case .document: return "application/octet-stream"
        }
    }

    private func applyAssignment(selectedUserID: String, to index: Int) {
        let trimmedID = selectedUserID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty,
              let member = assignableMembers.first(where: { $0.id == trimmedID }) else {
            template.items[index].assignedUserID = nil
            template.items[index].assignedUserName = nil
            template.items[index].assignedUserEmail = nil
            return
        }
        template.items[index].assignedUserID = member.id
        template.items[index].assignedUserName = displayName(member)
        template.items[index].assignedUserEmail = member.email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func assignmentLabel(for item: ChecklistItem) -> String? {
        if let member = assignedMember(for: item) {
            return displayName(member)
        }
        let storedName = item.assignedUserName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !storedName.isEmpty { return storedName }
        let storedEmail = item.assignedUserEmail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !storedEmail.isEmpty {
            return storedEmail.components(separatedBy: "@").first ?? storedEmail
        }
        return nil
    }

    private func assignedMember(for item: ChecklistItem) -> UserProfile? {
        let assignedID = item.assignedUserID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !assignedID.isEmpty,
           let member = assignableMembers.first(where: { $0.id == assignedID }) {
            return member
        }
        let assignedEmail = item.assignedUserEmail?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if !assignedEmail.isEmpty {
            return assignableMembers.first {
                $0.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == assignedEmail
            }
        }
        return nil
    }

    @ViewBuilder
    private func taskMetadataRow(_ item: ChecklistItem) -> some View {
        HStack(spacing: 8) {
            if let assignmentText = assignmentLabel(for: item) {
                Label(assignmentText, systemImage: "person.crop.circle")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.14))
                    .clipShape(Capsule())
            }
            if let dueDate = item.dueDate {
                Label(dueDateLabel(for: dueDate), systemImage: dueDate < Date() && !item.isDone ? "exclamationmark.circle" : "calendar")
                    .font(.caption.weight(.medium))
                    .foregroundColor(dueDate < Date() && !item.isDone ? .red : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background((dueDate < Date() && !item.isDone ? Color.red : Color.gray).opacity(0.12))
                    .clipShape(Capsule())
            }
            Spacer(minLength: 0)
        }
    }

    private func dueDateLabel(for dueDate: Date) -> String {
        if Calendar.current.isDateInToday(dueDate) { return "Today" }
        if Calendar.current.isDateInTomorrow(dueDate) { return "Tomorrow" }
        return dueDate.formatted(date: .abbreviated, time: .shortened)
    }

    private func displayChecklistText(_ text: String) -> String {
        let pattern = "(?<!\\S)@[A-Za-z0-9._-]+"
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        var cleaned = regex.stringByReplacingMatches(in: text, options: [], range: fullRange, withTemplate: "")
        cleaned = cleaned.replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
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
                template.completedBy = completionUserLabel()
            }
        } else {
            template.completedAt = nil
            template.completedBy = nil
        }
    }

    private func completionUserLabel() -> String {
        assignableMembers.first(where: { $0.email == Auth.auth().currentUser?.email })?.displayName
        ?? Auth.auth().currentUser?.email
        ?? "Unknown User"
    }

    private func mentionSuggestions(for query: String) -> [UserProfile] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return assignableMembers
            .filter { member in
                let email = member.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if q.isEmpty { return true }
                let name = displayName(member).lowercased()
                let localPart = email.split(separator: "@").first.map(String.init) ?? ""
                return name.contains(q) || email.contains(q) || localPart.contains(q)
            }
    }

    private func currentMentionContext(in text: String) -> (range: Range<String.Index>, query: String)? {
        guard let atIndex = text.lastIndex(of: "@") else { return nil }
        if atIndex != text.startIndex {
            let previous = text[text.index(before: atIndex)]
            if !previous.isWhitespace { return nil }
        }
        let queryStart = text.index(after: atIndex)
        let queryPart = text[queryStart...]
        if queryPart.contains(where: { $0.isWhitespace }) { return nil }
        return (atIndex..<text.endIndex, String(queryPart))
    }

    private func updateMentionContext(for text: String) {
        if let context = currentMentionContext(in: text) {
            activeMentionQuery = context.query
        } else {
            activeMentionQuery = ""
        }
    }

    private func mentionToken(for member: UserProfile) -> String {
        let name = displayName(member).trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            return name.lowercased().replacingOccurrences(of: " ", with: ".")
        }
        let email = member.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return email.split(separator: "@").first.map(String.init) ?? "user"
    }

    private func applyMention(_ member: UserProfile) {
        guard let itemIndex,
              let context = currentMentionContext(in: template.items[itemIndex].notes) else { return }
        template.items[itemIndex].notes.replaceSubrange(context.range, with: "@\(mentionToken(for: member)) ")
        updateMentionContext(for: template.items[itemIndex].notes)
        onSave()
    }
}

struct CreateChecklistView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var store: ProdConnectStore
    @State private var title = ""
    @State private var groupName = ""
    @State private var itemsText = "Item 1\nItem 2"
    @State private var hasDueDate = false
    @State private var dueDate = Date()
    private var canManageChecklistDueDate: Bool { store.user?.isAdmin == true || store.user?.isOwner == true }

    var onSave: (ChecklistTemplate) -> Void

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $title)
                Section("Group") {
                    TextField("Group", text: $groupName)
                        .textInputAutocapitalization(.words)
                    if !store.availableChecklistGroups.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(store.availableChecklistGroups, id: \.self) { group in
                                    Button(group) {
                                        groupName = group
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                        }
                    }
                }
                Section("Due Date") {
                    if canManageChecklistDueDate {
                        Toggle("Set due date", isOn: $hasDueDate)
                        if hasDueDate {
                            DatePicker("Due", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                        }
                    } else {
                        Text("Only owners and admins can set the overall checklist due date.")
                            .foregroundColor(.secondary)
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
                            groupName: groupName.trimmingCharacters(in: .whitespacesAndNewlines),
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
    @State private var selectedDirectChannel: ChatChannel?
    var isAdmin: Bool { store.user?.isAdmin == true }
    private var currentEmail: String? {
        store.user?.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    private var visibleChannels: [ChatChannel] {
        if isAdmin { return store.channels }
        guard let email = store.user?.email else { return [] }
        return store.channels.filter { !$0.isHidden && !$0.hiddenUserEmails.contains(email) }
    }
    private var channelsToShow: [ChatChannel] {
        visibleChannels
            .filter { $0.kind != .direct }
            .sorted { lhs, rhs in
                if lhs.position != rhs.position { return lhs.position < rhs.position }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }
    private var directChannelsToShow: [ChatChannel] {
        guard let currentEmail else { return [] }
        let raw = visibleChannels
            .filter { $0.kind == .direct }
            .filter { channel in
                let participants = channel.participantEmails.map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                }
                return participants.isEmpty || participants.contains(currentEmail)
            }

        // Deduplicate historical direct channels with the same participant set.
        var uniqueByParticipants: [String: ChatChannel] = [:]
        for channel in raw {
            let key = participantKey(for: channel, currentEmail: currentEmail)
            if let existing = uniqueByParticipants[key] {
                let existingTime = existing.lastMessageAt ?? existing.messages.last?.timestamp ?? .distantPast
                let incomingTime = channel.lastMessageAt ?? channel.messages.last?.timestamp ?? .distantPast
                if incomingTime > existingTime {
                    uniqueByParticipants[key] = channel
                }
            } else {
                uniqueByParticipants[key] = channel
            }
        }

        return Array(uniqueByParticipants.values)
            .sorted { lhs, rhs in
                if let l = lhs.lastMessageAt, let r = rhs.lastMessageAt, l != r { return l > r }
                if lhs.messages.count != rhs.messages.count { return lhs.messages.count > rhs.messages.count }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }
    private var directMessageUsersToShow: [UserProfile] {
        guard let currentEmail else { return [] }
        let existingOneToOneRecipients = Set(
            directChannelsToShow.compactMap { channel -> String? in
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
                            var reordered = channelsToShow
                            reordered.move(fromOffsets: indices, toOffset: newOffset)
                            for (idx, item) in reordered.enumerated() {
                                var updated = item
                                updated.position = idx
                                store.saveChannel(updated)
                            }
                        }
                        .onDelete { idx in
                            guard isAdmin else { return }
                            for i in idx {
                                store.deleteChannel(channelsToShow[i])
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
                    Section {
                        ForEach(directChannelsToShow) { channel in
                            NavigationLink {
                                ChatChannelDetailView(channel: channel)
                            } label: {
                                Text(directMessageTitle(for: channel))
                                    .font(.headline)
                            }
                        }
                        ForEach(directMessageUsersToShow) { member in
                            Button {
                                openOrCreateDirectMessage(with: [member])
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(displayName(for: member))
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                }
                            }
                        }
                    } header: {
                        Text("Direct Messages")
                            .font(.title3)
                            .fontWeight(.semibold)
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
                .navigationDestination(
                    isPresented: Binding(
                        get: { selectedDirectChannel != nil },
                        set: { isPresented in
                            if !isPresented { selectedDirectChannel = nil }
                        }
                    )
                ) {
                    if let channel = selectedDirectChannel {
                        ChatChannelDetailView(channel: channel)
                    }
                }
            }
            .navigationTitle("Chat")
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    private func displayName(for member: UserProfile) -> String {
        let trimmed = member.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return member.email.components(separatedBy: "@").first ?? member.email
    }

    private func directMessageTitle(for channel: ChatChannel) -> String {
        guard let currentEmail else { return channel.name }
        let participants = channel.participantEmails
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty && $0 != currentEmail }
        if participants.isEmpty { return channel.name }

        let names = participants.map { email in
            if let member = store.teamMembers.first(where: {
                $0.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == email
            }) {
                return displayName(for: member)
            }
            return email.components(separatedBy: "@").first ?? email
        }
        let uniqueNames = Array(NSOrderedSet(array: names)) as? [String] ?? names
        return uniqueNames.joined(separator: ", ")
    }

    private func participantKey(for channel: ChatChannel, currentEmail: String) -> String {
        let participants = channel.participantEmails
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        if participants.isEmpty {
            return "legacy:\(channel.id)"
        }
        let normalized = Array(Set(participants)).sorted()
        return normalized.joined(separator: "|")
    }

    private func openOrCreateDirectMessage(with members: [UserProfile]) {
        guard let teamCode = store.teamCode else { return }
        guard let currentEmail = currentEmail else { return }
        let recipients = members
            .map { $0.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty && $0 != currentEmail }
        guard !recipients.isEmpty else { return }

        let participants = Array(Set(recipients + [currentEmail])).sorted()
        if let existing = store.channels.first(where: { channel in
            channel.kind == .direct && channel.participantEmails.map { $0.lowercased() }.sorted() == participants
        }) {
            selectedDirectChannel = existing
            return
        }

        let dmName = "Direct Message"

        let newChannel = ChatChannel(
            name: dmName,
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
        selectedDirectChannel = newChannel
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
    @State private var showAddParticipants = false

    private let maxAttachmentBytes = 100 * 1024 * 1024
    private let maxMentionSuggestions = 8

    private var isAdmin: Bool { store.user?.isAdmin == true }
    private var isDirectMessage: Bool { channel.kind == .direct }
    private var channelTitle: String {
        guard isDirectMessage else { return channel.name }
        let participants = channel.participantEmails
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        guard !participants.isEmpty else { return channel.name }

        let currentEmail = store.user?.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let names = participants
            .filter { $0 != currentEmail }
            .map { email in
            if let member = store.teamMembers.first(where: {
                $0.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == email
            }) {
                return displayName(for: member)
            }
            if let current = store.user,
               current.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == email {
                return displayName(for: current)
            }
            return email.components(separatedBy: "@").first ?? email
        }

        let uniqueNames = Array(NSOrderedSet(array: names)) as? [String] ?? names
        if uniqueNames.isEmpty { return channel.name }
        return uniqueNames.joined(separator: ", ")
    }
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
                            let isMentioned = isCurrentUserMentioned(in: msg.text)
                            if !msg.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(msg.text)
                                    .padding(.horizontal, isMentioned ? 8 : 0)
                                    .padding(.vertical, isMentioned ? 6 : 0)
                                    .background(isMentioned ? Color.yellow.opacity(0.22) : Color.clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
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
                    store.setActiveChatChannel(channel.id)
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
                .onDisappear {
                    store.setActiveChatChannel(nil)
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
            VStack(spacing: 6) {
                if let context = currentMentionContext(in: newMessage) {
                    let suggestions = mentionSuggestions(for: context.query)
                    if !suggestions.isEmpty {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(suggestions.prefix(maxMentionSuggestions)) { member in
                                    Button {
                                        applyMention(member, context: context)
                                    } label: {
                                        HStack {
                                            Text(displayName(for: member))
                                                .foregroundColor(.primary)
                                            Spacer()
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 8)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    if member.id != suggestions.prefix(maxMentionSuggestions).last?.id {
                                        Divider()
                                    }
                                }
                            }
                        }
                        .frame(maxHeight: 180)
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                    }
                }
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
        .navigationTitle(channelTitle)
        .toolbar {
            if isDirectMessage {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") { showAddParticipants = true }
                }
            }
            if isAdmin && !isDirectMessage {
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
        .sheet(isPresented: Binding(
            get: { showSettings && !isDirectMessage },
            set: { showSettings = $0 }
        )) {
            ChannelSettingsView(channel: $channel)
        }
        .sheet(isPresented: $showAddParticipants) {
            DirectMessagePickerView(initialSelectedIDs: selectedParticipantIDsForPicker()) { selectedMembers in
                updateDirectMessageParticipants(with: selectedMembers)
            }
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
                channel.lastMessageAt = updatedMessages.last?.timestamp
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
                channel.lastMessageAt = updatedMessages.last?.timestamp
                if let idx = store.channels.firstIndex(where: { $0.id == channel.id }) {
                    store.channels[idx] = channel
                }
            case .failure(let error):
                attachmentError = "Update failed: \(error.localizedDescription)"
            }
        }
    }

    private func deleteMessage(_ msg: ChatMessage) {
        let attachmentURLToDelete = msg.attachmentURL
        let updatedMessages = channel.messages.filter { $0.id != msg.id }
        persistMessages(updatedMessages) { result in
            switch result {
            case .success:
                channel.messages = updatedMessages
                channel.lastMessageAt = updatedMessages.last?.timestamp
                if let idx = store.channels.firstIndex(where: { $0.id == channel.id }) {
                    store.channels[idx] = channel
                }
                deleteMessageAttachmentIfNeeded(attachmentURLToDelete)
            case .failure(let error):
                attachmentError = "Delete failed: \(error.localizedDescription)"
            }
        }
    }

    private func deleteMessageAttachmentIfNeeded(_ urlString: String?) {
        guard let raw = urlString?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return }
        guard raw.hasPrefix("gs://") || raw.contains("firebasestorage.googleapis.com") || raw.contains("storage.googleapis.com") else {
            return
        }
        Storage.storage().reference(forURL: raw).delete { error in
            if let error {
                print("DEBUG: Failed to delete chat attachment: \(error.localizedDescription)")
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
        let lastMessageAtValue: Any = messages.last.map { Timestamp(date: $0.timestamp) } ?? NSNull()
        store.db.collection("channels").document(channel.id).setData(["messages": payload, "lastMessageAt": lastMessageAtValue], merge: true) { error in
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

    private func isCurrentUserMentioned(in text: String) -> Bool {
        guard !isDirectMessage else { return false }
        let mentions = extractMentionTokens(from: text)
        guard !mentions.isEmpty else { return false }
        let currentTokens = mentionMatchTokensForCurrentUser()
        return !mentions.isDisjoint(with: currentTokens)
    }

    private func extractMentionTokens(from text: String) -> Set<String> {
        let pattern = "(?<!\\S)@([A-Za-z0-9._-]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        let matches = regex.matches(in: text, options: [], range: range)
        var tokens: Set<String> = []
        for match in matches where match.numberOfRanges > 1 {
            let token = nsText.substring(with: match.range(at: 1))
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            if !token.isEmpty {
                tokens.insert(token)
            }
        }
        return tokens
    }

    private func mentionMatchTokensForCurrentUser() -> Set<String> {
        guard let emailRaw = store.user?.email else { return [] }
        let email = emailRaw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !email.isEmpty else { return [] }

        var tokens: Set<String> = [email]
        if let localPart = email.split(separator: "@").first, !localPart.isEmpty {
            tokens.insert(String(localPart))
        }

        let currentDisplayName: String = {
            if let member = store.teamMembers.first(where: { $0.email.lowercased() == email }) {
                return member.displayName
            }
            return store.user?.displayName ?? ""
        }()

        let displayName = currentDisplayName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if !displayName.isEmpty {
            tokens.insert(displayName)
            tokens.insert(displayName.replacingOccurrences(of: " ", with: ""))
            tokens.insert(displayName.replacingOccurrences(of: " ", with: "."))
            tokens.insert(displayName.replacingOccurrences(of: " ", with: "_"))
            tokens.insert(displayName.replacingOccurrences(of: " ", with: "-"))
            let parts = displayName.split { $0 == " " || $0 == "." || $0 == "_" || $0 == "-" }
            for part in parts where !part.isEmpty {
                tokens.insert(String(part))
            }
        }

        return tokens
    }

    private func mentionSuggestions(for query: String) -> [UserProfile] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let currentEmail = store.user?.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return store.teamMembers
            .filter { member in
                let email = member.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if let currentEmail, email == currentEmail { return false }
                if trimmedQuery.isEmpty { return true }
                let name = displayName(for: member).lowercased()
                let localPart = email.split(separator: "@").first.map(String.init) ?? ""
                return name.contains(trimmedQuery) || email.contains(trimmedQuery) || localPart.contains(trimmedQuery)
            }
            .sorted { lhs, rhs in
                displayName(for: lhs).localizedCaseInsensitiveCompare(displayName(for: rhs)) == .orderedAscending
            }
    }

    private func currentMentionContext(in text: String) -> (range: Range<String.Index>, query: String)? {
        guard let atIndex = text.lastIndex(of: "@") else { return nil }
        if atIndex != text.startIndex {
            let previous = text[text.index(before: atIndex)]
            if !previous.isWhitespace { return nil }
        }
        let queryStart = text.index(after: atIndex)
        let queryPart = text[queryStart...]
        if queryPart.contains(where: { $0.isWhitespace }) { return nil }
        return (atIndex..<text.endIndex, String(queryPart))
    }

    private func applyMention(_ member: UserProfile, context: (range: Range<String.Index>, query: String)) {
        let mention = "@\(mentionToken(for: member))"
        newMessage.replaceSubrange(context.range, with: "\(mention) ")
    }

    private func mentionToken(for member: UserProfile) -> String {
        let name = displayName(for: member).trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            return name
                .lowercased()
                .replacingOccurrences(of: " ", with: ".")
        }
        let email = member.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return email.split(separator: "@").first.map(String.init) ?? "user"
    }

    private func displayName(for member: UserProfile) -> String {
        let trimmed = member.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return member.email.components(separatedBy: "@").first ?? member.email
    }

    private func selectedParticipantIDsForPicker() -> Set<String> {
        let currentEmail = store.user?.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let selectedIDs = store.teamMembers.compactMap { member -> String? in
            let email = member.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if email == currentEmail { return nil }
            return channel.participantEmails.map { $0.lowercased() }.contains(email) ? member.id : nil
        }
        return Set(selectedIDs)
    }

    private func updateDirectMessageParticipants(with members: [UserProfile]) {
        guard isDirectMessage else { return }
        guard let currentEmail = store.user?.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else { return }
        let recipients = members
            .map { $0.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty && $0 != currentEmail }
        guard !recipients.isEmpty else { return }

        let participants = Array(Set(recipients + [currentEmail])).sorted()
        if participants == channel.participantEmails.map({ $0.lowercased() }).sorted() {
            return
        }

        if let existing = store.channels.first(where: {
            $0.id != channel.id &&
            $0.kind == .direct &&
            $0.participantEmails.map { $0.lowercased() }.sorted() == participants
        }) {
            channel = existing
            return
        }

        channel.participantEmails = participants
        store.saveChannel(channel)
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

struct DirectMessagePickerView: View {
    @EnvironmentObject var store: ProdConnectStore
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selectedMemberIDs: Set<String> = []
    private let initialSelectedIDs: Set<String>
    var onSelect: ([UserProfile]) -> Void

    init(initialSelectedIDs: Set<String> = [], onSelect: @escaping ([UserProfile]) -> Void) {
        self.initialSelectedIDs = initialSelectedIDs
        self.onSelect = onSelect
        _selectedMemberIDs = State(initialValue: initialSelectedIDs)
    }

    private var currentEmail: String {
        store.user?.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }

    private var allMembers: [UserProfile] {
        store.teamMembers
            .filter { $0.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != currentEmail }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private var members: [UserProfile] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return allMembers }
        return allMembers.filter { member in
            let name = member.displayName.lowercased()
            let email = member.email.lowercased()
            return name.contains(query) || email.contains(query)
        }
    }

    private var selectedMembers: [UserProfile] {
        allMembers.filter { selectedMemberIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                if !selectedMembers.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(selectedMembers) { member in
                                HStack(spacing: 6) {
                                    Text(displayName(for: member))
                                        .font(.caption)
                                        .foregroundColor(.primary)
                                    Button {
                                        selectedMemberIDs.remove(member.id)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.secondary.opacity(0.14))
                                .clipShape(Capsule())
                            }
                        }
                    }
                    .padding(.horizontal)
                }

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Add users", text: $searchText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal)

                List(members) { member in
                    Button {
                        if selectedMemberIDs.contains(member.id) {
                            selectedMemberIDs.remove(member.id)
                        } else {
                            selectedMemberIDs.insert(member.id)
                        }
                    } label: {
                        HStack {
                            Text(displayName(for: member))
                                .foregroundColor(.primary)
                            Spacer()
                            if selectedMemberIDs.contains(member.id) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.blue)
                            } else {
                                Image(systemName: "circle")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("New Direct Message")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        onSelect(selectedMembers)
                        dismiss()
                    }
                    .disabled(selectedMemberIDs.isEmpty)
                }
            }
        }
    }

    private func displayName(for member: UserProfile) -> String {
        let trimmed = member.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return member.email.components(separatedBy: "@").first ?? member.email
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
                            isHidden: isHidden,
                            kind: .group
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
        MainTabView(
            selectedLaunchSection: .constant(nil),
            shouldOpenMoreTab: .constant(false)
        )
        .environmentObject(store)
    }
}

#endif


// MARK: - Views


// MARK: - View Stubs for Missing Views

struct ShareSheet: UIViewControllerRepresentable {
    var items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct IntegrationsView: View {
    private enum FreshserviceImportKind: String, CaseIterable, Identifiable {
        case assets
        case tickets

        var id: String { rawValue }

        var title: String {
            switch self {
            case .assets: return "Assets"
            case .tickets: return "Tickets"
            }
        }
    }

    private enum FreshserviceDestination: String, CaseIterable, Identifiable {
        case assetsTab
        case ticketsTab

        var id: String { rawValue }

        var title: String {
            switch self {
            case .assetsTab: return "Assets Tab"
            case .ticketsTab: return "Tickets Tab"
            }
        }
    }

    @EnvironmentObject private var store: ProdConnectStore
    @State private var freshserviceAPIURL = ""
    @State private var freshserviceAPIKey = ""
    @State private var freshserviceEnabled = false
    @State private var managedByGroupFilter = ""
    @State private var managedByGroupOptions: [String] = []
    @State private var freshserviceSyncMode: ProdConnectStore.FreshserviceSyncMode = .pull
    @State private var selectedImportKind: FreshserviceImportKind = .assets
    @State private var selectedDestination: FreshserviceDestination = .assetsTab
    @State private var isSaving = false
    @State private var isTesting = false
    @State private var isImporting = false
    @State private var isLoadingManagedByGroups = false
    @State private var externalTicketFormEnabled = false
    @State private var externalTicketFormAccessKey = ""
    @State private var isSavingExternalTicketForm = false
    @State private var externalTicketStatusMessage = ""
    @State private var isSharingExternalTicketLink = false
    @State private var statusMessage = ""

    private var canManageIntegrations: Bool {
        let isPrivilegedUser = store.user?.isAdmin == true || store.user?.isOwner == true
        return isPrivilegedUser && (
            (store.user?.hasChatAndTrainingFeatures ?? false)
            || (store.user?.hasTicketingFeatures ?? false)
        )
    }

    private var canImportTickets: Bool {
        store.user?.hasTicketingFeatures == true
    }

    private var availableImportKinds: [FreshserviceImportKind] {
        canImportTickets ? FreshserviceImportKind.allCases : [.assets]
    }

    private var availableDestinations: [FreshserviceDestination] {
        canImportTickets ? FreshserviceDestination.allCases : [.assetsTab]
    }

    private var availableManagedByGroupOptions: [String] {
        let trimmedFilter = managedByGroupFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        let merged = trimmedFilter.isEmpty ? managedByGroupOptions : managedByGroupOptions + [trimmedFilter]
        return Array(Set(merged)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var externalTicketFormURLString: String {
        let teamCode = (store.teamCode ?? store.user?.teamCode ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let accessKey = externalTicketFormAccessKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard externalTicketFormEnabled, !teamCode.isEmpty, !accessKey.isEmpty else { return "" }
        let slug = externalTicketFormSlug(from: store.organizationName)
        return "https://prodconnect-1ea3a.web.app/support/\(slug)?team=\(teamCode)&key=\(accessKey)"
    }

    var body: some View {
        NavigationStack {
            Form {
                if canManageIntegrations {
                    Section("Freshservice") {
                        Text("Connect Freshservice API")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Toggle("Enable Freshservice", isOn: $freshserviceEnabled)

                        Picker("Import Data", selection: $selectedImportKind) {
                            ForEach(availableImportKinds) { kind in
                                Text(kind.title).tag(kind)
                            }
                        }

                        Picker("Destination", selection: $selectedDestination) {
                            ForEach(availableDestinations) { destination in
                                Text(destination.title).tag(destination)
                            }
                        }

                        Picker("Sync Mode", selection: $freshserviceSyncMode) {
                            ForEach(ProdConnectStore.FreshserviceSyncMode.allCases, id: \.self) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }

                        TextField("Freshservice URL", text: $freshserviceAPIURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        SecureField("Freshservice API Key", text: $freshserviceAPIKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        if selectedImportKind == .assets {
                            Picker("Managed By Group", selection: $managedByGroupFilter) {
                                Text("All Groups").tag("")
                                ForEach(availableManagedByGroupOptions, id: \.self) { option in
                                    Text(option).tag(option)
                                }
                            }

                            Button {
                                refreshManagedByGroupOptions()
                            } label: {
                                if isLoadingManagedByGroups {
                                    ProgressView()
                                } else {
                                    Text("Refresh Groups")
                                }
                            }
                            .disabled(
                                isSaving
                                || isTesting
                                || isImporting
                                || isLoadingManagedByGroups
                                || freshserviceAPIURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                || freshserviceAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            )
                        }

                        Button {
                            saveConnection()
                        } label: {
                            if isSaving {
                                ProgressView()
                            } else {
                                Text("Save Connection")
                            }
                        }
                        .disabled(isSaving || isTesting || isImporting)

                        Button {
                            testConnection()
                        } label: {
                            if isTesting {
                                ProgressView()
                            } else {
                                Text("Test Connection")
                            }
                        }
                        .disabled(
                            isSaving
                            || isTesting
                            || isImporting
                            || freshserviceAPIURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || freshserviceAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )

                        Button {
                            importFreshserviceData()
                        } label: {
                            if isImporting {
                                ProgressView()
                            } else {
                                Text("Import")
                            }
                        }
                        .disabled(
                            isSaving
                            || isTesting
                            || isImporting
                            || freshserviceAPIURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || freshserviceAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )

                        if !statusMessage.isEmpty {
                            Text(statusMessage)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                } else {
                    Section("Integrations") {
                        Text("Integrations are available for basic and premium admin or owner accounts.")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Integrations")
            .onAppear(perform: loadState)
            .onReceive(store.$freshserviceIntegration) { _ in
                loadState()
            }
            .onReceive(store.$externalTicketFormIntegration) { _ in
                loadState()
            }
            .sheet(isPresented: $isSharingExternalTicketLink) {
                ShareSheet(items: [URL(string: externalTicketFormURLString)!])
            }
        }
    }

    private func loadState() {
        let settings = store.freshserviceIntegration
        freshserviceAPIURL = settings.apiURL
        freshserviceAPIKey = settings.apiKey
        freshserviceEnabled = settings.isEnabled
        managedByGroupFilter = settings.managedByGroup
        managedByGroupOptions = settings.managedByGroupOptions
        freshserviceSyncMode = settings.syncMode
        let externalSettings = store.externalTicketFormIntegration
        externalTicketFormEnabled = externalSettings.isEnabled
        externalTicketFormAccessKey = externalSettings.accessKey
        if externalTicketFormAccessKey.isEmpty, canImportTickets {
            externalTicketFormAccessKey = store.generateExternalTicketAccessKey()
        }
        if !canImportTickets, selectedImportKind == .tickets {
            selectedImportKind = .assets
        }
        if !availableDestinations.contains(selectedDestination) {
            selectedDestination = availableDestinations.first ?? .assetsTab
        }
    }

    private func saveConnection() {
        isSaving = true
        statusMessage = ""
        store.saveFreshserviceIntegration(
            apiURL: freshserviceAPIURL,
            apiKey: freshserviceAPIKey,
            managedByGroup: managedByGroupFilter,
            managedByGroupOptions: managedByGroupOptions,
            syncMode: freshserviceSyncMode,
            isEnabled: freshserviceEnabled
        ) { result in
            isSaving = false
            switch result {
            case .success:
                statusMessage = "Freshservice connection saved."
            case .failure(let error):
                statusMessage = "Save failed: \(error.localizedDescription)"
            }
        }
    }

    private func testConnection() {
        let trimmedURL = freshserviceAPIURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = freshserviceAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty, !trimmedKey.isEmpty else {
            statusMessage = "Enter both the Freshservice URL and API key."
            return
        }

        isTesting = true
        statusMessage = ""
        let assetCompletion: (Result<([[String: Any]], Bool), Error>) -> Void = { result in
            DispatchQueue.main.async {
                isTesting = false
                switch result {
                case .success(let payload):
                    let (items, reachedCap) = payload
                    let filteredItems = filteredFreshserviceItems(items)
                    if reachedCap {
                        statusMessage = "Connected to Freshservice. Found at least \(filteredItems.count) assets (2,000 asset test cap reached)."
                    } else {
                        statusMessage = "Connected to Freshservice. Found \(filteredItems.count) assets."
                    }
                case .failure(let error):
                    statusMessage = "Connection failed: \(error.localizedDescription)"
                }
            }
        }
        let ticketCompletion: (Result<([[String: Any]], Bool), Error>) -> Void = { result in
            DispatchQueue.main.async {
                isTesting = false
                switch result {
                case .success(let payload):
                    let (items, reachedCap) = payload
                    if reachedCap {
                        statusMessage = "Connected to Freshservice. Found at least \(items.count) tickets (20,000 ticket cap reached)."
                    } else {
                        statusMessage = "Connected to Freshservice. Found \(items.count) tickets."
                    }
                case .failure(let error):
                    statusMessage = "Connection failed: \(error.localizedDescription)"
                }
            }
        }
        switch selectedImportKind {
        case .assets:
            FreshserviceAPI.fetchAllAssetsWithAPIKey(apiKey: trimmedKey, apiUrl: trimmedURL, maxPages: 20, completion: assetCompletion)
        case .tickets:
            FreshserviceAPI.fetchAllTicketsWithAPIKey(apiKey: trimmedKey, apiUrl: trimmedURL, completion: ticketCompletion)
        }
    }

    private func importFreshserviceData() {
        let trimmedURL = freshserviceAPIURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = freshserviceAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty, !trimmedKey.isEmpty else {
            statusMessage = "Enter both the Freshservice URL and API key."
            return
        }

        isImporting = true
        statusMessage = ""
        let assetCompletion: (Result<([[String: Any]], Bool), Error>) -> Void = { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let payload):
                    let (items, reachedCap) = payload
                    logFreshserviceAssetSample(items)
                    let filteredItems = filteredFreshserviceItems(items)
                    switch selectedDestination {
                    case .assetsTab:
                        let saveAssets: ([[String: Any]]) -> Void = { importItems in
                            let imported = importItems.compactMap { mapFreshserviceAsset($0) }
                            store.upsertGear(imported) { saveResult in
                                isImporting = false
                                switch saveResult {
                                case .success:
                                    if reachedCap {
                                        statusMessage = "Imported \(imported.count) Freshservice \(selectedImportKind.rawValue) into Assets and Firebase. 20,000 asset cap reached."
                                    } else {
                                        statusMessage = "Imported \(imported.count) Freshservice \(selectedImportKind.rawValue) into Assets and Firebase."
                                    }
                                case .failure(let error):
                                    statusMessage = "Import failed while saving assets: \(error.localizedDescription)"
                                }
                            }
                        }

                        let resolveAndSave: ([[String: Any]]) -> Void = { assetsToResolve in
                            resolveFreshserviceAssetLookups(assetsToResolve, apiKey: trimmedKey, apiUrl: trimmedURL) { resolvedItems in
                                saveAssets(resolvedItems)
                            }
                        }

                        if hasResolvedFreshserviceAssetFields(filteredItems) {
                            resolveAndSave(filteredItems)
                        } else {
                            enrichFreshserviceAssets(filteredItems, apiKey: trimmedKey, apiUrl: trimmedURL) { enrichedItems in
                                DispatchQueue.main.async {
                                    resolveAndSave(enrichedItems)
                                }
                            }
                        }
                    case .ticketsTab:
                        let imported = filteredItems.compactMap { mapFreshserviceTicket($0) }
                        store.upsertTickets(imported) { saveResult in
                            isImporting = false
                            switch saveResult {
                            case .success:
                                if reachedCap {
                                    statusMessage = "Imported \(imported.count) Freshservice \(selectedImportKind.rawValue) into Tickets and Firebase. 30,000 asset cap reached."
                                } else {
                                    statusMessage = "Imported \(imported.count) Freshservice \(selectedImportKind.rawValue) into Tickets and Firebase."
                                }
                            case .failure(let error):
                                statusMessage = "Import failed while saving tickets: \(error.localizedDescription)"
                            }
                        }
                    }
                case .failure(let error):
                    isImporting = false
                    statusMessage = "Import failed: \(error.localizedDescription)"
                }
            }
        }
        let ticketCompletion: (Result<([[String: Any]], Bool), Error>) -> Void = { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let payload):
                    let (items, reachedCap) = payload
                    enrichFreshserviceTickets(items, apiKey: trimmedKey, apiUrl: trimmedURL) { enrichedItems in
                        DispatchQueue.main.async {
                            switch selectedDestination {
                            case .assetsTab:
                                let imported = enrichedItems.compactMap { mapFreshserviceAsset($0) }
                                store.upsertGear(imported) { saveResult in
                                    isImporting = false
                                    switch saveResult {
                                    case .success:
                                        if reachedCap {
                                            statusMessage = "Imported \(imported.count) Freshservice tickets into Assets and Firebase. 20,000 ticket cap reached."
                                        } else {
                                            statusMessage = "Imported \(imported.count) Freshservice tickets into Assets and Firebase."
                                        }
                                    case .failure(let error):
                                        statusMessage = "Import failed while saving assets: \(error.localizedDescription)"
                                    }
                                }
                            case .ticketsTab:
                                let imported = enrichedItems.compactMap { mapFreshserviceTicket($0) }
                                store.upsertTickets(imported) { saveResult in
                                    isImporting = false
                                    switch saveResult {
                                    case .success:
                                        if reachedCap {
                                            statusMessage = "Imported \(imported.count) Freshservice tickets into Tickets and Firebase. 20,000 ticket cap reached."
                                        } else {
                                            statusMessage = "Imported \(imported.count) Freshservice tickets into Tickets and Firebase."
                                        }
                                    case .failure(let error):
                                        statusMessage = "Import failed while saving tickets: \(error.localizedDescription)"
                                    }
                                }
                            }
                        }
                    }
                case .failure(let error):
                    isImporting = false
                    statusMessage = "Import failed: \(error.localizedDescription)"
                }
            }
        }
        switch selectedImportKind {
        case .assets:
            FreshserviceAPI.fetchAllAssetsForImportWithAPIKey(apiKey: trimmedKey, apiUrl: trimmedURL, completion: assetCompletion)
        case .tickets:
            FreshserviceAPI.fetchAllTicketsWithAPIKey(apiKey: trimmedKey, apiUrl: trimmedURL, completion: ticketCompletion)
        }
    }

    private func filteredFreshserviceItems(_ items: [[String: Any]]) -> [[String: Any]] {
        switch selectedImportKind {
        case .assets:
            let filter = managedByGroupFilter.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !filter.isEmpty else { return items }
            return items.filter { matchesManagedByGroup($0, filter: filter) }
        case .tickets:
            return items.filter { shouldIncludeFreshserviceTicket($0) }
        }
    }

    private func logFreshserviceAssetSample(_ items: [[String: Any]]) {
        guard selectedImportKind == .assets, let first = items.first else { return }

        let sortedKeys = first.keys.sorted()
        print("Freshservice asset sample keys:", sortedKeys.joined(separator: ", "))

        let interestingFields = [
            "id",
            "display_id",
            "name",
            "display_name",
            "asset_tag",
            "status",
            "status_name",
            "state",
            "state_name",
            "asset_state",
            "asset_state_name",
            "lifecycle_state",
            "lifecycle_state_name",
            "asset_type",
            "asset_type_name",
            "asset_type_id",
            "department",
            "department_name",
            "department_id",
            "location",
            "location_name",
            "location_id",
            "usage_type",
            "custom_fields"
        ]

        for field in interestingFields where first[field] != nil {
            print("Freshservice asset sample \(field):", String(describing: first[field]!))
        }
    }

    private func hasResolvedFreshserviceAssetFields(_ assets: [[String: Any]]) -> Bool {
        guard let first = assets.first else { return false }

        // Freshservice v2 API returns only IDs (location_id, asset_type_id) — never embedded
        // name objects or flat name strings. Per-asset detail fetches return the same structure,
        // so enrichment cannot resolve names. Skip it and let resolveFreshserviceAssetLookups
        // handle resolution via the /locations and /asset_types endpoints instead.
        let hasIDOnlyFields = stringValue(first["location_id"]) != nil
            || stringValue(first["asset_type_id"]) != nil
        if hasIDOnlyFields { return true }

        let resolvedFields = [
            nestedStringValue(first["asset_type"], key: "name"),
            stringValue(first["asset_type_name"]),
            stringValue(first["ci_type_name"]),
            stringValue(first["config_item_type_name"]),
            nestedStringValue(first["location"], key: "name"),
            stringValue(first["location_name"]),
            nestedStringValue(first["department"], key: "name"),
            stringValue(first["department_name"]),
            nestedStringValue(first["asset_state"], key: "name"),
            stringValue(first["asset_state_name"]),
            stringValue(first["state_name"])
        ]

        return resolvedFields
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .contains { !$0.isEmpty }
    }

    private func enrichFreshserviceAssets(
        _ assets: [[String: Any]],
        apiKey: String,
        apiUrl: String,
        completion: @escaping ([[String: Any]]) -> Void
    ) {
        let indexedAssets = assets.enumerated().compactMap { index, asset -> (Int, [String], [String: Any])? in
            let identifiers = [
                stringValue(asset["display_id"]),
                stringValue(asset["id"]),
                stringValue(asset["asset_tag"])
            ]
            .compactMap { $0 }
            .reduce(into: [String]()) { partialResult, identifier in
                if !partialResult.contains(identifier) {
                    partialResult.append(identifier)
                }
            }

            guard !identifiers.isEmpty else { return nil }
            return (index, identifiers, asset)
        }
        guard !indexedAssets.isEmpty else {
            completion(assets)
            return
        }

        let maxConcurrentRequests = 8
        let syncQueue = DispatchQueue(label: "FreshserviceAssetEnrichmentSync")
        var nextIndex = 0
        var activeRequests = 0
        var didComplete = false
        var enrichedAssets = assets

        func finishIfNeeded() {
            guard !didComplete else { return }
            if nextIndex >= indexedAssets.count && activeRequests == 0 {
                didComplete = true
                DispatchQueue.main.async {
                    completion(enrichedAssets)
                }
            }
        }

        func launchMoreRequests() {
            guard !didComplete else { return }
            while activeRequests < maxConcurrentRequests && nextIndex < indexedAssets.count {
                let (assetIndex, identifiers, originalAsset) = indexedAssets[nextIndex]
                nextIndex += 1
                activeRequests += 1

                fetchFreshserviceAssetDetails(
                    identifiers: identifiers,
                    apiKey: apiKey,
                    apiUrl: apiUrl
                ) { result in
                    syncQueue.async {
                        defer {
                            activeRequests -= 1
                            launchMoreRequests()
                            finishIfNeeded()
                        }

                        guard !didComplete else { return }
                        guard case .success(let detail) = result else { return }

                        var merged = originalAsset
                        merged.merge(detail) { _, new in new }
                        enrichedAssets[assetIndex] = merged
                    }
                }
            }
        }

        syncQueue.async {
            launchMoreRequests()
            finishIfNeeded()
        }
    }

    private func fetchFreshserviceAssetDetails(
        identifiers: [String],
        apiKey: String,
        apiUrl: String,
        completion: @escaping (Result<[String: Any], Error>) -> Void
    ) {
        guard let identifier = identifiers.first else {
            completion(.failure(NSError(
                domain: "Freshservice",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "No Freshservice asset identifier was available."]
            )))
            return
        }

        FreshserviceAPI.fetchAssetDetailsWithAPIKey(apiKey: apiKey, apiUrl: apiUrl, assetID: identifier) { result in
            switch result {
            case .success:
                completion(result)
            case .failure:
                let remaining = Array(identifiers.dropFirst())
                guard !remaining.isEmpty else {
                    completion(result)
                    return
                }
                fetchFreshserviceAssetDetails(
                    identifiers: remaining,
                    apiKey: apiKey,
                    apiUrl: apiUrl,
                    completion: completion
                )
            }
        }
    }



    /// Resolves `location_id` and `asset_type_id` to name strings by fetching the Freshservice
    /// locations and asset type lookup tables, then injects `location_name` and `asset_type_name`
    /// into each asset dict so the downstream mapping functions can read them.
    private func resolveFreshserviceAssetLookups(
        _ assets: [[String: Any]],
        apiKey: String,
        apiUrl: String,
        completion: @escaping ([[String: Any]]) -> Void
    ) {
        let group = DispatchGroup()
        var locationMap = [String: String]()
        var assetTypeMap = [String: String]()

        group.enter()
        FreshserviceAPI.fetchLocationsWithAPIKey(apiKey: apiKey, apiUrl: apiUrl) { result in
            if case .success(let map) = result { locationMap = map }
            group.leave()
        }

        group.enter()
        FreshserviceAPI.fetchAssetTypesWithAPIKey(apiKey: apiKey, apiUrl: apiUrl) { result in
            if case .success(let map) = result { assetTypeMap = map }
            group.leave()
        }

        group.notify(queue: .main) {
            let resolved = assets.map { asset -> [String: Any] in
                var enriched = asset

                // Inject location_name if not already present
                if stringValue(asset["location_name"]) == nil,
                   let locID = stringValue(asset["location_id"]),
                   let locName = locationMap[locID] {
                    enriched["location_name"] = locName
                }

                // Inject asset_type_name if not already present
                if stringValue(asset["asset_type_name"]) == nil,
                   let typeID = stringValue(asset["asset_type_id"]),
                   let typeName = assetTypeMap[typeID] {
                    enriched["asset_type_name"] = typeName
                }

                return enriched
            }
            completion(resolved)
        }
    }

    private func enrichFreshserviceTickets(
        _ tickets: [[String: Any]],
        apiKey: String,
        apiUrl: String,
        completion: @escaping ([[String: Any]]) -> Void
    ) {
        let ids = tickets.compactMap { stringValue($0["id"]) }
        guard !ids.isEmpty else {
            completion(tickets)
            return
        }

        let originalByID = Dictionary(uniqueKeysWithValues: tickets.compactMap { ticket in
            stringValue(ticket["id"]).map { ($0, ticket) }
        })

        var enrichedByID = originalByID
        var agentNameCache: [String: String] = [:]
        var groupNameCache: [String: String] = [:]
        var departmentNameCache: [String: String] = [:]
        let group = DispatchGroup()

        for ticketID in ids {
            group.enter()
            FreshserviceAPI.fetchTicketDetailsWithAPIKey(apiKey: apiKey, apiUrl: apiUrl, ticketID: ticketID) { result in
                switch result {
                case .success(let detail):
                    var merged = originalByID[ticketID] ?? [:]
                    merged.merge(detail) { _, new in new }

                    let nestedGroup = DispatchGroup()

                    if
                        let responderID = self.stringValue(merged["responder_id"]) ?? self.stringValue(merged["agent_id"]),
                        !responderID.isEmpty
                    {
                        merged["assigned_agent_id"] = responderID
                        if let cachedName = agentNameCache[responderID] {
                            merged["assigned_agent_name"] = cachedName
                        } else {
                            nestedGroup.enter()
                            FreshserviceAPI.fetchAgentNameWithAPIKey(apiKey: apiKey, apiUrl: apiUrl, agentID: responderID) { agentResult in
                                if case .success(let agentName) = agentResult, let agentName, !agentName.isEmpty {
                                    agentNameCache[responderID] = agentName
                                    merged["assigned_agent_name"] = agentName
                                } else if self.stringValue(merged["assigned_agent_name"]) == nil {
                                    merged["assigned_agent_name"] = "Agent \(responderID)"
                                }
                                nestedGroup.leave()
                            }
                        }
                    }

                    if let groupID = self.stringValue(merged["group_id"]), !groupID.isEmpty {
                        if let cachedGroupName = groupNameCache[groupID] {
                            merged["group_name"] = cachedGroupName
                        } else {
                            nestedGroup.enter()
                            FreshserviceAPI.fetchGroupNameWithAPIKey(apiKey: apiKey, apiUrl: apiUrl, groupID: groupID) { groupResult in
                                if case .success(let groupName) = groupResult, let groupName, !groupName.isEmpty {
                                    groupNameCache[groupID] = groupName
                                    merged["group_name"] = groupName
                                }
                                nestedGroup.leave()
                            }
                        }
                    }

                    if let departmentID = self.stringValue(merged["department_id"]), !departmentID.isEmpty {
                        if let cachedDepartmentName = departmentNameCache[departmentID] {
                            merged["department_name"] = cachedDepartmentName
                        } else {
                            nestedGroup.enter()
                            FreshserviceAPI.fetchDepartmentNameWithAPIKey(apiKey: apiKey, apiUrl: apiUrl, departmentID: departmentID) { departmentResult in
                                if case .success(let departmentName) = departmentResult, let departmentName, !departmentName.isEmpty {
                                    departmentNameCache[departmentID] = departmentName
                                    merged["department_name"] = departmentName
                                }
                                nestedGroup.leave()
                            }
                        }
                    }

                    nestedGroup.notify(queue: .global(qos: .userInitiated)) {
                        enrichedByID[ticketID] = merged
                        group.leave()
                    }
                    return
                case .failure:
                    break
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            let enriched = ids.compactMap { enrichedByID[$0] }
            completion(enriched.isEmpty ? tickets : enriched)
        }
    }

    private func refreshManagedByGroupOptions() {
        let trimmedURL = freshserviceAPIURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = freshserviceAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty, !trimmedKey.isEmpty else {
            statusMessage = "Enter both the Freshservice URL and API key."
            return
        }

        isLoadingManagedByGroups = true
        FreshserviceAPI.fetchAllAssetsWithAPIKey(apiKey: trimmedKey, apiUrl: trimmedURL) { result in
            DispatchQueue.main.async {
                isLoadingManagedByGroups = false
                switch result {
                case .success(let payload):
                    let (assets, reachedCap) = payload
                    managedByGroupOptions = extractManagedByGroupOptions(from: assets)
                    store.saveFreshserviceIntegration(
                        apiURL: freshserviceAPIURL,
                        apiKey: freshserviceAPIKey,
                        managedByGroup: managedByGroupFilter,
                        managedByGroupOptions: managedByGroupOptions,
                        syncMode: freshserviceSyncMode,
                        isEnabled: freshserviceEnabled
                    )
                    if managedByGroupOptions.isEmpty {
                        statusMessage = "Connected to Freshservice. No managed-by groups were found."
                    } else if reachedCap {
                        statusMessage = "Loaded \(managedByGroupOptions.count) managed-by groups from the first 30,000 assets."
                    } else {
                        statusMessage = "Loaded \(managedByGroupOptions.count) managed-by groups from Freshservice."
                    }
                case .failure(let error):
                    statusMessage = "Failed to load managed-by groups: \(error.localizedDescription)"
                }
            }
        }
    }

    private func regenerateExternalTicketLink() {
        externalTicketFormEnabled = true
        externalTicketFormAccessKey = store.generateExternalTicketAccessKey()
        externalTicketStatusMessage = "New public link generated. Save to make it active."
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
                externalTicketFormAccessKey = settings.accessKey
                externalTicketFormEnabled = settings.isEnabled
                externalTicketStatusMessage = settings.isEnabled ?
                    "External ticket form is live." :
                    "External ticket form is saved but disabled."
            case .failure(let error):
                externalTicketStatusMessage = "Save failed: \(error.localizedDescription)"
            }
        }
    }

    private func extractManagedByGroupOptions(from assets: [[String: Any]]) -> [String] {
        let values = assets.compactMap { asset in
            managedByGroupName(from: asset)
        }
        return Array(Set(values)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func managedByGroupName(from asset: [String: Any]) -> String? {
        let candidates: [String?] = [
            nestedStringValue(asset["managed_by_group"], key: "name"),
            nestedStringValue(asset["managed_by"], key: "name"),
            nestedStringValue(asset["group"], key: "name"),
            stringValue(asset["managed_by_group"]),
            stringValue(asset["managed_by"]),
            stringValue(asset["group_name"])
        ]

        return candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    private func mapFreshserviceAsset(_ asset: [String: Any]) -> GearItem? {
        let freshserviceID = stringValue(asset["id"]) ?? stringValue(asset["display_id"]) ?? stringValue(asset["asset_tag"])
        let name = stringValue(asset["name"])
            ?? stringValue(asset["display_name"])
            ?? nestedStringValue(asset["product"], key: "name")
            ?? "Freshservice Asset"
        let category = freshserviceAssetTypeName(from: asset) ?? "Freshservice"
        let location = freshserviceLocationName(from: asset) ?? ""
        let campus = freshserviceCampusName(from: asset) ?? location
        let room = typeFieldValue(from: asset, prefix: "lf_physical_room_location") ?? ""

        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        var item = GearItem(
            id: freshserviceID.map { "freshservice-\($0)" } ?? UUID().uuidString,
            name: name,
            category: category,
            status: mappedStatus(from: asset),
            teamCode: store.teamCode ?? "",
            location: location,
            room: room,
            serialNumber: stringValue(asset["serial_number"]) ?? "",
            campus: campus,
            assetId: stringValue(asset["asset_tag"]) ?? stringValue(asset["display_id"]) ?? "",
            maintenanceNotes: stringValue(asset["description"]) ?? "",
            createdBy: "Freshservice Import"
        )

        item.purchasedFrom = nestedStringValue(asset["vendor"], key: "name") ?? ""
        item.purchaseDate = parsedDate(from: asset["purchase_date"]) ?? parsedDate(from: asset["created_at"])
        item.installDate = parsedDate(from: asset["created_at"])
        item.cost = doubleValue(asset["cost"]) ?? doubleValue(asset["salvage_price"])
        return item
    }

    private func freshserviceAssetTypeName(from asset: [String: Any]) -> String? {
        [
            nestedStringValue(asset["asset_type"], key: "name"),
            stringValue(asset["asset_type_name"]),
            stringValue(asset["ci_type_name"]),
            stringValue(asset["config_item_type_name"]),
            nestedStringValue(asset["product"], key: "name")
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first { !$0.isEmpty }
    }

    private func freshserviceLocationName(from asset: [String: Any]) -> String? {
        [
            nestedStringValue(asset["location"], key: "name"),
            stringValue(asset["location_name"])
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first { !$0.isEmpty }
    }

    private func freshserviceCampusName(from asset: [String: Any]) -> String? {
        [
            nestedStringValue(asset["department"], key: "name"),
            stringValue(asset["department_name"]),
            nestedStringValue(asset["location"], key: "name"),
            stringValue(asset["location_name"])
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first { !$0.isEmpty }
    }

    private func mapFreshserviceTicket(_ ticket: [String: Any]) -> SupportTicket? {
        let ticketID = stringValue(ticket["id"]) ?? stringValue(ticket["display_id"])
        let title = stringValue(ticket["subject"]) ?? stringValue(ticket["name"]) ?? "Freshservice Ticket"
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let requesterName = nestedStringValue(ticket["requester"], key: "name")
            ?? nestedStringValue(ticket["requester"], key: "email")
            ?? stringValue(ticket["requester_name"])
            ?? stringValue(ticket["email"])

        let campusValue =
            nestedStringValue(ticket["department"], key: "name")
            ?? nestedStringValue(ticket["group"], key: "name")
            ?? nestedStringValue(ticket["custom_fields"], key: "department")
            ?? nestedStringValue(ticket["custom_fields"], key: "campus")
            ?? stringValue(ticket["department_name"])
            ?? stringValue(ticket["group_name"])
            ?? stringValue(ticket["campus"])

        let roomValue =
            nestedStringValue(ticket["location"], key: "name")
            ?? nestedStringValue(ticket["custom_fields"], key: "location")
            ?? nestedStringValue(ticket["custom_fields"], key: "room")
            ?? stringValue(ticket["location_name"])
            ?? stringValue(ticket["room"])

        let assignedAgentIDCandidates = [
            stringValue(ticket["assigned_agent_id"]),
            stringValue(ticket["responder_id"]),
            stringValue(ticket["agent_id"]),
            nestedStringValue(ticket["responder"], key: "id"),
            nestedStringValue(ticket["agent"], key: "id"),
            nestedStringValue(ticket["assigned_to"], key: "id")
        ]
        let assignedAgentID = assignedAgentIDCandidates.compactMap { $0 }.first

        let assignedAgentNameCandidates = [
            nestedStringValue(ticket["responder"], key: "name"),
            nestedStringValue(ticket["responder"], key: "email"),
            nestedStringValue(ticket["agent"], key: "name"),
            nestedStringValue(ticket["agent"], key: "email"),
            nestedStringValue(ticket["assigned_to"], key: "name"),
            nestedStringValue(ticket["assigned_to"], key: "email"),
            stringValue(ticket["responder_email"]),
            stringValue(ticket["agent_email"]),
            stringValue(ticket["responder_name"]),
            stringValue(ticket["agent_name"]),
            stringValue(ticket["assigned_agent_name"])
        ]
        let assignedAgentName = assignedAgentNameCandidates.compactMap { $0 }.first ?? assignedAgentID.map { "Agent \($0)" }

        var item = SupportTicket(
            id: ticketID.map { "freshservice-ticket-\($0)" } ?? UUID().uuidString,
            title: title,
            detail: stringValue(ticket["description_text"]) ?? stringValue(ticket["description"]) ?? "",
            teamCode: store.teamCode ?? "",
            campus: campusValue ?? "",
            room: roomValue ?? "",
            status: mappedTicketStatus(from: ticket),
            createdBy: requesterName
        )
        item.createdAt = parsedDate(from: ticket["created_at"]) ?? Date()
        item.updatedAt = parsedDate(from: ticket["updated_at"]) ?? item.createdAt
        item.assignedAgentID = assignedAgentID
        item.assignedAgentName = assignedAgentName
        item.lastUpdatedBy = assignedAgentName
        if let attachment = firstFreshserviceAttachment(from: ticket) {
            item.attachmentURL = attachment.url
            item.attachmentName = attachment.name
            item.attachmentKind = attachment.kind
        }
        return item
    }

    private func mappedStatus(from asset: [String: Any]) -> GearItem.GearStatus {
        // type_fields contains asset state when fetched with include=type_fields
        let typeFields = asset["type_fields"] as? [String: Any]
        let typeFieldState = typeFields.flatMap { fields -> String? in
            let candidates: [String?] = [
                fields["asset_state"] as? String,
                nestedStringValue(fields["asset_state"], key: "name"),
                fields["state"] as? String,
                nestedStringValue(fields["state"], key: "name"),
                fields["asset_state_name"] as? String,
                fields["state_name"] as? String
            ]
            return candidates.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
        }

        // usage_type from Freshservice v2 is an integer: 0 = permanent, 1 = loaner — not a state
        // string. Exclude it from raw string matching to avoid false positives.
        let raw = (
            typeFieldState
            ?? nestedStringValue(asset["asset_state"], key: "name")
            ?? stringValue(asset["asset_state_name"])
            ?? nestedStringValue(asset["state"], key: "name")
            ?? nestedStringValue(asset["ci_status"], key: "name")
            ?? stringValue(asset["state_name"])
            ?? stringValue(asset["ci_status_name"])
            ?? stringValue(asset["status"])
            ?? ""
        ).lowercased()

        if raw.contains("repair") || raw.contains("maint") { return .needsRepair }
        if raw.contains("retired") || raw.contains("disposal") { return .retired }
        if raw.contains("missing") || raw.contains("lost") { return .missing }
        if raw.contains("checkout") || raw.contains("checked out") { return .checkedOut }
        if raw.contains("use") || raw.contains("deployed") || raw.contains("assigned") || raw.contains("loaner") { return .inUse }
        if raw.contains("stock") || raw.contains("available") || raw.contains("store") || raw.contains("spare") { return .available }
        return .available
    }

    private func mappedTicketStatus(from ticket: [String: Any]) -> TicketStatus {
        let statusCode = stringValue(ticket["status"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let raw = (
            nestedStringValue(ticket["status"], key: "name")
            ?? stringValue(ticket["status_name"])
            ?? ""
        ).lowercased()

        if ["4", "5"].contains(statusCode) {
            return .resolved
        }
        if ["3", "6", "7"].contains(statusCode) {
            return .inProgress
        }
        if statusCode == "2" {
            return .open
        }
        if statusCode == "1" {
            return .new
        }

        if raw.contains("resolve") || raw.contains("closed") {
            return .resolved
        }
        if raw.contains("progress") || raw.contains("pending") || raw.contains("awaiting") || raw.contains("waiting") {
            return .inProgress
        }
        if raw.contains("open") {
            return .open
        }
        return .new
    }

    private func firstFreshserviceAttachment(from ticket: [String: Any]) -> (url: String, name: String?, kind: TicketAttachmentKind?)? {
        guard let attachments = ticket["attachments"] as? [[String: Any]], let first = attachments.first else {
            return nil
        }

        guard
            let url = stringValue(first["attachment_url"])
                ?? stringValue(first["url"])
                ?? stringValue(first["content_url"])
        else {
            return nil
        }

        let name = stringValue(first["name"]) ?? stringValue(first["file_name"])
        let contentType = (stringValue(first["content_type"]) ?? "").lowercased()
        let kind: TicketAttachmentKind?
        if contentType.hasPrefix("image/") {
            kind = .image
        } else if contentType.hasPrefix("video/") {
            kind = .video
        } else {
            kind = nil
        }

        return (url, name, kind)
    }

    private func shouldIncludeFreshserviceTicket(_ ticket: [String: Any]) -> Bool {
        let rawStatusName = (
            nestedStringValue(ticket["status"], key: "name")
            ?? stringValue(ticket["status_name"])
            ?? ""
        ).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let rawStatusCode = stringValue(ticket["status"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if ["1", "2", "3", "6"].contains(rawStatusCode) {
            return true
        }

        if rawStatusName.contains("new") {
            return true
        }
        if rawStatusName.contains("open") {
            return true
        }
        if rawStatusName.contains("pending") {
            return true
        }
        if rawStatusName.contains("awaiting response") || rawStatusName.contains("waiting on customer") || rawStatusName.contains("waiting for customer") {
            return true
        }

        return false
    }

    private func matchesManagedByGroup(_ asset: [String: Any], filter: String) -> Bool {
        let normalizedFilter = filter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedFilter.isEmpty else { return true }

        let candidates: [String?] = [
            nestedStringValue(asset["managed_by_group"], key: "name"),
            nestedStringValue(asset["managed_by"], key: "name"),
            nestedStringValue(asset["group"], key: "name"),
            stringValue(asset["managed_by_group"]),
            stringValue(asset["managed_by"]),
            stringValue(asset["group_name"])
        ]

        return candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .contains { $0 == normalizedFilter }
    }

    private func stringValue(_ value: Any?) -> String? {
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    private func nestedStringValue(_ value: Any?, key: String) -> String? {
        guard let dictionary = value as? [String: Any] else { return nil }
        return stringValue(dictionary[key])
    }

    private func typeFieldValue(from asset: [String: Any], prefix: String) -> String? {
        guard let typeFields = asset["type_fields"] as? [String: Any] else { return nil }
        for (key, value) in typeFields where key.hasPrefix(prefix) {
            if let string = stringValue(value) { return string }
        }
        return nil
    }

    private func doubleValue(_ value: Any?) -> Double? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let string = value as? String {
            return Double(string.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    private func parsedDate(from value: Any?) -> Date? {
        guard let raw = stringValue(value) else { return nil }
        let isoFormatter = ISO8601DateFormatter()
        if let date = isoFormatter.date(from: raw) {
            return date
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd", "yyyy-MM-dd HH:mm:ss", "MM/dd/yyyy"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: raw) {
                return date
            }
        }
        return nil
    }
}

private enum MainAppSection: String, CaseIterable, Identifiable {
    case chat
    case patchsheet
    case runOfShow
    case training
    case assets
    case integrations
    case notifications
    case checklist
    case ideas
    case tickets
    case customize
    case account
    case users

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chat: return "Chat"
        case .patchsheet: return "Patchsheet"
        case .runOfShow: return "Run of Show"
        case .training: return "Training"
        case .assets: return "Assets"
        case .integrations: return "Integrations"
        case .notifications: return "Notifications"
        case .checklist: return "Checklist"
        case .ideas: return "Ideas"
        case .tickets: return "Tickets"
        case .customize: return "Customize"
        case .account: return "Account"
        case .users: return "Users"
        }
    }

    var icon: String {
        switch self {
        case .chat: return "message"
        case .patchsheet: return "square.grid.3x2"
        case .runOfShow: return "list.bullet.rectangle.portrait"
        case .training: return "graduationcap"
        case .assets: return "shippingbox"
        case .integrations: return "link"
        case .notifications: return "bell"
        case .checklist: return "checklist"
        case .ideas: return "lightbulb"
        case .tickets: return "ticket"
        case .customize: return "slider.horizontal.3"
        case .account: return "person.crop.circle"
        case .users: return "person.3"
        }
    }
}

private let preferredMainTabSectionsStorageKey = "preferredMainTabSections"
private let defaultPreferredMainTabSections: [MainAppSection] = [.chat, .patchsheet, .runOfShow, .training]

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

private func availableMainAppSections(for store: ProdConnectStore) -> [MainAppSection] {
    let isPrivilegedUser = store.user?.isAdmin == true || store.user?.isOwner == true
    var sections: [MainAppSection] = [.notifications]

    if (store.user?.hasChatAndTrainingFeatures ?? false) && (isPrivilegedUser || store.user?.canSeeChat == true) {
        sections.append(.chat)
    }
    if isPrivilegedUser || store.user?.canSeePatchsheet == true {
        sections.append(.patchsheet)
    }
    if store.canSeeRunOfShow {
        sections.append(.runOfShow)
    }
    if (store.user?.hasChatAndTrainingFeatures ?? false) && (isPrivilegedUser || store.user?.canSeeTraining == true) {
        sections.append(.training)
    }
    if isPrivilegedUser || store.user?.canSeeGear == true {
        sections.append(.assets)
    }
    if isPrivilegedUser && (store.user?.hasChatAndTrainingFeatures ?? false) {
        sections.append(.integrations)
    }
    if isPrivilegedUser || store.user?.canSeeChecklists == true {
        sections.append(.checklist)
    }
    if isPrivilegedUser || store.user?.canSeeIdeas == true {
        sections.append(.ideas)
    }
    if store.canUseTickets {
        sections.append(.tickets)
    }
    sections.append(.customize)

    sections.append(.account)

    if isPrivilegedUser {
        sections.append(.users)
    }

    return sections
}

private func decodePreferredMainTabSections(from rawValue: String) -> [MainAppSection] {
    rawValue
        .split(separator: ",")
        .compactMap { MainAppSection(rawValue: String($0)) }
}

private func encodePreferredMainTabSections(_ sections: [MainAppSection]) -> String {
    sections.map(\.rawValue).joined(separator: ",")
}

private func resolvedPreferredMainTabSections(
    storedValue: String,
    availableSections: [MainAppSection],
    maxCount: Int = 4
) -> [MainAppSection] {
    let availableSet = Set(availableSections)
    let storedSections = decodePreferredMainTabSections(from: storedValue).filter { availableSet.contains($0) }
    var ordered: [MainAppSection] = []

    if !storedSections.isEmpty {
        for section in storedSections where !ordered.contains(section) {
            ordered.append(section)
        }

        if ordered.isEmpty, let firstAvailable = availableSections.first {
            ordered.append(firstAvailable)
        }

        return Array(ordered.prefix(maxCount))
    }

    for section in defaultPreferredMainTabSections where availableSet.contains(section) {
        if !ordered.contains(section) {
            ordered.append(section)
        }
    }

    for section in availableSections where !ordered.contains(section) {
        ordered.append(section)
    }

    return Array(ordered.prefix(maxCount))
}

@ViewBuilder
private func mainAppSectionDestination(_ section: MainAppSection) -> some View {
    switch section {
    case .chat:
        ChatListView()
    case .patchsheet:
        MainTabView.PatchsheetView()
    case .runOfShow:
        RunOfShowTabView()
    case .training:
        TrainingListView()
    case .assets:
        GearTabView()
    case .integrations:
        IntegrationsView()
    case .notifications:
        NotificationsListView()
    case .checklist:
        ChecklistsListView()
    case .ideas:
        IdeasListView()
    case .tickets:
        TicketsListView()
    case .customize:
        CustomizeView()
    case .account:
        AccountView()
    case .users:
        UsersView()
    }
}

private struct RunOfShowTabView: View {
    private enum DisplayMode: String, CaseIterable, Identifiable {
        case timeline = "Timeline"
        case live = "Live"
        case stagePlot = "Stage Plot"

        var id: String { rawValue }
    }

    private enum ExportSubject: String, Identifiable {
        case runOfShow = "Run of Show"
        case stagePlot = "Stage Plot"

        var id: String { rawValue }
    }

    private enum ExportFormat: String, Identifiable {
        case pdf = "PDF"
        case jpeg = "JPEG"

        var id: String { rawValue }
        var fileExtension: String { self == .pdf ? "pdf" : "jpg" }
    }

    @EnvironmentObject private var store: ProdConnectStore
    @State private var selectedShowID: String?
    @State private var mode: DisplayMode = .timeline
    @State private var showToDelete: RunOfShowDocument?
    @State private var showTitleDraft = ""
    @State private var selectedStagePlotItemID: String?
    @State private var editingStagePlotItemID: String?
    @State private var stagePlotDragPoints: [String: CGPoint] = [:]
    @State private var stagePlotRotationDrafts: [String: Double] = [:]
    @State private var activeStagePlotRotationItemID: String?
    @State private var exportURL: URL?
    @State private var exportErrorMessage: String?
    @State private var pendingExportSubject: ExportSubject?
    @State private var isShowingExportTargetDialog = false
    @State private var isShowingExportFormatDialog = false

    private var canEdit: Bool {
        store.canEditRunOfShow
    }

    private var shows: [RunOfShowDocument] {
        store.runOfShows.sorted { $0.updatedAt > $1.updatedAt }
    }

    private var selectedShow: RunOfShowDocument? {
        guard let selectedShowID else { return shows.first }
        return shows.first(where: { $0.id == selectedShowID }) ?? shows.first
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Run of Show")
                .toolbar { toolbarContent }
                .onAppear {
                    if selectedShowID == nil {
                        selectedShowID = shows.first?.id
                    }
                    syncShowTitleDraft()
                    syncSelectedStagePlotItem()
                    syncStagePlotDragPoints()
                }
                .onChange(of: shows.map(\.id)) { ids in
                    if let selectedShowID, ids.contains(selectedShowID) {
                        syncShowTitleDraft()
                        syncSelectedStagePlotItem()
                        syncStagePlotDragPoints()
                        return
                    }
                    self.selectedShowID = ids.first
                    syncShowTitleDraft()
                    syncSelectedStagePlotItem()
                    syncStagePlotDragPoints()
                }
                .alert("Delete Run of Show?", isPresented: Binding(
                    get: { showToDelete != nil },
                    set: { if !$0 { showToDelete = nil } }
                )) {
                    Button("Cancel", role: .cancel) {}
                    Button("Delete", role: .destructive) {
                        guard let showToDelete else { return }
                        store.deleteRunOfShow(showToDelete)
                        if selectedShowID == showToDelete.id {
                            selectedShowID = shows.first(where: { $0.id != showToDelete.id })?.id
                        }
                        self.showToDelete = nil
                    }
                } message: {
                    Text("This permanently deletes the selected run of show.")
                }
                .sheet(isPresented: Binding(
                    get: { editingStagePlotItemID != nil },
                    set: { if !$0 { editingStagePlotItemID = nil } }
                )) {
                    if let show = selectedShow,
                       let itemID = editingStagePlotItemID,
                       let item = show.sortedStagePlotItems.first(where: { $0.id == itemID }) {
                        stagePlotEditorSheet(show: show, item: item)
                    }
                }
                .sheet(isPresented: Binding(
                    get: { exportURL != nil },
                    set: { if !$0 { exportURL = nil } }
                )) {
                    if let url = exportURL {
                        ShareSheet(items: [url])
                    }
                }
                .alert("Export Failed", isPresented: Binding(
                    get: { exportErrorMessage != nil },
                    set: { if !$0 { exportErrorMessage = nil } }
                )) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(exportErrorMessage ?? "Unable to export this file.")
                }
                .confirmationDialog(
                    "Export",
                    isPresented: $isShowingExportTargetDialog,
                    titleVisibility: .visible
                ) {
                    if selectedShow != nil {
                        Button("Run of Show") {
                            pendingExportSubject = .runOfShow
                            isShowingExportFormatDialog = true
                        }
                        Button("Stage Plot") {
                            pendingExportSubject = .stagePlot
                            isShowingExportFormatDialog = true
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                }
                .confirmationDialog(
                    "Choose Format",
                    isPresented: $isShowingExportFormatDialog,
                    titleVisibility: .visible
                ) {
                    if let show = selectedShow, let subject = pendingExportSubject {
                        Button("PDF") {
                            performExport(subject: subject, format: .pdf, show: show)
                        }
                        Button("JPEG") {
                            performExport(subject: subject, format: .jpeg, show: show)
                        }
                    }
                    Button("Cancel", role: .cancel) {
                        pendingExportSubject = nil
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let show = selectedShow {
            showContent(show)
        } else {
            emptyState
        }
    }

    private func showContent(_ show: RunOfShowDocument) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header(show)
                modePicker
                activeModeView(for: show)
            }
            .padding()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "list.bullet.rectangle.portrait")
                .font(.system(size: 42, weight: .regular))
                .foregroundStyle(.secondary)
            Text("No Run of Show")
                .font(.headline)
            Text("Create a show to start building your service timeline.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var modePicker: some View {
        Picker("Mode", selection: $mode) {
            ForEach(DisplayMode.allCases) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private func activeModeView(for show: RunOfShowDocument) -> some View {
        if mode == .timeline {
            timelineView(show)
        } else if mode == .stagePlot {
            stagePlotView(show)
        } else {
            liveView(show)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            Menu {
                ForEach(shows) { show in
                    Button(show.title.isEmpty ? "Untitled Show" : show.title) {
                        selectedShowID = show.id
                    }
                }
            } label: {
                Label("Shows", systemImage: "list.bullet")
            }

            if selectedShow != nil {
                Button {
                    isShowingExportTargetDialog = true
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
            }

            if canEdit {
                Button {
                    addShow()
                } label: {
                    Label("Add Show", systemImage: "plus")
                }
            }
        }
    }

    private func header(_ show: RunOfShowDocument) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField(
                "Show Title",
                text: $showTitleDraft
            )
            .font(.title.bold())
            .disabled(!canEdit)
            .onSubmit {
                commitShowTitle(for: show)
            }
            .onDisappear {
                commitShowTitle(for: show)
            }

            HStack {
                DatePicker(
                    "Start",
                    selection: Binding(
                        get: { show.scheduledStart },
                        set: { newValue in
                            updateShow(show) { $0.scheduledStart = newValue }
                        }
                    ),
                    displayedComponents: [.date, .hourAndMinute]
                )
                .disabled(!canEdit)

                Spacer()

                if canEdit {
                    Button("Delete", role: .destructive) {
                        showToDelete = show
                    }
                }
            }

            Toggle(
                "Auto Start",
                isOn: Binding(
                    get: { show.autoStartLive },
                    set: { newValue in
                        updateShow(show) { $0.autoStartLive = newValue }
                    }
                )
            )
            .disabled(!canEdit)

            Text("\(show.sortedItems.count) items • \(formatDuration(seconds: show.totalDurationSeconds)) total")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func timelineView(_ show: RunOfShowDocument) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if canEdit {
                Button {
                    addItem(to: show)
                } label: {
                    Label("Add Item", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }

            ScrollView(.horizontal, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 0) {
                        timelineHeader("Time", width: 90)
                        timelineHeader("Length", width: 90)
                        timelineHeader("Title", width: 220)
                        timelineHeader("Person", width: 150)
                        timelineHeader("Notes", width: 260)
                        timelineHeader("", width: 88)
                    }
                    .background(Color.secondary.opacity(0.12))

                    ForEach(Array(show.sortedItems.enumerated()), id: \.element.id) { index, item in
                        HStack(spacing: 0) {
                            timelineCell(startTimeText(for: show, itemIndex: index), width: 90)
                            HStack(spacing: 6) {
                                TextField(
                                    "0",
                                    text: Binding(
                                        get: { String(max(item.lengthMinutes, 0)) },
                                        set: { newValue in
                                            let digits = newValue.filter(\.isNumber)
                                            let parsed = Int(digits) ?? 0
                                            updateItemDuration(show, itemID: item.id, minutes: min(max(parsed, 0), 600), seconds: item.lengthSeconds)
                                        }
                                    )
                                )
                                .keyboardType(.numberPad)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 34)
                                .multilineTextAlignment(.trailing)
                                Text(":")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                TextField(
                                    "00",
                                    text: Binding(
                                        get: { String(format: "%02d", min(max(item.lengthSeconds, 0), 59)) },
                                        set: { newValue in
                                            let digits = newValue.filter(\.isNumber)
                                            let parsed = Int(digits) ?? 0
                                            updateItemDuration(show, itemID: item.id, minutes: item.lengthMinutes, seconds: min(max(parsed, 0), 59))
                                        }
                                    )
                                )
                                .keyboardType(.numberPad)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 34)
                                .multilineTextAlignment(.trailing)
                                Text("min")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(width: 90, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 10)
                            .disabled(!canEdit)

                            inlineField("Title", text: item.title, width: 220) { newValue in
                                updateItem(show, itemID: item.id) { $0.title = newValue }
                            }
                            inlineField("Person", text: item.person, width: 150) { newValue in
                                updateItem(show, itemID: item.id) { $0.person = newValue }
                            }
                            inlineField("Notes", text: item.notes, width: 260) { newValue in
                                updateItem(show, itemID: item.id) { $0.notes = newValue }
                            }

                            HStack(spacing: 8) {
                                Button {
                                    moveItem(show, from: index, direction: -1)
                                } label: {
                                    Image(systemName: "arrow.up")
                                }
                                .disabled(index == 0 || !canEdit)

                                Button(role: .destructive) {
                                    deleteItem(show, itemID: item.id)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .disabled(!canEdit)
                            }
                            .frame(width: 88)
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 0, style: .continuous)
                                .fill(index.isMultiple(of: 2) ? Color(.secondarySystemBackground) : Color(.systemBackground))
                        )
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func liveView(_ show: RunOfShowDocument) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button(show.isLiveActive ? "Restart" : "Start") {
                    startLive(show)
                }
                .buttonStyle(.borderedProminent)
                .disabled(show.sortedItems.isEmpty || !canEdit)

                Button("Previous") {
                    moveLive(show, direction: -1)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!show.isLiveActive || !canEdit)

                Button("Next") {
                    moveLive(show, direction: 1)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!show.isLiveActive || !canEdit)

                Button("Reset") {
                    resetLive(show)
                }
                .buttonStyle(.borderedProminent)
                .disabled((!show.isLiveActive && show.liveCurrentItemID == nil) || !canEdit)
            }

            TimelineView(.periodic(from: .now, by: 1)) { context in
                liveSnapshot(show: show, now: context.date)
            }
        }
        .padding()
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private func stagePlotView(_ show: RunOfShowDocument) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            stagePlotHeader(show)
            stagePlotCanvas(show)

            if show.sortedStagePlotItems.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "music.note.house")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Text("No Stage Plot Items")
                        .font(.headline)

                    Text("Add instruments or vocals to build a stage layout for this show.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                stagePlotList(show)
            }
        }
    }

    private func stagePlotCanvas(_ show: RunOfShowDocument) -> some View {
        GeometryReader { proxy in
            let size = proxy.size

            ZStack {
                stagePlotStageSurface(type: show.stageType)

                VStack {
                    Text("UPSTAGE")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.7))
                    Spacer()
                    HStack {
                        Text("STAGE RIGHT")
                        Spacer()
                        Text("STAGE LEFT")
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.55))
                    Text("DOWNSTAGE")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.7))
                }
                .padding(16)

                ForEach(show.sortedStagePlotItems) { item in
                    stagePlotCanvasItem(item, show: show, canvasSize: size)
                }
            }
        }
        .frame(height: 360)
    }

    private func stagePlotHeader(_ show: RunOfShowDocument) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Stage Plot")
                        .font(.title3.weight(.semibold))
                    Text("Drag labels into position on the stage.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if canEdit {
                    Menu {
                        stagePlotAddButtons(show: show)
                    } label: {
                        Label("Add Item", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            Picker(
                "Stage Type",
                selection: Binding(
                    get: { show.stageType },
                    set: { newValue in
                        updateShow(show) { $0.stageType = newValue }
                    }
                )
            ) {
                ForEach(RunOfShowStageType.allCases) { stageType in
                    Text(stageType.rawValue).tag(stageType)
                }
            }
            .pickerStyle(.segmented)
            .disabled(!canEdit)
        }
    }

    private func stagePlotList(_ show: RunOfShowDocument) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(show.sortedStagePlotItems) { item in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(stagePlotColor(for: item.role).opacity(0.2))
                        .frame(width: 8)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(stagePlotItemTitle(item))
                            .font(.headline)
                            .foregroundStyle(item.id == selectedStagePlotItemID ? Color.accentColor : Color.primary)
                        Text(item.subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? item.role.rawValue : item.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("X \(Int((item.x * 100).rounded()))  •  Y \(Int((item.y * 100).rounded()))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    Spacer()

                    if canEdit {
                        Button("Edit") {
                            openStagePlotEditor(item.id)
                        }
                        .buttonStyle(.bordered)

                        Button(role: .destructive) {
                            deleteStagePlotItem(show, itemID: item.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(item.id == selectedStagePlotItemID ? Color.accentColor.opacity(0.08) : Color(.secondarySystemBackground))
                )
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .onTapGesture {
                    selectedStagePlotItemID = item.id
                }
                .contextMenu {
                    if canEdit {
                        Button("Rename / Edit") {
                            openStagePlotEditor(item.id)
                        }
                        Button(role: .destructive) {
                            deleteStagePlotItem(show, itemID: item.id)
                        } label: {
                            Text("Delete")
                        }
                    }
                }
            }
        }
    }

    private func stagePlotCanvasItem(_ item: RunOfShowStagePlotItem, show: RunOfShowDocument, canvasSize: CGSize) -> some View {
        let isSelected = item.id == selectedStagePlotItemID
        let displayPosition = stagePlotDisplayPosition(for: item)
        let displayRotation = stagePlotDisplayRotation(for: item)

        return stagePlotCanvasNode(item, isSelected: isSelected)
        .overlay {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(item.role.usesSymbolArtwork ? Color.clear : Color.white.opacity(isSelected ? 0.95 : 0.28), lineWidth: isSelected ? 2 : 1)
                if canEdit && isSelected {
                    stagePlotRotationHotZone(item: item, show: show)
                }
            }
        }
        .scaleEffect(item.sizeScale)
        .rotationEffect(.degrees(displayRotation))
        .shadow(color: Color.black.opacity(0.24), radius: 12, y: 6)
        .position(stagePlotPoint(x: displayPosition.x, y: displayPosition.y, canvasSize: canvasSize))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard canEdit else { return }
                    selectedStagePlotItemID = item.id
                    stagePlotDragPoints[item.id] = normalizedStagePlotPoint(for: value.location, canvasSize: canvasSize)
                }
                .onEnded { value in
                    guard canEdit else { return }
                    let point = normalizedStagePlotPoint(for: value.location, canvasSize: canvasSize)
                    stagePlotDragPoints[item.id] = point
                    updateStagePlotItem(show, itemID: item.id) {
                        $0.x = point.x
                        $0.y = point.y
                    }
                    stagePlotDragPoints[item.id] = nil
                }
        )
        .onTapGesture {
            selectedStagePlotItemID = item.id
        }
        .contextMenu {
            if canEdit {
                Button("Rename / Edit") {
                    openStagePlotEditor(item.id)
                }
                Button(role: .destructive) {
                    deleteStagePlotItem(show, itemID: item.id)
                } label: {
                    Text("Delete")
                }
            }
        }
    }

    private func stagePlotEditorSheet(show: RunOfShowDocument, item: RunOfShowStagePlotItem) -> some View {
        NavigationStack {
            Form {
                Picker(
                    "Type",
                    selection: Binding(
                        get: { item.role },
                        set: { newValue in
                            updateStagePlotItem(show, itemID: item.id) { $0.role = newValue }
                        }
                    )
                ) {
                    ForEach(RunOfShowStagePlotRole.allCases) { role in
                        Text(role.rawValue).tag(role)
                    }
                }

                TextField(
                    item.role.usesSymbolArtwork ? "Label" : (item.role == .instrument ? "Instrument Name" : "Vocal Name"),
                    text: Binding(
                        get: { item.title },
                        set: { newValue in
                            updateStagePlotItem(show, itemID: item.id) { $0.title = newValue }
                        }
                    )
                )

                TextField(
                    item.role == .vocal ? "Mic / Notes" : "Player / Notes",
                    text: Binding(
                        get: { item.subtitle },
                        set: { newValue in
                            updateStagePlotItem(show, itemID: item.id) { $0.subtitle = newValue }
                        }
                    )
                )

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Size")
                        Spacer()
                        Text("\(Int((item.sizeScale * 100).rounded()))%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    Slider(
                        value: Binding(
                            get: { item.sizeScale },
                            set: { newValue in
                                updateStagePlotItem(show, itemID: item.id) { $0.sizeScale = newValue }
                            }
                        ),
                        in: 0.6...1.8,
                        step: 0.05
                    )
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Rotation")
                        Spacer()
                        Text("\(Int(item.rotationDegrees.rounded()))°")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Button("-15°") {
                            updateStagePlotItem(show, itemID: item.id) { $0.rotationDegrees -= 15 }
                        }
                        Button("Reset") {
                            updateStagePlotItem(show, itemID: item.id) { $0.rotationDegrees = 0 }
                        }
                        Button("+15°") {
                            updateStagePlotItem(show, itemID: item.id) { $0.rotationDegrees += 15 }
                        }
                    }
                }
            }
            .navigationTitle("Edit Stage Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        editingStagePlotItemID = nil
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    @ViewBuilder
    private func stagePlotStageSurface(type: RunOfShowStageType) -> some View {
        ZStack {
            switch type {
            case .rectangle:
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.19, green: 0.2, blue: 0.23),
                                Color(red: 0.08, green: 0.09, blue: 0.12)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
                    .padding(10)
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.18), Color.clear],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .padding(.horizontal, 36)
                    .padding(.bottom, 14)
            case .archedFront:
                StagePlotArchedFrontShape(curveDepth: 0.18, cornerRadius: 24)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.19, green: 0.2, blue: 0.23),
                            Color(red: 0.08, green: 0.09, blue: 0.12)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                StagePlotArchedFrontShape(curveDepth: 0.18, cornerRadius: 24)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
                .padding(10)
                StagePlotArchedFrontShape(curveDepth: 0.24, cornerRadius: 24)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.18), Color.clear],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .padding(.horizontal, 36)
                .padding(.bottom, 14)
            case .round:
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.19, green: 0.2, blue: 0.23),
                                Color(red: 0.08, green: 0.09, blue: 0.12)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                Circle()
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
                    .padding(10)
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.18), Color.clear],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .padding(.horizontal, 36)
                    .padding(.bottom, 14)
            }
        }
    }

    private func stagePlotPoint(for item: RunOfShowStagePlotItem, canvasSize: CGSize) -> CGPoint {
        stagePlotPoint(x: item.x, y: item.y, canvasSize: canvasSize)
    }

    private func stagePlotPoint(x: Double, y: Double, canvasSize: CGSize) -> CGPoint {
        CGPoint(
            x: 36 + x * max(canvasSize.width - 72, 1),
            y: 42 + y * max(canvasSize.height - 84, 1)
        )
    }

    private func normalizedStagePlotPoint(for location: CGPoint, canvasSize: CGSize) -> CGPoint {
        let x = min(max((location.x - 36) / max(canvasSize.width - 72, 1), 0), 1)
        let y = min(max((location.y - 42) / max(canvasSize.height - 84, 1), 0), 1)
        return CGPoint(x: x, y: y)
    }

    private func stagePlotItemTitle(_ item: RunOfShowStagePlotItem) -> String {
        let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? item.role.defaultTitle : title
    }

    private func openStagePlotEditor(_ itemID: String) {
        selectedStagePlotItemID = itemID
        editingStagePlotItemID = itemID
    }

    private func liveSnapshot(show: RunOfShowDocument, now: Date) -> some View {
        let items = show.sortedItems
        let activeCurrentItemID = show.isLiveActive ? show.liveCurrentItemID : items.first?.id
        let currentIndex = show.itemIndex(for: activeCurrentItemID)
        let currentItem = currentIndex.flatMap { items.indices.contains($0) ? items[$0] : nil }
        let nextItem = currentIndex.flatMap { index in
            let nextIndex = index + 1
            return items.indices.contains(nextIndex) ? items[nextIndex] : nil
        }
        let remaining = currentItem.map { item in
            show.isLiveActive ? show.currentRemainingSeconds(at: now) : item.durationSeconds
        } ?? 0
        let endTime = show.isLiveActive
            ? show.projectedEndTime(at: now)
            : show.scheduledStart.addingTimeInterval(TimeInterval(show.totalDurationSeconds))
        let currentTitle = currentItem?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let currentNotes = currentItem?.notes.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let nextTitle = nextItem?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let endTimeText = show.isLiveActive
            ? "ends \(endTime.formatted(date: .omitted, time: .shortened))"
            : "live not started"
        let currentItemSummary = currentItem.map { item -> String in
            let person = item.person.trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(item.formattedDuration) • \(person.isEmpty ? "No person assigned" : person)"
        } ?? "Waiting to start"
        let nextItemSummary = nextItem.map { item -> String in
            let person = item.person.trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(item.formattedDuration) • \(person.isEmpty ? "No person assigned" : person)"
        } ?? "End of show"
        let visibleItems = Array(items.prefix(6))
        let currentItemID = currentItem?.id

        return VStack(spacing: 0) {
            liveSnapshotHeader(remaining: remaining, endTimeText: endTimeText, currentTitle: currentTitle, currentItemSummary: currentItemSummary)
            liveSnapshotNotes(currentNotes: currentNotes)
            liveSnapshotNext(nextTitle: nextTitle, nextItemSummary: nextItemSummary)
            liveSnapshotQueue(show: show, items: visibleItems, currentItemID: currentItemID)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .background(Color.black)
    }

    private func liveSnapshotHeader(remaining: Int, endTimeText: String, currentTitle: String, currentItemSummary: String) -> some View {
        HStack(spacing: 0) {
            VStack(spacing: 8) {
                Text(formattedClock(seconds: remaining))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(endTimeText)
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.82))
            }
            .frame(width: 128)
            .padding(.vertical, 18)
            .background(Color(red: 0.38, green: 0.77, blue: 0.2))

            VStack(alignment: .leading, spacing: 6) {
                Text("NOW")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.white.opacity(0.72))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                Text(currentTitle.isEmpty ? "No active item" : currentTitle)
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(Color.white.opacity(0.94))
                    .lineLimit(2)
                Text(currentItemSummary)
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.68))
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(red: 0.11, green: 0.12, blue: 0.14))
        }
    }

    private func liveSnapshotNotes(currentNotes: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ITEM NOTES")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.72))
            Text(currentNotes.isEmpty ? "No item notes" : currentNotes)
                .foregroundStyle(Color.white.opacity(0.9))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(18)
        .background(Color(red: 0.08, green: 0.09, blue: 0.11))
    }

    private func liveSnapshotNext(nextTitle: String, nextItemSummary: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("NEXT")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.white.opacity(0.72))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text(nextTitle.isEmpty ? "No next item" : nextTitle)
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(Color.white.opacity(0.88))
                .lineLimit(2)
            Text(nextItemSummary)
                .font(.subheadline)
                .foregroundStyle(Color.white.opacity(0.68))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.11, green: 0.12, blue: 0.14))
    }

    private func liveSnapshotQueue(show: RunOfShowDocument, items: [RunOfShowItem], currentItemID: String?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                let isCurrent = item.id == currentItemID
                let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)

                HStack(spacing: 10) {
                    Text(startTimeText(for: show, itemIndex: index))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(isCurrent ? Color.orange : Color.white.opacity(0.58))
                        .frame(width: 62, alignment: .leading)
                    Text(title.isEmpty ? "Untitled" : title)
                        .font(.subheadline.weight(isCurrent ? .semibold : .regular))
                        .foregroundStyle(isCurrent ? Color.white : Color.white.opacity(0.7))
                        .lineLimit(2)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(isCurrent ? Color.orange.opacity(0.18) : (index.isMultiple(of: 2) ? Color.white.opacity(0.04) : Color.clear))
            }
        }
        .background(Color(red: 0.08, green: 0.09, blue: 0.11))
    }

    private func timelineHeader(_ title: String, width: CGFloat) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
            .frame(width: width, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
    }

    private func timelineCell(_ value: String, width: CGFloat) -> some View {
        Text(value)
            .frame(width: width, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
    }

    private func inlineField(_ placeholder: String, text: String, width: CGFloat, setter: @escaping (String) -> Void) -> some View {
        TextField(placeholder, text: Binding(get: { text }, set: setter))
            .frame(width: width, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
            .disabled(!canEdit)
    }

    private func addShow() {
        guard canEdit else { return }
        let show = RunOfShowDocument(
            title: "New Run of Show",
            teamCode: store.teamCode ?? "",
            scheduledStart: Date(),
            items: [
                RunOfShowItem(title: "Welcome", lengthMinutes: 5, lengthSeconds: 0, position: 0),
                RunOfShowItem(title: "Song 1", lengthMinutes: 5, lengthSeconds: 0, position: 1)
            ]
        )
        store.saveRunOfShow(show)
        selectedShowID = show.id
    }

    private func performExport(subject: ExportSubject, format: ExportFormat, show: RunOfShowDocument) {
        pendingExportSubject = nil

        let export: (Data?, String) = {
            switch (subject, format) {
            case (.runOfShow, .pdf):
                return (makeRunOfShowPDFData(show), exportFilename(prefix: "RunOfShow", showTitle: show.title, fileExtension: format.fileExtension))
            case (.runOfShow, .jpeg):
                return (makeRunOfShowJPEGData(show), exportFilename(prefix: "RunOfShow", showTitle: show.title, fileExtension: format.fileExtension))
            case (.stagePlot, .pdf):
                return (makeStagePlotPDFData(show), exportFilename(prefix: "StagePlot", showTitle: show.title, fileExtension: format.fileExtension))
            case (.stagePlot, .jpeg):
                return (makeStagePlotJPEGData(show), exportFilename(prefix: "StagePlot", showTitle: show.title, fileExtension: format.fileExtension))
            }
        }()

        guard let data = export.0 else {
            exportErrorMessage = "Unable to render \(subject.rawValue) \(format.rawValue)."
            return
        }

        exportSelectedShow(data: data, filename: export.1)
    }

    private func exportSelectedShow(data: Data, filename: String) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try data.write(to: url, options: .atomic)
            exportURL = url
        } catch {
            exportErrorMessage = error.localizedDescription
        }
    }

    private func exportFilename(prefix: String, showTitle: String, fileExtension: String) -> String {
        let trimmed = showTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "UntitledShow" : trimmed
        let sanitized = base.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return "\(prefix)-\(sanitized).\(fileExtension)"
    }

    private func makeRunOfShowPDFData(_ show: RunOfShowDocument) -> Data? {
        let width: CGFloat = 920
        let height = runOfShowExportHeight(for: show, rowHeight: 52, minimumHeight: 520)
        let size = CGSize(width: width, height: height)
        let content = runOfShowExportView(show)
            .frame(width: width, height: height)

        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(size)
        renderer.scale = 1

        guard let image = renderer.uiImage else { return nil }
        let bounds = CGRect(origin: .zero, size: size)
        let pdfRenderer = UIGraphicsPDFRenderer(bounds: bounds)
        return pdfRenderer.pdfData { context in
            context.beginPage()
            image.draw(in: bounds)
        }
    }

    private func makeRunOfShowJPEGData(_ show: RunOfShowDocument) -> Data? {
        let width: CGFloat = 1120
        let height = runOfShowExportHeight(for: show, rowHeight: 62, minimumHeight: 760)
        let size = CGSize(width: width, height: height)
        let content = runOfShowExportView(show)
            .frame(width: width, height: height)

        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(size)
        renderer.scale = 1
        return renderer.uiImage?.jpegData(compressionQuality: 0.92)
    }

    private func makeStagePlotPDFData(_ show: RunOfShowDocument) -> Data? {
        let size = CGSize(width: 1100, height: 720)
        let content = stagePlotExportView(show)
            .frame(width: size.width, height: size.height)

        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(size)
        renderer.scale = 1

        guard let image = renderer.uiImage else { return nil }
        let bounds = CGRect(origin: .zero, size: size)
        let pdfRenderer = UIGraphicsPDFRenderer(bounds: bounds)
        return pdfRenderer.pdfData { context in
            context.beginPage()
            image.draw(in: bounds)
        }
    }

    private func makeStagePlotJPEGData(_ show: RunOfShowDocument) -> Data? {
        let size = CGSize(width: 1600, height: 900)
        let content = stagePlotExportView(show)
            .frame(width: size.width, height: size.height)

        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(size)
        renderer.scale = 1
        return renderer.uiImage?.jpegData(compressionQuality: 0.92)
    }

    private func runOfShowExportView(_ show: RunOfShowDocument) -> some View {
        let items = show.sortedItems

        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text(show.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Run of Show" : show.title)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(Color.black)
                Text("Scheduled Start: \(show.scheduledStart.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.65))
                Text("\(items.count) items • \(formatDuration(seconds: show.totalDurationSeconds)) total")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.65))
            }
            .padding(.leading, 60)
            .padding(.trailing, 12)
            .padding(.top, 28)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(red: 0.95, green: 0.97, blue: 1.0))

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    exportHeaderCell("Time", width: 115)
                    exportHeaderCell("Length", width: 90)
                    exportHeaderCell("Title", width: 220)
                    exportHeaderCell("Person", width: 150)
                    exportHeaderCell("Notes", width: 247)
                }

                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    HStack(alignment: .top, spacing: 0) {
                        exportValueCell(startTimeText(for: show, itemIndex: index), width: 115)
                        exportValueCell(item.formattedDuration, width: 90)
                        exportValueCell(item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled" : item.title, width: 220)
                        exportValueCell(item.person.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Unassigned" : item.person, width: 150)
                        exportValueCell(item.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? " " : item.notes, width: 247)
                    }
                    .background(index.isMultiple(of: 2) ? Color.black.opacity(0.03) : Color.white)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(Color.black.opacity(0.08))
                            .frame(height: 1)
                    }
                }
            }
            .padding(.leading, 60)
            .padding(.trailing, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white)
    }

    private func runOfShowExportHeight(for show: RunOfShowDocument, rowHeight: CGFloat, minimumHeight: CGFloat) -> CGFloat {
        let itemCount = CGFloat(max(show.sortedItems.count, 1))
        let headerHeight: CGFloat = 118
        let tableHeaderHeight: CGFloat = 42
        let bottomPadding: CGFloat = 24
        return max(minimumHeight, headerHeight + tableHeaderHeight + (itemCount * rowHeight) + bottomPadding)
    }

    private func stagePlotExportView(_ show: RunOfShowDocument) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(show.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Stage Plot" : show.title)
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Stage Plot")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.68))
                }
                Spacer()
                Text(show.stageType.rawValue)
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
                    .foregroundStyle(.white)
            }

            GeometryReader { proxy in
                let size = proxy.size

                ZStack {
                    stagePlotStageSurface(type: show.stageType)

                    VStack {
                        Text("UPSTAGE")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.76))
                        Spacer()
                        HStack {
                            Text("STAGE RIGHT")
                            Spacer()
                            Text("STAGE LEFT")
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.58))
                        Text("DOWNSTAGE")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.76))
                    }
                    .padding(28)

                    ForEach(show.sortedStagePlotItems) { item in
                        stagePlotCanvasNode(item, isSelected: false)
                            .scaleEffect(item.sizeScale)
                            .rotationEffect(.degrees(item.rotationDegrees))
                            .position(stagePlotPoint(x: item.x, y: item.y, canvasSize: size))
                    }
                }
            }
        }
        .padding(28)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.09, green: 0.1, blue: 0.13),
                    Color(red: 0.03, green: 0.04, blue: 0.06)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func exportHeaderCell(_ title: String, width: CGFloat) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .textCase(.uppercase)
            .foregroundStyle(Color.black.opacity(0.65))
            .frame(width: width, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.05))
    }

    private func exportValueCell(_ value: String, width: CGFloat) -> some View {
        Text(value)
            .font(.system(size: 13))
            .foregroundStyle(Color.black.opacity(0.9))
            .frame(width: width, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .lineLimit(3)
    }

    private func addItem(to show: RunOfShowDocument) {
        updateShow(show) { mutable in
            mutable.items.append(RunOfShowItem(title: "New Item", lengthMinutes: 5, lengthSeconds: 0, position: mutable.items.count))
        }
    }

    private func deleteItem(_ show: RunOfShowDocument, itemID: String) {
        updateShow(show) { mutable in
            mutable.items.removeAll { $0.id == itemID }
        }
    }

    private func moveItem(_ show: RunOfShowDocument, from index: Int, direction: Int) {
        updateShow(show) { mutable in
            var items = mutable.sortedItems
            let newIndex = index + direction
            guard items.indices.contains(index), items.indices.contains(newIndex) else { return }
            let moved = items.remove(at: index)
            items.insert(moved, at: newIndex)
            mutable.items = items.enumerated().map { offset, item in
                var updated = item
                updated.position = offset
                return updated
            }
        }
    }

    private func startLive(_ show: RunOfShowDocument) {
        updateShow(show) { mutable in
            guard let first = mutable.sortedItems.first else { return }
            let now = Date()
            mutable.isLiveActive = true
            mutable.liveCurrentItemID = first.id
            mutable.liveShowStartedAt = now
            mutable.liveItemStartedAt = now
        }
    }

    private func moveLive(_ show: RunOfShowDocument, direction: Int) {
        updateShow(show) { mutable in
            let items = mutable.sortedItems
            guard let currentIndex = mutable.itemIndex(for: mutable.liveCurrentItemID) else { return }
            let newIndex = currentIndex + direction
            guard items.indices.contains(newIndex) else { return }
            mutable.isLiveActive = true
            mutable.liveCurrentItemID = items[newIndex].id
            mutable.liveItemStartedAt = Date()
            if mutable.liveShowStartedAt == nil {
                mutable.liveShowStartedAt = Date()
            }
        }
    }

    private func resetLive(_ show: RunOfShowDocument) {
        updateShow(show) { mutable in
            mutable.isLiveActive = false
            mutable.liveCurrentItemID = nil
            mutable.liveShowStartedAt = nil
            mutable.liveItemStartedAt = nil
        }
    }

    private func updateItem(_ show: RunOfShowDocument, itemID: String, change: (inout RunOfShowItem) -> Void) {
        updateShow(show) { mutable in
            guard let index = mutable.items.firstIndex(where: { $0.id == itemID }) else { return }
            change(&mutable.items[index])
        }
    }

    private func updateItemDuration(_ show: RunOfShowDocument, itemID: String, minutes: Int, seconds: Int) {
        guard canEdit else { return }
        var mutable = show
        guard let index = mutable.items.firstIndex(where: { $0.id == itemID }) else { return }
        mutable.items[index].lengthMinutes = max(minutes, 0)
        mutable.items[index].lengthSeconds = min(max(seconds, 0), 59)
        store.saveRunOfShow(mutable)
    }

    private func updateShow(_ show: RunOfShowDocument, change: (inout RunOfShowDocument) -> Void) {
        guard canEdit else { return }
        var mutable = show
        change(&mutable)
        DispatchQueue.main.async {
            store.saveRunOfShow(mutable)
        }
    }

    private func syncShowTitleDraft() {
        let nextTitle = selectedShow?.title ?? ""
        if showTitleDraft != nextTitle {
            showTitleDraft = nextTitle
        }
    }

    private func syncSelectedStagePlotItem() {
        let ids = Set(selectedShow?.sortedStagePlotItems.map(\.id) ?? [])
        if let selectedStagePlotItemID, ids.contains(selectedStagePlotItemID) {
            return
        }
        selectedStagePlotItemID = selectedShow?.sortedStagePlotItems.first?.id
    }

    private func syncStagePlotDragPoints() {
        let validIDs = Set(selectedShow?.sortedStagePlotItems.map(\.id) ?? [])
        stagePlotDragPoints = stagePlotDragPoints.filter { validIDs.contains($0.key) }
        stagePlotRotationDrafts = stagePlotRotationDrafts.filter { validIDs.contains($0.key) }
        if let activeStagePlotRotationItemID, !validIDs.contains(activeStagePlotRotationItemID) {
            self.activeStagePlotRotationItemID = nil
        }
    }

    private func commitShowTitle(for show: RunOfShowDocument) {
        guard canEdit else { return }
        let normalizedTitle = showTitleDraft
        guard normalizedTitle != show.title else { return }
        updateShow(show) { $0.title = normalizedTitle }
    }

    private func startTimeText(for show: RunOfShowDocument, itemIndex: Int) -> String {
        let offsetSeconds = show.sortedItems.prefix(itemIndex).reduce(0) { $0 + $1.durationSeconds }
        let start = show.scheduledStart.addingTimeInterval(TimeInterval(offsetSeconds))
        return start.formatted(date: .omitted, time: .shortened)
    }

    private func formattedClock(seconds: Int) -> String {
        let minutes = max(seconds, 0) / 60
        let remainingSeconds = max(seconds, 0) % 60
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }

    private func formatDuration(seconds: Int) -> String {
        let minutes = max(seconds, 0) / 60
        let remainingSeconds = max(seconds, 0) % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }

    private func addStagePlotItem(to show: RunOfShowDocument, role: RunOfShowStagePlotRole) {
        updateShow(show) { mutable in
            let nextPosition = mutable.stagePlotItems.count
            let defaultPosition = role.defaultPosition
            let newItem = RunOfShowStagePlotItem(
                role: role,
                title: role.defaultTitle,
                subtitle: "",
                x: defaultPosition.x,
                y: defaultPosition.y,
                position: nextPosition
            )
            mutable.stagePlotItems.append(newItem)
            selectedStagePlotItemID = newItem.id
        }
    }

    private func updateStagePlotItem(_ show: RunOfShowDocument, itemID: String, change: (inout RunOfShowStagePlotItem) -> Void) {
        updateShow(show) { mutable in
            guard let index = mutable.stagePlotItems.firstIndex(where: { $0.id == itemID }) else { return }
            change(&mutable.stagePlotItems[index])
            mutable.stagePlotItems[index].x = min(max(mutable.stagePlotItems[index].x, 0), 1)
            mutable.stagePlotItems[index].y = min(max(mutable.stagePlotItems[index].y, 0), 1)
            mutable.stagePlotItems[index].rotationDegrees = min(max(mutable.stagePlotItems[index].rotationDegrees, -180), 180)
            mutable.stagePlotItems[index].sizeScale = min(max(mutable.stagePlotItems[index].sizeScale, 0.6), 1.8)
        }
    }

    private func deleteStagePlotItem(_ show: RunOfShowDocument, itemID: String) {
        updateShow(show) { mutable in
            mutable.stagePlotItems.removeAll { $0.id == itemID }
            mutable.stagePlotItems = mutable.stagePlotItems.enumerated().map { offset, item in
                var updated = item
                updated.position = offset
                return updated
            }
            if selectedStagePlotItemID == itemID {
                selectedStagePlotItemID = mutable.sortedStagePlotItems.first?.id
            }
        }
    }

    private func stagePlotColor(for role: RunOfShowStagePlotRole) -> Color {
        switch role {
        case .instrument:
            return Color(red: 0.25, green: 0.52, blue: 0.94)
        case .vocal:
            return Color(red: 0.88, green: 0.33, blue: 0.46)
        case .drumSet:
            return Color(red: 0.77, green: 0.41, blue: 0.18)
        case .guitar:
            return Color(red: 0.98, green: 0.66, blue: 0.19)
        case .bassGuitar:
            return Color(red: 0.28, green: 0.77, blue: 0.58)
        case .microphoneStand:
            return Color(red: 0.69, green: 0.37, blue: 0.93)
        case .keyboard:
            return Color(red: 0.36, green: 0.72, blue: 0.96)
        case .speaker:
            return Color(red: 0.54, green: 0.59, blue: 0.66)
        }
    }

    @ViewBuilder
    private func stagePlotAddButtons(show: RunOfShowDocument) -> some View {
        ForEach(RunOfShowStagePlotRole.allCases) { role in
            Button {
                addStagePlotItem(to: show, role: role)
            } label: {
                if let symbol = role.systemImageName {
                    Label(role.rawValue, systemImage: symbol)
                } else {
                    Text(role.rawValue)
                }
            }
        }
    }

    private func stagePlotDisplayPosition(for item: RunOfShowStagePlotItem) -> CGPoint {
        stagePlotDragPoints[item.id] ?? CGPoint(x: item.x, y: item.y)
    }

    private func stagePlotDisplayRotation(for item: RunOfShowStagePlotItem) -> Double {
        stagePlotRotationDrafts[item.id] ?? item.rotationDegrees
    }

    private func normalizedStagePlotRotation(_ degrees: Double) -> Double {
        let wrapped = degrees.truncatingRemainder(dividingBy: 360)
        if wrapped > 180 { return wrapped - 360 }
        if wrapped < -180 { return wrapped + 360 }
        return wrapped
    }

    private func stagePlotRotationAngle(for location: CGPoint, in size: CGSize) -> Double {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radians = atan2(location.y - center.y, location.x - center.x)
        return normalizedStagePlotRotation((radians * 180 / .pi) + 90)
    }

    private func commitStagePlotRotation(_ rotation: Double, show: RunOfShowDocument, itemID: String) {
        let normalized = normalizedStagePlotRotation(rotation)
        stagePlotRotationDrafts[itemID] = normalized
        updateStagePlotItem(show, itemID: itemID) { $0.rotationDegrees = normalized }
        stagePlotRotationDrafts[itemID] = nil
    }

    private func stagePlotRotationHotZone(item: RunOfShowStagePlotItem, show: RunOfShowDocument) -> some View {
        GeometryReader { proxy in
            let gesture = LongPressGesture(minimumDuration: 0.18)
                .sequenced(before: DragGesture(minimumDistance: 0))

            Circle()
                .fill(Color.clear)
                .frame(width: 34, height: 34)
                .overlay {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 22, height: 22)
                        .overlay(
                            Image(systemName: "rotate.right.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color.black.opacity(0.72))
                        )
                        .shadow(color: Color.black.opacity(0.22), radius: 4, y: 2)
                        .opacity(activeStagePlotRotationItemID == item.id ? 1 : 0)
                }
                .contentShape(Circle())
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .offset(x: 14, y: -14)
                .gesture(
                    gesture
                        .onChanged { value in
                            switch value {
                            case .second(true, let drag?):
                                activeStagePlotRotationItemID = item.id
                                stagePlotRotationDrafts[item.id] = stagePlotRotationAngle(for: drag.location, in: proxy.size)
                            default:
                                break
                            }
                        }
                        .onEnded { value in
                            defer { activeStagePlotRotationItemID = nil }
                            switch value {
                            case .second(true, let drag?):
                                commitStagePlotRotation(
                                    stagePlotRotationAngle(for: drag.location, in: proxy.size),
                                    show: show,
                                    itemID: item.id
                                )
                            default:
                                stagePlotRotationDrafts[item.id] = nil
                            }
                        }
                )
        }
    }

    @ViewBuilder
    private func stagePlotCanvasNode(_ item: RunOfShowStagePlotItem, isSelected: Bool) -> some View {
        if item.role.usesSymbolArtwork {
            VStack(spacing: 6) {
                stagePlotArtwork(for: item.role, color: stagePlotColor(for: item.role))
                    .frame(width: 46, height: 40)
                Text(stagePlotItemTitle(item))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(isSelected ? 0.45 : 0.28))
                    .clipShape(Capsule())
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(isSelected ? 0.1 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(isSelected ? 0.4 : 0.14), lineWidth: isSelected ? 2 : 1)
            )
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text(stagePlotItemTitle(item))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if !item.subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(item.subtitle)
                        .font(.caption2)
                        .foregroundStyle(Color.white.opacity(0.72))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(minWidth: 74, maxWidth: 126, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(stagePlotColor(for: item.role).opacity(isSelected ? 0.95 : 0.78))
            )
        }
    }

    @ViewBuilder
    private func stagePlotArtwork(for role: RunOfShowStagePlotRole, color: Color) -> some View {
        switch role {
        case .drumSet:
            ZStack {
                Circle().fill(Color.white.opacity(0.92)).frame(width: 14, height: 14).offset(x: -14, y: -10)
                Circle().fill(Color.white.opacity(0.92)).frame(width: 14, height: 14).offset(x: 14, y: -10)
                Circle().fill(color.opacity(0.85)).frame(width: 16, height: 16).offset(x: -2, y: 2)
                Circle().fill(color.opacity(0.78)).frame(width: 20, height: 20).offset(x: -16, y: 10)
                Circle().fill(color.opacity(0.78)).frame(width: 20, height: 20).offset(x: 12, y: 10)
                Circle().fill(Color.white.opacity(0.95)).frame(width: 18, height: 18).offset(x: 20, y: 4)
                Rectangle().fill(Color.black.opacity(0.45)).frame(width: 2, height: 16).offset(x: -14, y: 0)
                Rectangle().fill(Color.black.opacity(0.45)).frame(width: 2, height: 16).offset(x: 14, y: 0)
                Rectangle().fill(Color.black.opacity(0.45)).frame(width: 2, height: 14).offset(x: -4, y: 12)
                Rectangle().fill(Color.black.opacity(0.45)).frame(width: 2, height: 14).offset(x: 10, y: 12)
            }
        case .guitar:
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.black.opacity(0.82))
                    .frame(width: 24, height: 4)
                    .offset(x: 10, y: -2)
                Circle().fill(color.opacity(0.92)).frame(width: 14, height: 12).offset(x: -10, y: -3)
                Circle().fill(color.opacity(0.82)).frame(width: 18, height: 14).offset(x: -16, y: 4)
                Circle().fill(color.opacity(0.88)).frame(width: 16, height: 12).offset(x: -8, y: 6)
                RoundedRectangle(cornerRadius: 2).fill(Color.black.opacity(0.76)).frame(width: 8, height: 2).offset(x: -13, y: 4)
                Capsule().fill(Color.black.opacity(0.9)).frame(width: 5, height: 3).offset(x: 23, y: -2)
            }
        case .bassGuitar:
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.black.opacity(0.84))
                    .frame(width: 26, height: 4)
                    .offset(x: 11, y: -1)
                Circle().fill(color.opacity(0.9)).frame(width: 16, height: 13).offset(x: -11, y: -1)
                Circle().fill(color.opacity(0.78)).frame(width: 18, height: 14).offset(x: -17, y: 5)
                RoundedRectangle(cornerRadius: 3).fill(color.opacity(0.86)).frame(width: 16, height: 12).offset(x: -8, y: 5)
                RoundedRectangle(cornerRadius: 2).fill(Color.black.opacity(0.72)).frame(width: 8, height: 3).offset(x: -13, y: 4)
                Capsule().fill(Color.black.opacity(0.9)).frame(width: 6, height: 4).offset(x: 25, y: -1)
            }
        case .microphoneStand:
            ZStack {
                Circle().fill(Color.black.opacity(0.32)).frame(width: 22, height: 22).offset(y: 10)
                Rectangle().fill(Color.black.opacity(0.72)).frame(width: 2, height: 26).offset(y: -2)
                Capsule().fill(Color.gray.opacity(0.92)).frame(width: 8, height: 14).offset(y: -16)
                Circle().fill(Color.gray.opacity(0.85)).frame(width: 7, height: 7).offset(y: -22)
            }
        case .keyboard:
            ZStack {
                RoundedRectangle(cornerRadius: 3).fill(Color.black.opacity(0.82)).frame(width: 40, height: 10).offset(y: -6)
                HStack(spacing: 1.2) {
                    ForEach(0..<7, id: \.self) { _ in
                        Rectangle().fill(Color.white.opacity(0.95)).frame(width: 4, height: 8)
                    }
                }
                .offset(y: -5)
                HStack(spacing: 4) {
                    Rectangle().fill(Color.black.opacity(0.7)).frame(width: 2, height: 14).rotationEffect(.degrees(22)).offset(y: 8)
                    Rectangle().fill(Color.black.opacity(0.7)).frame(width: 2, height: 14).rotationEffect(.degrees(-22)).offset(y: 8)
                }
                .offset(y: 10)
            }
        case .speaker:
            ZStack {
                RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(0.88)).frame(width: 24, height: 30)
                Circle().fill(Color.gray.opacity(0.6)).frame(width: 12, height: 12).offset(y: 5)
                Circle().fill(Color.gray.opacity(0.72)).frame(width: 6, height: 6).offset(y: -7)
            }
        case .instrument, .vocal:
            EmptyView()
        }
    }
}

private struct StagePlotArchedFrontShape: Shape {
    var curveDepth: CGFloat
    var cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let depth = max(12, min(rect.height * curveDepth, rect.height * 0.35))
        let radius = min(cornerRadius, rect.width * 0.12, rect.height * 0.18)
        let top = rect.minY
        let left = rect.minX
        let right = rect.maxX
        let backBottom = rect.maxY - depth

        var path = Path()
        path.move(to: CGPoint(x: left + radius, y: top))
        path.addLine(to: CGPoint(x: right - radius, y: top))
        path.addQuadCurve(
            to: CGPoint(x: right, y: top + radius),
            control: CGPoint(x: right, y: top)
        )
        path.addLine(to: CGPoint(x: right, y: backBottom))
        path.addQuadCurve(
            to: CGPoint(x: left, y: backBottom),
            control: CGPoint(x: rect.midX, y: rect.maxY + depth * 1.05)
        )
        path.addLine(to: CGPoint(x: left, y: top + radius))
        path.addQuadCurve(
            to: CGPoint(x: left + radius, y: top),
            control: CGPoint(x: left, y: top)
        )
        path.closeSubpath()
        return path
    }
}

private struct MainTabView: View {
    @EnvironmentObject var store: ProdConnectStore
    @Binding var selectedLaunchSection: MainAppSection?
    @Binding var shouldOpenMoreTab: Bool
    @AppStorage("reviewPromptLaunchCount") private var reviewPromptLaunchCount = 0
    @AppStorage("reviewPromptLastRequestTime") private var reviewPromptLastRequestTime: Double = 0
    @AppStorage("reviewPromptHasRequestedBefore") private var reviewPromptHasRequestedBefore = false
    @AppStorage(preferredMainTabSectionsStorageKey) private var preferredMainTabSections = ""
    @State private var showAppReviewPrompt = false
    @State private var selectedAppReviewRating = 0
    @State private var selectedTabID = ""
    @State private var pendingOverflowSection: MainAppSection?

    private let moreTabID = "__more__"

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
        @State private var field4 = ""
        @State private var selectedCampus: String = ""
        @State private var showCampusDialog = false
        @State private var saveErrorMessage: String?
        @State private var exportURL: URL?
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

        private var selectedCategory: String {
            categories[selectedTab]
        }

        private var showsLightingUniverseColumn: Bool {
            selectedCategory == "Lighting"
        }

        private var nameColumnTitle: String {
            selectedCategory == "Lighting" ? "Fixture" : "Name"
        }

        private var inputColumnTitle: String {
            switch selectedCategory {
            case "Video": return "Source"
            case "Lighting": return "DMX Channel"
            default: return "Input"
            }
        }

        private var outputColumnTitle: String {
            switch selectedCategory {
            case "Video": return "Destination"
            case "Lighting": return "Channel Count"
            default: return "Output"
            }
        }

        private var patchsheetTableWidth: CGFloat {
            showsLightingUniverseColumn ? 770 : 680
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
                        Button(action: exportPatchsheet) {
                            Label("Export", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.bordered)
                        .disabled(filteredPatches.isEmpty)

                        if canSelectCampus {
                            Button {
                                showCampusDialog = true
                            } label: {
                                HStack {
                                    Text(selectedCampus.isEmpty ? "Campus/Location" : selectedCampus)
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
                    .confirmationDialog("Select Campus/Location", isPresented: $showCampusDialog, titleVisibility: .visible) {
                        ForEach(store.locations.sorted(), id: \.self) { campus in
                            Button(campus) { selectedCampus = campus }
                        }
                        if !selectedCampus.isEmpty {
                            Button("Clear", role: .destructive) { selectedCampus = "" }
                        }
                        Button("Cancel", role: .cancel) {}
                    }
                    ScrollView([.horizontal, .vertical]) {
                        VStack(alignment: .leading, spacing: 0) {
                            patchsheetHeaderRow
                            ForEach(filteredPatches) { patch in
                                NavigationLink(destination: EditPatchView(patch: patch).environmentObject(store)) {
                                    patchsheetRow(for: patch)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .frame(width: patchsheetTableWidth, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Spacer()
                    VStack(spacing: 8) {
                        TextField(selectedCategory == "Lighting" ? "Fixture" : "Name", text: $field1)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .submitLabel(.next)

                        HStack(spacing: 8) {
                            TextField(
                                selectedCategory == "Video" ? "Source" : (selectedCategory == "Lighting" ? "DMX Channel" : "Input"),
                                text: $field2
                            )
                            .submitLabel(selectedCategory == "Lighting" ? .next : .done)
                            TextField(
                                selectedCategory == "Video" ? "Destination" : (selectedCategory == "Lighting" ? "Channel Count" : "Output"),
                                text: $field3
                            )
                            .submitLabel(selectedCategory == "Lighting" ? .next : .done)
                        }
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        
                        if selectedCategory == "Lighting" {
                            TextField("Universe", text: $field4)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .submitLabel(.done)
                        }
                    }
                    .onSubmit {
                        submitNewPatch()
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    Button {
                        submitNewPatch()
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
                .alert("Unable to Save Patch", isPresented: Binding(
                    get: { saveErrorMessage != nil },
                    set: { if !$0 { saveErrorMessage = nil } }
                )) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(saveErrorMessage ?? "")
                }
            }
            .sheet(isPresented: Binding(get: { exportURL != nil }, set: { if !$0 { exportURL = nil } })) {
                if let url = exportURL {
                    ShareSheet(items: [url])
                }
            }
        }

        private var patchsheetHeaderRow: some View {
            HStack(spacing: 0) {
                patchsheetHeaderCell(nameColumnTitle, width: 190, alignment: .leading)
                patchsheetHeaderCell(inputColumnTitle, width: 140, alignment: .leading)
                patchsheetHeaderCell(outputColumnTitle, width: 140, alignment: .leading)
                if showsLightingUniverseColumn {
                    patchsheetHeaderCell("Universe", width: 90, alignment: .leading)
                }
                patchsheetHeaderCell("Notes", width: 210, alignment: .leading)
            }
            .background(Color.secondary.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }

        private func patchsheetHeaderCell(_ title: String, width: CGFloat, alignment: Alignment) -> some View {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .frame(width: width, alignment: alignment)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        }

        private func patchsheetRow(for patch: PatchRow) -> some View {
            HStack(spacing: 0) {
                patchsheetValueCell(patch.name, width: 190, alignment: .leading, emphasized: true)
                patchsheetValueCell(patch.input, width: 140, alignment: .leading)
                patchsheetValueCell(patch.output, width: 140, alignment: .leading)
                if showsLightingUniverseColumn {
                    patchsheetValueCell(patch.universe ?? "", width: 90, alignment: .leading)
                }
                patchsheetValueCell(patch.notes, width: 210, alignment: .leading)
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
        }

        private func patchsheetValueCell(_ text: String, width: CGFloat, alignment: Alignment, emphasized: Bool = false) -> some View {
            Text(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? " " : text)
                .font(emphasized ? .body.weight(.semibold) : .body)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: width, alignment: alignment)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
        }

        private var addPatchEnabled: Bool {
            if selectedCategory == "Audio" {
                return !field1.isEmpty && (!field2.isEmpty || !field3.isEmpty)
            } else if selectedCategory == "Video" {
                return !field1.isEmpty && (!field2.isEmpty || !field3.isEmpty)
            } else {
                return !field1.isEmpty && (!field2.isEmpty || !field3.isEmpty)
            }
        }

        private func submitNewPatch() {
            guard addPatchEnabled else { return }
            let trimmedChannelCount = field3.trimmingCharacters(in: .whitespacesAndNewlines)
            let parsedChannelCount = Int(trimmedChannelCount)
            let isLighting = selectedCategory == "Lighting"
            let patch = PatchRow(
                name: field1,
                input: field2,
                output: field3,
                teamCode: store.teamCode ?? "",
                category: selectedCategory,
                campus: effectiveCampusFilter,
                room: "",
                channelCount: isLighting ? parsedChannelCount : nil,
                universe: isLighting ? field4.trimmingCharacters(in: .whitespacesAndNewlines) : nil
            )
            store.savePatch(patch) { result in
                switch result {
                case .success:
                    field1 = ""
                    field2 = ""
                    field3 = ""
                    field4 = ""
                case .failure(let error):
                    saveErrorMessage = error.localizedDescription
                }
            }
        }

        private func exportPatchsheet() {
            guard !filteredPatches.isEmpty else { return }

            let header = [
                "Name",
                inputColumnTitle,
                outputColumnTitle,
                "Universe",
                "Notes",
                "Category",
                "Campus",
                "Room",
                "NDI Enabled"
            ].map(csvEscaped).joined(separator: ",")

            let rows = filteredPatches.map { patch in
                [
                    patch.name,
                    patch.input,
                    patch.output,
                    patch.universe ?? "",
                    patch.notes,
                    patch.category,
                    patch.campus,
                    patch.room,
                    patch.ndiEnabled ? "Yes" : "No"
                ].map(csvEscaped).joined(separator: ",")
            }

            let csv = "\u{FEFF}" + ([header] + rows).joined(separator: "\n")
            let filename = "Patchsheet-\(selectedCategory.replacingOccurrences(of: " ", with: ""))-\(UUID().uuidString).csv"
            let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

            do {
                try csv.write(to: fileURL, atomically: true, encoding: .utf8)
                exportURL = fileURL
            } catch {
                saveErrorMessage = error.localizedDescription
            }
        }

        private func csvEscaped(_ value: String) -> String {
            "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
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
                    let header = "Name,Category,Status,Location,Room,Notes\n"
                    let rows = filteredGear.map { item in
                        let notes = item.maintenanceNotes.replacingOccurrences(of: ",", with: ";")
                        return "\(item.name),\(item.category),\(item.status.rawValue),\(item.location),\(item.room),\(notes)"
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
                            .navigationTitle("Assets")
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
                        AddGearView { _ in
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
            store.patchsheet
                .filter { $0.category == categories[selectedTab] && (effectiveCampusFilter.isEmpty || $0.campus == effectiveCampusFilter) }
                .sorted(by: PatchRow.autoSort)
        }
    }
    private var availableSections: [MainAppSection] {
        availableMainAppSections(for: store)
    }

    private var featuredSections: [MainAppSection] {
        resolvedPreferredMainTabSections(
            storedValue: preferredMainTabSections,
            availableSections: availableSections
        )
    }

    private var overflowSections: [MainAppSection] {
        availableSections.filter { !featuredSections.contains($0) }
    }

    private var appStoreReviewURL: URL? {
        URL(string: "https://apps.apple.com/app/id6758495145?action=write-review")
    }

    private func completeReviewPromptCycle() {
        reviewPromptLastRequestTime = Date().timeIntervalSince1970
        reviewPromptHasRequestedBefore = true
        reviewPromptLaunchCount = 0
    }

    private func submitAppReview() {
        guard
            selectedAppReviewRating > 0,
            let reviewURL = appStoreReviewURL,
            UIApplication.shared.canOpenURL(reviewURL)
        else { return }

        UIApplication.shared.open(reviewURL)
        showAppReviewPrompt = false
        completeReviewPromptCycle()
    }

    private func maybeRequestAppReview() {
        guard store.user != nil else { return }

        reviewPromptLaunchCount += 1

        let minimumLaunches = reviewPromptHasRequestedBefore ? 20 : 6
        guard reviewPromptLaunchCount >= minimumLaunches else { return }

        let cooldown: TimeInterval = 120 * 24 * 60 * 60
        let now = Date().timeIntervalSince1970
        guard now - reviewPromptLastRequestTime >= cooldown else { return }

        // Keep the request timing unpredictable so it feels natural.
        let requestChancePercent = reviewPromptHasRequestedBefore ? 12 : 25
        let shouldRequestNow = Int.random(in: 1...100) <= requestChancePercent
        guard shouldRequestNow else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            selectedAppReviewRating = 0
            showAppReviewPrompt = true
        }
    }

    var body: some View {
        TabView(selection: $selectedTabID) {
            ForEach(featuredSections) { section in
                mainAppSectionDestination(section)
                    .tabItem {
                        Label(section.title, systemImage: section.icon)
                    }
                    .badge(section == .notifications && store.notificationBadgeCount > 0 ? store.notificationBadgeCount : 0)
                    .tag(section.rawValue)
            }
            MoreTabView(sections: overflowSections, pendingSection: $pendingOverflowSection)
                .tabItem {
                    Label("More", systemImage: "ellipsis")
                }
                .badge(overflowSections.contains(.notifications) && store.notificationBadgeCount > 0 ? store.notificationBadgeCount : 0)
                .tag(moreTabID)
        }
        .onAppear {
            if selectedTabID.isEmpty {
                selectedTabID = featuredSections.first?.rawValue ?? moreTabID
            }
            handleLaunchSelection(selectedLaunchSection)
            handleOpenMoreTab()
            maybeRequestAppReview()
        }
        .onChange(of: selectedLaunchSection) { newValue in
            handleLaunchSelection(newValue)
        }
        .onChange(of: shouldOpenMoreTab) { _ in
            handleOpenMoreTab()
        }
        .onChange(of: featuredSections.map(\.rawValue)) { newValue in
            guard !newValue.contains(selectedTabID), selectedTabID != moreTabID else { return }
            selectedTabID = featuredSections.first?.rawValue ?? moreTabID
        }
        .sheet(isPresented: $showAppReviewPrompt, onDismiss: {
            selectedAppReviewRating = 0
        }) {
            AppReviewPromptView(
                selectedRating: $selectedAppReviewRating,
                onSubmit: submitAppReview,
                onNotNow: {
                    showAppReviewPrompt = false
                    completeReviewPromptCycle()
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }

    private func handleLaunchSelection(_ section: MainAppSection?) {
        guard let section else { return }

        if featuredSections.contains(section) {
            selectedTabID = section.rawValue
        } else {
            pendingOverflowSection = section
            selectedTabID = moreTabID
        }

        DispatchQueue.main.async {
            selectedLaunchSection = nil
        }
    }

    private func handleOpenMoreTab() {
        guard shouldOpenMoreTab else { return }
        selectedTabID = moreTabID
        DispatchQueue.main.async {
            shouldOpenMoreTab = false
        }
    }
}

private struct AppReviewPromptView: View {
    @Binding var selectedRating: Int
    let onSubmit: () -> Void
    let onNotNow: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Capsule()
                .fill(Color.secondary.opacity(0.35))
                .frame(width: 42, height: 5)
                .padding(.top, 8)

            VStack(spacing: 8) {
                Text("Rate ProdConnect")
                    .font(.title3.weight(.semibold))
                Text("How has ProdConnect been working for you?")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 14) {
                ForEach(1...5, id: \.self) { rating in
                    Button {
                        selectedRating = rating
                    } label: {
                        Image(systemName: rating <= selectedRating ? "star.fill" : "star")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundColor(rating <= selectedRating ? .yellow : .secondary)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(rating) star\(rating == 1 ? "" : "s")")
                }
            }
            .padding(.vertical, 4)

            Text(selectedRating == 0 ? "Select a rating to continue" : "\(selectedRating) out of 5 stars")
                .font(.footnote)
                .foregroundColor(.secondary)

            VStack(spacing: 12) {
                Button(action: onSubmit) {
                    Text("Submit")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedRating == 0)

                Button("Not Now", action: onNotNow)
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }
}

private struct NotificationsListView: View {
    @EnvironmentObject var store: ProdConnectStore

    var body: some View {
        List {
            if store.notificationIncomingChannels.isEmpty
                && store.notificationAssignedTickets.isEmpty
                && store.notificationTicketReminders.isEmpty
                && store.checklistNotificationNotices.isEmpty
                && store.checklistReminderNotices.isEmpty {
                Text("No new notifications")
                    .foregroundColor(.secondary)
            }

            if !store.notificationIncomingChannels.isEmpty {
                Section("Messages") {
                    ForEach(store.notificationIncomingChannels) { channel in
                        NavigationLink {
                            ChatChannelDetailView(channel: channel)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(channel.name.isEmpty ? "Chat" : channel.name)
                                    .font(.headline)
                                if let last = channel.messages.last {
                                    Text(last.text.isEmpty ? "New attachment" : last.text)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                    }
                }
            }

            if !store.notificationAssignedTickets.isEmpty {
                Section("Assigned Tickets") {
                    ForEach(store.notificationAssignedTickets) { ticket in
                        NavigationLink {
                            TicketDetailView(ticket: ticket)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(ticket.title.isEmpty ? "Untitled Ticket" : ticket.title)
                                    .font(.headline)
                                Text(ticket.status.rawValue)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }

            if !store.notificationTicketReminders.isEmpty {
                Section("Ticket Reminders") {
                    ForEach(store.notificationTicketReminders) { notice in
                        NavigationLink {
                            TicketDetailView(ticket: notice.ticket)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(notice.ticket.title.isEmpty ? "Untitled Ticket" : notice.ticket.title)
                                    .font(.headline)
                                Text("\(notice.kind.title) • \(notice.ticket.dueDate?.formatted(date: .abbreviated, time: .shortened) ?? "")")
                                    .font(.caption)
                                    .foregroundColor(notice.kind == .overdue ? .red : .secondary)
                            }
                        }
                    }
                }
            }

            if !store.checklistNotificationNotices.isEmpty {
                Section("Checklist Assignments") {
                    ForEach(store.checklistNotificationNotices) { notice in
                        NavigationLink {
                            ChecklistRunView(template: notice.checklist)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(notice.checklist.title)
                                    .font(.headline)
                                Text(notice.item.text)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
            }

            if !store.checklistReminderNotices.isEmpty {
                Section("Checklist Reminders") {
                    ForEach(store.checklistReminderNotices) { notice in
                        NavigationLink {
                            ChecklistRunView(template: notice.checklist)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(notice.checklist.title)
                                    .font(.headline)
                                Text("\(notice.kind.title) • \(notice.checklist.dueDate?.formatted(date: .abbreviated, time: .shortened) ?? "")")
                                    .font(.caption)
                                    .foregroundColor(notice.kind == .overdue ? .red : .secondary)
                                if let preview = notice.itemPreview, !preview.isEmpty {
                                    Text(preview)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Notifications")
        .onAppear {
            store.markAllNotificationsSeen()
        }
        .onChange(of: store.notificationBadgeCount) { _ in
            store.markAllNotificationsSeen()
        }
    }
}

private struct MoreTabView: View {
    @EnvironmentObject var store: ProdConnectStore
    let sections: [MainAppSection]
    @Binding var pendingSection: MainAppSection?
    @State private var presentedSection: MainAppSection?
    @State private var isPresentingPendingSection = false

    private var notificationRow: some View {
        HStack {
            Label("Notifications", systemImage: MainAppSection.notifications.icon)
            Spacer()
            if store.notificationBadgeCount > 0 {
                Text(store.notificationBadgeCount > 99 ? "99+" : "\(store.notificationBadgeCount)")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.red, in: Capsule())
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if sections.isEmpty {
                    Text("No additional sections")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(sections) { section in
                        NavigationLink {
                            mainAppSectionDestination(section)
                        } label: {
                            if section == .notifications {
                                notificationRow
                            } else {
                                Label(section.title, systemImage: section.icon)
                            }
                        }
                    }
                }
            }
            .navigationTitle("More")
            .navigationDestination(isPresented: $isPresentingPendingSection) {
                if let presentedSection {
                    mainAppSectionDestination(presentedSection)
                }
            }
        }
        .onAppear {
            openPendingSectionIfNeeded()
        }
        .onChange(of: pendingSection?.rawValue) { _ in
            openPendingSectionIfNeeded()
        }
        .onChange(of: isPresentingPendingSection) { isPresenting in
            if !isPresenting {
                presentedSection = nil
            }
        }
    }

    private func openPendingSectionIfNeeded() {
        guard let pendingSection, sections.contains(pendingSection) else { return }
        presentedSection = pendingSection
        isPresentingPendingSection = true
        DispatchQueue.main.async {
            self.pendingSection = nil
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
