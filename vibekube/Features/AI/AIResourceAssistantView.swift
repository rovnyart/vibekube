import AppKit
import SwiftUI

@MainActor
enum AIResourceAssistantWindow {
    private static let registry = AIResourceAssistantWindowRegistry()

    static func open(detail: ResourceDetailSnapshot, appModel: AppModel) {
        registry.open(detail: detail, appModel: appModel)
    }
}

@MainActor
private final class AIResourceAssistantWindowRegistry: NSObject, NSWindowDelegate {
    private var windows: [String: NSWindow] = [:]

    func open(detail: ResourceDetailSnapshot, appModel: AppModel) {
        let key = detail.query.id
        if let window = windows[key] {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1220, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "AI Resource Assistant"
        window.subtitle = detail.query.id
        window.minSize = NSSize(width: 980, height: 660)
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.delegate = self
        window.identifier = NSUserInterfaceItemIdentifier(key)
        window.contentView = NSHostingView(
            rootView: AIResourceAssistantView(detail: detail) { [weak window] in
                window?.close()
            }
            .environmentObject(appModel)
        )

        windows[key] = window
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let key = window.identifier?.rawValue else {
            return
        }
        windows[key] = nil
    }
}

struct AIResourceAssistantView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var messages: [AIChatTranscriptMessage] = []
    @State private var draftPrompt = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var selectedContextSectionID: AIContextSection.ID?
    @State private var sentContext: AIContextBundle?
    @FocusState private var composerFocused: Bool

    let detail: ResourceDetailSnapshot
    var close: (() -> Void)?

    var body: some View {
        ZStack {
            assistantBackground

            VStack(spacing: 0) {
                header

                if appModel.aiIsConfigured {
                    configuredContent
                } else {
                    notConfiguredContent
                }
            }
        }
        .frame(minWidth: 980, idealWidth: 1220, maxWidth: .infinity, minHeight: 660, idealHeight: 820, maxHeight: .infinity)
        .task(id: detail.query.id) {
            appModel.loadResourceEvents(for: detail)
        }
    }

