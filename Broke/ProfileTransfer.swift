//
//  ProfileTransfer.swift
//  Broke
//
//  The on-disk format profiles are exported to and imported from.
//

import Foundation
import ManagedSettings
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let brokeProfile = UTType(exportedAs: "com.Brokeest.ios.profile")
}

/// A profile without its `id`, because an import always mints a new one.
struct TransferableProfile: Codable {
    var name: String
    var icon: String
    var restrictWebToAllowlist: Bool
    var schedules: [Schedule]
    var appTokens: Set<ApplicationToken>
    var categoryTokens: Set<ActivityCategoryToken>
    var webDomainTokens: Set<WebDomainToken>
}

struct ProfileTransfer: Codable {
    static let currentVersion = 1
    static let fileExtension = "brokeprofile"

    var version: Int
    var installIdentifier: UUID
    var exportedAt: Date
    var profiles: [TransferableProfile]
}

extension ProfileTransfer {
    init(exporting profiles: [Profile]) {
        version = Self.currentVersion
        installIdentifier = SharedStore.installIdentifier
        exportedAt = Date()
        self.profiles = profiles.map { profile in
            TransferableProfile(
                name: profile.name,
                icon: profile.icon,
                restrictWebToAllowlist: profile.restrictWebToAllowlist,
                schedules: profile.schedules,
                appTokens: profile.appTokens,
                categoryTokens: profile.categoryTokens,
                webDomainTokens: profile.webDomainTokens
            )
        }
    }

    /// The system issues app, category, and website tokens per install, so a file's selections mean nothing anywhere else.
    var carriesUsableSelections: Bool {
        installIdentifier == SharedStore.installIdentifier
    }

    func writeToTemporaryFile(named name: String) throws -> URL {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(ProfileTransfer.safeFileName(name))
            .appendingPathExtension(ProfileTransfer.fileExtension)
        try encoder.encode(self).write(to: url, options: .atomic)
        return url
    }

    static func read(from url: URL) throws -> ProfileTransfer {
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let transfer: ProfileTransfer
        do {
            transfer = try decoder.decode(ProfileTransfer.self, from: Data(contentsOf: url))
        } catch {
            throw ProfileTransferError.unreadable
        }

        guard transfer.version <= currentVersion else { throw ProfileTransferError.newerVersion }
        guard !transfer.profiles.isEmpty else { throw ProfileTransferError.empty }
        return transfer
    }

    private static func safeFileName(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(.whitespaces)
        let cleaned = name.components(separatedBy: allowed.inverted).joined()
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "Broke Profiles" : cleaned
    }
}

enum ProfileTransferError: LocalizedError {
    case unreadable
    case newerVersion
    case empty

    var errorDescription: String? {
        switch self {
        case .unreadable: return "That file is not a Broke profile export."
        case .newerVersion: return "That file comes from a newer version of Broke."
        case .empty: return "That file holds no profiles."
        }
    }
}

struct ProfileImportResult {
    let importedNames: [String]
    let keptSelections: Bool

    var message: String {
        let names = importedNames.joined(separator: ", ")
        if keptSelections {
            return "Imported \(names)."
        }
        return "Imported \(names). App, category, and website selections stay on the device that wrote the file, so the imported schedules are off. Open each profile, choose its apps, then turn the schedules back on."
    }
}

/// A file waiting to be shared. `URL` is not `Identifiable`, and `.sheet(item:)` needs that.
struct ProfileExportFile: Identifiable {
    let id = UUID()
    let url: URL
}

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

#if DEBUG
import FamilyControls

/// Exercises export, import, and app selection without a tag scan. Debug builds only.
struct ProfileTransferDebugView: View {
    @ObservedObject var profileManager: ProfileManager
    let onDismiss: () -> Void

    @State private var showImporter = false
    @State private var exportFile: ProfileExportFile?
    @State private var selectingProfileId: UUID?
    @State private var activitySelection = FamilyActivitySelection()
    @State private var message: String?

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Transfer")) {
                    Button("Export All Profiles") { export(profileManager.profiles, named: "Broke Profiles") }
                        .disabled(profileManager.profiles.isEmpty)
                    Button("Import From File") { showImporter = true }
                }

                Section(header: Text("Profiles")) {
                    ForEach(profileManager.profiles) { profile in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(profile.name).fontWeight(.semibold)
                            Text("apps \(profile.appTokens.count) · categories \(profile.categoryTokens.count) · web \(profile.webDomainTokens.count) · schedules \(profile.schedules.count)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            HStack(spacing: 16) {
                                Button("Select Apps") { beginSelection(for: profile) }
                                Button("Export") { export([profile], named: profile.name) }
                            }
                            .buttonStyle(.borderless)
                            .font(.callout)
                        }
                        .padding(.vertical, 2)
                    }
                }

                Section(header: Text("Install")) {
                    Text(SharedStore.installIdentifier.uuidString)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Profile Transfer")
            .navigationBarItems(trailing: Button("Done", action: onDismiss))
            .sheet(item: $exportFile) { file in
                ShareSheet(url: file.url)
            }
            .sheet(isPresented: Binding(get: { selectingProfileId != nil }, set: { if !$0 { selectingProfileId = nil } })) {
                NavigationView {
                    FamilyActivityPicker(selection: $activitySelection)
                        .navigationTitle("Select Apps")
                        .navigationBarItems(trailing: Button("Done", action: commitSelection))
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.brokeProfile]) { result in
                handleImport(result)
            }
            .alert(
                "Profile Transfer",
                isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(message ?? "")
            }
        }
    }

    private func export(_ profiles: [Profile], named name: String) {
        do {
            let transfer = ProfileTransfer(exporting: profiles)
            exportFile = ProfileExportFile(url: try transfer.writeToTemporaryFile(named: name))
        } catch {
            message = error.localizedDescription
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        do {
            let transfer = try ProfileTransfer.read(from: try result.get())
            message = profileManager.importProfiles(from: transfer).message
        } catch {
            message = error.localizedDescription
        }
    }

    private func beginSelection(for profile: Profile) {
        var selection = FamilyActivitySelection()
        selection.applicationTokens = profile.appTokens
        selection.categoryTokens = profile.categoryTokens
        selection.webDomainTokens = profile.webDomainTokens
        activitySelection = selection
        selectingProfileId = profile.id
    }

    private func commitSelection() {
        if let id = selectingProfileId {
            profileManager.updateProfile(
                id: id,
                appTokens: activitySelection.applicationTokens,
                categoryTokens: activitySelection.categoryTokens,
                webDomainTokens: activitySelection.webDomainTokens
            )
            ScheduleManager.sync(profiles: profileManager.profiles)
        }
        selectingProfileId = nil
    }
}
#endif
