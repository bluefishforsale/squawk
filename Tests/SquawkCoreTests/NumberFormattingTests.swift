import Testing

@testable import SquawkCore

@Suite struct NumberFormattingTests {
    private func format(_ text: String) -> String {
        TextCleanup(endWithPeriod: false).apply(text)
    }

    @Test func mixedDictationFromTheFirstComplaint() {
        #expect(
            format("2020 eleven forty eight nine seven seven six but you should")
                == "2020 1148 9776 but you should")
        #expect(
            format("eighteen forty eight, eleven twenty-six. Two thousand twenty nine. One hundred thousand five hundred thirty-eight.")
                == "1848, 1126. 2029. 100,538.")
    }

    @Test func loneDigitIsSpelledOut() {
        #expect(format("I have 3 cats and 0 dogs") == "I have three cats and zero dogs")
    }

    @Test func spelledOutDigitAtSentenceStartIsCapitalized() {
        #expect(format("It broke. 3 builds failed") == "It broke. Three builds failed")
    }

    @Test func digitsInsideDecimalsTimesVersionsAndUnitsSurvive() {
        let text = "Version 3.5 at 12:30 on v2 for 5% off, $5, 1,000 and 2nd place"
        #expect(format(text) == text)
    }

    @Test func tenAndUpBecomeDigits() {
        #expect(format("ten people and twenty-one cats in ninety days") == "10 people and 21 cats in 90 days")
    }

    @Test func unitWordsStayWords() {
        let text = "The one I want is one or two of the five, and oh well, a lot"
        #expect(format(text) == text)
    }

    @Test func hyphenatedCompoundKeepsItsTail() {
        #expect(format("a twenty-one-year-old and a five-year-old") == "a 21-year-old and a five-year-old")
    }

    @Test func yearSaidWithOh() {
        #expect(format("built in nineteen oh five") == "built in 1905")
    }

    @Test func roundNumbersWithAAndAnd() {
        #expect(format("a hundred and five of a thousand") == "105 of 1000")
    }

    @Test func spokenDigitRunIsACode() {
        #expect(format("the PIN is four four one two") == "the PIN is 4412")
    }

    @Test func spokenPhoneNumberIsHyphenated() {
        #expect(format("call five four one two two six three eight four three") == "call 541-226-3843")
        #expect(format("or two two six three eight four three") == "or 226-3843")
    }

    @Test func writtenPhoneNumberIsHyphenated() {
        #expect(format("call 541 226 3843 or (541) 226.3843 or 5412263843") == "call 541-226-3843 or 541-226-3843 or 541-226-3843")
        #expect(format("dial 1 541 226 3843") == "dial 1-541-226-3843")
    }

    @Test func largeRoundNumberIsNotMistakenForAPhoneNumber() {
        #expect(format("two billion") == "2,000,000,000")
        #expect(format("id 1234567890") == "id 1234567890")
    }

    @Test func dateWithCompoundOrdinalFromTheFailedDictation() {
        #expect(format("like January 20 eighth is when") == "like January 28th is when")
        #expect(format("January twenty-eighth twenty twenty six") == "January 28th 2026")
    }

    @Test func teenAndTensOrdinalsBecomeDigitsWithTheRightSuffix() {
        #expect(format("the eleventh, twelfth, thirteenth and twentieth") == "the 11th, 12th, 13th and 20th")
        #expect(format("thirty first, forty second and fifty third") == "31st, 42nd and 53rd")
    }

    @Test func ordinalsUnderTenStayWords() {
        let text = "The first time, the second try and the ninth day"
        #expect(format(text) == text)
    }

    @Test func fractionsKeepTheirWords() {
        let text = "a tenth of it and one twentieth of that"
        #expect(format(text) == text)
    }

    @Test func numbersUntouchedWhenTheSettingIsOff() {
        let text = "I have 3 cats and twenty dogs"
        #expect(TextCleanup(endWithPeriod: false, formatNumbers: false).apply(text) == text)
    }
}
