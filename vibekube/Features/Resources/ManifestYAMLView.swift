import AppKit
import SwiftUI

struct ManifestYAMLView: View {
    @State private var searchText = ""
    @State private var selectedMatchIndex = 0
    @State private var copiedToClipboard = false
    @State private var isEditing = false
    @State private var draftYAML: String
    @State private var previewState: ManifestMutationPreviewState = .idle

    let yaml: String
    var saveYAML: (() -> Void)?
    var previewMutation: ((String) async throws -> KubernetesMutationPreview)?

    init(
        yaml: String,
        saveYAML: (() -> Void)? = nil,
        previewMutation: ((String) async throws -> KubernetesMutationPreview)? = nil
    ) {
        self.yaml = yaml
        self.saveYAML = saveYAML
        self.previewMutation = previewMutation
        _draftYAML = State(initialValue: yaml)
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            Divider()

            if isEditing {
                editContent
            } else {
                ManifestYAMLTextView(
                    yaml: displayYAML,
                    matches: matches,
                    selectedMatch: selectedMatch
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: yaml) {
            searchText = ""
            selectedMatchIndex = 0
            copiedToClipboard = false
            draftYAML = yaml
            previewState = .idle
        }
        .onChange(of: searchText) {
            selectedMatchIndex = 0
        }
        .onChange(of: draftYAML) {
            if !previewState.isLoading {
                previewState = .idle
            }
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
            if isEditing {
                Button {
                    Task {
                        await previewDraft()
                    }
                } label: {
                    Label("Preview", systemImage: previewState.isLoading ? "hourglass" : "doc.text.magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
                .disabled(previewMutation == nil || previewState.isLoading)
                .help(previewMutation == nil ? "Preview unavailable" : "Preview")
                .accessibilityIdentifier("resource.detail.yaml.preview")

                Button {
                    draftYAML = yaml
                    previewState = .idle
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .disabled(draftYAML == yaml)
                .help("Reset")
                .accessibilityIdentifier("resource.detail.yaml.reset")

                Button {
                    cancelEditing()
                } label: {
                    Label("Cancel", systemImage: "xmark")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .help("Cancel")
                .accessibilityIdentifier("resource.detail.yaml.cancelEdit")
            } else {
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
            }

            Divider()
                .frame(height: 18)

            if !isEditing {
                Button {
                    startEditing()
                } label: {
                    Label("Edit YAML", systemImage: "pencil")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .disabled(previewMutation == nil)
                .help(previewMutation == nil ? "Edit unavailable" : "Edit YAML")
                .accessibilityIdentifier("resource.detail.yaml.edit")

                Button {
                    copyYAML()
                } label: {
                    Label(copiedToClipboard ? "Copied" : "Copy YAML", systemImage: copiedToClipboard ? "checkmark" : "doc.on.doc")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .help(copiedToClipboard ? "Copied" : "Copy YAML")
                .accessibilityIdentifier("resource.detail.yaml.copy")

                Button {
                    saveYAML?()
                } label: {
                    Label("Save YAML", systemImage: "square.and.arrow.down")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .disabled(saveYAML == nil)
                .help("Save YAML")
                .accessibilityIdentifier("resource.detail.yaml.save")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
    }

    private var editContent: some View {
        VStack(spacing: 0) {
            ManifestYAMLEditorView(text: $draftYAML)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)
                .clipped()
                .accessibilityIdentifier("resource.detail.yaml.editor")

            if !previewState.isIdle {
                Divider()

                ManifestMutationPreviewPane(state: previewState)
                    .frame(minHeight: 180, idealHeight: 220, maxHeight: 280)
            }
        }
    }

    private var displayYAML: String {
        yaml.trimmingTrailingNewlines()
    }

    private var matches: [ManifestSearchMatch] {
        ManifestSearchIndex.matches(in: displayYAML, query: searchText)
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

    private func startEditing() {
        draftYAML = yaml
        previewState = .idle
        isEditing = true
    }

    private func cancelEditing() {
        isEditing = false
        draftYAML = yaml
        previewState = .idle
    }

    @MainActor
    private func previewDraft() async {
        guard let previewMutation else {
            previewState = .failed(message: "Preview unavailable.", causes: [])
            return
        }

        previewState = .loading
        let submittedYAML = draftYAML
        do {
            let preview = try await previewMutation(submittedYAML)
            guard draftYAML == submittedYAML else {
                previewState = .idle
                return
            }
            previewState = .loaded(preview)
        } catch let error as KubernetesMutationPreviewError {
            guard draftYAML == submittedYAML else {
                previewState = .idle
                return
            }
            previewState = .failed(
                message: error.localizedDescription,
                causes: error.fieldCauses
            )
        } catch let error as LocalizedError {
            guard draftYAML == submittedYAML else {
                previewState = .idle
                return
            }
            previewState = .failed(
                message: error.errorDescription ?? error.localizedDescription,
                causes: []
            )
        } catch {
            guard draftYAML == submittedYAML else {
                previewState = .idle
                return
            }
            previewState = .failed(message: error.localizedDescription, causes: [])
        }
    }
}

private enum ManifestMutationPreviewState {
    case idle
    case loading
    case loaded(KubernetesMutationPreview)
    case failed(message: String, causes: [KubernetesStatusCause])

    var isIdle: Bool {
        if case .idle = self {
            return true
        }
        return false
    }

    var isLoading: Bool {
        if case .loading = self {
            return true
        }
        return false
    }
}

private struct ManifestMutationPreviewPane: View {
    let state: ManifestMutationPreviewState

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            content
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .accessibilityIdentifier("resource.detail.yaml.previewPane")
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: headerImage)
                .foregroundStyle(headerTint)

            Text(headerTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle:
            EmptyView()
        case .loading:
            ProgressView("Previewing")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let preview):
            if preview.diff.hasChanges {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(preview.diff.lines.enumerated()), id: \.offset) { _, line in
                            ManifestMutationDiffLineView(line: line)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .accessibilityIdentifier("resource.detail.yaml.diff")
            } else {
                Text("No changes")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .failed(let message, let causes):
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)

                    ForEach(Array(causes.enumerated()), id: \.offset) { _, cause in
                        Text(causeText(cause))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
            }
        }
    }

    private var headerImage: String {
        switch state {
        case .idle:
            "doc.text"
        case .loading:
            "hourglass"
        case .loaded(let preview):
            preview.diff.hasChanges ? "plusminus" : "checkmark.circle"
        case .failed:
            "exclamationmark.triangle"
        }
    }

    private var headerTitle: String {
        switch state {
        case .idle:
            ""
        case .loading:
            "Dry-run Preview"
        case .loaded(let preview):
            preview.diff.hasChanges ? "Dry-run Diff" : "Dry-run Preview"
        case .failed:
            "Preview Failed"
        }
    }

    private var headerTint: Color {
        switch state {
        case .idle, .loading:
            .secondary
        case .loaded(let preview):
            preview.diff.hasChanges ? .orange : .green
        case .failed:
            .red
        }
    }

    private func causeText(_ cause: KubernetesStatusCause) -> String {
        [
            cause.field,
            cause.message,
            cause.reason
        ]
        .compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        .joined(separator: " - ")
    }
}

private struct ManifestMutationDiffLineView: View {
    let line: KubernetesYAMLDiffLine

    var body: some View {
        Text(line.unifiedText)
            .font(.caption.monospaced())
            .foregroundStyle(foregroundStyle)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 1)
            .background(backgroundStyle)
            .textSelection(.enabled)
    }

    private var foregroundStyle: Color {
        switch line.kind {
        case .context:
            .secondary
        case .addition:
            .green
        case .removal:
            .red
        }
    }

    private var backgroundStyle: Color {
        switch line.kind {
        case .context:
            .clear
        case .addition:
            Color.green.opacity(0.10)
        case .removal:
            Color.red.opacity(0.10)
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

private struct ManifestYAMLTextView: NSViewRepresentable {
    let yaml: String
    let matches: [ManifestSearchMatch]
    let selectedMatch: ManifestSearchMatch?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let textView = NSTextView(
            frame: NSRect(
                origin: .zero,
                size: NSSize(width: max(1, scrollView.contentSize.width), height: max(1, scrollView.contentSize.height))
            )
        )
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.allowsUndo = false
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.insertionPointColor = .labelColor
        textView.textContainerInset = NSSize(width: 10, height: 8)
        textView.font = ManifestYAMLAttributedRenderer.font
        textView.textColor = .labelColor
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(
            width: scrollView.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(
            width: max(1, scrollView.contentSize.width),
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.setAccessibilityIdentifier("resource.detail.yaml.text")

        scrollView.documentView = textView
        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else {
            return
        }

        let renderState = Coordinator.RenderState(
            yaml: yaml,
            matches: matches,
            selectedMatchID: selectedMatch?.id
        )
        let yamlChanged = context.coordinator.renderState?.yaml != yaml

        if context.coordinator.renderState != renderState {
            let selectedRange = textView.selectedRange()
            textView.textStorage?.setAttributedString(
                ManifestYAMLAttributedRenderer.attributedString(
                    yaml: yaml,
                    matches: matches,
                    selectedMatch: selectedMatch
                )
            )
            textView.selectedRange = selectedRange.clamped(to: textView.string.utf16.count)
            context.coordinator.renderState = renderState
        }

        Self.resizeDocumentView(textView, in: scrollView)

        if yamlChanged, selectedMatch == nil {
            scrollView.contentView.scroll(to: .zero)
            scrollView.reflectScrolledClipView(scrollView.contentView)
            context.coordinator.scrolledMatchID = nil
        }

        if context.coordinator.scrolledMatchID != selectedMatch?.id {
            context.coordinator.scrolledMatchID = selectedMatch?.id
            if let selectedMatch,
               let range = ManifestYAMLAttributedRenderer.range(for: selectedMatch, in: yaml) {
                textView.scrollRangeToVisible(range)
            }
        }
    }

    private static func resizeDocumentView(_ textView: NSTextView, in scrollView: NSScrollView) {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return
        }

        let width = max(1, scrollView.contentSize.width)
        textView.maxSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)

        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        let inset = textView.textContainerInset
        let height = max(scrollView.contentSize.height, ceil(usedRect.height + inset.height * 2 + 16))
        let size = NSSize(width: width, height: max(1, height))

        if textView.frame.size != size {
            textView.setFrameSize(size)
        }
    }

    final class Coordinator {
        struct RenderState: Equatable {
            var yaml: String
            var matches: [ManifestSearchMatch]
            var selectedMatchID: String?
        }

        weak var textView: NSTextView?
        var renderState: RenderState?
        var scrolledMatchID: String?
    }
}

private struct ManifestYAMLEditorView: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> ManifestYAMLEditorContainerView {
        let container = ManifestYAMLEditorContainerView()
        let scrollView = ManifestYAMLEditorScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let textView = ManifestYAMLEditingTextView(frame: .zero)
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.insertionPointColor = .labelColor
        textView.textContainerInset = NSSize(width: 12, height: 10)
        textView.font = ManifestYAMLAttributedRenderer.font
        textView.textColor = .labelColor
        textView.usesFindBar = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.minSize = NSSize(width: 0, height: scrollView.contentSize.height)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.lineFragmentPadding = 0
        textView.typingAttributes = ManifestYAMLAttributedRenderer.editorTypingAttributes
        textView.setAccessibilityIdentifier("resource.detail.yaml.editor.text")

        scrollView.documentView = textView
        let rulerView = ManifestYAMLLineNumberRulerView(textView: textView)
        scrollView.verticalRulerView = rulerView
        container.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        context.coordinator.textView = textView
        context.coordinator.rulerView = rulerView
        context.coordinator.scrollView = scrollView
        context.coordinator.apply(text, scrollToTop: true)
        return container
    }

    func updateNSView(_ container: ManifestYAMLEditorContainerView, context: Context) {
        guard let textView = context.coordinator.textView,
              let scrollView = context.coordinator.scrollView else {
            return
        }

        if textView.string != text {
            context.coordinator.apply(text, scrollToTop: true)
        } else {
            context.coordinator.highlightVisibleLine()
        }

        context.coordinator.rulerView?.needsDisplay = true
        Self.resizeDocumentView(textView, in: scrollView)
    }

    private static func resizeDocumentView(_ textView: NSTextView, in scrollView: NSScrollView) {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return
        }

        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        let inset = textView.textContainerInset
        let width = max(scrollView.contentSize.width, ceil(usedRect.width + inset.width * 2 + 24))
        let height = max(scrollView.contentSize.height, ceil(usedRect.height + inset.height * 2 + 24))
        let size = NSSize(width: max(1, width), height: max(1, height))

        if textView.frame.size != size {
            textView.setFrameSize(size)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding private var text: String
        weak var textView: NSTextView?
        weak var rulerView: ManifestYAMLLineNumberRulerView?
        weak var scrollView: NSScrollView?
        private var isApplying = false

        init(text: Binding<String>) {
            _text = text
        }

        func apply(_ value: String, scrollToTop: Bool = false) {
            guard let textView else { return }

            isApplying = true
            let selectedRange = textView.selectedRange()
            textView.textStorage?.setAttributedString(
                ManifestYAMLAttributedRenderer.editorAttributedString(yaml: value)
            )
            textView.selectedRange = selectedRange.clamped(to: textView.string.utf16.count)
            textView.typingAttributes = ManifestYAMLAttributedRenderer.editorTypingAttributes
            highlightVisibleLine()
            rulerView?.needsDisplay = true
            if scrollToTop {
                textView.scrollRangeToVisible(NSRange(location: 0, length: 0))
            }
            isApplying = false
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplying, let textView else {
                return
            }

            text = textView.string
            applySyntaxPreservingSelection()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            highlightVisibleLine()
        }

        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            guard let replacementString else {
                return true
            }

            if replacementString == "\t" {
                textView.insertText("  ", replacementRange: affectedCharRange)
                return false
            }

            if replacementString == "\n" {
                textView.insertText("\n\(currentLineIndent(in: textView, range: affectedCharRange))", replacementRange: affectedCharRange)
                return false
            }

            return true
        }

        func highlightVisibleLine() {
            guard let textView,
                  let textStorage = textView.textStorage else {
                return
            }

            textStorage.removeAttribute(
                .backgroundColor,
                range: NSRange(location: 0, length: textStorage.length)
            )
            let lineRange = (textView.string as NSString).lineRange(for: textView.selectedRange())
            guard lineRange.length > 0 else {
                return
            }

            textStorage.addAttribute(
                .backgroundColor,
                value: NSColor.controlAccentColor.withAlphaComponent(0.08),
                range: lineRange.clamped(to: textStorage.length)
            )
        }

        private func applySyntaxPreservingSelection() {
            guard let textView else { return }

            let selectedRange = textView.selectedRange()
            isApplying = true
            textView.textStorage?.setAttributedString(
                ManifestYAMLAttributedRenderer.editorAttributedString(yaml: textView.string)
            )
            textView.selectedRange = selectedRange.clamped(to: textView.string.utf16.count)
            textView.typingAttributes = ManifestYAMLAttributedRenderer.editorTypingAttributes
            highlightVisibleLine()
            rulerView?.needsDisplay = true
            isApplying = false
        }

        private func currentLineIndent(in textView: NSTextView, range: NSRange) -> String {
            let nsText = textView.string as NSString
            let location = min(range.location, nsText.length)
            let lineRange = nsText.lineRange(for: NSRange(location: location, length: 0))
            let line = nsText.substring(with: lineRange)

            var indent = ""
            for character in line {
                if character == " " {
                    indent.append(character)
                } else {
                    break
                }
            }

            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasSuffix(":") || trimmed == "-" {
                indent += "  "
            }

            return indent
        }
    }
}

private final class ManifestYAMLEditorContainerView: NSView {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override var fittingSize: NSSize {
        .zero
    }
}

private final class ManifestYAMLEditorScrollView: NSScrollView {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override var fittingSize: NSSize {
        .zero
    }
}

private final class ManifestYAMLEditingTextView: NSTextView {
    override var acceptsFirstResponder: Bool {
        true
    }

    override func paste(_ sender: Any?) {
        guard let pasted = NSPasteboard.general.string(forType: .string) else {
            super.paste(sender)
            return
        }

        insertText(pasted.replacingOccurrences(of: "\t", with: "  "), replacementRange: selectedRange())
    }
}

private final class ManifestYAMLLineNumberRulerView: NSRulerView {
    private weak var textView: NSTextView?
    private let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    private let textColor = NSColor.tertiaryLabelColor

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 48

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(invalidateDisplay),
            name: NSView.boundsDidChangeNotification,
            object: textView.enclosingScrollView?.contentView
        )
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return
        }

        NSColor.controlBackgroundColor.setFill()
        rect.fill()

        let visibleRect = textView.visibleRect
        let glyphRange = layoutManager.glyphRange(
            forBoundingRect: visibleRect,
            in: textContainer
        )
        let lineNumberAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]
        var lineNumber = lineNumberForGlyph(at: glyphRange.location, layoutManager: layoutManager)

        layoutManager.enumerateLineFragments(
            forGlyphRange: glyphRange
        ) { _, usedRect, _, glyphRange, _ in
            let characterRange = layoutManager.characterRange(
                forGlyphRange: glyphRange,
                actualGlyphRange: nil
            )
            guard characterRange.length > 0 else {
                return
            }

            let label = "\(lineNumber)" as NSString
            let labelSize = label.size(withAttributes: lineNumberAttributes)
            let y = usedRect.minY + textView.textContainerOrigin.y + (usedRect.height - labelSize.height) / 2
            let x = self.ruleThickness - labelSize.width - 8
            label.draw(
                at: NSPoint(x: x, y: y),
                withAttributes: lineNumberAttributes
            )
            lineNumber += 1
        }
    }

    @objc private func invalidateDisplay() {
        needsDisplay = true
    }

    private func lineNumberForGlyph(
        at glyphIndex: Int,
        layoutManager: NSLayoutManager
    ) -> Int {
        guard let textView else {
            return 1
        }

        let glyphCount = layoutManager.numberOfGlyphs
        guard glyphCount > 0 else {
            return 1
        }

        let safeGlyphIndex = min(max(glyphIndex, 0), glyphCount - 1)
        let characterIndex = layoutManager.characterIndexForGlyph(at: safeGlyphIndex)
        let prefix = (textView.string as NSString).substring(
            to: min(characterIndex, textView.string.utf16.count)
        )
        return prefix.reduce(1) { count, character in
            character == "\n" ? count + 1 : count
        }
    }
}

private enum ManifestYAMLAttributedRenderer {
    static let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    private static let lineNumberFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
    static let editorTypingAttributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.labelColor
    ]

    static func attributedString(
        yaml: String,
        matches: [ManifestSearchMatch],
        selectedMatch: ManifestSearchMatch?
    ) -> NSAttributedString {
        let document = renderedDocument(in: yaml)
        let attributed = NSMutableAttributedString(
            string: document.text,
            attributes: [
                .font: font,
                .foregroundColor: NSColor.labelColor
            ]
        )

        for line in document.lines {
            attributed.addAttributes(
                [
                    .font: lineNumberFont,
                    .foregroundColor: NSColor.tertiaryLabelColor
                ],
                range: NSRange(location: line.displayStartUTF16, length: line.contentStartUTF16 - line.displayStartUTF16)
            )
            applySyntax(to: attributed, line: line.text, baseUTF16Offset: line.contentStartUTF16)
        }

        for match in matches {
            guard let range = range(for: match, in: yaml) else {
                continue
            }

            let color = match.ordinal == selectedMatch?.ordinal
                ? NSColor.controlAccentColor.withAlphaComponent(0.42)
                : NSColor.systemYellow.withAlphaComponent(0.28)
            attributed.addAttribute(.backgroundColor, value: color, range: range)
        }

        return attributed
    }

    static func editorAttributedString(yaml: String) -> NSAttributedString {
        let lines = yaml.isEmpty
            ? [""]
            : yaml.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let attributed = NSMutableAttributedString(
            string: yaml,
            attributes: editorTypingAttributes
        )
        var offset = 0

        for line in lines {
            applySyntax(to: attributed, line: line, baseUTF16Offset: offset)
            offset += line.utf16.count + 1
        }

        return attributed
    }

    static func range(for match: ManifestSearchMatch, in yaml: String) -> NSRange? {
        let document = renderedDocument(in: yaml)
        guard document.lines.indices.contains(match.lineNumber - 1) else {
            return nil
        }

        let line = document.lines[match.lineNumber - 1]
        return nsRange(
            in: line.text,
            start: match.lowerBound,
            length: match.length,
            baseUTF16Offset: line.contentStartUTF16
        )
    }

    private struct RenderedDocument {
        var text: String
        var lines: [LineInfo]
    }

    private struct LineInfo {
        var text: String
        var displayStartUTF16: Int
        var contentStartUTF16: Int
    }

    private static func renderedDocument(in yaml: String) -> RenderedDocument {
        let lines = yaml.isEmpty
            ? [""]
            : yaml.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let numberWidth = max(2, String(lines.count).count)

        var infos: [LineInfo] = []
        var displayText = ""
        var displayStartUTF16 = 0

        for (index, line) in lines.enumerated() {
            let prefix = String(format: "%\(numberWidth)d  ", index + 1)
            displayText += prefix
            displayText += line
            infos.append(
                LineInfo(
                    text: line,
                    displayStartUTF16: displayStartUTF16,
                    contentStartUTF16: displayStartUTF16 + prefix.utf16.count
                )
            )
            displayStartUTF16 += prefix.utf16.count + line.utf16.count
            if index < lines.count - 1 {
                displayText += "\n"
                displayStartUTF16 += 1
            }
        }

        return RenderedDocument(text: displayText, lines: infos)
    }

    private static func applySyntax(
        to attributed: NSMutableAttributedString,
        line: String,
        baseUTF16Offset: Int
    ) {
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
            setForeground(
                .secondaryLabelColor,
                start: firstTextOffset,
                length: 1,
                in: attributed,
                line: line,
                baseUTF16Offset: baseUTF16Offset
            )
        }

        guard let colonOffset = yamlColonOffset(in: line) else {
            applySequenceScalarSyntax(
                to: attributed,
                line: line,
                firstTextOffset: firstTextOffset,
                baseUTF16Offset: baseUTF16Offset
            )
            return
        }

        let keyStart = keyStartOffset(in: line, firstTextOffset: firstTextOffset)
        if keyStart < colonOffset {
            setForeground(
                .systemCyan,
                start: keyStart,
                length: colonOffset - keyStart,
                in: attributed,
                line: line,
                baseUTF16Offset: baseUTF16Offset
            )
        }
        setForeground(
            .secondaryLabelColor,
            start: colonOffset,
            length: 1,
            in: attributed,
            line: line,
            baseUTF16Offset: baseUTF16Offset
        )

        let valueStart = firstNonWhitespaceOffset(in: line, after: colonOffset + 1)
        if valueStart < lineLength {
            applyScalarSyntax(
                to: attributed,
                line: line,
                start: valueStart,
                length: lineLength - valueStart,
                baseUTF16Offset: baseUTF16Offset
            )
        }
    }

