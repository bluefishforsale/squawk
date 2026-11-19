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

    @Test func stutteredFunctionWordCollapses() {
        #expect(TextCleanup().apply("I I think the the build passed.") == "I think the build passed.")
    }

    @Test func deliberateRepetitionAndGrammaticalDoublesSurvive() {
        let text = "It was very very good, no no, and he had had enough of that that day."
        #expect(TextCleanup().apply(text) == text)
    }

    @Test func likeIsUntouchedUnlessTheSettingIsOn() {
        let text = "So, like, I went home."
        #expect(TextCleanup().apply(text) == text)
    }

    @Test func fillerLikeBetweenCommasIsRemoved() {
        let cleanup = TextCleanup(rewriteLike: true)
        #expect(cleanup.apply("So, like, I went home.") == "So I went home.")
        #expect(cleanup.apply("It was, like, huge.") == "It was huge.")
    }

    @Test func leadingFillerLikeRecapitalizes() {
        #expect(TextCleanup(rewriteLike: true).apply("Like, the deploy failed.") == "The deploy failed.")
    }

    @Test func quotativeLikeBecomesSaid() {
        let cleanup = TextCleanup(rewriteLike: true)
        #expect(cleanup.apply("She was like, no way.") == "She said, no way.")
        #expect(cleanup.apply("And I'm like, ship it.") == "And I said, ship it.")
        #expect(cleanup.apply("They were all like, sure.") == "They said, sure.")
    }

    @Test func likeBeforeIntensifierIsDroppedAfterToBe() {
        #expect(TextCleanup(rewriteLike: true).apply("It was like really big.") == "It was really big.")
    }

    @Test func meaningfulLikeSurvivesTheRewrite() {
        let text = "I like really spicy food and it looks like rain, just like yesterday."
        #expect(TextCleanup(rewriteLike: true).apply(text) == text)
    }

    @Test func missingSpaceAfterPunctuationIsInserted() {
        #expect(TextCleanup().apply("First,second.Third!fourth") == "First, second. Third! fourth")
    }

    @Test func decimalsDomainsAndAbbreviationsKeepTheirDots() {
        let text = "Version 3.5 at example.com in the U.S. at 12:30."
        #expect(TextCleanup().apply(text) == text)
    }

    @Test func spacingIsLeftAloneWhenTheSettingIsOff() {
        #expect(TextCleanup(spaceAfterPunctuation: false).apply("First,second") == "First,second")
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
