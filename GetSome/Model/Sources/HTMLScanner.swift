/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
Helpers that HTML-scraping sources share.
*/

import Foundation

/// Helpers that HTML-scraping sources share.
///
/// None of this knows about a particular site — it's the small toolkit a new
/// ``ContentSource`` reaches for when the site it wraps publishes markup.
enum HTMLScanner {

    /// Replaces `&#39;` and `&#x27;` style escapes with their characters.
    private static func decodeNumericEntities(_ text: String) -> String {
        guard text.contains("&#") else { return text }
        guard let expression = try? NSRegularExpression(pattern: #"&#(x?)([0-9A-Fa-f]+);"#) else { return text }

        var result = text
        let matches = expression.matches(in: text, range: NSRange(text.startIndex..., in: text))
        // Replace from the back so earlier ranges stay valid.
        for match in matches.reversed() {
            guard let whole = Range(match.range, in: result),
                  let flagRange = Range(match.range(at: 1), in: result),
                  let digitsRange = Range(match.range(at: 2), in: result) else { continue }
            let radix = result[flagRange].isEmpty ? 10 : 16
            guard let code = UInt32(result[digitsRange], radix: radix),
                  let scalar = Unicode.Scalar(code) else { continue }
            result.replaceSubrange(whole, with: String(Character(scalar)))
        }
        return result
    }

    /// Returns the first capture group of the specified pattern.
    static func firstMatch(
        of pattern: String,
        in text: String,
        dotMatchesNewlines: Bool = false
    ) -> String? {
        var options: NSRegularExpression.Options = [.caseInsensitive]
        if dotMatchesNewlines {
            options.insert(.dotMatchesLineSeparators)
        }
        guard let expression = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = expression.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let captured = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[captured])
    }

    /// Returns every value the pattern's first capture group matches, in order.
    static func allMatches(of pattern: String, in text: String) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let range = NSRange(text.startIndex..., in: text)
        return expression.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let captured = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[captured])
        }
    }

    /// Returns the content of a `<meta>` tag with the specified attribute value.
    static func metaContent(_ name: String, in html: String) -> String? {
        let pattern = #"<meta[^>]+(?:property|name)="\#(NSRegularExpression.escapedPattern(for: name))"[^>]+content="([^"]*)""#
        return firstMatch(of: pattern, in: html).map(decode)
    }

    /// Converts a `mm:ss` or `hh:mm:ss` duration into seconds.
    static func seconds(fromClock text: String) -> Int {
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ":")
            .compactMap { Int($0) }
        guard !parts.isEmpty else { return 0 }
        return parts.reduce(0) { $0 * 60 + $1 }
    }

    /// Converts an ISO 8601 duration such as `PT34M59S` into seconds.
    static func seconds(fromISO8601 text: String) -> Int {
        var total = 0
        var value = 0
        for character in text {
            if character.isNumber, let digit = character.wholeNumberValue {
                value = value * 10 + digit
            } else {
                switch character {
                case "H": total += value * 3600
                case "M": total += value * 60
                case "S": total += value
                default: break
                }
                if character != "P" && character != "T" { value = 0 }
            }
        }
        return total
    }

    /// Abbreviates a raw count the way listing pages usually do, such as `889.7K`.
    static func abbreviated(_ text: String?) -> String {
        guard let text, let count = Int(text) else { return text ?? "" }
        switch count {
        case 1_000_000...:
            return String(format: "%.1fM", Double(count) / 1_000_000)
        case 1_000...:
            return String(format: "%.1fK", Double(count) / 1_000)
        default:
            return String(count)
        }
    }

    /// The named entities site titles actually contain.
    ///
    /// Mostly punctuation: sites write titles in a CMS that turns quotes and dashes
    /// into typographic forms, and those arrive named rather than numeric. Accented
    /// letters are left to ``decodeNumericEntities(_:)`` — they come through as
    /// numeric escapes or as plain UTF-8, and listing every one of them here would
    /// be a table without an end.
    ///
    /// `&amp;` is deliberately absent; see ``decode(_:)``.
    private static let namedEntities = [
        ("&quot;", "\""), ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " "),
        ("&rsquo;", "’"), ("&lsquo;", "‘"), ("&rdquo;", "”"), ("&ldquo;", "“"),
        ("&mdash;", "—"), ("&ndash;", "–"), ("&hellip;", "…"), ("&bull;", "•"),
        ("&middot;", "·"), ("&laquo;", "«"), ("&raquo;", "»"), ("&deg;", "°"),
        ("&times;", "×"), ("&copy;", "©"), ("&reg;", "®"), ("&trade;", "™")
    ]

    /// Replaces the HTML entities that markup commonly contains.
    static func decode(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = text
        for (entity, replacement) in namedEntities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        result = decodeNumericEntities(result)
        // Last, always. `&amp;lt;` is an escaped literal "&lt;", so decoding the
        // ampersand first would turn it into a "<" the title never contained.
        return result.replacingOccurrences(of: "&amp;", with: "&")
    }
}

extension Date {
    /// A formatter for the `yyyy-MM-dd` dates that sites commonly publish.
    static let siteFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
