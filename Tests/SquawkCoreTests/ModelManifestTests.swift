import Foundation
import Testing

@testable import SquawkCore

@Suite struct ModelManifestTests {
    private let tree = Data(
        """
        [
          {"type":"directory","oid":"aaa","size":0,"path":"Encoder.mlmodelc"},
          {"type":"file","oid":"AECDE9A8C4FF70C5B5D227A079650FCF5033CAEE","size":2921,"path":"Encoder.mlmodelc/metadata.json"},
          {"type":"file","oid":"1111111111111111111111111111111111111111","size":134,
           "lfs":{"oid":"e2020f323703477a5b21d7c2d282c403e371afb5962e79877e3033e73ba6f421","size":445187200,"pointerSize":134},
           "path":"Encoder.mlmodelc/weights/weight.bin"}
        ]
        """.utf8)

    @Test func keepsFilesAndDropsDirectories() throws {
        let files = try ModelManifest.parse(tree: tree)
        #expect(files.keys.sorted() == ["Encoder.mlmodelc/metadata.json", "Encoder.mlmodelc/weights/weight.bin"])
    }

    @Test func smallFilesCarryTheirGitBlobIdInLowercase() throws {
        let file = try #require(ModelManifest.parse(tree: tree)["Encoder.mlmodelc/metadata.json"])
        #expect(file.size == 2921)
        #expect(file.digest == .gitBlobSHA1("aecde9a8c4ff70c5b5d227a079650fcf5033caee"))
    }

    @Test func largeFilesUseTheRealSizeAndHashNotThePointerFile() throws {
        let file = try #require(ModelManifest.parse(tree: tree)["Encoder.mlmodelc/weights/weight.bin"])
        #expect(file.size == 445_187_200)
        #expect(file.digest == .sha256("e2020f323703477a5b21d7c2d282c403e371afb5962e79877e3033e73ba6f421"))
    }

    @Test func rejectsAListingThatIsNotAnArray() {
        #expect(throws: (any Error).self) {
            try ModelManifest.parse(tree: Data(#"{"error":"Repository not found"}"#.utf8))
        }
    }
}
