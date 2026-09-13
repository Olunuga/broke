//
//  ProfileTransferTests.swift
//  BrokeTests
//

import XCTest
@testable import Broke

final class ProfileTransferTests: BrokeTestCase {
    func testRoundTripKeepsEveryPortableField() throws {
        let schedule = Fixture.schedule(name: "Evenings", mode: .allow, weekdays: [2, 4], budgetMinutes: 30)
        let profile = Fixture.profile(name: "Focus", schedules: [schedule], restrictWebToAllowlist: true, icon: "book")

        let url = try ProfileTransfer(exporting: [profile]).writeToTemporaryFile(named: "Focus")
        let read = try ProfileTransfer.read(from: url)

        XCTAssertEqual(read.version, ProfileTransfer.currentVersion)
        XCTAssertEqual(read.profiles.count, 1)
        XCTAssertEqual(read.profiles[0].name, "Focus")
        XCTAssertEqual(read.profiles[0].icon, "book")
        XCTAssertTrue(read.profiles[0].restrictWebToAllowlist)
        XCTAssertEqual(read.profiles[0].schedules, [schedule])
    }

    func testFileWrittenByThisInstallCarriesUsableSelections() throws {
        let url = try ProfileTransfer(exporting: [Fixture.profile()]).writeToTemporaryFile(named: "Work")
        XCTAssertTrue(try ProfileTransfer.read(from: url).carriesUsableSelections)
    }

    func testFileFromAnotherInstallDoesNotCarryUsableSelections() throws {
        let url = try foreignTransfer(profiles: [transferable(name: "Work")]).writeToTemporaryFile(named: "Work")
        XCTAssertFalse(try ProfileTransfer.read(from: url).carriesUsableSelections)
    }

    func testExportUsesTheBrokeProfileExtension() throws {
        let url = try ProfileTransfer(exporting: [Fixture.profile()]).writeToTemporaryFile(named: "Work")
        XCTAssertEqual(url.pathExtension, ProfileTransfer.fileExtension)
    }

    func testFileNameDropsPathSeparators() throws {
        let url = try ProfileTransfer(exporting: [Fixture.profile()]).writeToTemporaryFile(named: "Work / Home")
        XCTAssertFalse(url.deletingPathExtension().lastPathComponent.contains("/"))
    }

    func testEmptyFileNameFallsBackToADefault() throws {
        let url = try ProfileTransfer(exporting: [Fixture.profile()]).writeToTemporaryFile(named: "   ")
        XCTAssertEqual(url.deletingPathExtension().lastPathComponent, "Broke Profiles")
    }

    // MARK: - Rejected files

    func testTextThatIsNotJsonIsRejected() throws {
        let url = try write(Data("not a profile".utf8))
        XCTAssertThrowsError(try ProfileTransfer.read(from: url)) { error in
            XCTAssertEqual(error as? ProfileTransferError, .unreadable)
        }
    }

    func testJsonOfTheWrongShapeIsRejected() throws {
        let url = try write(Data(#"{"something": 1}"#.utf8))
        XCTAssertThrowsError(try ProfileTransfer.read(from: url)) { error in
            XCTAssertEqual(error as? ProfileTransferError, .unreadable)
        }
    }

    func testFileFromANewerVersionIsRejected() throws {
        var transfer = foreignTransfer(profiles: [transferable(name: "Work")])
        transfer.version = ProfileTransfer.currentVersion + 1
        let url = try transfer.writeToTemporaryFile(named: "Work")

        XCTAssertThrowsError(try ProfileTransfer.read(from: url)) { error in
            XCTAssertEqual(error as? ProfileTransferError, .newerVersion)
        }
    }

    func testFileWithNoProfilesIsRejected() throws {
        let url = try ProfileTransfer(exporting: []).writeToTemporaryFile(named: "Empty")
        XCTAssertThrowsError(try ProfileTransfer.read(from: url)) { error in
            XCTAssertEqual(error as? ProfileTransferError, .empty)
        }
    }

    // MARK: - Helpers

    private func transferable(name: String, schedules: [Schedule] = []) -> TransferableProfile {
        TransferableProfile(
            name: name,
            icon: "bell.slash",
            restrictWebToAllowlist: false,
            schedules: schedules,
            appTokens: [],
            categoryTokens: [],
            webDomainTokens: []
        )
    }

    private func foreignTransfer(profiles: [TransferableProfile]) -> ProfileTransfer {
        ProfileTransfer(
            version: ProfileTransfer.currentVersion,
            installIdentifier: UUID(),
            exportedAt: Date(),
            profiles: profiles
        )
    }

    private func write(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ProfileTransfer.fileExtension)
        try data.write(to: url)
        return url
    }
}

extension ProfileTransferError: Equatable {
    public static func == (lhs: ProfileTransferError, rhs: ProfileTransferError) -> Bool {
        String(describing: lhs) == String(describing: rhs)
    }
}
