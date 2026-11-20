// Reads Hugging Face's file listing for a model repository, so the app can
// tell whether the weights published there differ from the ones on disk.
// Comparing content, not commit ids, matters: most commits to a model
// repository edit the README or add a variant this app does not load, and
// none of those should be offered to the user as a new model.

import Foundation

public struct RemoteModelFile: Equatable {
    public enum Digest: Equatable {
        /// Large files: the SHA-256 of the content, from Git LFS.
        case sha256(String)
        /// Small files: Git's blob id, SHA-1 over "blob <size>\0" + content.
        case gitBlobSHA1(String)
    }

    public let path: String
    public let size: Int
    public let digest: Digest

    public init(path: String, size: Int, digest: Digest) {
        self.path = path
        self.size = size
        self.digest = digest
    }
}

public enum ModelManifest {
    private struct Entry: Decodable {
        struct LFS: Decodable {
            let oid: String
            let size: Int
        }
        let type: String
        let path: String
        let size: Int?
        let oid: String?
        let lfs: LFS?
    }

    /// Parses the JSON from `/api/models/<repo>/tree/<revision>?recursive=true`
    /// into files keyed by path. Directories are dropped.
    public static func parse(tree: Data) throws -> [String: RemoteModelFile] {
        let entries = try JSONDecoder().decode([Entry].self, from: tree)
        var files: [String: RemoteModelFile] = [:]
        for entry in entries where entry.type == "file" {
            if let lfs = entry.lfs {
                files[entry.path] = RemoteModelFile(path: entry.path, size: lfs.size, digest: .sha256(lfs.oid.lowercased()))
            } else if let oid = entry.oid, let size = entry.size {
                files[entry.path] = RemoteModelFile(path: entry.path, size: size, digest: .gitBlobSHA1(oid.lowercased()))
            }
        }
        return files
    }
}
