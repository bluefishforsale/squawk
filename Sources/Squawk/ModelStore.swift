// Where the speech model lives and how a newer one is found. The model is
// versioned separately from the app: a model update installs into its own
// folder, pinned to one Hugging Face revision, and the app switches to it
// without being replaced itself.
//
// A fresh install uses FluidAudio's shared cache, whatever was on the
// repository's main branch that day. Updates go to Squawk's own folder, so
// they never disturb another app that shares FluidAudio's cache.

import CryptoKit
import FluidAudio
import Foundation
import SquawkCore

struct ModelUpdate: Equatable {
    /// The Hugging Face commit the new files come from.
    let revision: String
    let published: Date?
    let bytes: Int
}

enum ModelStore {
    static let repository = "FluidInference/parakeet-tdt-0.6b-v3-coreml"
    private static let revisionKey = "modelRevision"
    private static let checkedKey = "modelCheckedRevision"
    private static let checkedAgainstKey = "modelCheckedAgainst"
    private static let checkedResultKey = "modelCheckedHasUpdate"
    private static let checkedBytesKey = "modelCheckedBytes"
    private static let checkedDateKey = "modelCheckedPublished"

    private static var defaults: UserDefaults { .standard }

    /// The revision an installed update is pinned to, or nil while the model
    /// is still the one first downloaded.
    static var revision: String? {
        get { defaults.string(forKey: revisionKey) }
        set { defaults.set(newValue, forKey: revisionKey) }
    }

    private static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Squawk/Models", isDirectory: true)
    }

    /// FluidAudio wants the model in a folder with the repository's own name,
    /// so each revision gets a parent folder of its own.
    static func directory(forRevision revision: String) -> URL {
        root.appendingPathComponent(revision, isDirectory: true)
            .appendingPathComponent(AsrModels.defaultCacheDirectory(for: .v3).lastPathComponent, isDirectory: true)
    }

    /// The model to load: the installed update if it is intact, otherwise the
    /// shared cache.
    static var active: (directory: URL, revision: String?) {
        if let revision, isRevision(revision) {
            let directory = directory(forRevision: revision)
            if AsrModels.modelsExist(at: directory, version: .v3) { return (directory, revision) }
        }
        return (AsrModels.defaultCacheDirectory(for: .v3), nil)
    }

    /// FluidAudio refuses to load a folder whose recorded revision differs
    /// from the one it has been told to expect, so this must match the folder
    /// about to be loaded or downloaded, every time.
    static func expect(revision: String?) {
        ModelRegistry.revisionOverrides[repository] = revision
    }

    /// Deletes every installed update except `revision`. The shared cache is
    /// left alone: other apps may be using it.
    static func removeUpdates(except revision: String?) {
        let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        for folder in folders where folder.lastPathComponent != revision {
            try? FileManager.default.removeItem(at: folder)
        }
    }

    /// Revisions are 40 hex digits. They become a folder name and part of a
    /// URL, so nothing else is accepted.
    static func isRevision(_ string: String) -> Bool {
        string.utf8.count == 40 && string.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    // MARK: Checking

    private struct Info: Decodable {
        let sha: String
        let lastModified: String?
    }

    /// Returns an update if the repository's current weights differ from the
    /// files on disk. One or two anonymous GETs; nothing local is sent.
    static func check() async throws -> ModelUpdate? {
        let info = try JSONDecoder().decode(Info.self, from: try await get("https://huggingface.co/api/models/\(repository)"))
        guard isRevision(info.sha) else { return nil }
        let current = active
        guard info.sha != current.revision else { return nil }
        let published = info.lastModified.flatMap { ISO8601DateFormatter.fractional.date(from: $0) }

        // Hashing half a gigabyte is only worth doing once per upstream
        // commit; after that the answer is remembered.
        let against = current.revision ?? ""
        if defaults.string(forKey: checkedKey) == info.sha, defaults.string(forKey: checkedAgainstKey) == against {
            guard defaults.bool(forKey: checkedResultKey) else { return nil }
            return ModelUpdate(
                revision: info.sha, published: defaults.object(forKey: checkedDateKey) as? Date,
                bytes: defaults.integer(forKey: checkedBytesKey))
        }

        let listing = try await get(
            "https://huggingface.co/api/models/\(repository)/tree/\(info.sha)?recursive=true&limit=1000")
        let remote = try ModelManifest.parse(tree: listing)
        let comparison = try compare(directory: current.directory, with: remote)

        defaults.set(info.sha, forKey: checkedKey)
        defaults.set(against, forKey: checkedAgainstKey)
        defaults.set(comparison.differs, forKey: checkedResultKey)
        defaults.set(comparison.bytes, forKey: checkedBytesKey)
        defaults.set(published, forKey: checkedDateKey)
        return comparison.differs ? ModelUpdate(revision: info.sha, published: published, bytes: comparison.bytes) : nil
    }

    private static func get(_ address: String) async throws -> Data {
        guard let url = URL(string: address) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        // A listing that continues on another page cannot be compared safely.
        if http.value(forHTTPHeaderField: "Link")?.contains("rel=\"next\"") == true {
            throw URLError(.dataLengthExceedsMaximum)
        }
        return data
    }

    /// Compares only the files this app has on disk. Files that exist
    /// upstream but not here are variants Squawk does not load.
    static func compare(
        directory: URL, with remote: [String: RemoteModelFile]
    ) throws -> (differs: Bool, bytes: Int) {
        let root = directory.resolvingSymlinksInPath()
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey])
        else { return (false, 0) }
        var differs = false
        var bytes = 0
        for case let file as URL in enumerator {
            let file = file.resolvingSymlinksInPath()
            let name = file.lastPathComponent
            guard try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true,
                !name.hasPrefix("."), !name.hasSuffix(".partial"), !name.hasSuffix(".etag")
            else { continue }
            let path = String(file.path.dropFirst(root.path.count + 1))
            guard let expected = remote[path] else { continue }
            bytes += expected.size
            if !differs, try !matches(file, expected) { differs = true }
        }
        return (differs, bytes)
    }

    private static func matches(_ file: URL, _ expected: RemoteModelFile) throws -> Bool {
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? -1
        guard size == expected.size else { return false }
        switch expected.digest {
        case .sha256(let digest):
            return try hash(file, with: SHA256()) == digest
        case .gitBlobSHA1(let digest):
            var hasher = Insecure.SHA1()
            hasher.update(data: Data("blob \(size)\0".utf8))
            return try hash(file, with: hasher) == digest
        }
    }

    private static func hash<Hasher: HashFunction>(_ file: URL, with initial: Hasher) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = initial
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

extension ISO8601DateFormatter {
    fileprivate static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
