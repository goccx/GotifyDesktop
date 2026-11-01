import AppKit
import SwiftUI

/// Structured block representation of a Markdown message body.
/// Kept Equatable and Sendable so block parsing can be deterministically unit-tested.
enum MarkdownBlock: Equatable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(text: String)
    case unorderedListItem(indent: Int, text: String)
    case orderedListItem(indent: Int, marker: String, text: String)
    case blockquote(text: String)
    case codeBlock(language: String?, code: String)
    case table(headers: [String], rows: [[String]])
    case horizontalRule
}

/// Native Markdown parser and sanitizer tailored for Gotify messages and AI assistant replies.
/// Preserves raw message data in memory while rendering headings, lists, code blocks, tables,
/// dividers, CJK bold spans, and links cleanly without WebView.
enum MessageMarkdownParser {
    /// Parses a raw Markdown document into ordered visual blocks.
    static func parseBlocks(from rawText: String) -> [MarkdownBlock] {
        let normalized = rawText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")

        var blocks: [MarkdownBlock] = []
        var paragraphLines: [String] = []
        var blockquoteLines: [String] = []

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            let joined = paragraphLines.joined(separator: "\n")
            if !joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                blocks.append(.paragraph(text: joined))
            }
            paragraphLines.removeAll(keepingCapacity: true)
        }

        func flushBlockquote() {
            guard !blockquoteLines.isEmpty else { return }
            let joined = blockquoteLines.joined(separator: "\n")
            blocks.append(.blockquote(text: joined))
            blockquoteLines.removeAll(keepingCapacity: true)
        }

        var index = 0
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // 1. Fenced code block (``` or ~~~, optionally indented inside a list)
            if let fence = parseCodeFenceOpening(from: line) {
                flushParagraph()
                flushBlockquote()
                var codeLines: [String] = []
                index += 1
                while index < lines.count {
                    let candidate = lines[index]
                    if isCodeFenceClosing(candidate, marker: fence.marker, minCount: fence.count) {
                        index += 1
                        break
                    }
                    codeLines.append(stripLeadingIndentation(candidate, maxSpaces: fence.indent))
                    index += 1
                }
                blocks.append(.codeBlock(language: fence.language, code: codeLines.joined(separator: "\n")))
                continue
            }

            // 2. Empty line ends current paragraph or blockquote
            if trimmed.isEmpty {
                flushParagraph()
                flushBlockquote()
                index += 1
                continue
            }

            // 3. Horizontal rule (---, ***, ___)
            if isHorizontalRule(trimmed) {
                flushParagraph()
                flushBlockquote()
                blocks.append(.horizontalRule)
                index += 1
                continue
            }

            // 4. ATX Heading (# to ######)
            if let heading = parseHeading(from: trimmed) {
                flushParagraph()
                flushBlockquote()
                blocks.append(.heading(level: heading.level, text: heading.text))
                index += 1
                continue
            }

            // 5. Pipe Table (header row + separator row `| --- | --- |`)
            if index + 1 < lines.count,
               isTableRow(trimmed),
               isTableSeparatorRow(lines[index + 1].trimmingCharacters(in: .whitespaces)) {
                flushParagraph()
                flushBlockquote()
                let headers = parseTableCells(from: trimmed)
                var rows: [[String]] = []
                index += 2
                while index < lines.count {
                    let rowTrimmed = lines[index].trimmingCharacters(in: .whitespaces)
                    guard isTableRow(rowTrimmed), !isTableSeparatorRow(rowTrimmed) else { break }
                    rows.append(parseTableCells(from: rowTrimmed))
                    index += 1
                }
                blocks.append(.table(headers: headers, rows: rows))
                continue
            }

            // 6. Blockquote (> ...)
            if let quoted = parseBlockquoteLine(from: trimmed) {
                flushParagraph()
                blockquoteLines.append(quoted)
                index += 1
                continue
            } else {
                flushBlockquote()
            }

            // 7. Unordered or Ordered List Item
            if let listItem = parseListItem(from: line) {
                flushParagraph()
                blocks.append(listItem)
                index += 1
                continue
            }

            // 8. Regular paragraph line
            paragraphLines.append(line)
            index += 1
        }

        flushParagraph()
        flushBlockquote()
        return blocks
    }

    /// Parses inline Markdown into an `AttributedString` for rich display.
    /// - External `http://` and `https://` links remain clickable in the default browser.
    /// - Non-HTTP links (such as `file://` or relative workspace paths) are unwrapped to their readable label.
    /// - CJK bold spans (`**...**`) that CommonMark's strict flanking rule skips are promoted to bold.
    static func inlineAttributedString(from rawInline: String, styleCodeBackground: Bool = true) -> AttributedString {
        let sanitized = sanitizeMarkdownLinks(in: rawInline)
        var attributed: AttributedString
        if let parsed = try? AttributedString(
            markdown: sanitized,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) {
            attributed = parsed
        } else {
            attributed = AttributedString(sanitized)
        }

        applyRemainingBoldSpans(in: &attributed)
        sanitizeLinksAndStyleInlineCode(in: &attributed, styleCodeBackground: styleCodeBackground)
        return attributed
    }

    /// Produces a compact inline `AttributedString` for the 2-line message list preview,
    /// stripping block-level syntax (`###`, fences, `---`, list markers) and links while preserving inline bold & code.
    static func summaryAttributedString(from rawText: String) -> AttributedString {
        let collapsed = collapseBlockSyntaxForSummary(from: rawText)
        var attributed = inlineAttributedString(from: collapsed, styleCodeBackground: false)
        for run in attributed.runs where run.link != nil {
            attributed[run.range].link = nil
        }
        return attributed
    }

    /// Produces a clean plain-text summary (for 1-line fallback titles, dialogs, and system banners)
    /// with all Markdown block markers, `**` delimiters, backticks, and `file://` URLs removed.
    static func plainTextSummary(from rawText: String) -> String {
        let truncatedInput = rawText.count > 600 ? String(rawText.prefix(600)) : rawText
        let summaryAttr = summaryAttributedString(from: truncatedInput)
        let rendered = String(summaryAttr.characters)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return rendered.isEmpty ? rawText.trimmingCharacters(in: .whitespacesAndNewlines) : rendered
    }

    /// Produces a compact plain-text 2-line preview for `MessageRowContent` so `NSTableView` on macOS 12
    /// uses fast `Text(String)` layout instead of bridging `AttributedString` per row.
    static func listRowSummaryText(from rawText: String) -> String {
        let truncatedInput = rawText.count > 600 ? String(rawText.prefix(600)) : rawText
        let summaryAttr = summaryAttributedString(from: truncatedInput)
        let rendered = String(summaryAttr.characters)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if rendered.isEmpty {
            let fallback = truncatedInput.trimmingCharacters(in: .whitespacesAndNewlines)
            return fallback.count > 240 ? String(fallback.prefix(240)) : fallback
        }
        return rendered.count > 240 ? String(rendered.prefix(240)) : rendered
    }

    // MARK: - Link Sanitization & Inline Post-Processing

    /// Unwraps `[label](target)` to `label` unless `target` is an external `http://` or `https://` URL,
    /// and percent-encodes valid HTTP/HTTPS URLs if needed so `AttributedString(markdown:)` never dumps raw URLs.
    static func sanitizeMarkdownLinks(in text: String) -> String {
        let chars = Array(text)
        let count = chars.count
        var result = String()
        result.reserveCapacity(count)

        var i = 0
        while i < count {
            // Preserve inline code spans starting outside of a link label
            if chars[i] == "`" {
                let tickStart = i
                while i < count && chars[i] == "`" { i += 1 }
                let tickLen = i - tickStart
                result.append(contentsOf: chars[tickStart..<i])

                while i < count {
                    if chars[i] == "`" {
                        let closeStart = i
                        while i < count && chars[i] == "`" { i += 1 }
                        result.append(contentsOf: chars[closeStart..<i])
                        if i - closeStart == tickLen { break }
                    } else {
                        result.append(chars[i])
                        i += 1
                    }
                }
                continue
            }

            // Escaped character
            if chars[i] == "\\", i + 1 < count {
                result.append(chars[i])
                result.append(chars[i + 1])
                i += 2
                continue
            }

            // Image prefix `![alt](url)` -> treat like link label
            let isImage = chars[i] == "!" && (i + 1 < count && chars[i + 1] == "[")
            let bracketStart = isImage ? i + 1 : i

            if chars[bracketStart] == "[",
               let match = matchMarkdownLink(in: chars, from: bracketStart) {
                let label = String(chars[match.labelRange])
                let rawTarget = String(chars[match.targetRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                let urlPart = rawTarget.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? ""

                if !isImage, let validWebURL = validatedExternalWebURLString(from: urlPart) {
                    result.append("[")
                    result.append(label)
                    result.append("](")
                    result.append(validWebURL)
                    result.append(")")
                } else {
                    result.append(label)
                }
                i = match.nextIndex
                continue
            }

            result.append(chars[i])
            i += 1
        }

        return result
    }

    private struct LinkMatch {
        let labelRange: Range<Int>
        let targetRange: Range<Int>
        let nextIndex: Int
    }

    private static func matchMarkdownLink(in chars: [Character], from bracketStart: Int) -> LinkMatch? {
        let count = chars.count
        var i = bracketStart + 1
        var bracketDepth = 1

        while i < count {
            let ch = chars[i]
            if ch == "\n" { return nil }
            if ch == "\\", i + 1 < count {
                i += 2
                continue
            }
            // Skip over inline code spans inside the link label (e.g. [`file.swift`](file:///...))
            if ch == "`" {
                let tickStart = i
                while i < count && chars[i] == "`" { i += 1 }
                let tickLen = i - tickStart
                while i < count {
                    if chars[i] == "`" {
                        let closeStart = i
                        while i < count && chars[i] == "`" { i += 1 }
                        if i - closeStart == tickLen { break }
                    } else if chars[i] == "\n" {
                        return nil
                    } else {
                        i += 1
                    }
                }
                continue
            }
            if ch == "[" {
                bracketDepth += 1
            } else if ch == "]" {
                bracketDepth -= 1
                if bracketDepth == 0 { break }
            }
            i += 1
        }

        guard i < count, chars[i] == "]", i + 1 < count, chars[i + 1] == "(" else {
            return nil
        }

        let labelRange = (bracketStart + 1)..<i
        let targetStart = i + 2
        var j = targetStart
        var parenDepth = 1

        while j < count {
            let ch = chars[j]
            if ch == "\n" { return nil }
            if ch == "\\", j + 1 < count {
                j += 2
                continue
            }
            if ch == "(" {
                parenDepth += 1
            } else if ch == ")" {
                parenDepth -= 1
                if parenDepth == 0 {
                    return LinkMatch(
                        labelRange: labelRange,
                        targetRange: targetStart..<j,
                        nextIndex: j + 1
                    )
                }
            }
            j += 1
        }

        return nil
    }

    private static func validatedExternalWebURLString(from candidate: String) -> String? {
        let unwrapped: String
        if candidate.hasPrefix("<") && candidate.hasSuffix(">") && candidate.count > 2 {
            unwrapped = String(candidate.dropFirst().dropLast())
        } else {
            unwrapped = candidate
        }
        let lower = unwrapped.lowercased()
        guard lower.hasPrefix("http://") || lower.hasPrefix("https://") else {
            return nil
        }
        if let url = URL(string: unwrapped), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            return unwrapped
        }
        if let encoded = unwrapped.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: encoded),
           let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            return encoded
        }
        return nil
    }

    /// Converts any remaining literal `**...**` pairs outside inline code into `.stronglyEmphasized` runs.
    /// CommonMark rejects `**` when adjacent to CJK punctuation on one side and CJK ideographs on the other
    /// (for example `都是**“唯一”**` or `**注意：**请检查` or `**Antigravity (`a.sh`)**：`).
    private static func applyRemainingBoldSpans(in attributed: inout AttributedString) {
        while let (openRange, closeRange) = findNextUnparsedBoldPair(in: attributed) {
            let innerRange = openRange.upperBound..<closeRange.lowerBound
            for run in attributed[innerRange].runs {
                let clampedRange = run.range.clamped(to: innerRange)
                let existing = run.inlinePresentationIntent ?? []
                attributed[clampedRange].inlinePresentationIntent = existing.union(.stronglyEmphasized)
            }
            attributed.removeSubrange(closeRange)
            attributed.removeSubrange(openRange)
        }
    }

    private static func findNextUnparsedBoldPair(
        in attributed: AttributedString
    ) -> (Range<AttributedString.Index>, Range<AttributedString.Index>)? {
        var openRange: Range<AttributedString.Index>?

        for run in attributed.runs {
            if run.inlinePresentationIntent?.contains(.code) == true {
                continue
            }
            let runSlice = attributed[run.range].characters
            var idx = runSlice.startIndex
            while idx < runSlice.endIndex {
                let nextIdx = runSlice.index(after: idx)
                if runSlice[idx] == "*", nextIdx < runSlice.endIndex, runSlice[nextIdx] == "*" {
                    let afterSecond = runSlice.index(after: nextIdx)
                    let candidateRange = idx..<afterSecond
                    if let currentOpen = openRange {
                        if currentOpen.upperBound < candidateRange.lowerBound {
                            return (currentOpen, candidateRange)
                        } else {
                            // Empty `****`, advance past it
                            openRange = nil
                        }
                    } else {
                        openRange = candidateRange
                    }
                    idx = afterSecond
                } else {
                    idx = nextIdx
                }
            }
        }
        return nil
    }

    private static func sanitizeLinksAndStyleInlineCode(
        in attributed: inout AttributedString,
        styleCodeBackground: Bool
    ) {
        for run in attributed.runs {
            if let link = run.link {
                let scheme = link.scheme?.lowercased() ?? ""
                if scheme != "http" && scheme != "https" {
                    attributed[run.range].link = nil
                }
            }
            if styleCodeBackground, run.inlinePresentationIntent?.contains(.code) == true {
                attributed[run.range].backgroundColor = Color.secondary.opacity(0.14)
            }
        }
    }

    // MARK: - Block Parsing Helpers

    private struct CodeFenceOpening {
        let indent: Int
        let marker: Character
        let count: Int
        let language: String?
    }

    private static func parseCodeFenceOpening(from line: String) -> CodeFenceOpening? {
        let indent = line.prefix(while: { $0 == " " || $0 == "\t" }).count
        let trimmed = line.dropFirst(indent)
        guard let first = trimmed.first, first == "`" || first == "~" else { return nil }
        let fenceChars = trimmed.prefix(while: { $0 == first })
        guard fenceChars.count >= 3 else { return nil }
        let rest = trimmed.dropFirst(fenceChars.count).trimmingCharacters(in: .whitespaces)
        // A single-line ` ```code``` ` has closing backticks on the same line, which is inline code, not a fence.
        if first == "`" && rest.contains("`") {
            return nil
        }
        let language = rest.isEmpty ? nil : String(rest.split(separator: " ").first ?? Substring(rest))
        return CodeFenceOpening(indent: indent, marker: first, count: fenceChars.count, language: language)
    }

    private static func isCodeFenceClosing(_ line: String, marker: Character, minCount: Int) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        let fenceChars = trimmed.prefix(while: { $0 == marker })
        guard fenceChars.count >= minCount else { return false }
        return trimmed.dropFirst(fenceChars.count).trimmingCharacters(in: .whitespaces).isEmpty
    }

    private static func stripLeadingIndentation(_ line: String, maxSpaces: Int) -> String {
        guard maxSpaces > 0 else { return line }
        var removed = 0
        var idx = line.startIndex
        while idx < line.endIndex, removed < maxSpaces {
            if line[idx] == " " {
                removed += 1
                idx = line.index(after: idx)
            } else if line[idx] == "\t" {
                removed += min(4, maxSpaces - removed)
                idx = line.index(after: idx)
            } else {
                break
            }
        }
        return String(line[idx...])
    }

    private static func isHorizontalRule(_ trimmed: String) -> Bool {
        let compact = trimmed.filter { !$0.isWhitespace }
        guard compact.count >= 3, let first = compact.first else { return false }
        guard first == "-" || first == "*" || first == "_" else { return false }
        return compact.allSatisfy { $0 == first }
    }

    private static func parseHeading(from trimmed: String) -> (level: Int, text: String)? {
        let hashes = trimmed.prefix(while: { $0 == "#" })
        guard (1...6).contains(hashes.count) else { return nil }
        let remainder = trimmed.dropFirst(hashes.count)
        guard remainder.first == " " || remainder.first == "\t" else { return nil }
        let headingText = remainder.trimmingCharacters(in: .whitespaces)
        guard !headingText.isEmpty else { return nil }
        return (hashes.count, headingText)
    }

    private static func parseBlockquoteLine(from trimmed: String) -> String? {
        guard trimmed.hasPrefix(">") else { return nil }
        let remainder = trimmed.dropFirst()
        if remainder.hasPrefix(" ") {
            return String(remainder.dropFirst())
        }
        return String(remainder)
    }

    private static func parseListItem(from line: String) -> MarkdownBlock? {
        var spaceCount = 0
        var idx = line.startIndex
        while idx < line.endIndex {
            if line[idx] == " " {
                spaceCount += 1
            } else if line[idx] == "\t" {
                spaceCount += 4
            } else {
                break
            }
            idx = line.index(after: idx)
        }
        let indentLevel = min(spaceCount / 2, 4)
        let remainder = line[idx...]

        // Unordered list: `- `, `* `, `+ `
        if let first = remainder.first, (first == "-" || first == "*" || first == "+") {
            let afterMarker = remainder.dropFirst()
            if afterMarker.first == " " || afterMarker.first == "\t" {
                let itemText = afterMarker.trimmingCharacters(in: .whitespaces)
                if !itemText.isEmpty {
                    return .unorderedListItem(indent: indentLevel, text: itemText)
                }
            }
        }

        // Ordered list: `1. ` or `1) `
        let digits = remainder.prefix(while: \.isWholeNumber)
        if !digits.isEmpty, digits.count <= 9 {
            let afterDigits = remainder.dropFirst(digits.count)
            if let delimiter = afterDigits.first, (delimiter == "." || delimiter == ")") {
                let afterDelimiter = afterDigits.dropFirst()
                if afterDelimiter.first == " " || afterDelimiter.first == "\t" {
                    let itemText = afterDelimiter.trimmingCharacters(in: .whitespaces)
                    if !itemText.isEmpty {
                        return .orderedListItem(
                            indent: indentLevel,
                            marker: "\(digits)\(delimiter)",
                            text: itemText
                        )
                    }
                }
            }
        }

        return nil
    }

    private static func isTableRow(_ trimmed: String) -> Bool {
        trimmed.hasPrefix("|") && trimmed.hasSuffix("|") && trimmed.count >= 3
    }

    private static func isTableSeparatorRow(_ trimmed: String) -> Bool {
        guard isTableRow(trimmed) else { return false }
        let cells = parseTableCells(from: trimmed)
        guard !cells.isEmpty else { return false }
        return cells.allSatisfy { cell in
            let cleaned = cell.trimmingCharacters(in: .whitespaces)
            guard !cleaned.isEmpty else { return false }
            let withoutColons = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            return withoutColons.count >= 3 && withoutColons.allSatisfy { $0 == "-" }
        }
    }

    private static func parseTableCells(from trimmedRow: String) -> [String] {
        var inner = trimmedRow
        if inner.hasPrefix("|") { inner.removeFirst() }
        if inner.hasSuffix("|") { inner.removeLast() }
        return inner
            .components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func collapseBlockSyntaxForSummary(from rawText: String) -> String {
        let blocks = parseBlocks(from: rawText)
        var summaryLines: [String] = []
        summaryLines.reserveCapacity(min(blocks.count, 4))

        for block in blocks {
            switch block {
            case let .heading(_, text):
                summaryLines.append(text)
            case let .paragraph(text):
                summaryLines.append(text)
            case let .unorderedListItem(_, text):
                summaryLines.append("• \(text)")
            case let .orderedListItem(_, marker, text):
                summaryLines.append("\(marker) \(text)")
            case let .blockquote(text):
                summaryLines.append(text)
            case let .codeBlock(_, code):
                let firstCodeLine = code
                    .split(separator: "\n", omittingEmptySubsequences: true)
                    .first
                    .map(String.init) ?? ""
                if !firstCodeLine.isEmpty {
                    summaryLines.append("`\(firstCodeLine)`")
                }
            case let .table(headers, rows):
                let firstRow = rows.first ?? headers
                if !firstRow.isEmpty {
                    summaryLines.append(firstRow.joined(separator: " · "))
                }
            case .horizontalRule:
                continue
            }
            if summaryLines.count >= 4 {
                break
            }
        }

        return summaryLines.joined(separator: "\n")
    }
}

