// Numbers in a transcript follow one house style: zero to nine as words, ten
// and up as digits, and a phone number hyphenated. The recognizer mixes both
// forms in one sentence ("2020 eleven forty eight"), so the rule has to run
// in both directions.

import Foundation

enum NumberFormatting {
    static func apply(_ transcript: String) -> String {
        // Phone numbers twice: first so the "1" in "1 541 226 3843" is not
        // spelled out, then again for the ones that were read out as words.
        let written = ordinalsToDigits(hyphenatingPhoneNumbers(in: transcript))
        return hyphenatingPhoneNumbers(in: wordsToDigits(digitsToWords(written)))
    }

    // MARK: Ordinals

    private static let unitOrdinals = ["first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth"]
    private static let teenOrdinals = [
        "tenth", "eleventh", "twelfth", "thirteenth", "fourteenth", "fifteenth", "sixteenth", "seventeenth",
        "eighteenth", "nineteenth",
    ]
    private static let tensOrdinals = [
        "twentieth", "thirtieth", "fortieth", "fiftieth", "sixtieth", "seventieth", "eightieth", "ninetieth",
    ]

    /// "twenty eighth" and "20 eighth" (the recognizer writes both), a teen or
    /// tens ordinal or "hundredth" on its own, and any of those or "first" to
    /// "ninth" after a number that ends in "hundred" or a scale word ("one
    /// hundred twenty first", "a hundred and first"). "first" to "ninth"
    /// alone stay words, like the cardinals under ten.
    /// NOTE: after "a" or "one" an ordinal is a fraction ("a tenth of", "one
    /// twenty fifth") or a duration ("a thirty second clip"), so it is left
    /// alone, compounds included. Without the "a" the words cannot tell "thirty
    /// second delay" from "forty second street", and both become ordinals.
    private static let ordinal: NSRegularExpression = {
        let tens: String = tensNames.joined(separator: "|")
        let units: String = unitOrdinals.joined(separator: "|")
        let lone: String = (teenOrdinals + tensOrdinals + ["hundredth"]).joined(separator: "|")
        let cardinalWord: String = (unitNames + teenNames + tensNames).joined(separator: "|")
        let multiplier: String = (["hundred"] + scales.keys.sorted()).joined(separator: "|")
        let lead: String = "(?<lead>(?:a[\\s-]+)?(?:(?:" + cardinalWord + "|" + multiplier + ")[\\s-]+)*?(?:"
            + multiplier + "))(?:\\s+and)?[\\s-]+"
        let compound: String = "(?<![$£€#])(?:(?<tens>" + tens + ")|(?<tensDigits>[2-9]0))[\\s-]+(?<unit>" + units + ")"
        let tail: String = "(?<!\\ba\\s|\\bone\\s)(?:" + compound + "|(?<lone>" + lone + ")|(?<leadUnit>" + units + "))"
        let pattern: String = "(?i)(?<![\\p{L}\\p{N}'’])(?:" + lead + ")?" + tail + "(?![\\p{L}\\p{N}'’])"
        return try! NSRegularExpression(pattern: pattern)
    }()

