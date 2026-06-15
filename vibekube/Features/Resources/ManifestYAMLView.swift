import AppKit
import SwiftUI

struct ManifestYAMLView: View {
    @State private var searchText = ""
    @State private var selectedMatchIndex = 0
    @State private var copiedToClipboard = false

    let yaml: String

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            Divider()

            ScrollViewReader { proxy in
                ScrollView([.vertical, .horizontal]) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                            ManifestYAMLLineView(
                                lineNumber: index + 1,
                                lineNumberWidth: lineNumberWidth,
                                text: line,
                                matches: matchesByLine[index + 1] ?? [],
                                selectedMatchOrdinal: selectedMatch?.ordinal
                            )
                            .id(index + 1)
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.trailing, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .onChange(of: selectedMatch?.id) {
                    scrollToSelectedMatch(with: proxy)
                }
                .onAppear {
                    scrollToSelectedMatch(with: proxy)
                }
            }
        }
        .onChange(of: yaml) {
            searchText = ""
            selectedMatchIndex = 0
            copiedToClipboard = false
        }
        .onChange(of: searchText) {
            selectedMatchIndex = 0
        }
        .onChange(of: matches.count) { _, count in
            if selectedMatchIndex >= count {
                selectedMatchIndex = max(0, count - 1)
            }
        }
        .accessibilityIdentifier("resource.detail.yaml")
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Find", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 120, idealWidth: 160, maxWidth: 220)
                .accessibilityIdentifier("resource.detail.yaml.search")

            Text(matchSummary)
                .font(.caption.monospacedDigit())
                .foregroundStyle(matches.isEmpty ? .tertiary : .secondary)
                .frame(minWidth: 48, alignment: .trailing)

            Button {
                selectPreviousMatch()
            } label: {
                Label("Previous Match", systemImage: "chevron.up")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.bordered)
            .disabled(matches.isEmpty)
            .help("Previous Match")
            .accessibilityIdentifier("resource.detail.yaml.previousMatch")

            Button {
                selectNextMatch()
            } label: {
                Label("Next Match", systemImage: "chevron.down")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.bordered)
            .disabled(matches.isEmpty)
            .help("Next Match")
            .accessibilityIdentifier("resource.detail.yaml.nextMatch")

            Divider()
                .frame(height: 18)

            Button {
                copyYAML()
            } label: {
                Label(copiedToClipboard ? "Copied" : "Copy YAML", systemImage: copiedToClipboard ? "checkmark" : "doc.on.doc")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.bordered)
            .help(copiedToClipboard ? "Copied" : "Copy YAML")
            .accessibilityIdentifier("resource.detail.yaml.copy")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var lines: [String] {
        guard !displayYAML.isEmpty else {
            return [""]
        }

        return displayYAML.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    private var displayYAML: String {
        yaml.trimmingTrailingNewlines()
    }

    private var lineNumberWidth: CGFloat {
        max(34, CGFloat(String(lines.count).count) * 8 + 16)
    }

    private var matches: [ManifestSearchMatch] {
        ManifestSearchIndex.matches(in: displayYAML, query: searchText)
    }

    private var matchesByLine: [Int: [ManifestSearchMatch]] {
        Dictionary(grouping: matches, by: \.lineNumber)
    }

    private var selectedMatch: ManifestSearchMatch? {
        guard matches.indices.contains(selectedMatchIndex) else {
            return nil
        }

        return matches[selectedMatchIndex]
    }

    private var matchSummary: String {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return ""
        }

        guard !matches.isEmpty else {
            return "0/0"
        }

        return "\(selectedMatchIndex + 1)/\(matches.count)"
    }

    private func selectPreviousMatch() {
        guard !matches.isEmpty else {
            return
        }

        selectedMatchIndex = selectedMatchIndex == 0 ? matches.count - 1 : selectedMatchIndex - 1
    }

    private func selectNextMatch() {
        guard !matches.isEmpty else {
            return
        }

        selectedMatchIndex = selectedMatchIndex == matches.count - 1 ? 0 : selectedMatchIndex + 1
    }

    private func copyYAML() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(yaml, forType: .string)
        copiedToClipboard = true

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            copiedToClipboard = false
        }
    }

    private func scrollToSelectedMatch(with proxy: ScrollViewProxy) {
        guard let selectedMatch else {
            return
        }

        withAnimation(.easeInOut(duration: 0.16)) {
            proxy.scrollTo(selectedMatch.lineNumber, anchor: .center)
        }
    }
}

