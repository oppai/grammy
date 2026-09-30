import SwiftUI

/// Word-level diff used to highlight what the correction changed.
enum WordDiff {
    enum Op {
        case equal(String)
        case insert(String)
        case delete(String)
    }

    static func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var currentIsSpace: Bool?
        for ch in text {
            let isSpace = ch.isWhitespace
            if currentIsSpace != nil, currentIsSpace != isSpace {
                tokens.append(current)
                current = ""
            }
            current.append(ch)
            currentIsSpace = isSpace
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    static func diff(_ old: String, _ new: String) -> [Op] {
        let a = tokenize(old)
        let b = tokenize(new)
        let n = a.count, m = b.count
        // Guard against pathological sizes; fall back to "replace everything".
        guard n * m <= 250_000 else { return [.delete(old), .insert(new)] }

        var lcs = Array(repeating: Array(repeating: Int32(0), count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                lcs[i][j] = a[i] == b[j] ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
            }
        }

        var ops: [Op] = []
        var i = 0, j = 0
        while i < n, j < m {
            if a[i] == b[j] {
                ops.append(.equal(a[i])); i += 1; j += 1
            } else if lcs[i + 1][j] >= lcs[i][j + 1] {
                ops.append(.delete(a[i])); i += 1
            } else {
                ops.append(.insert(b[j])); j += 1
            }
        }
        while i < n { ops.append(.delete(a[i])); i += 1 }
        while j < m { ops.append(.insert(b[j])); j += 1 }
        return ops
    }

    static func attributed(from old: String, to new: String) -> AttributedString {
        var result = AttributedString()
        for op in diff(old, new) {
            switch op {
            case let .equal(s):
                result += AttributedString(s)
            case let .delete(s):
                guard !s.allSatisfy(\.isWhitespace) else { continue }
                var part = AttributedString(s)
                part.foregroundColor = .red
                part.strikethroughStyle = .single
                result += part
            case let .insert(s):
                var part = AttributedString(s)
                if !s.allSatisfy(\.isWhitespace) {
                    part.foregroundColor = .green
                    part.inlinePresentationIntent = .stronglyEmphasized
                }
                result += part
            }
        }
        return result
    }
}
