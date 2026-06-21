import AppKit
import SwiftUI
import WebKit

struct ManifestYAMLMutationTarget: Equatable {
    var clusterName: String
    var namespace: String?
    var apiVersion: String
    var kind: String
    var name: String

    var displayTitle: String {
        "\(kind)/\(name)"
    }

    var scopeText: String {
        if let namespace, !namespace.isEmpty {
            return "\(clusterName) · \(namespace) · \(apiVersion)"
        }
        return "\(clusterName) · cluster-scoped · \(apiVersion)"
    }

    var confirmationDescription: String {
        if let namespace, !namespace.isEmpty {
            return "\(kind)/\(name) in namespace \(namespace) on \(clusterName)"
        }
        return "cluster-scoped \(kind)/\(name) on \(clusterName)"
    }
}

struct ManifestYAMLView: View {
    @State private var searchText = ""
    @State private var selectedMatchIndex = 0
    @State private var copiedToClipboard = false
    @State private var isEditing = false
    @State private var draftYAML: String
    @State private var editSearchText = ""
    @State private var selectedEditMatchIndex = 0
    @State private var editSearchNavigationToken = 0
    @State private var previewState: ManifestMutationPreviewState = .idle
    @State private var isPreviewExpanded = false
    @State private var showsApplyConfirmation = false
    @State private var isApplying = false

    let yaml: String
    var mutationTarget: ManifestYAMLMutationTarget?
    var saveYAML: (() -> Void)?
    var previewMutation: ((String) async throws -> KubernetesMutationPreview)?
    var applyMutation: ((KubernetesMutationPreview) async throws -> KubernetesResourceDetail)?

