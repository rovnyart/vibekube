import AppKit
import SwiftUI

struct AIMarkdownView: View {
    let text: String
    var isStreaming = false

    private var blocks: [AIMarkdownBlock] {
        AIMarkdownParser.parse(text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(blocks) { block in
                view(for: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func view(for block: AIMarkdownBlock) -> some View {
        switch block.kind {
        case .heading(let level, let text):
            Text(inlineMarkdown(text))
                .font(headingFont(level))
                .foregroundStyle(.primary)
                .padding(.top, level == 1 ? 4 : 2)

        case .paragraph(let text):
            Text(inlineMarkdown(text))
                .font(.callout)
                .lineSpacing(3)
                .foregroundStyle(.primary)

        case .unorderedList(let items):
            VStack(alignment: .leading, spacing: 7) {
                ForEach(items.indices, id: \.self) { index in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle()
                            .fill(Color.accentColor.opacity(0.75))
                            .frame(width: 5, height: 5)
                        Text(inlineMarkdown(items[index]))
                            .font(.callout)
                            .lineSpacing(3)
                    }
                }
            }

        case .orderedList(let items):
            VStack(alignment: .leading, spacing: 7) {
                ForEach(items.indices, id: \.self) { index in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(index + 1).")
                            .font(.callout.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, alignment: .trailing)
                        Text(inlineMarkdown(items[index]))
                            .font(.callout)
                            .lineSpacing(3)
                    }
                }
            }

        case .quote(let text):
            HStack(alignment: .top, spacing: 10) {
                Capsule()
                    .fill(Color.accentColor.opacity(0.42))
                    .frame(width: 3)
                Text(inlineMarkdown(text))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
            }
            .padding(.vertical, 4)

        case .code(let language, let code):
            AICodeBlockView(language: language, code: code)

        case .divider:
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.45))
                .frame(height: 1)
                .padding(.vertical, 4)
        }
    }

    private func inlineMarkdown(_ text: String) -> AttributedString {
        if let attributed = try? AttributedString(markdown: text) {
            return attributed
        }
        return AttributedString(text)
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1:
            .title3.weight(.semibold)
        case 2:
            .headline.weight(.semibold)
        default:
            .subheadline.weight(.semibold)
        }
    }
}

struct AICodeBlockView: View {
    let language: String?
    let code: String
    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Label(languageTitle, systemImage: "chevron.left.forwardslash.chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)

                Spacer()

                Button {
                    copy(code)
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.thinMaterial)

            ScrollView(.horizontal) {
                Text(highlightedCode)
                    .font(.system(size: 12, design: .monospaced))
                    .lineSpacing(2)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .background(Color(nsColor: .textBackgroundColor).opacity(0.74))
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.28))
        }
    }

    private var languageTitle: String {
        let title = language?.trimmingCharacters(in: .whitespacesAndNewlines)
        return title?.isEmpty == false ? title!.uppercased() : "CODE"
    }

    private var highlightedCode: AttributedString {
        AttributedString(AICodeHighlighter.highlight(code, language: language))
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            await MainActor.run {
                copied = false
            }
        }
    }
}

private struct AIMarkdownBlock: Identifiable {
    enum Kind {
        case heading(Int, String)
        case paragraph(String)
        case unorderedList([String])
        case orderedList([String])
        case quote(String)
        case code(String?, String)
        case divider
    }

    var id = UUID()
    var kind: Kind
}