    private static func applySequenceScalarSyntax(
        to attributed: NSMutableAttributedString,
        line: String,
        firstTextOffset: Int,
        baseUTF16Offset: Int
    ) {
        guard line.character(at: firstTextOffset) == "-" else {
            return
        }

        let valueStart = firstNonWhitespaceOffset(in: line, after: firstTextOffset + 1)
        if valueStart < line.count {
            applyScalarSyntax(
                to: attributed,
                line: line,
                start: valueStart,
                length: line.count - valueStart,
                baseUTF16Offset: baseUTF16Offset
            )
        }
    }

    private static func applyScalarSyntax(
        to attributed: NSMutableAttributedString,
        line: String,
        start: Int,
        length: Int,
        baseUTF16Offset: Int
    ) {
        let value = line.substring(start: start, length: length)
        let color: NSColor
        if value == "<redacted>" {
            color = .systemRed
        } else if value.hasPrefix("\"") {
            color = .systemGreen
        } else if ["true", "false"].contains(value.lowercased()) {
            color = .systemPurple
        } else if ["null", "[]", "{}"].contains(value.lowercased()) {
            color = .secondaryLabelColor
        } else if Double(value) != nil {
            color = .systemOrange
        } else {
            color = .systemGreen
        }

        setForeground(
            color,
            start: start,
            length: length,
            in: attributed,
            line: line,
            baseUTF16Offset: baseUTF16Offset
        )
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
        _ color: NSColor,
        start: Int,
        length: Int,
        in attributed: NSMutableAttributedString,
        line: String,
        baseUTF16Offset: Int
    ) {
        guard let range = nsRange(
            in: line,
            start: start,
            length: length,
            baseUTF16Offset: baseUTF16Offset
        ) else {
            return
        }

        attributed.addAttribute(.foregroundColor, value: color, range: range)
    }

    private static func nsRange(
        in line: String,
        start: Int,
        length: Int,
        baseUTF16Offset: Int
    ) -> NSRange? {
        guard length > 0,
              start >= 0,
              start < line.count else {
            return nil
        }

        let lower = line.index(line.startIndex, offsetBy: start)
        let upper = line.index(
            lower,
            offsetBy: min(length, line.distance(from: lower, to: line.endIndex))
        )
        let localRange = NSRange(lower..<upper, in: line)
        return NSRange(location: baseUTF16Offset + localRange.location, length: localRange.length)
    }
}

private extension NSRange {
    func clamped(to upperBound: Int) -> NSRange {
        guard upperBound > 0 else {
            return NSRange(location: 0, length: 0)
        }

        let location = min(max(0, self.location), upperBound)
        let length = min(max(0, self.length), max(0, upperBound - location))
        return NSRange(location: location, length: length)
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