    init(
        yaml: String,
        mutationTarget: ManifestYAMLMutationTarget? = nil,
        saveYAML: (() -> Void)? = nil,
        previewMutation: ((String) async throws -> KubernetesMutationPreview)? = nil,
        applyMutation: ((KubernetesMutationPreview) async throws -> KubernetesResourceDetail)? = nil
    ) {
        self.yaml = yaml
        self.mutationTarget = mutationTarget
        self.saveYAML = saveYAML
        self.previewMutation = previewMutation
        self.applyMutation = applyMutation
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
            editSearchText = ""
            selectedEditMatchIndex = 0
            editSearchNavigationToken = 0
            previewState = .idle
            isPreviewExpanded = false
            isApplying = false
        }
        .onChange(of: searchText) {
            selectedMatchIndex = 0
        }
        .onChange(of: editSearchText) {
            selectedEditMatchIndex = 0
        }
        .onChange(of: draftYAML) {
            if !previewState.isLoading {
                previewState = .idle
                isPreviewExpanded = false
            }
            if selectedEditMatchIndex >= editMatches.count {
                selectedEditMatchIndex = max(0, editMatches.count - 1)
            }
        }
        .onChange(of: matches.count) { _, count in
            if selectedMatchIndex >= count {
                selectedMatchIndex = max(0, count - 1)
            }
        }
        .onChange(of: editMatches.count) { _, count in
            if selectedEditMatchIndex >= count {
                selectedEditMatchIndex = max(0, count - 1)
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
                    showsApplyConfirmation = true
                } label: {
                    Label(isApplying ? "Applying" : "Apply", systemImage: isApplying ? "hourglass" : "checkmark.circle")
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(!canApplyPreview)
                .help(applyHelpText)
                .accessibilityIdentifier("resource.detail.yaml.apply")

                Divider()
                    .frame(height: 18)

                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Find Draft", text: $editSearchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 120, idealWidth: 160, maxWidth: 220)
                    .onSubmit {
                        jumpToSelectedEditMatch()
                    }
                    .accessibilityIdentifier("resource.detail.yaml.editSearch")

                Text(editMatchSummary)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(editMatches.isEmpty ? .tertiary : .secondary)
                    .frame(minWidth: 48, alignment: .trailing)

                Button {
                    selectPreviousEditMatch()
                } label: {
                    Label("Previous Draft Match", systemImage: "chevron.up")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .disabled(editMatches.isEmpty)
                .help("Previous Draft Match")
                .accessibilityIdentifier("resource.detail.yaml.previousEditMatch")

                Button {
                    selectNextEditMatch()
                } label: {
                    Label("Next Draft Match", systemImage: "chevron.down")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .disabled(editMatches.isEmpty)
                .help("Next Draft Match")
                .accessibilityIdentifier("resource.detail.yaml.nextEditMatch")

                Spacer(minLength: 8)

                Button {
                    draftYAML = yaml
                    previewState = .idle
                    isPreviewExpanded = false
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
        .confirmationDialog(
            "Apply YAML changes?",
            isPresented: $showsApplyConfirmation,
            titleVisibility: .visible
        ) {
            Button("Apply Changes") {
                Task {
                    await applyPreview()
                }
            }
            .disabled(!canApplyPreview)

            Button("Cancel", role: .cancel) {}
        } message: {
            Text(applyConfirmationMessage)
        }
    }

    private var editContent: some View {
        Group {
            if previewState.isIdle {
                editorView
            } else {
                HSplitView {
                    editorView
                        .frame(minWidth: 360)

                    ManifestMutationPreviewPane(
                        state: previewState,
                        target: mutationTarget,
                        canApply: canApplyPreview,
                        isApplying: isApplying,
                        onApply: {
                            showsApplyConfirmation = true
                        },
                        onExpand: {
                            isPreviewExpanded = true
                        }
                    )
                    .frame(minWidth: 360, idealWidth: 460, maxWidth: .infinity)
                }
            }
        }
        .sheet(isPresented: $isPreviewExpanded) {
            ManifestMutationPreviewPane(
                state: previewState,
                target: mutationTarget,
                canApply: canApplyPreview,
                isApplying: isApplying,
                onApply: {
                    closeExpandedPreviewAndConfirmApply()
                },
                onExpand: nil
            )
            .frame(minWidth: 820, minHeight: 560)
        }
    }

    private var editorView: some View {
        VStack(spacing: 0) {
            ManifestYAMLEditorView(
                text: $draftYAML,
                searchQuery: editSearchText,
                selectedSearchOrdinal: selectedEditMatch?.ordinal,
                searchNavigationToken: editSearchNavigationToken
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)
                .clipped()
                .accessibilityIdentifier("resource.detail.yaml.editor")
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

    private var editMatches: [ManifestSearchMatch] {
        ManifestSearchIndex.matches(in: draftYAML, query: editSearchText)
    }

    private var selectedEditMatch: ManifestSearchMatch? {
        guard editMatches.indices.contains(selectedEditMatchIndex) else {
            return nil
        }

        return editMatches[selectedEditMatchIndex]
    }

    private var loadedPreview: KubernetesMutationPreview? {
        if case .loaded(let preview) = previewState {
            return preview
        }
        return nil
    }

    private var canApplyPreview: Bool {
        guard let loadedPreview else {
            return false
        }

        return applyMutation != nil &&
            loadedPreview.diff.hasChanges &&
            !previewState.isLoading &&
            !isApplying
    }

    private var applyHelpText: String {
        if applyMutation == nil {
            return "Apply unavailable"
        }
        guard let loadedPreview else {
            return "Preview first"
        }
        if !loadedPreview.diff.hasChanges {
            return "No changes to apply"
        }
        return "Apply previewed changes"
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

    private var editMatchSummary: String {
        let query = editSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return ""
        }

        guard !editMatches.isEmpty else {
            return "0/0"
        }

        return "\(selectedEditMatchIndex + 1)/\(editMatches.count)"
    }

    private var applyConfirmationMessage: String {
        let target = mutationTarget?.confirmationDescription ?? "the selected Kubernetes resource"
        return "This will update \(target). Preview has already passed a server-side dry run. The change will be sent to the cluster."
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

    private func selectPreviousEditMatch() {
        guard !editMatches.isEmpty else {
            return
        }

        selectedEditMatchIndex = selectedEditMatchIndex == 0 ? editMatches.count - 1 : selectedEditMatchIndex - 1
        jumpToSelectedEditMatch()
    }

    private func selectNextEditMatch() {
        guard !editMatches.isEmpty else {
            return
        }

        selectedEditMatchIndex = selectedEditMatchIndex == editMatches.count - 1 ? 0 : selectedEditMatchIndex + 1
        jumpToSelectedEditMatch()
    }

    private func jumpToSelectedEditMatch() {
        guard selectedEditMatch != nil else {
            return
        }

        editSearchNavigationToken += 1
    }

    private func closeExpandedPreviewAndConfirmApply() {
        isPreviewExpanded = false
        DispatchQueue.main.async {
            showsApplyConfirmation = true
        }
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
        isPreviewExpanded = false
        isApplying = false
        isEditing = true
    }

    private func cancelEditing() {
        isEditing = false
        draftYAML = yaml
        previewState = .idle
        isPreviewExpanded = false
        isApplying = false
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

    @MainActor
    private func applyPreview() async {
        guard let applyMutation else {
            previewState = .failed(message: "Apply unavailable.", causes: [])
            return
        }
        guard let preview = loadedPreview else {
            previewState = .failed(message: "Preview changes before applying.", causes: [])
            return
        }

        isApplying = true
        do {
            let applied = try await applyMutation(preview)
            draftYAML = applied.yaml
            previewState = .idle
            isPreviewExpanded = false
            isEditing = false
        } catch let error as KubernetesMutationPreviewError {
            previewState = .failed(
                message: error.localizedDescription,
                causes: error.fieldCauses
            )
        } catch let error as LocalizedError {
            previewState = .failed(
                message: error.errorDescription ?? error.localizedDescription,
                causes: []
            )
        } catch {
            previewState = .failed(message: error.localizedDescription, causes: [])
        }
        isApplying = false
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
    let target: ManifestYAMLMutationTarget?
    let canApply: Bool
    let isApplying: Bool
    var onApply: (() -> Void)?
    var onExpand: (() -> Void)?

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
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: headerImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(headerTint)

            VStack(alignment: .leading, spacing: 2) {
                Text(headerTitle)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if let onExpand {
                Button {
                    onExpand()
                } label: {
                    Label("Expand Preview", systemImage: "arrow.up.left.and.arrow.down.right")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .help("Expand Preview")
                .accessibilityIdentifier("resource.detail.yaml.expandPreview")
            }

            Button {
                onApply?()
            } label: {
                Label(isApplying ? "Applying" : "Apply", systemImage: isApplying ? "hourglass" : "checkmark.circle")
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(!canApply || onApply == nil)
            .help(canApply ? "Apply previewed changes" : "Preview changes before applying")
            .accessibilityIdentifier("resource.detail.yaml.applyFromPreview")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle:
            EmptyView()
        case .loading:
            VStack(spacing: 8) {
                ProgressView()
                Text("Running server-side dry run")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
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
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.green)
                    Text("No changes")
                        .font(.callout.weight(.semibold))
                    Text("The dry-run resource matches the live resource.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .failed(let message, let causes):
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Preview or apply failed", systemImage: "exclamationmark.triangle")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.red)

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

    private var subtitle: String {
        switch state {
        case .loaded(let preview) where preview.diff.hasChanges:
            let additions = preview.diff.lines.filter { $0.kind == .addition }.count
            let removals = preview.diff.lines.filter { $0.kind == .removal }.count
            return "\(target?.displayTitle ?? "Selected resource") · +\(additions) -\(removals)"
        case .loaded:
            return "\(target?.displayTitle ?? "Selected resource") · dry run succeeded"
        case .failed:
            return target?.scopeText ?? "Validation failed before apply"
        case .loading:
            return target?.scopeText ?? "Server-side validation"
        case .idle:
            return target?.scopeText ?? ""
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
    var searchQuery: String = ""
    var selectedSearchOrdinal: Int?
    var searchNavigationToken: Int = 0

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> WKWebView {
        let userContentController = WKUserContentController()
        userContentController.add(context.coordinator, name: "editor")

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = userContentController

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.loadHTMLString(Self.htmlDocument(initialText: text), baseURL: nil)
        context.coordinator.webView = webView
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.setText(text, in: webView)
        context.coordinator.setSearch(
            query: searchQuery,
            ordinal: selectedSearchOrdinal,
            navigationToken: searchNavigationToken,
            in: webView
        )
    }

    private static func htmlDocument(initialText: String) -> String {
        let initialJSON = jsonStringLiteral(initialText)
        return #"""
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<style>
:root {
    color-scheme: light dark;
    --background: Canvas;
    --foreground: CanvasText;
    --gutter: color-mix(in srgb, CanvasText 35%, Canvas);
    --gutter-bg: color-mix(in srgb, CanvasText 4%, Canvas);
    --divider: color-mix(in srgb, CanvasText 14%, Canvas);
    --current-line: color-mix(in srgb, Highlight 12%, transparent);
    --key: #0891b2;
    --punctuation: color-mix(in srgb, CanvasText 48%, Canvas);
    --string: #16a34a;
    --number: #d97706;
    --boolean: #9333ea;
    --null: color-mix(in srgb, CanvasText 52%, Canvas);
    --danger: #dc2626;
}

html, body {
    width: 100%;
    height: 100%;
    margin: 0;
    overflow: hidden;
    background: var(--background);
}

body {
    font: 12px ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", monospace;
    color: var(--foreground);
}

#shell {
    display: grid;
    grid-template-columns: 48px minmax(0, 1fr);
    width: 100%;
    height: 100%;
    background: var(--background);
}

#gutter {
    overflow: hidden;
    padding: 10px 8px 10px 0;
    box-sizing: border-box;
    border-right: 1px solid var(--divider);
    background: var(--gutter-bg);
    color: var(--gutter);
    text-align: right;
    line-height: 17px;
    user-select: none;
}

#editorLayer {
    position: relative;
    min-width: 0;
    height: 100%;
    overflow: hidden;
    background: var(--background);
}

#highlight,
#editor {
    position: absolute;
    inset: 0;
    box-sizing: border-box;
    margin: 0;
    border: 0;
    padding: 10px 12px;
    font: inherit;
    line-height: 17px;
    tab-size: 2;
    white-space: pre;
}

#highlight {
    z-index: 1;
    pointer-events: none;
    min-width: 100%;
    min-height: 100%;
    color: var(--foreground);
}

#currentLine {
    position: absolute;
    left: 0;
    right: 0;
    height: 17px;
    background: var(--current-line);
    pointer-events: none;
    z-index: 0;
}

#editor {
    z-index: 2;
    width: 100%;
    height: 100%;
    resize: none;
    outline: none;
    overflow: auto;
    background: transparent;
    color: rgba(0, 0, 0, 0.01);
    caret-color: var(--foreground);
    -webkit-text-fill-color: rgba(0, 0, 0, 0.01);
}

#editor::selection {
    background: color-mix(in srgb, Highlight 38%, transparent);
}

.key { color: var(--key); }
.punctuation { color: var(--punctuation); }
.string { color: var(--string); }
.number { color: var(--number); }
.boolean { color: var(--boolean); }
.null { color: var(--null); }
.danger { color: var(--danger); }
</style>
</head>
<body>
<div id="shell">
    <div id="gutter" aria-hidden="true"></div>
    <div id="editorLayer">
        <div id="currentLine" aria-hidden="true"></div>
        <pre id="highlight" aria-hidden="true"></pre>
        <textarea id="editor" spellcheck="false" autocorrect="off" autocapitalize="off" wrap="off" aria-label="YAML editor"></textarea>
    </div>
</div>
<script>
const editor = document.getElementById("editor");
const highlight = document.getElementById("highlight");
const gutter = document.getElementById("gutter");
const currentLine = document.getElementById("currentLine");
var isApplyingNativeText = false;

function escapeHTML(value) {
    return value
        .replaceAll("&", "&amp;")
        .replaceAll("<", "&lt;")
        .replaceAll(">", "&gt;");
}

function classForScalar(value) {
    const trimmed = value.trim();
    if (trimmed === "&lt;redacted&gt;") return "danger";
    if (/^".*"$/.test(trimmed) || /^'.*'$/.test(trimmed)) return "string";
    if (/^(true|false)$/i.test(trimmed)) return "boolean";
    if (/^(null|\{\}|\[\])$/i.test(trimmed)) return "null";
    if (/^-?\d+(\.\d+)?$/.test(trimmed)) return "number";
    return "string";
}

function firstSeparator(line) {
    let quoted = false;
    let escaped = false;
    for (let index = 0; index < line.length; index += 1) {
        const character = line[index];
        if (escaped) {
            escaped = false;
            continue;
        }
        if (character === "\\") {
            escaped = true;
            continue;
        }
        if (character === "\"") {
            quoted = !quoted;
            continue;
        }
        if (character === ":" && !quoted) {
            const next = line[index + 1];
            if (next === undefined || /\s/.test(next)) return index;
        }
    }
    return -1;
}

function highlightLine(rawLine) {
    const line = escapeHTML(rawLine);
    const firstText = line.search(/\S/);
    if (firstText < 0) return line;

    let prefix = "";
    let contentStart = firstText;
    if (line[firstText] === "-") {
        prefix = line.slice(0, firstText) + '<span class="punctuation">-</span>';
        contentStart = firstText + 1;
        while (contentStart < line.length && /\s/.test(line[contentStart])) {
            prefix += line[contentStart];
            contentStart += 1;
        }
    }

    const colon = firstSeparator(line);
    if (colon > contentStart) {
        const beforeKey = prefix ? "" : line.slice(0, contentStart);
        const key = line.slice(contentStart, colon);
        const afterColon = line.slice(colon + 1);
        const valueStart = afterColon.search(/\S/);
        if (valueStart < 0) {
            return beforeKey + prefix + '<span class="key">' + key + '</span><span class="punctuation">:</span>' + afterColon;
        }
        const spacing = afterColon.slice(0, valueStart);
        const value = afterColon.slice(valueStart);
        return beforeKey + prefix + '<span class="key">' + key + '</span><span class="punctuation">:</span>' + spacing + '<span class="' + classForScalar(value) + '">' + value + '</span>';
    }

    if (prefix) {
        const value = line.slice(contentStart);
        return prefix + '<span class="' + classForScalar(value) + '">' + value + '</span>';
    }

    return line;
}

function lineIndent(text, location) {
    const lineStart = text.lastIndexOf("\n", Math.max(0, location - 1)) + 1;
    const line = text.slice(lineStart, location);
    const base = (line.match(/^\s*/) || [""])[0];
    const trimmed = line.trim();
    return base + ((trimmed.endsWith(":") || trimmed === "-") ? "  " : "");
}

function replaceSelection(value) {
    const start = editor.selectionStart;
    const end = editor.selectionEnd;
    editor.setRangeText(value, start, end, "end");
    editor.dispatchEvent(new Event("input", { bubbles: true }));
}

function currentLineNumber() {
    return editor.value.slice(0, editor.selectionStart).split("\n").length;
}

function render() {
    const lines = editor.value.length === 0 ? [""] : editor.value.split("\n");
    highlight.innerHTML = lines.map(highlightLine).join("\n");
    gutter.innerHTML = lines.map((_, index) => '<div>' + (index + 1) + '</div>').join("");
    syncScroll();
    updateCurrentLine();
}

function syncScroll() {
    highlight.style.transform = 'translate(' + (-editor.scrollLeft) + 'px, ' + (-editor.scrollTop) + 'px)';
    gutter.style.transform = 'translateY(' + (-editor.scrollTop) + 'px)';
}

function updateCurrentLine() {
    const line = currentLineNumber() - 1;
    currentLine.style.transform = 'translateY(' + (10 + line * 17 - editor.scrollTop) + 'px)';
}

function postChange() {
    if (isApplyingNativeText) return;
    window.webkit.messageHandlers.editor.postMessage({ type: "change", text: editor.value });
}

window.vibekubeSetText = function(value) {
    if (editor.value === value) return;
    isApplyingNativeText = true;
    editor.value = value;
    editor.selectionStart = 0;
    editor.selectionEnd = 0;
    editor.scrollTop = 0;
    editor.scrollLeft = 0;
    render();
    isApplyingNativeText = false;
};

window.vibekubeSelectSearch = function(query, ordinal) {
    if (!query || !ordinal) return;

    const haystack = editor.value.toLocaleLowerCase();
    const needle = query.toLocaleLowerCase();
    let from = 0;
    let found = -1;
    for (let count = 1; count <= ordinal; count += 1) {
        found = haystack.indexOf(needle, from);
        if (found < 0) return;
        from = found + Math.max(needle.length, 1);
    }

    const end = found + query.length;
    editor.focus({ preventScroll: true });
    editor.setSelectionRange(found, end);

    const line = editor.value.slice(0, found).split("\n").length - 1;
    const lineTop = line * 17;
    const lineBottom = lineTop + 17;
    if (lineTop < editor.scrollTop || lineBottom > editor.scrollTop + editor.clientHeight) {
        editor.scrollTop = Math.max(0, lineTop - 34);
    }
    syncScroll();
    updateCurrentLine();
};

editor.addEventListener("input", () => {
    render();
    postChange();
});

editor.addEventListener("scroll", syncScroll);
editor.addEventListener("keyup", updateCurrentLine);
editor.addEventListener("click", updateCurrentLine);
editor.addEventListener("select", updateCurrentLine);

editor.addEventListener("keydown", event => {
    if (event.key === "Tab") {
        event.preventDefault();
        replaceSelection("  ");
    } else if (event.key === "Enter") {
        event.preventDefault();
        replaceSelection("\n" + lineIndent(editor.value, editor.selectionStart));
    }
});

editor.value = __INITIAL_TEXT__;
editor.selectionStart = 0;
editor.selectionEnd = 0;
editor.scrollTop = 0;
editor.scrollLeft = 0;
render();
editor.focus();
window.webkit.messageHandlers.editor.postMessage({ type: "ready" });
</script>
</body>
</html>
"""#.replacingOccurrences(of: "__INITIAL_TEXT__", with: initialJSON)
    }

    private static func jsonStringLiteral(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value]),
              let json = String(data: data, encoding: .utf8),
              json.hasPrefix("["),
              json.hasSuffix("]") else {
            return "\"\""
        }
        return String(json.dropFirst().dropLast())
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        @Binding private var text: String
        weak var webView: WKWebView?
        private var isLoaded = false
        private var pendingText: String?
        private var renderedText: String?
        private var pendingSearch: (query: String, ordinal: Int?)?
        private var renderedSearchToken = 0

        init(text: Binding<String>) {
            _text = text
        }

        func setText(_ value: String, in webView: WKWebView) {
            guard isLoaded else {
                pendingText = value
                return
            }
            guard renderedText != value || pendingText != nil else {
                return
            }

            pendingText = nil
            renderedText = value
            webView.evaluateJavaScript("window.vibekubeSetText(\(ManifestYAMLEditorView.jsonStringLiteral(value)));")
        }

        func setSearch(
            query: String,
            ordinal: Int?,
            navigationToken: Int,
            in webView: WKWebView
        ) {
            guard navigationToken != renderedSearchToken else {
                return
            }

            guard isLoaded else {
                pendingSearch = (query, ordinal)
                return
            }

            renderedSearchToken = navigationToken
            pendingSearch = nil
            guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let ordinal else {
                return
            }

            webView.evaluateJavaScript(
                "window.vibekubeSelectSearch(\(ManifestYAMLEditorView.jsonStringLiteral(query)), \(ordinal));"
            )
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any],
                  let type = body["type"] as? String else {
                return
            }

            if type == "ready" {
                isLoaded = true
                if let pendingText, let webView {
                    setText(pendingText, in: webView)
                } else {
                    renderedText = text
                }
                if let pendingSearch, let webView {
                    setSearch(
                        query: pendingSearch.query,
                        ordinal: pendingSearch.ordinal,
                        navigationToken: renderedSearchToken + 1,
                        in: webView
                    )
                }
                return
            }

            guard type == "change",
                  let changedText = body["text"] as? String else {
                return
            }

            DispatchQueue.main.async {
                self.renderedText = changedText
                self.text = changedText
            }
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