    private var assistantBackground: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)

            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.10),
                    Color.cyan.opacity(0.06),
                    Color(nsColor: .windowBackgroundColor).opacity(0.00)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(.thinMaterial)
                Image(systemName: "sparkles")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("AI Resource Assistant")
                        .font(.title3.weight(.semibold))
                    AIModelStatusChip(text: appModel.aiProviderSettings.selectedModelID ?? "No model", tint: appModel.aiIsConfigured ? .green : .orange)
                }

                Text(context.title)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .textSelection(.enabled)
            }

            Spacer()

            Button {
                copyToPasteboard(context.promptText)
            } label: {
                Label("Copy Context", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)
            .help("Copy redacted context")

            Button {
                close?()
            } label: {
                Label("Close", systemImage: "xmark")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.28))
                .frame(height: 1)
        }
    }

    private var configuredContent: some View {
        HSplitView {
            AIContextPanel(context: context, selectedSectionID: $selectedContextSectionID)
                .frame(minWidth: 330, idealWidth: 430, maxWidth: 560)

            chatPane
                .frame(minWidth: 560)
        }
    }

    private var chatPane: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if messages.isEmpty {
                            promptSuggestions
                                .padding(.top, 8)
                        }

                        ForEach(messages) { message in
                            AIChatBubble(message: message)
                                .id(message.id)
                        }

                        if isSending, messages.last?.role != .assistant {
                            AIThinkingCard()
                        }

                        if let errorMessage {
                            AIErrorCard(message: errorMessage)
                        }
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(.regularMaterial.opacity(0.42))
                .onChange(of: messages.map(\.text).joined(separator: "\u{0}")) {
                    if let last = messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }

            composer
        }
    }

    private var promptSuggestions: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Start with the resource")
                        .font(.headline)
                    Text("Vibekube sends only the redacted context shown on the left.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                LiquidThinkingView()
                    .opacity(0.72)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], alignment: .leading, spacing: 10) {
                suggestionButton("Explain what is happening", systemImage: "text.magnifyingglass")
                suggestionButton("Summarize warning events", systemImage: "exclamationmark.triangle")
                suggestionButton("Explain pod readiness failure", systemImage: "checklist")
                suggestionButton("Summarize selected logs", systemImage: "terminal")
                suggestionButton("Suggest copy-only kubectl checks", systemImage: "doc.on.clipboard")
                suggestionButton("Draft YAML remediation without applying it", systemImage: "doc.badge.gearshape")
            }
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.22))
        }
    }

    private func suggestionButton(_ title: String, systemImage: String) -> some View {
        Button {
            draftPrompt = title
            sendPrompt()
        } label: {
            HStack(spacing: 9) {
                Image(systemName: systemImage)
                    .foregroundStyle(Color.accentColor)
                Text(title)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(minHeight: 46)
        }
        .buttonStyle(.plain)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.56), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.20))
        }
        .disabled(isSending)
    }

    private var composer: some View {
        VStack(spacing: 10) {
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Ask about the selected resource", text: $draftPrompt, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .lineLimit(1...6)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.68), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(composerFocused ? Color.accentColor.opacity(0.62) : Color(nsColor: .separatorColor).opacity(0.28))
                    }
                    .focused($composerFocused)
                    .onSubmit {
                        sendPrompt()
                    }

                Button {
                    sendPrompt()
                } label: {
                    Label(isSending ? "Streaming" : "Send", systemImage: isSending ? "hourglass" : "paperplane.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isSending || draftPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
            }

            HStack(spacing: 8) {
                Label("Enter inserts a newline", systemImage: "return")
                Text("Command-Return sends")
                Spacer()
                if isSending {
                    LiquidThinkingView()
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.25))
                .frame(height: 1)
        }
    }

    private var notConfiguredContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "key.slash")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)

            Text("AI is not configured")
                .font(.title3.weight(.semibold))

            Text("Add a provider URL, Keychain-stored API key, and model in Settings before Vibekube can send any AI request.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)

            Button {
                appModel.selectResource(.settings)
                close?()
            } label: {
                Label("Open AI Settings", systemImage: "gearshape")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }

    private var context: AIContextBundle {
        sentContext ?? appModel.aiContextBundle(for: detail)
    }

    private func sendPrompt() {
        let prompt = draftPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isSending else {
            return
        }

        draftPrompt = ""
        errorMessage = nil
        isSending = true
        messages.append(AIChatTranscriptMessage(role: .user, text: prompt))
        messages.append(
            AIChatTranscriptMessage(
                role: .tool,
                text: "- Gathering read-only cluster context before asking the provider.",
                isStreaming: true
            )
        )
        let toolID = messages.last?.id

        Task {
            do {
                let gatheredContext = await appModel.gatherAIContext(for: detail, userPrompt: prompt)
                await MainActor.run {
                    sentContext = gatheredContext.context
                    selectedContextSectionID = gatheredContext.context.sections.first(where: { $0.title == "Related Pod Health" })?.id
                        ?? "vibekube-read-only-tools"
                    if let toolID,
                       let index = messages.firstIndex(where: { $0.id == toolID }) {
                        messages[index].text = gatheredContext.toolSummary
                        messages[index].isStreaming = false
                    }
                    messages.append(AIChatTranscriptMessage(role: .assistant, text: "", isStreaming: true))
                }

                let assistantID = await MainActor.run {
                    messages.last?.id
                }
                let stream = try appModel.streamAIChat(context: gatheredContext.context, userPrompt: prompt)
                var didReceiveText = false
                for try await chunk in stream {
                    await MainActor.run {
                        guard let assistantID,
                              let index = messages.firstIndex(where: { $0.id == assistantID }) else {
                            return
                        }
                        if !chunk.textDelta.isEmpty {
                            didReceiveText = true
                            messages[index].text += chunk.textDelta
                        }
                        if chunk.isFinished {
                            messages[index].isStreaming = false
                            isSending = false
                        }
                    }
                }

                await MainActor.run {
                    if let assistantID,
                       let index = messages.firstIndex(where: { $0.id == assistantID }) {
                        messages[index].isStreaming = false
                        if !didReceiveText && messages[index].text.isEmpty {
                            messages[index].text = "The provider finished without returning text."
                        }
                    }
                    isSending = false
                }
            } catch {
                await MainActor.run {
                    if let toolID,
                       let index = messages.firstIndex(where: { $0.id == toolID }) {
                        messages[index].isStreaming = false
                    }
                    errorMessage = error.localizedDescription
                    isSending = false
                }
            }
        }
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

private struct AIModelStatusChip: View {
    let text: String
    let tint: Color

    var body: some View {
        Label(text, systemImage: "cpu")
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .foregroundStyle(tint)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

private struct AIContextPanel: View {
    let context: AIContextBundle
    @Binding var selectedSectionID: AIContextSection.ID?

    private var selectedSection: AIContextSection? {
        if let selectedSectionID,
           let section = context.sections.first(where: { $0.id == selectedSectionID }) {
            return section
        }
        return context.sections.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Redacted Context")
                            .font(.headline)
                        Text("\(context.sections.count) sections · sent on demand")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Label("Safe", systemImage: "lock.shield")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.12), in: Capsule())
                }

                Text(context.identity)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.58), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .padding(16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    sectionPicker

                    if let selectedSection {
                        AIContextSectionCard(section: selectedSection)
                    }
                }
                .padding(14)
            }
        }
        .background(.thinMaterial)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.28))
                .frame(width: 1)
        }
        .onAppear {
            ensureSelectionExists()
        }
        .onChange(of: context.sections.map(\.id)) {
            ensureSelectionExists()
        }
    }

    private var sectionPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(context.sections) { section in
                Button {
                    selectedSectionID = section.id
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: icon(for: section))
                            .foregroundStyle(section.id == selectedSection?.id ? Color.accentColor : Color.secondary)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(section.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(sectionSummary(section.content))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(section.id == selectedSection?.id ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor).opacity(0.38), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(section.id == selectedSection?.id ? Color.accentColor.opacity(0.28) : Color(nsColor: .separatorColor).opacity(0.16))
                }
            }
        }
    }

    private func icon(for section: AIContextSection) -> String {
        let title = section.title.lowercased()
        if title.contains("yaml") {
            return "curlybraces"
        }
        if title.contains("event") {
            return "waveform.path.ecg"
        }
        if title.contains("log") {
            return "terminal"
        }
        if title.contains("related") {
            return "point.3.connected.trianglepath.dotted"
        }
        return "doc.text.magnifyingglass"
    }

    private func sectionSummary(_ content: String) -> String {
        content
            .split(separator: "\n")
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
            .map(String.init) ?? "No content"
    }

    private func ensureSelectionExists() {
        guard !context.sections.isEmpty else {
            selectedSectionID = nil
            return
        }
        if let selectedSectionID,
           context.sections.contains(where: { $0.id == selectedSectionID }) {
            return
        }
        selectedSectionID = context.sections.first?.id
    }
}

