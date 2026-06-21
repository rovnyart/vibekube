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
    @State private var sendTask: Task<Void, Never>?
    @State private var autoFollowsChat = true
    @State private var showsJumpToBottom = false
    @State private var scrollToBottomGeneration = 0
    @State private var lastScrollRequestAt = Date.distantPast
    @State private var composerFocused = false
    @State private var composerTextHeight: CGFloat = 30

    private let chatBottomID = "ai-chat-bottom"

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
        .onDisappear {
            stopGenerating()
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
                clearChat()
            } label: {
                Label("Clear Chat", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .disabled(messages.isEmpty && errorMessage == nil && sentContext == nil)
            .help("Clear this chat")

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
                ZStack(alignment: .bottom) {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            AIChatScrollObserver { isAtBottom in
                                autoFollowsChat = isAtBottom
                                showsJumpToBottom = !isAtBottom
                            }
                            .frame(width: 0, height: 0)

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

                            Color.clear
                                .frame(height: 1)
                                .id(chatBottomID)
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .background(.regularMaterial.opacity(0.42))
                    .onChange(of: scrollToBottomGeneration) {
                        scrollToBottomIfNeeded(proxy: proxy)
                    }
                    .onChange(of: isSending) {
                        requestChatAutoScroll(force: true)
                    }

                    if showsJumpToBottom {
                        Button {
                            autoFollowsChat = true
                            showsJumpToBottom = false
                            withAnimation(.snappy(duration: 0.18)) {
                                proxy.scrollTo(chatBottomID, anchor: .bottom)
                            }
                        } label: {
                            Label("Jump to bottom", systemImage: "arrow.down")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        .background(.thinMaterial, in: Capsule())
                        .overlay {
                            Capsule()
                                .strokeBorder(Color.accentColor.opacity(0.26))
                        }
                        .shadow(color: Color.black.opacity(0.12), radius: 18, x: 0, y: 8)
                        .padding(.bottom, 14)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
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
                ZStack(alignment: .topLeading) {
                    AIComposerTextView(
                        text: $draftPrompt,
                        measuredHeight: $composerTextHeight,
                        onSubmit: sendPrompt,
                        onFocusChange: { composerFocused = $0 }
                    )
                    .frame(height: composerTextHeight)

                    if draftPrompt.isEmpty {
                        Text("Ask about the selected resource")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 1)
                            .allowsHitTesting(false)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(minHeight: 54)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.68), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(composerFocused ? Color.accentColor.opacity(0.62) : Color(nsColor: .separatorColor).opacity(0.28))
                }

                Button {
                    if isSending {
                        stopGenerating()
                    } else {
                        sendPrompt()
                    }
                } label: {
                    Label(isSending ? "Stop" : "Send", systemImage: isSending ? "stop.fill" : "paperplane.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(height: 54)
                .tint(isSending ? .red : nil)
                .disabled(!isSending && draftPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
            }

            HStack(spacing: 10) {
                HStack(spacing: 5) {
                    AIKeycap("↩")
                    Text("newline")
                }

                HStack(spacing: 5) {
                    AIKeycap("⌘")
                    AIKeycap("↩")
                    Text("send")
                }

                Spacer()
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

    private func scrollToBottomIfNeeded(proxy: ScrollViewProxy) {
        guard autoFollowsChat else {
            showsJumpToBottom = true
            return
        }
        withAnimation(.snappy(duration: 0.16)) {
            proxy.scrollTo(chatBottomID, anchor: .bottom)
        }
    }

    private func requestChatAutoScroll(force: Bool = false) {
        guard autoFollowsChat else {
            showsJumpToBottom = true
            return
        }

        let now = Date()
        guard force || now.timeIntervalSince(lastScrollRequestAt) >= 0.12 else {
            return
        }
        lastScrollRequestAt = now
        scrollToBottomGeneration += 1
    }

    private func sendPrompt() {
        let prompt = draftPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isSending else {
            return
        }

        draftPrompt = ""
        errorMessage = nil
        isSending = true
        autoFollowsChat = true
        showsJumpToBottom = false
        messages.append(AIChatTranscriptMessage(role: .user, text: prompt))
        messages.append(
            AIChatTranscriptMessage(
                role: .tool,
                text: "- Gathering read-only cluster context before asking the provider.",
                isStreaming: true
            )
        )
        let toolID = messages.last?.id
        requestChatAutoScroll(force: true)

        let task = Task {
            do {
                let gatheredContext = await appModel.gatherAIContext(for: detail, userPrompt: prompt)
                try Task.checkCancellation()
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
                    requestChatAutoScroll(force: true)
                }

                let assistantID = await MainActor.run {
                    messages.last?.id
                }
                let stream = try appModel.streamAIChat(context: gatheredContext.context, userPrompt: prompt)
                var didReceiveText = false
                for try await chunk in stream {
                    try Task.checkCancellation()
                    if !chunk.textDelta.isEmpty {
                        didReceiveText = true
                        await appendAssistantText(chunk.textDelta, assistantID: assistantID)
                    }
                    if chunk.isFinished {
                        await MainActor.run {
                            guard let assistantID,
                                  let index = messages.firstIndex(where: { $0.id == assistantID }) else {
                                return
                            }
                            messages[index].isStreaming = false
                            isSending = false
                            requestChatAutoScroll(force: true)
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
                    sendTask = nil
                    requestChatAutoScroll(force: true)
                }
            } catch is CancellationError {
                await MainActor.run {
                    finishStoppedResponse()
                }
            } catch {
                await MainActor.run {
                    if let toolID,
                       let index = messages.firstIndex(where: { $0.id == toolID }) {
                        messages[index].isStreaming = false
                    }
                    errorMessage = error.localizedDescription
                    isSending = false
                    sendTask = nil
                }
            }
        }
        sendTask = task
    }

    private func appendAssistantText(_ text: String, assistantID: AIChatTranscriptMessage.ID?) async {
        await MainActor.run {
            guard let assistantID,
                  let index = messages.firstIndex(where: { $0.id == assistantID }) else {
                return
            }
            messages[index].text += text
            requestChatAutoScroll()
        }
    }

    private func stopGenerating() {
        guard isSending || sendTask != nil else {
            return
        }
        sendTask?.cancel()
        finishStoppedResponse()
    }

    private func finishStoppedResponse() {
        sendTask = nil
        isSending = false
        for index in messages.indices where messages[index].isStreaming {
            messages[index].isStreaming = false
            if messages[index].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                messages[index].text = "Stopped."
            } else if messages[index].role == .tool,
                      messages[index].text == "- Gathering read-only cluster context before asking the provider." {
                messages[index].text = "- Stopped before asking the provider."
            }
        }
    }

    private func clearChat() {
        stopGenerating()
        messages.removeAll()
        draftPrompt = ""
        errorMessage = nil
        sentContext = nil
        selectedContextSectionID = nil
        autoFollowsChat = true
        showsJumpToBottom = false
        requestChatAutoScroll(force: true)
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

private struct AIKeycap: View {
    let symbol: String

    init(_ symbol: String) {
        self.symbol = symbol
    }

    var body: some View {
        Text(symbol)
            .font(.caption.weight(.semibold))
            .monospaced()
            .frame(minWidth: 22, minHeight: 20)
            .foregroundStyle(.secondary)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.86), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.34))
            }
    }
}

private struct AIComposerTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var measuredHeight: CGFloat
    var onSubmit: () -> Void
    var onFocusChange: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay

        let textView = AIComposerNSTextView(frame: .zero)
        textView.delegate = context.coordinator
        textView.onCommandReturn = onSubmit
        textView.string = text
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.textColor = .labelColor
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? AIComposerNSTextView else {
            return
        }

        textView.onCommandReturn = onSubmit
        if textView.string != text {
            textView.string = text
        }
        context.coordinator.publishHeight(for: textView)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: AIComposerTextView

        init(_ parent: AIComposerTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                return
            }
            parent.text = textView.string
            publishHeight(for: textView)
        }

        func textDidBeginEditing(_ notification: Notification) {
            parent.onFocusChange(true)
        }

        func textDidEndEditing(_ notification: Notification) {
            parent.onFocusChange(false)
        }

        func publishHeight(for textView: NSTextView) {
            guard let textContainer = textView.textContainer,
                  let layoutManager = textView.layoutManager else {
                return
            }

            layoutManager.ensureLayout(for: textContainer)
            let usedHeight = layoutManager.usedRect(for: textContainer).height
            let height = min(112, max(30, ceil(usedHeight + 2)))
            guard abs(parent.measuredHeight - height) > 0.5 else {
                return
            }

            DispatchQueue.main.async {
                self.parent.measuredHeight = height
            }
        }
    }
}

private final class AIComposerNSTextView: NSTextView {
    var onCommandReturn: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        if isReturn, flags.contains(.command) {
            onCommandReturn?()
            return
        }

        super.keyDown(with: event)
    }
}

