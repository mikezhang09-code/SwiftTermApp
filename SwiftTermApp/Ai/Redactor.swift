//
//  Redactor.swift
//  SwiftTermApp
//
//  Best-effort scrubbing of secrets and identifying values from terminal
//  text before it is sent to an AI provider.  Replacements use stable,
//  numbered placeholders ([IP-1], [SECRET-2], ...) so the model can still
//  reason about "the same address appears twice".
//
//  This is heuristic by design — the redacted preview shown before sending
//  is the real safety net.
//

import Foundation

struct RedactionResult {
    var text: String
    /// category -> number of distinct values replaced
    var counts: [String: Int]

    var summary: String {
        if counts.isEmpty {
            return "Nothing was redacted"
        }
        let parts = counts.sorted { $0.key < $1.key }.map { "\($0.value) \($0.key)" }
        return "Redacted: " + parts.joined (separator: ", ")
    }
}

struct Redactor {
    /// Loopback/wildcard addresses are meaningful for diagnosis and not identifying
    static let ipv4Allowlist: Set<String> = ["127.0.0.1", "0.0.0.0", "255.255.255.255"]

    struct Rule {
        var category: String     // placeholder prefix and summary label
        var pattern: String
        /// Index of the capture group holding the secret; 0 = whole match.
        /// Groups before it are preserved verbatim (e.g. "password=").
        var secretGroup: Int
        var allowlist: Set<String> = []
    }

    // Order matters: multi-line blocks first, then structured secrets, then addresses
    static let rules: [Rule] = [
        Rule (category: "private key",
              pattern: "-----BEGIN [A-Z ]*PRIVATE KEY-----[\\s\\S]*?(?:-----END [A-Z ]*PRIVATE KEY-----|\\z)",
              secretGroup: 0),
        Rule (category: "auth header",
              pattern: "(?i)(authorization\\s*:\\s*(?:bearer|basic|token)\\s+)([^\\s\"']+)",
              secretGroup: 2),
        Rule (category: "secret",
              pattern: "(?i)\\b((?:password|passwd|pwd|token|secret|api[_-]?key|apikey|access[_-]?key|private[_-]?key)\\b\\s*[=:]\\s*[\"']?)([^\\s\"',;]+)",
              secretGroup: 2),
        Rule (category: "email",
              pattern: "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}",
              secretGroup: 0),
        // At least three colon-separated hex groups so times like 12:34:56
        // are not caught; also catches MAC addresses, which is fine.
        Rule (category: "IPv6/MAC",
              pattern: "\\b(?:[0-9a-fA-F]{1,4}:){3,7}[0-9a-fA-F]{1,4}\\b|\\b[0-9a-fA-F]{1,4}::[0-9a-fA-F:]{1,24}\\b",
              secretGroup: 0),
        Rule (category: "IP",
              pattern: "\\b(?:\\d{1,3}\\.){3}\\d{1,3}\\b",
              secretGroup: 0,
              allowlist: ipv4Allowlist),
    ]

    static func placeholderPrefix (for category: String) -> String {
        switch category {
        case "private key": return "PRIVATE-KEY"
        case "auth header": return "TOKEN"
        case "secret": return "SECRET"
        case "email": return "EMAIL"
        case "IPv6/MAC": return "IP6"
        case "IP": return "IP"
        default: return "REDACTED"
        }
    }

    static func redact (_ input: String) -> RedactionResult {
        var text = input
        var counts: [String: Int] = [:]

        for rule in rules {
            guard let regex = try? NSRegularExpression (pattern: rule.pattern) else { continue }
            // Same value -> same placeholder within this run
            var mapping: [String: String] = [:]
            let prefix = placeholderPrefix (for: rule.category)

            let range = NSRange (text.startIndex..., in: text)
            let matches = regex.matches (in: text, range: range)

            func secretIn (_ match: NSTextCheckingResult) -> (Range<String.Index>, String)? {
                let secretRange = match.range (at: rule.secretGroup)
                guard secretRange.location != NSNotFound,
                      let swiftRange = Range (secretRange, in: text) else { return nil }
                let secret = String (text [swiftRange])
                if rule.allowlist.contains (secret) { return nil }
                if secret.hasPrefix ("[") && secret.hasSuffix ("]") { return nil }
                return (swiftRange, secret)
            }

            // Number placeholders in order of first appearance...
            for match in matches {
                guard let (_, secret) = secretIn (match) else { continue }
                if mapping [secret] == nil {
                    mapping [secret] = "[\(prefix)-\(mapping.count + 1)]"
                }
            }
            // ...then replace back-to-front so earlier ranges stay valid
            for match in matches.reversed () {
                guard let (swiftRange, secret) = secretIn (match), let placeholder = mapping [secret] else { continue }
                text.replaceSubrange (swiftRange, with: placeholder)
            }
            if !mapping.isEmpty {
                counts [rule.category] = mapping.count
            }
        }
        return RedactionResult (text: text, counts: counts)
    }
}
