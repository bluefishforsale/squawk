import Testing

@testable import SquawkCore

@Suite struct AppVersionTests {
    @Test func parsesATagWithOrWithoutTheLeadingV() {
        #expect(AppVersion("v1.2.3")?.parts == [1, 2, 3])
        #expect(AppVersion("1.2.3")?.parts == [1, 2, 3])
    }

    @Test func rejectsTagsThatAreNotPlainReleases() {
        #expect(AppVersion("v0.0.0-signing-test") == nil)
        #expect(AppVersion("1.2.beta") == nil)
        #expect(AppVersion("1..2") == nil)
        #expect(AppVersion("") == nil)
        #expect(AppVersion("v") == nil)
    }

    @Test func comparesNumericallyNotAsText() throws {
        let nine = try #require(AppVersion("0.9.0"))
        let ten = try #require(AppVersion("0.10.0"))
        #expect(nine < ten)
    }

    @Test func treatsMissingFieldsAsZero() throws {
        let short = try #require(AppVersion("1.2"))
        let long = try #require(AppVersion("1.2.0"))
        #expect(short == long)
        #expect(try #require(AppVersion("1.2.1")) > short)
    }

    @Test func recognisesALocalBuild() throws {
        #expect(try #require(AppVersion("0.0.0")).isDevelopmentBuild)
        #expect(try !#require(AppVersion("0.1.0")).isDevelopmentBuild)
    }
}