/// Renders a Gotify message body with native SwiftUI typography, code blocks, lists, quotes, tables, and dividers.
struct MessageMarkdownView: View {
    let text: String
    @Environment(\.openURL) private var openURL

    var body: some View {
        let blocks = MessageMarkdownParser.parseBlocks(from: text)
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(for: block)
            }
        }
        .environment(\.openURL, OpenURLAction { url in
            guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
                return .discarded
            }
            NSWorkspace.shared.open(url)
            return .handled
        })
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(for block: MarkdownBlock) -> some View {
        switch block {
        case let .heading(level, headingText):
            Text(MessageMarkdownParser.inlineAttributedString(from: headingText))
                .font(headingFont(for: level))
                .textSelection(.enabled)
                .padding(.top, level <= 2 ? 4 : 2)
                .frame(maxWidth: .infinity, alignment: .leading)

        case let .paragraph(paragraphText):
            Text(MessageMarkdownParser.inlineAttributedString(from: paragraphText))
                .font(.body)
                .lineSpacing(3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

        case let .unorderedListItem(indent, itemText):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(bulletSymbol(for: indent))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(MessageMarkdownParser.inlineAttributedString(from: itemText))
                    .font(.body)
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, CGFloat(indent) * 16)

        case let .orderedListItem(indent, marker, itemText):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(marker)
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(MessageMarkdownParser.inlineAttributedString(from: itemText))
                    .font(.body)
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, CGFloat(indent) * 16)

        case let .blockquote(quoteText):
            Text(MessageMarkdownParser.inlineAttributedString(from: quoteText))
                .font(.body)
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .textSelection(.enabled)
                .padding(.leading, 13)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(Color.secondary.opacity(0.45))
                        .frame(width: 3)
                }
                .padding(.vertical, 2)

        case let .codeBlock(language, code):
            VStack(alignment: .leading, spacing: 6) {
                if let language, !language.isEmpty {
                    Text(language)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Text(verbatim: code)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )

        case let .table(headers, rows):
            VStack(alignment: .leading, spacing: 0) {
                tableRowView(cells: headers, isHeader: true)
                Divider()
                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                    tableRowView(cells: row, isHeader: false)
                    if rowIndex + 1 < rows.count {
                        Divider()
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )

        case .horizontalRule:
            Divider()
                .padding(.vertical, 4)
        }
    }

    private func tableRowView(cells: [String], isHeader: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                Text(MessageMarkdownParser.inlineAttributedString(from: cell))
                    .font(isHeader ? .subheadline.weight(.semibold) : .subheadline)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func headingFont(for level: Int) -> Font {
        switch level {
        case 1:
            return .title2.weight(.bold)
        case 2:
            return .title3.weight(.semibold)
        case 3:
            return .headline.weight(.semibold)
        default:
            return .subheadline.weight(.semibold)
        }
    }

    private func bulletSymbol(for indent: Int) -> String {
        switch indent {
        case 0:
            return "•"
        case 1:
            return "◦"
        default:
            return "▪"
        }
    }
}