    private static func ordinalsToDigits(_ transcript: String) -> String {
        var text = transcript
        for match in ordinal.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            func range(_ name: String) -> Range<String.Index>? {
                Range(match.range(withName: name), in: text)
            }
            func group(_ name: String) -> String? {
                range(name).map { text[$0].lowercased() }
            }
            guard let whole = Range(match.range, in: text),
                let tailStart = ["tens", "tensDigits", "lone", "leadUnit"].compactMap({ range($0)?.lowerBound }).min()
            else { continue }
            let lead = group("lead").flatMap(leadValue)
            let value: Int
            if let unit = (group("unit") ?? group("leadUnit")).flatMap(unitOrdinals.firstIndex(of:)) {
                if group("leadUnit") != nil, lead == nil { continue }
                let tens = group("tens").flatMap(tensNames.firstIndex(of:)).map { ($0 + 2) * 10 } ?? Int(group("tensDigits") ?? "") ?? 0
                value = tens + unit + 1
            } else if let lone = group("lone") {
                if lone == "hundredth" {
                    // "two hundredth" and "one thousand hundredth" are not 100th.
                    guard group("lead") == nil, !followsNumberWord(text[..<tailStart]) else { continue }
                    value = 100
                } else {
                    value = teenOrdinals.firstIndex(of: lone).map { $0 + 10 }
                        ?? (tensOrdinals.firstIndex(of: lone)! + 2) * 10
                }
            } else {
                continue
            }
            let total = (lead ?? 0) + value
            text.replaceSubrange(lead == nil ? tailStart..<whole.upperBound : whole, with: "\(grouped(total))\(ordinalSuffix(total))")
        }
        return text
    }

    /// The number before the ordinal, or nil when those words do not make one
    /// number ("nine five hundred").
    private static func leadValue(_ words: String) -> Int? {
        Int(wordsToDigits(words).replacingOccurrences(of: ",", with: ""))
    }

    private static func followsNumberWord(_ before: Substring) -> Bool {
        let last = before.trimmingCharacters(in: .whitespaces).split(whereSeparator: { !$0.isLetter }).last
        return last.map { numberWords.contains($0.lowercased()) } ?? false
    }

    private static func ordinalSuffix(_ value: Int) -> String {
        if (11...13).contains(value % 100) { return "th" }
        switch value % 10 {
        case 1: return "st"
        case 2: return "nd"
        case 3: return "rd"
        default: return "th"
        }
    }

    // MARK: Digits to words

    /// NOTE: a lone digit only. "3.5", "12:30", "v2", "5%", "$5" and "1,000"
    /// keep their digits; spelling those out would change what they mean.
    private static let loneDigit = try! NSRegularExpression(
        pattern: #"(?<![\p{L}\p{N}'’$£€#.,:/\-])\d(?![\p{L}\p{N}%°]|[.,:/\-]\p{N})"#)

    private static func digitsToWords(_ transcript: String) -> String {
        var text = transcript
        for match in loneDigit.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let range = Range(match.range, in: text), let digit = Int(text[range]) else { continue }
            var word = unitNames[digit]
            if startsSentence(text[..<range.lowerBound]) { word = word.capitalized }
            text.replaceSubrange(range, with: word)
        }
        return text
    }

    private static func startsSentence(_ before: Substring) -> Bool {
        let trimmed = before.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty || ".!?".contains(trimmed.last!)
    }

    // MARK: Words to digits

    private static let unitNames = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine"]
    private static let teenNames = [
        "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen",
    ]
    private static let tensNames = ["twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"]
    private static let scales = ["thousand": 1_000, "million": 1_000_000, "billion": 1_000_000_000]

    /// "a", "and" and "oh" only count as part of a number in the right
    /// neighbourhood ("a hundred", "one hundred and five", "nineteen oh five");
    /// anywhere else they come back out unchanged.
    private static let numberWords: Set<String> = Set(unitNames + teenNames + tensNames + scales.keys)
        .union(["hundred", "a", "and", "oh"])

    private static let word = try! NSRegularExpression(pattern: #"(?<![\p{L}\p{N}'’])\p{L}+(?![\p{L}\p{N}'’])"#)
    private static let wordGap = try! NSRegularExpression(pattern: #"^(?:\s+|-)$"#)

    private static func wordsToDigits(_ transcript: String) -> String {
        var text = transcript
        let matches = word.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap { Range($0.range, in: text) }
        var runs: [[Range<String.Index>]] = []
        for range in matches {
            guard numberWords.contains(text[range].lowercased()) else { continue }
            if let previous = runs.last?.last, isGap(text[previous.upperBound..<range.lowerBound]) {
                runs[runs.count - 1].append(range)
            } else {
                runs.append([range])
            }
        }
        for run in runs.reversed() {
            if tensNames.contains(text[run.last!].lowercased()), startsWithUnitOrdinal(text[run.last!.upperBound...]) {
                continue
            }
            guard let rewritten = Run(text: text, words: run).rewritten() else { continue }
            text.replaceSubrange(run.first!.lowerBound..<run.last!.upperBound, with: rewritten)
        }
        return text
    }

    /// NOTE: a tens word right before "first" to "ninth" is a compound ordinal
    /// the ordinal pass left alone on purpose ("one twenty fifth", "a thirty
    /// second clip"). Turning only its cardinal half into digits would give
    /// "one 20 fifth".
    private static let unitOrdinalAhead = try! NSRegularExpression(
        pattern: "(?i)^[\\s-]+(?:" + unitOrdinals.joined(separator: "|") + ")(?![\\p{L}\\p{N}'’])")

    private static func startsWithUnitOrdinal(_ after: Substring) -> Bool {
        let after = String(after)
        return unitOrdinalAhead.firstMatch(in: after, range: NSRange(after.startIndex..., in: after)) != nil
    }

    private static func isGap(_ gap: Substring) -> Bool {
        let gap = String(gap)
        return wordGap.firstMatch(in: gap, range: NSRange(gap.startIndex..., in: gap)) != nil
    }

    /// One stretch of adjacent number words, such as "eleven forty eight nine
    /// seven seven six", split into the numbers the speaker meant.
    private struct Run {
        let text: String
        let words: [Range<String.Index>]
        let lower: [String]

        init(text: String, words: [Range<String.Index>]) {
            self.text = text
            self.words = words
            self.lower = words.map { text[$0].lowercased() }
        }

        private enum Piece {
            case words(Range<Int>)
            case digits(String)
        }

        /// Nil when every word stays a word, so the run's spacing is untouched.
        func rewritten() -> String? {
            var pieces: [Piece] = []
            var i = 0
            while i < lower.count {
                let (piece, end) = next(at: i)
                if case .words(let range) = piece, case .words(let previous)? = pieces.last {
                    pieces[pieces.count - 1] = .words(previous.lowerBound..<range.upperBound)
                } else {
                    pieces.append(piece)
                }
                i = end
            }
            guard pieces.contains(where: { if case .digits = $0 { true } else { false } }) else { return nil }
            return pieces.map { piece in
                switch piece {
                case .digits(let digits): digits
                case .words(let range): String(text[words[range.lowerBound].lowerBound..<words[range.upperBound - 1].upperBound])
                }
            }.joined(separator: " ")
        }

        private func next(at i: Int) -> (Piece, Int) {
            if let (value, end) = cardinal(at: i) {
                return (.digits(grouped(value)), end)
            }
            guard let first = small(at: i) else { return (.words(i..<i + 1), i + 1) }
            if first.width == 2 {
                // Years and the like are said in pairs: "eighteen forty eight", "nineteen oh five".
                if let second = small(at: first.end), second.width == 2, cardinal(at: first.end) == nil {
                    return (.digits("\(first.value)\(second.value)"), second.end)
                }
                if word(first.end) == "oh", let unit = small(at: first.end + 1), unit.width == 1 {
                    return (.digits("\(first.value)0\(unit.value)"), unit.end)
                }
                return (.digits(String(first.value)), first.end)
            }
            // A run of single digits is a code or a phone number read out.
            var digits = String(first.value)
            var j = first.end
            while j < lower.count {
                if word(j) == "oh" {
                    digits += "0"
                    j += 1
                } else if let unit = small(at: j), unit.width == 1, cardinal(at: j) == nil {
                    digits += String(unit.value)
                    j = unit.end
                } else {
                    break
                }
            }
            // NOTE: "one or two" and "two three-hour calls" are prose, so two
            // digits in a row stay words; three or more is a code.
            guard digits.count >= 3 else { return (.words(i..<first.end), first.end) }
            return (.digits(phoneShaped(digits)), j)
        }

        private func word(_ i: Int) -> String? {
            i < lower.count ? lower[i] : nil
        }

        /// A number under a hundred: a unit (width 1), or a teen or a tens
        /// word with its unit (width 2).
        private func small(at i: Int) -> (value: Int, width: Int, end: Int)? {
            guard let word = word(i) else { return nil }
            if let tens = tensNames.firstIndex(of: word) {
                let value = (tens + 2) * 10
                if let unit = self.word(i + 1).flatMap(unitNames.firstIndex(of:)), unit > 0 {
                    return (value + unit, 2, i + 2)
                }
                return (value, 2, i + 1)
            }
            if let teen = teenNames.firstIndex(of: word) { return (teen + 10, 2, i + 1) }
            if let unit = unitNames.firstIndex(of: word) { return (unit, 1, i + 1) }
            return nil
        }

        /// A number built with "hundred" or a scale word, such as "two
        /// thousand twenty nine". Nil when neither appears, so "eighteen
        /// forty eight" is left to the pairing rule.
        private func cardinal(at start: Int) -> (value: Int, end: Int)? {
            var total = 0
            var hundreds = 0
            var sub = 0
            var hasSub = false
            var hasHundred = false
            var lastScale = Int.max
            var afterMultiplier = false
            var j = start
            while let word = word(j) {
                if word == "a", j == start, let following = self.word(j + 1),
                    following == "hundred" || scales[following] != nil
                {
                    sub = 1
                    hasSub = true
                    j += 1
                } else if word == "hundred" {
                    guard hasSub, !hasHundred else { break }
                    hundreds = sub
                    sub = 0
                    hasSub = false
                    hasHundred = true
                    afterMultiplier = true
                    j += 1
                } else if let scale = scales[word] {
                    guard hasSub || hasHundred, scale < lastScale else { break }
                    total += (hundreds * 100 + sub) * scale
                    hundreds = 0
                    sub = 0
                    hasSub = false
                    hasHundred = false
                    lastScale = scale
                    afterMultiplier = true
                    j += 1
                } else if word == "and" {
                    guard afterMultiplier, !hasSub, small(at: j + 1) != nil else { break }
                    afterMultiplier = false
                    j += 1
                } else if let small = small(at: j) {
                    guard !hasSub else { break }
                    sub = small.value
                    hasSub = true
                    afterMultiplier = false
                    j = small.end
                } else {
                    break
                }
            }
            guard lastScale != Int.max || hundreds > 0 || hasHundred else { return nil }
            return (total + hundreds * 100 + sub, j)
        }
    }

    /// Thousands separators from five digits up, so a year stays "2029".
    private static func grouped(_ value: Int) -> String {
        let digits = String(value)
        guard digits.count >= 5 else { return digits }
        var out = ""
        for (index, character) in digits.enumerated() {
            if index > 0, (digits.count - index) % 3 == 0 { out += "," }
            out.append(character)
        }
        return out
    }

    private static func phoneShaped(_ digits: String) -> String {
        let d = Array(digits)
        switch d.count {
        case 7: return "\(String(d[0..<3]))-\(String(d[3...]))"
        case 10: return "\(String(d[0..<3]))-\(String(d[3..<6]))-\(String(d[6...]))"
        case 11 where d[0] == "1": return "1-\(String(d[1..<4]))-\(String(d[4..<7]))-\(String(d[7...]))"
        default: return digits
        }
    }

    // MARK: Phone numbers

    /// NOTE: North American shape only, with area code and exchange starting
    /// 2 to 9. That is what keeps "2,000,000,000" or a ten-digit ID with a
    /// leading 1 or 0 from being read as a phone number.
    private static let phoneNumber = try! NSRegularExpression(
        pattern: #"(?<![\p{N}\-.,(])(?:(1)[ .\-]?)?\(?([2-9]\d{2})\)?[ .\-]?([2-9]\d{2})[ .\-]?(\d{4})(?![\p{N}])"#)

    private static func hyphenatingPhoneNumbers(in transcript: String) -> String {
        var text = transcript
        for match in phoneNumber.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let range = Range(match.range, in: text) else { continue }
            let parts = (1...4).compactMap { Range(match.range(at: $0), in: text).map { String(text[$0]) } }
            text.replaceSubrange(range, with: parts.joined(separator: "-"))
        }
        return text
    }
}
