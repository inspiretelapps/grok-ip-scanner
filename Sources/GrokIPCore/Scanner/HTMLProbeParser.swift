import Foundation

public enum HTMLProbeParser: Sendable {
    public static func title(from html: String) -> String? {
        let pattern = #"<title[^>]*>([\s\S]*?)</title>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              let titleRange = Range(match.range(at: 1), in: html) else {
            return nil
        }
        let raw = String(html[titleRange])
        let collapsed = raw
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let decoded = unescape(collapsed)
        return decoded.isEmpty ? nil : String(decoded.prefix(120))
    }

    public static func hasPasswordField(_ html: String) -> Bool {
        let lower = html.lowercased()
        return lower.contains("type=\"password\"")
            || lower.contains("type='password'")
            || lower.contains("type=password")
            || lower.contains("name=\"password\"")
            || lower.contains("name='password'")
            || lower.contains("id=\"password\"")
    }

    public static func looksLikeLogin(status: Int, headers: [String: String], html: String) -> Bool {
        if status == 401 { return true }
        if headers.keys.contains(where: { $0.lowercased() == "www-authenticate" }) { return true }
        if hasPasswordField(html) { return true }
        let lower = html.lowercased()
        let hasLoginWord = lower.contains("login") || lower.contains("sign in") || lower.contains("signin")
        let hasUserWord = lower.contains("username") || lower.contains("user name") || lower.contains("password")
        return hasLoginWord && hasUserWord
    }

    public static func unescape(_ string: String) -> String {
        var result = string
        let entities: [(String, String)] = [
            ("&nbsp;", " "),
            ("&amp;", "&"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&quot;", "\""),
            ("&#39;", "'"),
            ("&apos;", "'")
        ]
        for (entity, value) in entities {
            result = result.replacingOccurrences(of: entity, with: value)
            result = result.replacingOccurrences(of: entity.uppercased(), with: value)
        }
        return result
    }
}
