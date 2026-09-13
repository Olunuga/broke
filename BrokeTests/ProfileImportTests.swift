//
//  ProfileImportTests.swift
//  BrokeTests
//

import XCTest
@testable import Broke

final class ProfileImportTests: BrokeTestCase {
    func testImportAssignsFreshProfileAndScheduleIds() throws {
        let schedule = Fixture.schedule(name: "Evenings")
        let source = Fixture.profile(name: "Focus", schedules: [schedule])
        let manager = ProfileManager()

        manager.importProfiles(from: ProfileTransfer(exporting: [source]))

        let imported = try XCTUnwrap(manager.profiles.first { $0.name == "Focus" })
        XCTAssertNotEqual(imported.id, source.id)
        XCTAssertEqual(imported.schedules.count, 1)
        XCTAssertNotEqual(imported.schedules[0].id, schedule.id)
        XCTAssertEqual(imported.schedules[0].name, "Evenings")
    }

    func testImportLeavesTheCurrentProfileAlone() {
        let manager = ProfileManager()
        let before = manager.currentProfileId

        manager.importProfiles(from: ProfileTransfer(exporting: [Fixture.profile(name: "Focus")]))

        XCTAssertEqual(manager.currentProfileId, before)
    }

    func testImportAppendsRatherThanReplaces() {
        let manager = ProfileManager()
        let before = manager.profiles.count

        manager.importProfiles(from: ProfileTransfer(exporting: [Fixture.profile(name: "Focus")]))

        XCTAssertEqual(manager.profiles.count, before + 1)
    }

    func testRepeatedImportNumbersTheDuplicateNames() {
        let manager = ProfileManager()
        let transfer = ProfileTransfer(exporting: [Fixture.profile(name: "Focus")])

        let first = manager.importProfiles(from: transfer)
        let second = manager.importProfiles(from: transfer)
        let third = manager.importProfiles(from: transfer)

        XCTAssertEqual(first.importedNames, ["Focus"])
        XCTAssertEqual(second.importedNames, ["Focus 2"])
        XCTAssertEqual(third.importedNames, ["Focus 3"])
    }

    func testProfileWithNoNameGetsAPlaceholder() {
        let manager = ProfileManager()
        let result = manager.importProfiles(from: ProfileTransfer(exporting: [Fixture.profile(name: "")]))

        XCTAssertEqual(result.importedNames, ["Imported Profile"])
    }

    func testImportFromThisInstallKeepsSelectionsAndScheduleState() throws {
        let source = Fixture.profile(name: "Focus", schedules: [Fixture.schedule(isEnabled: true)])
        let manager = ProfileManager()

        let result = manager.importProfiles(from: ProfileTransfer(exporting: [source]))

        XCTAssertTrue(result.keptSelections)
        let imported = try XCTUnwrap(manager.profiles.first { $0.name == "Focus" })
        XCTAssertTrue(imported.schedules[0].isEnabled)
    }

    func testImportFromAnotherInstallDisablesEverySchedule() throws {
        let manager = ProfileManager()
        let transfer = ProfileTransfer(
            version: ProfileTransfer.currentVersion,
            installIdentifier: UUID(),
            exportedAt: Date(),
            profiles: [
                TransferableProfile(
                    name: "Focus",
                    icon: "book",
                    restrictWebToAllowlist: true,
                    schedules: [Fixture.schedule(isEnabled: true), Fixture.schedule(name: "Second", isEnabled: true)],
                    appTokens: [],
                    categoryTokens: [],
                    webDomainTokens: []
                )
            ]
        )

        let result = manager.importProfiles(from: transfer)

        XCTAssertFalse(result.keptSelections)
        let imported = try XCTUnwrap(manager.profiles.first { $0.name == "Focus" })
        XCTAssertEqual(imported.schedules.count, 2)
        XCTAssertTrue(imported.schedules.allSatisfy { !$0.isEnabled })
        XCTAssertTrue(imported.restrictWebToAllowlist)
        XCTAssertEqual(imported.icon, "book")
    }

    func testImportSurvivesAReload() {
        let manager = ProfileManager()
        manager.importProfiles(from: ProfileTransfer(exporting: [Fixture.profile(name: "Focus")]))

        XCTAssertTrue(SharedStore.loadProfiles().contains { $0.name == "Focus" })
    }

    // MARK: - Result message

    func testMessageNamesTheImportedProfiles() {
        let result = ProfileImportResult(importedNames: ["Focus", "Sleep"], keptSelections: true)
        XCTAssertEqual(result.message, "Imported Focus, Sleep.")
    }

    func testMessageExplainsWhatWasDroppedWhenSelectionsDoNotTransfer() {
        let result = ProfileImportResult(importedNames: ["Focus"], keptSelections: false)
        XCTAssertTrue(result.message.hasPrefix("Imported Focus."))
        XCTAssertTrue(result.message.contains("choose its apps"))
    }
}
