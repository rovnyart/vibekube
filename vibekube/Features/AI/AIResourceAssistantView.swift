import AppKit
import SwiftUI

struct AIResourceAssistantView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var messages: [AIChatTranscriptMessage] = []
    @State private var draftPrompt = ""
    @State private var isSending = false
    @State private var errorMessage: String?

    let detail: ResourceDetailSnapshot

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            if appModel.aiIsConfigured {
                configuredContent
            } else {
                notConfiguredContent
            }
        }
        .frame(minWidth: 860, idealWidth: 980, minHeight: 620, idealHeight: 720)
        .background(Color(nsColor: .windowBackgroundColor))
        .task(id: detail.query.id) {
            appModel.loadResourceEvents(for: detail)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.title3)
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text("AI Resource Assistant")
                    .font(.headline)
                Text(context.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Label("Close", systemImage: "xmark")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var configuredContent: some View {
        HSplitView {
            contextPreview
                .frame(minWidth: 320, idealWidth: 390)

            chatPane
                .frame(minWidth: 420)
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
                dismiss()
                appModel.selectResource(.settings)
            } label: {
                Label("Open AI Settings", systemImage: "gearshape")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }

    private var contextPreview: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Redacted Context")
                    .font(.headline)

                Spacer()

                Button {
                    copyToPasteboard(context.promptText)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("Copy redacted context")
            }
            .padding(14)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(context.identity)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)

                    ForEach(context.sections) { section in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(section.title)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)

                            Text(section.content)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var chatPane: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if messages.isEmpty {
                            promptSuggestions
                                .padding(.top, 6)
                        }

                        ForEach(messages) { message in
                            AIChatBubble(message: message)
                                .id(message.id)
                        }

                        if isSending {
                            ProgressView("Asking provider")
                                .padding(.vertical, 8)
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.callout)
                                .foregroundStyle(.red)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: messages.count) {
                    if let last = messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }

            Divider()

            composer
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var promptSuggestions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ask about this resource")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 8)], alignment: .leading, spacing: 8) {
                suggestionButton("Explain what is happening")
                suggestionButton("Summarize warning events")
                suggestionButton("Explain pod readiness failure")
                suggestionButton("Summarize selected logs")
                suggestionButton("Suggest copy-only kubectl checks")
                suggestionButton("Draft YAML remediation without applying it")
            }
        }
    }

    private func suggestionButton(_ title: String) -> some View {
        Button(title) {
            draftPrompt = title
            sendPrompt()
        }
        .buttonStyle(.bordered)
        .disabled(isSending)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Ask about the selected resource", text: $draftPrompt, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...5)
                .onSubmit {
                    sendPrompt()
                }

            Button {
                sendPrompt()
            } label: {
                Label("Send", systemImage: "paperplane.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSending || draftPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(12)
    }

    private var context: AIContextBundle {
        appModel.aiContextBundle(for: detail)
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

        let context = context
        Task {
            do {
                let response = try await appModel.completeAIChat(context: context, userPrompt: prompt)
                await MainActor.run {
                    messages.append(AIChatTranscriptMessage(role: .assistant, text: response.text))
                    isSending = false
                }
            } catch {
                await MainActor.run {
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

private struct AIChatTranscriptMessage: Identifiable, Equatable {
    enum Role {
        case user
        case assistant
    }

    var id = UUID()
    var role: Role
    var text: String
}

private struct AIChatBubble: View {
    let message: AIChatTranscriptMessage

    var body: some View {
        HStack(alignment: .top) {
            if message.role == .user {
                Spacer(minLength: 80)
            }

            Text(message.text)
                .font(.callout)
                .textSelection(.enabled)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(backgroundStyle, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(borderStyle, lineWidth: 1)
                }

            if message.role == .assistant {
                Spacer(minLength: 80)
            }
        }
    }

    private var backgroundStyle: Color {
        switch message.role {
        case .user:
            Color.accentColor.opacity(0.12)
        case .assistant:
            Color(nsColor: .textBackgroundColor)
        }
    }

    private var borderStyle: Color {
        switch message.role {
        case .user:
            Color.accentColor.opacity(0.25)
        case .assistant:
            Color.secondary.opacity(0.18)
        }
    }
}
