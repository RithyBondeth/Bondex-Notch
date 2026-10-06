import Foundation

/// A JSON value that remembers the order of its keys and the spelling of its
/// numbers, for editing files that belong to someone else.
///
/// `JSONSerialization` reads an object into a dictionary, so writing it back
/// shuffles the keys, prints `"key" : value`, and can turn `2` into `2.0`. That
/// is harmless for a file Bondex owns and rude for an agent's settings, which
/// people read and keep in version control. Parsing into this instead means an
/// edit changes the lines it means to and nothing else: a file written the way
/// the agents write theirs (`JSON.stringify(value, null, 2)`) comes back out
/// byte for byte.
indirect enum OrderedJSON: Equatable {
    /// Pairs rather than a dictionary: order is the point, and a duplicate key
    /// survives the round trip instead of being silently dropped.
    case object([(key: String, value: OrderedJSON)])
    case array([OrderedJSON])
    case string(String)
    /// The literal as written, so nothing is lost converting through Double.
    case number(String)
    case bool(Bool)
    case null

    static func == (lhs: OrderedJSON, rhs: OrderedJSON) -> Bool {
        switch (lhs, rhs) {
        case let (.object(a), .object(b)):
            return a.count == b.count && zip(a, b).allSatisfy { $0.key == $1.key && $0.value == $1.value }
        case let (.array(a), .array(b)): return a == b
        case let (.string(a), .string(b)): return a == b
        case let (.number(a), .number(b)): return a == b
        case let (.bool(a), .bool(b)): return a == b
        case (.null, .null): return true
        default: return false
        }
    }

    // MARK: Access

    /// The value for a key. With a duplicate key the last one wins, as in
    /// `JSON.parse`.
    subscript(key: String) -> OrderedJSON? {
        guard case .object(let pairs) = self else { return nil }
        return pairs.last(where: { $0.key == key })?.value
    }

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var arrayValue: [OrderedJSON]? {
        if case .array(let values) = self { return values }
        return nil
    }

    var isObject: Bool {
        if case .object = self { return true }
        return false
    }

    /// Replaces the value for a key in place, or appends the key at the end.
    /// Only meaningful on an object; anything else is left as it is.
    mutating func set(_ key: String, to value: OrderedJSON) {
        guard case .object(var pairs) = self else { return }
        if let index = pairs.lastIndex(where: { $0.key == key }) {
            pairs[index].value = value
        } else {
            pairs.append((key, value))
        }
        self = .object(pairs)
    }

    mutating func remove(_ key: String) {
        guard case .object(var pairs) = self else { return }
        pairs.removeAll { $0.key == key }
        self = .object(pairs)
    }

    // MARK: Reading

    struct ParseError: Error, LocalizedError, Equatable {
        let offset: Int
        let reason: String
        var errorDescription: String? { "\(reason) at byte \(offset)" }
    }

    static func parse(_ data: Data) throws -> OrderedJSON {
        var parser = Parser(bytes: [UInt8](data))
        // A byte-order mark is not JSON, but editors do write one.
        if parser.bytes.starts(with: [0xEF, 0xBB, 0xBF]) { parser.index = 3 }
        parser.skipWhitespace()
        let value = try parser.value(depth: 0)
        parser.skipWhitespace()
        guard parser.index == parser.bytes.count else {
            throw parser.error("Unexpected content after the end")
        }
        return value
    }

    private struct Parser {
        let bytes: [UInt8]
        var index = 0

        /// Deep enough for any real settings file, shallow enough that a
        /// hostile one cannot exhaust the stack.
        private static let maxDepth = 512

        func error(_ reason: String) -> ParseError {
            ParseError(offset: index, reason: reason)
        }

        mutating func skipWhitespace() {
            while index < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[index]) {
                index += 1
            }
        }

        mutating func value(depth: Int) throws -> OrderedJSON {
            guard depth < Self.maxDepth else { throw error("Nested too deeply") }
            guard index < bytes.count else { throw error("Unexpected end") }
            switch bytes[index] {
            case UInt8(ascii: "{"): return try object(depth: depth)
            case UInt8(ascii: "["): return try array(depth: depth)
            case UInt8(ascii: "\""): return .string(try string())
            case UInt8(ascii: "t"): try literal("true"); return .bool(true)
            case UInt8(ascii: "f"): try literal("false"); return .bool(false)
            case UInt8(ascii: "n"): try literal("null"); return .null
            case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"): return try number()
            default:
                // Comments land here too. JSONC is not JSON, and a file with
                // comments is one to leave alone rather than strip them from.
                throw error("Unexpected character")
            }
        }

        private mutating func object(depth: Int) throws -> OrderedJSON {
            index += 1
            var pairs: [(key: String, value: OrderedJSON)] = []
            skipWhitespace()
            if index < bytes.count, bytes[index] == UInt8(ascii: "}") {
                index += 1
                return .object(pairs)
            }
            while true {
                skipWhitespace()
                guard index < bytes.count, bytes[index] == UInt8(ascii: "\"") else {
                    throw error("Expected a key")
                }
                let key = try string()
                skipWhitespace()
                guard index < bytes.count, bytes[index] == UInt8(ascii: ":") else {
                    throw error("Expected ':'")
                }
                index += 1
                skipWhitespace()
                pairs.append((key, try value(depth: depth + 1)))
                skipWhitespace()
                guard index < bytes.count else { throw error("Unexpected end") }
                if bytes[index] == UInt8(ascii: ",") { index += 1; continue }
                if bytes[index] == UInt8(ascii: "}") { index += 1; return .object(pairs) }
                throw error("Expected ',' or '}'")
            }
        }

        private mutating func array(depth: Int) throws -> OrderedJSON {
            index += 1
            var values: [OrderedJSON] = []
            skipWhitespace()
            if index < bytes.count, bytes[index] == UInt8(ascii: "]") {
                index += 1
                return .array(values)
            }
            while true {
                skipWhitespace()
                values.append(try value(depth: depth + 1))
                skipWhitespace()
                guard index < bytes.count else { throw error("Unexpected end") }
                if bytes[index] == UInt8(ascii: ",") { index += 1; continue }
                if bytes[index] == UInt8(ascii: "]") { index += 1; return .array(values) }
                throw error("Expected ',' or ']'")
            }
        }

        private mutating func string() throws -> String {
            index += 1
            var scalars = String.UnicodeScalarView()
            var runStart = index
            func flushRun(_ end: Int) {
                guard end > runStart else { return }
                scalars.append(contentsOf: String(decoding: bytes[runStart..<end], as: UTF8.self).unicodeScalars)
            }
            while index < bytes.count {
                let byte = bytes[index]
                if byte == UInt8(ascii: "\"") {
                    flushRun(index)
                    index += 1
                    return String(scalars)
                }
                if byte < 0x20 { throw error("Control character in a string") }
                if byte != UInt8(ascii: "\\") { index += 1; continue }

                flushRun(index)
                index += 1
                guard index < bytes.count else { break }
                let escape = bytes[index]
                index += 1
                switch escape {
                case UInt8(ascii: "\""): scalars.append("\"")
                case UInt8(ascii: "\\"): scalars.append("\\")
                case UInt8(ascii: "/"): scalars.append("/")
                case UInt8(ascii: "b"): scalars.append("\u{08}")
                case UInt8(ascii: "f"): scalars.append("\u{0C}")
                case UInt8(ascii: "n"): scalars.append("\n")
                case UInt8(ascii: "r"): scalars.append("\r")
                case UInt8(ascii: "t"): scalars.append("\t")
                case UInt8(ascii: "u"):
                    let unit = try hex4()
                    if (0xD800...0xDBFF).contains(unit) {
                        // A surrogate pair is two escapes making one scalar.
                        guard index + 1 < bytes.count,
                              bytes[index] == UInt8(ascii: "\\"),
                              bytes[index + 1] == UInt8(ascii: "u") else {
                            throw error("Unpaired surrogate")
                        }
                        index += 2
                        let low = try hex4()
                        guard (0xDC00...0xDFFF).contains(low) else { throw error("Unpaired surrogate") }
                        let combined = 0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00)
                        guard let scalar = Unicode.Scalar(combined) else { throw error("Invalid escape") }
                        scalars.append(scalar)
                    } else {
                        guard let scalar = Unicode.Scalar(unit) else { throw error("Unpaired surrogate") }
                        scalars.append(scalar)
                    }
                default:
                    throw error("Invalid escape")
                }
                runStart = index
            }
            throw error("Unterminated string")
        }

        private mutating func hex4() throws -> UInt32 {
            guard index + 4 <= bytes.count else { throw error("Invalid escape") }
            var value: UInt32 = 0
            for byte in bytes[index..<index + 4] {
                guard let digit = Character(Unicode.Scalar(byte)).hexDigitValue else {
                    throw error("Invalid escape")
                }
                value = value * 16 + UInt32(digit)
            }
            index += 4
            return value
        }

        private mutating func number() throws -> OrderedJSON {
            let start = index
            func digits() -> Int {
                let from = index
                while index < bytes.count, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(bytes[index]) {
                    index += 1
                }
                return index - from
            }
            if bytes[index] == UInt8(ascii: "-") { index += 1 }
            guard index < bytes.count else { throw error("Invalid number") }
            if bytes[index] == UInt8(ascii: "0") {
                index += 1
            } else if digits() == 0 {
                throw error("Invalid number")
            }
            if index < bytes.count, bytes[index] == UInt8(ascii: ".") {
                index += 1
                guard digits() > 0 else { throw error("Invalid number") }
            }
            if index < bytes.count, bytes[index] == UInt8(ascii: "e") || bytes[index] == UInt8(ascii: "E") {
                index += 1
                if index < bytes.count, bytes[index] == UInt8(ascii: "+") || bytes[index] == UInt8(ascii: "-") {
                    index += 1
                }
                guard digits() > 0 else { throw error("Invalid number") }
            }
            return .number(String(decoding: bytes[start..<index], as: UTF8.self))
        }

        private mutating func literal(_ word: String) throws {
            let expected = Array(word.utf8)
            guard bytes.count - index >= expected.count,
                  Array(bytes[index..<index + expected.count]) == expected else {
                throw error("Unexpected character")
            }
            index += expected.count
        }
    }

    // MARK: Writing

    /// How a file lays itself out, so an edit can write it back the same way.
    struct Style: Equatable {
        var indent = "  "
        var trailingNewline = true

        /// Reads the indent from the first indented line, which is one level
        /// deep in any pretty-printed file.
        static func detect(in data: Data) -> Style {
            var style = Style()
            let text = String(decoding: data, as: UTF8.self)
            style.trailingNewline = text.hasSuffix("\n")
            for line in text.split(separator: "\n", omittingEmptySubsequences: true).dropFirst() {
                let leading = line.prefix { $0 == " " || $0 == "\t" }
                if !leading.isEmpty {
                    style.indent = String(leading)
                    break
                }
            }
            return style
        }
    }

    /// Pretty-printed the way `JSON.stringify(value, null, indent)` prints it.
    func serialized(style: Style = Style()) -> Data {
        var output = ""
        write(into: &output, level: 0, indent: style.indent)
        if style.trailingNewline { output += "\n" }
        return Data(output.utf8)
    }

    private func write(into output: inout String, level: Int, indent: String) {
        switch self {
        case .object(let pairs):
            guard !pairs.isEmpty else { output += "{}"; return }
            output += "{\n"
            for (offset, pair) in pairs.enumerated() {
                output += String(repeating: indent, count: level + 1)
                Self.writeString(pair.key, into: &output)
                output += ": "
                pair.value.write(into: &output, level: level + 1, indent: indent)
                output += offset == pairs.count - 1 ? "\n" : ",\n"
            }
            output += String(repeating: indent, count: level) + "}"
        case .array(let values):
            guard !values.isEmpty else { output += "[]"; return }
            output += "[\n"
            for (offset, value) in values.enumerated() {
                output += String(repeating: indent, count: level + 1)
                value.write(into: &output, level: level + 1, indent: indent)
                output += offset == values.count - 1 ? "\n" : ",\n"
            }
            output += String(repeating: indent, count: level) + "]"
        case .string(let value):
            Self.writeString(value, into: &output)
        case .number(let literal):
            output += literal
        case .bool(let value):
            output += value ? "true" : "false"
        case .null:
            output += "null"
        }
    }

    private static func writeString(_ value: String, into output: inout String) {
        output += "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": output += "\\\""
            case "\\": output += "\\\\"
            case "\n": output += "\\n"
            case "\r": output += "\\r"
            case "\t": output += "\\t"
            case "\u{08}": output += "\\b"
            case "\u{0C}": output += "\\f"
            case let control where control.value < 0x20:
                output += String(format: "\\u%04x", control.value)
            default:
                output.unicodeScalars.append(scalar)
            }
        }
        output += "\""
    }
}
