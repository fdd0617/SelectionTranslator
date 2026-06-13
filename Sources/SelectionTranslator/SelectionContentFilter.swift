import Foundation

enum SelectionContentFilter {
    static func shouldTranslate(_ text: String) -> Bool {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return false
        }

        if isURL(trimmedText) {
            return false
        }

        if isPureNumber(trimmedText) {
            return false
        }

        if isLongAlphaNumericToken(trimmedText) {
            return false
        }

        if isPathLike(trimmedText) {
            return false
        }

        if isChineseOnly(trimmedText) {
            return false
        }

        return true
    }

    private static func isURL(_ text: String) -> Bool {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return false
        }

        let range = NSRange(location: 0, length: (text as NSString).length)
        let matches = detector.matches(in: text, options: [], range: range)
        return matches.contains { match in
            match.range.location == 0 && match.range.length == range.length
        }
    }

    private static func isPureNumber(_ text: String) -> Bool {
        let compactText = text.unicodeScalars.filter { !$0.properties.isWhitespace }
        guard compactText.contains(where: { CharacterSet.decimalDigits.contains($0) }) else {
            return false
        }

        let allowedScalars = CharacterSet.decimalDigits.union(CharacterSet(charactersIn: ".,:+-/%¥$€£()[]{}"))
        return compactText.allSatisfy { allowedScalars.contains($0) }
    }

    private static func isLongAlphaNumericToken(_ text: String) -> Bool {
        let token = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard token.count >= 16, !token.unicodeScalars.contains(where: { $0.properties.isWhitespace }) else {
            return false
        }

        let allowedScalars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        guard token.unicodeScalars.allSatisfy({ allowedScalars.contains($0) }) else {
            return false
        }

        let containsLatinLetter = token.unicodeScalars.contains { scalar in
            CharacterSet.letters.contains(scalar)
        }
        let containsDigit = token.unicodeScalars.contains { scalar in
            CharacterSet.decimalDigits.contains(scalar)
        }

        return containsLatinLetter && containsDigit
    }

    private static func isPathLike(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count >= 3, !value.contains("://") else {
            return false
        }

        if value.hasPrefix("/") || value.hasPrefix("~/") || value.hasPrefix("./") || value.hasPrefix("../") {
            return true
        }

        if isWindowsDrivePath(value) || value.hasPrefix("\\\\") {
            return true
        }

        if value.contains("/") || value.contains("\\") {
            let separators = value.filter { $0 == "/" || $0 == "\\" }.count
            let hasPathishSegment = value.split(whereSeparator: { $0 == "/" || $0 == "\\" }).contains { segment in
                segment.contains(".") || segment.contains("_") || segment.contains("-")
            }
            return separators >= 2 || hasPathishSegment
        }

        return false
    }

    private static func isWindowsDrivePath(_ text: String) -> Bool {
        guard text.count >= 3 else {
            return false
        }

        let scalars = Array(text.unicodeScalars)
        let drive = scalars[0]
        let separator = scalars[2]

        return CharacterSet.letters.contains(drive) && scalars[1] == ":" && (separator == "\\" || separator == "/")
    }

    private static func isChineseOnly(_ text: String) -> Bool {
        let scalars = text.unicodeScalars
        let containsChinese = scalars.contains(where: isCJKIdeograph)
        let containsLatinLetter = scalars.contains { scalar in
            ("A"..."Z").contains(Character(scalar)) || ("a"..."z").contains(Character(scalar))
        }

        return containsChinese && !containsLatinLetter
    }

    private static func isCJKIdeograph(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3400...0x4DBF,
             0x4E00...0x9FFF,
             0xF900...0xFAFF,
             0x20000...0x2A6DF,
             0x2A700...0x2B73F,
             0x2B740...0x2B81F,
             0x2B820...0x2CEAF:
            return true
        default:
            return false
        }
    }
}