private struct AIContextSectionCard: View {
    let section: AIContextSection

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(section.title)
                    .font(.headline)
                Spacer()
                Text("\(section.content.split(separator: "\n", omittingEmptySubsequences: false).count.formatted()) lines")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            AICodeBlockView(language: language, code: section.content)
        }
    }

    private var language: String {
        section.title.lowercased().contains("yaml") ? "yaml" : "text"
    }
}

private struct AIChatTranscriptMessage: Identifiable, Equatable {
    enum Role {
        case user
        case tool
        case assistant
    }

    var id = UUID()
    var role: Role
    var text: String
    var isStreaming = false
}

private struct AIChatBubble: View {
    let message: AIChatTranscriptMessage
    @State private var copied = false

    var body: some View {
        HStack(alignment: .top) {
            if message.role == .user {
                Spacer(minLength: 120)
            }

            VStack(alignment: .leading, spacing: 10) {
                bubbleHeader

                if message.role == .assistant || message.role == .tool {
                    AIMarkdownView(text: message.text, isStreaming: message.isStreaming)
                } else {
                    Text(message.text)
                        .font(.callout)
                        .lineSpacing(3)
                        .textSelection(.enabled)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: message.role == .user ? 520 : 760, alignment: .leading)
            .background(background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(border, lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.06), radius: 18, x: 0, y: 8)

            if message.role != .user {
                Spacer(minLength: 80)
            }
        }
    }

    private var bubbleHeader: some View {
        HStack(spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)

            if message.isStreaming {
                Text("streaming")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.7), in: Capsule())
            }

            Spacer()

            Button {
                copy(message.text)
            } label: {
                Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help("Copy message")
            .disabled(message.text.isEmpty)
        }
    }

    private var background: some ShapeStyle {
        if message.role == .user {
            return AnyShapeStyle(Color.accentColor.opacity(0.14))
        }
        if message.role == .tool {
            return AnyShapeStyle(Color(nsColor: .controlBackgroundColor).opacity(0.54))
        }
        return AnyShapeStyle(.thinMaterial)
    }

    private var border: Color {
        switch message.role {
        case .user:
            Color.accentColor.opacity(0.26)
        case .tool:
            Color.blue.opacity(0.20)
        case .assistant:
            Color(nsColor: .separatorColor).opacity(0.28)
        }
    }

    private var title: String {
        switch message.role {
        case .user:
            "You"
        case .tool:
            "Vibekube tools"
        case .assistant:
            "Vibekube AI"
        }
    }

    private var systemImage: String {
        switch message.role {
        case .user:
            "person.crop.circle"
        case .tool:
            "wrench.and.screwdriver"
        case .assistant:
            "sparkles"
        }
    }

    private var tint: Color {
        switch message.role {
        case .user:
            .secondary
        case .tool:
            .blue
        case .assistant:
            Color.accentColor
        }
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

private struct AIThinkingCard: View {
    var body: some View {
        HStack(spacing: 12) {
            LiquidThinkingView()
            Text("Asking provider")
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.22))
        }
    }
}

private struct AIErrorCard: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.callout)
                .foregroundStyle(.red)
                .textSelection(.enabled)
        }
        .padding(14)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.red.opacity(0.18))
        }
    }
}