struct ManifestSearchMatch: Identifiable, Equatable {
    var lineNumber: Int
    var lowerBound: Int
    var length: Int
    var ordinal: Int

    var id: String {
        "\(lineNumber):\(lowerBound):\(length):\(ordinal)"
    }
}

enum ManifestSearchIndex {
    static func matches(in text: String, query: String) -> [ManifestSearchMatch] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else {
            return []
        }

        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var matches: [ManifestSearchMatch] = []
        var ordinal = 0

        for (lineIndex, line) in lines.enumerated() {
            var searchRange = line.startIndex..<line.endIndex
            while let range = line.range(
                of: needle,
                options: [.caseInsensitive, .diacriticInsensitive],
                range: searchRange
            ) {
                ordinal += 1
                matches.append(
                    ManifestSearchMatch(
                        lineNumber: lineIndex + 1,
                        lowerBound: line.distance(from: line.startIndex, to: range.lowerBound),
                        length: line.distance(from: range.lowerBound, to: range.upperBound),
                        ordinal: ordinal
                    )
                )

                guard range.upperBound < line.endIndex else {
                    break
                }
                searchRange = range.upperBound..<line.endIndex
            }
        }

        return matches
    }
}

private struct ManifestYAMLLineView: View {
    let lineNumber: Int
    let lineNumberWidth: CGFloat
    let text: String
    let matches: [ManifestSearchMatch]
    let selectedMatchOrdinal: Int?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(lineNumber)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: lineNumberWidth, alignment: .trailing)
                .textSelection(.disabled)

            Text(
                ManifestYAMLHighlighter.attributedLine(
                    text,
                    matches: matches,
                    selectedMatchOrdinal: selectedMatchOrdinal
                )
            )
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 1)
        .background(lineContainsSelectedMatch ? Color.accentColor.opacity(0.08) : Color.clear)
    }

    private var lineContainsSelectedMatch: Bool {
        guard let selectedMatchOrdinal else {
            return false
        }

        return matches.contains { $0.ordinal == selectedMatchOrdinal }
    }
}

private enum ManifestYAMLHighlighter {
    static func attributedLine(
        _ line: String,
        matches: [ManifestSearchMatch],
        selectedMatchOrdinal: Int?
    ) -> AttributedString {
        var attributed = AttributedString(line.isEmpty ? " " : line)
        attributed.foregroundColor = .primary
        applySyntax(to: &attributed, source: line)
        applySearchHighlights(
            to: &attributed,
            matches: matches,
            selectedMatchOrdinal: selectedMatchOrdinal
        )
        return attributed
    }

    private static func applySyntax(to attributed: inout AttributedString, source line: String) {
        guard !line.isEmpty else {
            return
        }

        let lineLength = line.count
        let firstTextOffset = line.distance(
            from: line.startIndex,
            to: line.firstIndex { !$0.isWhitespace } ?? line.endIndex
        )
        guard firstTextOffset < lineLength else {
            return
        }

        if line.character(at: firstTextOffset) == "-" {
            setForeground(.secondary, start: firstTextOffset, length: 1, in: &attributed)
        }

        guard let colonOffset = yamlColonOffset(in: line) else {
            applySequenceScalarSyntax(to: &attributed, source: line, firstTextOffset: firstTextOffset)
            return
        }

        let keyStart = keyStartOffset(in: line, firstTextOffset: firstTextOffset)
        if keyStart < colonOffset {
            setForeground(.cyan, start: keyStart, length: colonOffset - keyStart, in: &attributed)
        }
        setForeground(.secondary, start: colonOffset, length: 1, in: &attributed)

        let valueStart = firstNonWhitespaceOffset(in: line, after: colonOffset + 1)
        if valueStart < lineLength {
            applyScalarSyntax(
                to: &attributed,
                source: line,
                start: valueStart,
                length: lineLength - valueStart
            )
        }
    }

