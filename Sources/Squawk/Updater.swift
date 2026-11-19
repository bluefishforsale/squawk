// Finds newer releases on GitHub and installs them in place. Nothing about the
// user or the machine is sent: the check is one anonymous GET of the public
// releases feed. An update is only installed if it is signed by the same
// Developer ID team as the app that is running, so a tampered download, or a
// release from anyone else, is refused.

import AppKit
import Foundation
import Security
import SquawkCore

struct AvailableUpdate: Equatable {
    let version: AppVersion
    let dmg: URL
    let page: URL
}

enum UpdateError: LocalizedError {
    case notSigned
    case mount(String)
    case wrongSignature
    case notNewer

    var errorDescription: String? {
        switch self {
        case .notSigned: "This build is not signed with a Developer ID, so it cannot update itself."
        case .mount(let detail): "Could not open the download: \(detail)"
        case .wrongSignature: "The download is not signed by Squawk's developer. Nothing was installed."
        case .notNewer: "The download is not newer than this version."
        }
    }
}

enum Updater {
    static let releasesPage = URL(string: "https://github.com/bluefishforsale/squawk/releases")!
    private static let latest = URL(string: "https://api.github.com/repos/bluefishforsale/squawk/releases/latest")!
    private static let bundleIdentifier = "com.bluefishforsale.squawk"

    static var currentVersion: AppVersion? {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String).flatMap(AppVersion.init)
    }

    private struct Release: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: URL
        }
        let tag_name: String
        let html_url: URL
        let assets: [Asset]
    }

    /// Returns the newest published release if it is newer than this app.
    /// GitHub's "latest" already leaves out drafts and pre-releases.
    static func check() async throws -> AvailableUpdate? {
        guard let current = currentVersion, !current.isDevelopmentBuild else { return nil }
        var request = URLRequest(url: latest)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        // 404 means no release has been published yet.
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let release = try JSONDecoder().decode(Release.self, from: data)
        guard let version = AppVersion(release.tag_name), version > current,
            let asset = release.assets.first(where: { $0.name.hasSuffix(".dmg") }),
            isFromThisRepository(asset.browser_download_url)
        else { return nil }
        return AvailableUpdate(version: version, dmg: asset.browser_download_url, page: release.html_url)
    }

    private static func isFromThisRepository(_ url: URL) -> Bool {
        url.scheme == "https" && url.host == "github.com" && url.path.hasPrefix("/bluefishforsale/squawk/")
    }

    /// Downloads the update, checks its signature, swaps it in for the running
    /// app and relaunches. Throws without having changed anything on disk.
    static func install(_ update: AvailableUpdate) async throws {
        // Relaunching ends the process, so the disk image has to be unmounted
        // and the download removed before it starts, not in a defer racing it.
        let installed = try await replaceInstalledApp(with: update)
        relaunch(installed)
    }

    private static func replaceInstalledApp(with update: AvailableUpdate) async throws -> URL {
        guard let team = ownTeamIdentifier() else { throw UpdateError.notSigned }

        let work = FileManager.default.temporaryDirectory.appendingPathComponent("squawk-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }

        let (downloaded, _) = try await URLSession.shared.download(from: update.dmg)
        let dmg = work.appendingPathComponent("Squawk.dmg")
        try FileManager.default.moveItem(at: downloaded, to: dmg)

        let mount = work.appendingPathComponent("mount")
        try run("/usr/bin/hdiutil", "attach", "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path, dmg.path)
        defer { _ = try? run("/usr/bin/hdiutil", "detach", "-force", mount.path) }

        let source = mount.appendingPathComponent("Squawk.app")
        try verify(source, team: team)
        let version = (Bundle(url: source)?.infoDictionary?["CFBundleShortVersionString"] as? String).flatMap(AppVersion.init)
        guard let version, let current = currentVersion, version > current else { throw UpdateError.notNewer }

        // Copy next to the installed app first, then swap in one step, so a
        // failure part way through never leaves half an app behind.
        let installed = Bundle.main.bundleURL
        let staging = try FileManager.default.url(
            for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: installed, create: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        let staged = staging.appendingPathComponent("Squawk.app")
        try FileManager.default.copyItem(at: source, to: staged)
        _ = try FileManager.default.replaceItemAt(installed, withItemAt: staged)
        return installed
    }

    /// The team that signed the running app, or nil for an ad-hoc build.
    private static func ownTeamIdentifier() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var info: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(staticCode, flags, &info) == errSecSuccess else { return nil }
        return (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String
    }

    private static func verify(_ app: URL, team: String) throws {
        // Team identifiers are ten letters and digits; anything else must not
        // reach the requirement string.
        guard team.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { throw UpdateError.wrongSignature }
        let text =
            "anchor apple generic and identifier \"\(bundleIdentifier)\" and certificate leaf[subject.OU] = \"\(team)\""
        var requirement: SecRequirement?
        var code: SecStaticCode?
        guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess,
            SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess,
            let requirement, let code
        else { throw UpdateError.wrongSignature }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)
        guard SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess else {
            throw UpdateError.wrongSignature
        }
    }

    private static func relaunch(_ app: URL) {
        // The shell outlives this process, waits for it to exit, then opens
        // the new copy. The path is passed as an argument, never interpolated.
        let script = "while /bin/kill -0 \"$1\" 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open \"$2\""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, "sh", String(ProcessInfo.processInfo.processIdentifier), app.path]
        try? process.run()
        DispatchQueue.main.async {
            // NSApp is nil when run from the command line.
            if let app = NSApp { app.terminate(nil) } else { exit(0) }
        }
    }

    @discardableResult
    private static func run(_ tool: String, _ arguments: String...) throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UpdateError.mount(output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return output
    }
}
