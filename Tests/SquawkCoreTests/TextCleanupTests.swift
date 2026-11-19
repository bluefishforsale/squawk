import Testing

@testable import SquawkCore

@Suite struct TextCleanupTests {
    @Test func fillerMidSentenceIsRemovedWithItsComma() {
        #expect(TextCleanup().apply("I think, um, we should ship.") == "I think, we should ship.")
    }

    @Test func leadingFillerRecapitalizesTheSentence() {
        #expect(TextCleanup().apply("Uh, the build is red.") == "The build is red.")
    }

    @Test func fillerAfterFullStopRecapitalizesNextSentence() {
        #expect(TextCleanup().apply("It works. Um, mostly.") == "It works. Mostly.")
    }

    @Test func fillerBeforeFullStopLeavesNoDanglingComma() {
        #expect(TextCleanup().apply("That is fine, uh.") == "That is fine.")
    }

    @Test func wordsContainingFillerLettersSurvive() {
        let text = "The umbrella and the hummus are uhuru."
        #expect(TextCleanup().apply(text) == text)
    }

    @Test func fillersKeptWhenDisabled() {
        #expect(TextCleanup(removeFillers: false).apply("Um, hello.") == "Um, hello.")
    }

    @Test func replacementMatchesWholeWordsIgnoringCase() {
        let cleanup = TextCleanup(replacements: [Replacement(spoken: "cube control", written: "kubectl")])
        #expect(cleanup.apply("Run Cube Control apply.") == "Run kubectl apply.")
    }

    @Test func replacementDoesNotFireInsideLongerWord() {
        let cleanup = TextCleanup(replacements: [Replacement(spoken: "cat", written: "dog")])
        #expect(cleanup.apply("Concatenate the cat.") == "Concatenate the dog.")
    }

    @Test func replacementTextWithDollarSignIsLiteral() {
        let cleanup = TextCleanup(replacements: [Replacement(spoken: "home dir", written: "$HOME")])
        #expect(cleanup.apply("cd to home dir") == "cd to $HOME")
    }

    @Test func parseSkipsLinesWithoutArrow() {
        let rules = Replacement.parse("cube control => kubectl\nhalf typed\n => orphan\nterrac=>Terrac")
        #expect(
            rules == [
                Replacement(spoken: "cube control", written: "kubectl"),
                Replacement(spoken: "terrac", written: "Terrac"),
            ])
    }
}
