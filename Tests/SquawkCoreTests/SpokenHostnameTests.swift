import Testing

@testable import SquawkCore

@Suite struct SpokenHostnameTests {
    @Test func halfJoinedHostnameFromDictationIsFinished() {
        #expect(SpokenHostname.joining("terrac.com home.terrac dot com.") == "terrac.com home.terrac.com.")
    }

    @Test func fullySpokenHostnameIsJoinedAndLowercased() {
        #expect(SpokenHostname.joining("Go to Home dot Terrac dot com now") == "Go to home.terrac.com now")
    }

    @Test func fleetHostnameEndingInHomeIsJoined() {
        #expect(SpokenHostname.joining("ssh to ocean dot home") == "ssh to ocean.home")
    }

    @Test func dotInProseIsLeftAlone() {
        let text = "Connect the dot to the line, then dot the i."
        #expect(SpokenHostname.joining(text) == text)
    }

    @Test func emailAndPathAreNotJoinedFromTheMiddle() {
        let text = "Mail me@home dot com or open a/b dot com"
        #expect(SpokenHostname.joining(text) == text)
    }
}