    private static func applySequenceScalarSyntax(
        to attributed: inout AttributedString,
        source line: String,
        firstTextOffset: Int
    ) {
        guard line.character(at: firstTextOffset) == "-" else {
            return
        }

        let valueStart = firstNonWhitespaceOffset(in: line, after: firstTextOffset + 1)
        if valueStart < line.count {
            applyScalarSyntax(
                to: &attributed,
                source: line,
                start: valueStart,
                length: line.count - valueStart
            )
        }
    }

    private static func applyScalarSyntax(
        to attributed: inout AttributedString,
        source line: String,
        start: Int,
        length: Int
    ) {
        let value = line.substring(start: start, length: length)
        let color: Color
        if value == "<redacted>" {
            color = .red
        } else if value.hasPrefix("\"") {
            color = .green
        } else if ["true", "false"].contains(value.lowercased()) {
            color = .purple
        } else if ["null", "[]", "{}"].contains(value.lowercased()) {
            color = .secondary
        } else if Double(value) != nil {
            color = .orange
        } else {
            color = .green
        }

        setForeground(color, start: start, length: length, in: &attributed)
    }

    private static func applySearchHighlights(
        to attributed: inout AttributedString,
        matches: [ManifestSearchMatch],
        selectedMatchOrdinal: Int?
    ) {
        for match in matches {
            setBackground(
                match.ordinal == selectedMatchOrdinal ? Color.accentColor.opacity(0.42) : Color.yellow.opacity(0.28),
                start: match.lowerBound,
                length: match.length,
                in: &attributed
            )
        }
    }

    private static func keyStartOffset(in line: String, firstTextOffset: Int) -> Int {
        guard line.character(at: firstTextOffset) == "-" else {
            return firstTextOffset
        }

        return firstNonWhitespaceOffset(in: line, after: firstTextOffset + 1)
    }

    private static func firstNonWhitespaceOffset(in line: String, after offset: Int) -> Int {
        guard offset < line.count else {
            return line.count
        }

        var currentOffset = offset
        var index = line.index(line.startIndex, offsetBy: offset)
        while index < line.endIndex, line[index].isWhitespace {
            currentOffset += 1
            index = line.index(after: index)
        }
        return currentOffset
    }

    private static func yamlColonOffset(in line: String) -> Int? {
        var isQuoted = false
        var isEscaped = false

        for (offset, character) in line.enumerated() {
            if isEscaped {
                isEscaped = false
                continue
            }

            if character == "\\" {
                isEscaped = true
                continue
            }

            if character == "\"" {
                isQuoted.toggle()
                continue
            }

            if character == ":", !isQuoted, isYAMLKeySeparator(in: line, at: offset) {
                return offset
            }
        }

        return nil
    }

    private static func isYAMLKeySeparator(in line: String, at offset: Int) -> Bool {
        let nextOffset = offset + 1
        guard nextOffset < line.count else {
            return true
        }

        return line.character(at: nextOffset).isWhitespace
    }

    private static func setForeground(
        _ color: Color,
        start: Int,
        length: Int,
        in attributed: inout AttributedString
    ) {
        guard let range = attributedRange(start: start, length: length, in: attributed) else {
            return
        }

        attributed[range].foregroundColor = color
    }

    private static func setBackground(
        _ color: Color,
        start: Int,
        length: Int,
        in attributed: inout AttributedString
    ) {
        guard let range = attributedRange(start: start, length: length, in: attributed) else {
            return
        }

        attributed[range].backgroundColor = color
    }

    private static func attributedRange(
        start: Int,
        length: Int,
        in attributed: AttributedString
    ) -> Range<AttributedString.Index>? {
        guard length > 0,
              start >= 0,
              start < attributed.characters.count else {
            return nil
        }

        let lower = attributed.characters.index(attributed.startIndex, offsetBy: start)
        let upper = attributed.characters.index(
            lower,
            offsetBy: min(length, attributed.characters.distance(from: lower, to: attributed.endIndex))
        )
        return lower..<upper
    }
}

private extension String {
    func trimmingTrailingNewlines() -> String {
        var value = self
        while value.last == "\n" || value.last == "\r" {
            value.removeLast()
        }
        return value
    }

    func character(at offset: Int) -> Character {
        self[index(startIndex, offsetBy: offset)]
    }

    func substring(start: Int, length: Int) -> String {
        let lower = index(startIndex, offsetBy: start)
        let upper = index(lower, offsetBy: min(length, distance(from: lower, to: endIndex)))
        return String(self[lower..<upper])
    }
}