private enum AIMarkdownParser {
    static func parse(_ text: String) -> [AIMarkdownBlock] {
        var blocks: [AIMarkdownBlock] = []
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                index += 1
                continue
            }

            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                let fence = String(trimmed.prefix(3))
                let language = trimmed.dropFirst(3).trimmingCharacters(in: .whitespacesAndNewlines)
                index += 1
                var codeLines: [String] = []
                while index < lines.count {
                    let next = lines[index]
                    if next.trimmingCharacters(in: .whitespaces).hasPrefix(fence) {
                        index += 1
                        break
                    }
                    codeLines.append(next)
                    index += 1
                }
                blocks.append(AIMarkdownBlock(kind: .code(language.isEmpty ? nil : language, codeLines.joined(separator: "\n"))))
                continue
            }

            if trimmed == "---" || trimmed == "***" {
                blocks.append(AIMarkdownBlock(kind: .divider))
                index += 1
                continue
            }

            if let heading = heading(in: trimmed) {
                blocks.append(AIMarkdownBlock(kind: .heading(heading.level, heading.text)))
                index += 1
                continue
            }

            if isUnorderedListLine(trimmed) {
                var items: [String] = []
                while index < lines.count {
                    let item = lines[index].trimmingCharacters(in: .whitespaces)
                    guard isUnorderedListLine(item) else {
                        break
                    }
                    items.append(String(item.dropFirst(2)).trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                blocks.append(AIMarkdownBlock(kind: .unorderedList(items)))
                continue
            }

            if let ordered = orderedItem(in: trimmed) {
                var items = [ordered]
                index += 1
                while index < lines.count,
                      let item = orderedItem(in: lines[index].trimmingCharacters(in: .whitespaces)) {
                    items.append(item)
                    index += 1
                }
                blocks.append(AIMarkdownBlock(kind: .orderedList(items)))
                continue
            }

            if trimmed.hasPrefix(">") {
                var quoteLines: [String] = []
                while index < lines.count {
                    let quote = lines[index].trimmingCharacters(in: .whitespaces)
                    guard quote.hasPrefix(">") else {
                        break
                    }
                    quoteLines.append(String(quote.dropFirst()).trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                blocks.append(AIMarkdownBlock(kind: .quote(quoteLines.joined(separator: "\n"))))
                continue
            }

            var paragraphLines = [trimmed]
            index += 1
            while index < lines.count {
                let next = lines[index].trimmingCharacters(in: .whitespaces)
                guard !next.isEmpty,
                      !next.hasPrefix("```"),
                      !next.hasPrefix("~~~"),
                      heading(in: next) == nil,
                      !isUnorderedListLine(next),
                      orderedItem(in: next) == nil,
                      !next.hasPrefix(">"),
                      next != "---",
                      next != "***" else {
                    break
                }
                paragraphLines.append(next)
                index += 1
            }
            blocks.append(AIMarkdownBlock(kind: .paragraph(paragraphLines.joined(separator: "\n"))))
        }

        return blocks
    }

    private static func heading(in line: String) -> (level: Int, text: String)? {
        let markerCount = line.prefix { $0 == "#" }.count
        guard markerCount > 0,
              markerCount <= 3,
              line.dropFirst(markerCount).first == " " else {
            return nil
        }
        return (markerCount, String(line.dropFirst(markerCount + 1)))
    }

    private static func isUnorderedListLine(_ line: String) -> Bool {
        line.hasPrefix("- ") || line.hasPrefix("* ")
    }

    private static func orderedItem(in line: String) -> String? {
        guard let dotIndex = line.firstIndex(of: ".") else {
            return nil
        }
        let prefix = line[..<dotIndex]
        guard !prefix.isEmpty,
              prefix.allSatisfy(\.isNumber),
              line.index(after: dotIndex) < line.endIndex,
              line[line.index(after: dotIndex)] == " " else {
            return nil
        }
        return String(line[line.index(dotIndex, offsetBy: 2)...])
    }
}

private enum AICodeHighlighter {
    static func highlight(_ code: String, language: String?) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byClipping

        let result = NSMutableAttributedString(
            string: code,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraphStyle
            ]
        )

        let normalizedLanguage = language?.lowercased() ?? ""
        if normalizedLanguage.contains("yaml") || normalizedLanguage.contains("yml") {
            highlightYAML(result, code: code)
        } else if normalizedLanguage.contains("json") {
            highlightJSON(result, code: code)
        } else if normalizedLanguage.contains("sh") || normalizedLanguage.contains("bash") || normalizedLanguage.contains("shell") {
            highlightShell(result, code: code)
        } else {
            highlightGeneric(result, code: code)
        }

        return result
    }

    private static func highlightYAML(_ result: NSMutableAttributedString, code: String) {
        apply(#"(?m)^(\s*-?\s*)?([A-Za-z0-9_.\/-]+)(?=\s*:)"#, to: result, code: code, color: .systemCyan, weight: .semibold)
        apply(#"\b(?:true|false|null)\b"#, to: result, code: code, color: .systemOrange)
        apply(#"(?<![\w.])-?\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b"#, to: result, code: code, color: .systemPurple)
        apply(#""(?:\\.|[^"\\])*""#, to: result, code: code, color: .systemGreen)
        apply(#"<redacted>|<truncated[^>]*>"#, to: result, code: code, color: .systemRed, weight: .semibold)
    }

    private static func highlightJSON(_ result: NSMutableAttributedString, code: String) {
        apply(#""(?:\\.|[^"\\])*"(?=\s*:)"#, to: result, code: code, color: .controlAccentColor, weight: .semibold)
        apply(#""(?:\\.|[^"\\])*""#, to: result, code: code, color: .systemGreen)
        apply(#"\b(?:true|false|null)\b"#, to: result, code: code, color: .systemOrange)
        apply(#"(?<![\w.])-?\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b"#, to: result, code: code, color: .systemPurple)
    }

    private static func highlightShell(_ result: NSMutableAttributedString, code: String) {
        apply(#"\b(?:kubectl|helm|stern|grep|awk|sed|jq|yq|curl)\b"#, to: result, code: code, color: .controlAccentColor, weight: .semibold)
        apply(#"--[A-Za-z0-9-]+"#, to: result, code: code, color: .systemPurple)
        apply(#""(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'"#, to: result, code: code, color: .systemGreen)
        apply(#"(?m)#.*$"#, to: result, code: code, color: .secondaryLabelColor)
    }

    private static func highlightGeneric(_ result: NSMutableAttributedString, code: String) {
        apply(#"\b(?:apiVersion|kind|metadata|spec|status|containers|image|name|namespace|selector|labels|annotations)\b"#, to: result, code: code, color: .controlAccentColor, weight: .semibold)
        apply(#""(?:\\.|[^"\\])*""#, to: result, code: code, color: .systemGreen)
        apply(#"`[^`]+`"#, to: result, code: code, color: .systemOrange)
    }

    private static func apply(
        _ pattern: String,
        to result: NSMutableAttributedString,
        code: String,
        color: NSColor,
        weight: NSFont.Weight = .regular
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return
        }
        let range = NSRange(location: 0, length: (code as NSString).length)
        regex.enumerateMatches(in: code, range: range) { match, _, _ in
            guard let matchRange = match?.range else {
                return
            }
            result.addAttributes(
                [
                    .foregroundColor: color,
                    .font: NSFont.monospacedSystemFont(ofSize: 12, weight: weight)
                ],
                range: matchRange
            )
        }
    }
}