private struct AIChatScrollObserver: NSViewRepresentable {
    var onBottomStateChanged: (Bool) -> Void

    func makeNSView(context: Context) -> AIChatScrollObserverView {
        let view = AIChatScrollObserverView()
        view.onBottomStateChanged = onBottomStateChanged
        DispatchQueue.main.async {
            view.attachToScrollView()
        }
        return view
    }

    func updateNSView(_ nsView: AIChatScrollObserverView, context: Context) {
        nsView.onBottomStateChanged = onBottomStateChanged
        DispatchQueue.main.async {
            nsView.attachToScrollView()
            nsView.publishBottomState()
        }
    }
}

private final class AIChatScrollObserverView: NSView {
    var onBottomStateChanged: ((Bool) -> Void)?

    private weak var observedScrollView: NSScrollView?
    private var boundsObserver: NSObjectProtocol?
    private var lastIsAtBottom: Bool?

    deinit {
        detach()
    }

    func attachToScrollView() {
        guard let scrollView = enclosingScrollView,
              scrollView !== observedScrollView else {
            return
        }

        detach()
        observedScrollView = scrollView
        scrollView.contentView.postsBoundsChangedNotifications = true

        boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            self?.publishBottomState()
        }

        publishBottomState()
    }

    func publishBottomState() {
        guard let scrollView = observedScrollView ?? enclosingScrollView else {
            return
        }

        let visibleMaxY = scrollView.contentView.bounds.maxY
        let contentHeight = scrollView.documentView?.bounds.height ?? scrollView.contentView.bounds.height
        let isAtBottom = max(0, contentHeight - visibleMaxY) <= 28
        guard isAtBottom != lastIsAtBottom else {
            return
        }

        lastIsAtBottom = isAtBottom
        onBottomStateChanged?(isAtBottom)
    }

    private func detach() {
        if let boundsObserver {
            NotificationCenter.default.removeObserver(boundsObserver)
        }
        boundsObserver = nil
        observedScrollView = nil
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
            ProgressView()
                .controlSize(.small)
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
