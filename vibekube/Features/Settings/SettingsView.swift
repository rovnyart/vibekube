import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var exportStatus: String?
    @State private var kubeconfigPathDraft = ""
    @State private var aiAPIKeyDraft = ""
    @State private var aiHeadersDraft: [AISecretHeader] = []
    @State private var aiSecretStatus: String?
    @State private var showsResetLocalPreferencesConfirmation = false

    private let logLineLimitOptions = [1_000, 5_000, 10_000, 20_000, 50_000]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                SectionSurface(title: "Kubernetes", systemImage: "shippingbox") {
                    VStack(alignment: .leading, spacing: 14) {
                        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 18, verticalSpacing: 12) {
                            GridRow {
                                Text("Kubeconfig")
                                    .foregroundStyle(.secondary)

                                VStack(alignment: .leading, spacing: 8) {
                                    TextField("Default: $KUBECONFIG or ~/.kube/config", text: $kubeconfigPathDraft)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.callout.monospaced())

                                    HStack(spacing: 8) {
                                        Button {
                                            chooseKubeconfigFile()
                                        } label: {
                                            Label("Browse", systemImage: "folder")
                                        }

                                        Button {
                                            applyKubeconfigPathDraft()
                                        } label: {
                                            Label("Apply", systemImage: "arrow.clockwise")
                                        }
                                        .disabled(!kubeconfigPathHasChanges)

                                        Button {
                                            resetKubeconfigPath()
                                        } label: {
                                            Label("Reset", systemImage: "arrow.uturn.backward")
                                        }
                                        .disabled(appModel.kubeconfigPathOverride == nil && kubeconfigPathDraft.isEmpty)
                                    }
                                    .controlSize(.small)

                                    Text(kubeconfigPathHelpText)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            GridRow {
                                Text("Initial namespace")
                                    .foregroundStyle(.secondary)

                                Picker("Initial namespace", selection: defaultNamespaceBehaviorBinding) {
                                    ForEach(DefaultNamespaceBehavior.allCases) { behavior in
                                        Text(behavior.title).tag(behavior)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .frame(width: 220, alignment: .leading)
                            }

                        }

                        Toggle("Use live resource watches", isOn: resourceWatchesEnabledBinding)
                    }
                }

                aiSettingsSection

                SectionSurface(title: "Appearance", systemImage: "paintbrush") {
                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 18, verticalSpacing: 12) {
                        GridRow {
                            Text("Theme")
                                .foregroundStyle(.secondary)

                            Picker("Theme", selection: appAppearanceBinding) {
                                ForEach(AppAppearance.allCases) { appearance in
                                    Text(appearance.title).tag(appearance)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(width: 300, alignment: .leading)
                        }

                        GridRow {
                            Text("Table density")
                                .foregroundStyle(.secondary)

                            Picker("Table density", selection: tableDensityBinding) {
                                ForEach(TableDensity.allCases) { density in
                                    Text(density.title).tag(density)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(width: 300, alignment: .leading)
                        }
                    }
                }

                SectionSurface(title: "Debugging", systemImage: "ladybug") {
                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 18, verticalSpacing: 12) {
                        GridRow {
                            Text("External terminal")
                                .foregroundStyle(.secondary)

                            Picker("External terminal", selection: externalTerminalAppBinding) {
                                ForEach(ExternalTerminalApp.allCases) { terminalApp in
                                    Text(terminalApp.title).tag(terminalApp)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(width: 180, alignment: .leading)
                        }
                    }
                }

                SectionSurface(title: "Logs", systemImage: "terminal") {
                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 18, verticalSpacing: 12) {
                        GridRow {
                            Text("Live buffer")
                                .foregroundStyle(.secondary)

                            Picker("Live buffer", selection: podLogLineLimitBinding) {
                                ForEach(logLineLimitOptions, id: \.self) { lineLimit in
                                    Text("\(lineLimit.formatted()) lines").tag(lineLimit)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(width: 180, alignment: .leading)
                        }
                    }
                }

                SectionSurface(title: "Secrets", systemImage: "eye") {
                    Toggle("Confirm before revealing Secret-backed values", isOn: secretRevealConfirmationBinding)
                }

                SectionSurface(title: "Diagnostics", systemImage: "waveform.path.ecg.rectangle") {
                    VStack(alignment: .leading, spacing: 14) {
                        Toggle("Write diagnostics to file", isOn: fileLoggingBinding)

                        Toggle("Include cluster names in diagnostics", isOn: includeClusterNamesBinding)
                            .disabled(!appModel.diagnosticsFileLoggingEnabled)

                        HStack {
                            Stepper("Keep logs for \(appModel.diagnosticsRetentionDays) days", value: retentionBinding, in: 1...30)
                            Spacer()
                            Text("50 MB cap")
                                .foregroundStyle(.secondary)
                        }
                        .disabled(!appModel.diagnosticsFileLoggingEnabled)

                        Divider()

                        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 8) {
                            GridRow {
                                Text("Location")
                                    .foregroundStyle(.secondary)
                                Text(appModel.diagnosticsLogDirectoryPath)
                                    .font(.callout.monospaced())
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .textSelection(.enabled)
                            }
                        }

                        HStack(spacing: 10) {
                            Button {
                                copyDiagnostics()
                            } label: {
                                Label("Copy Export", systemImage: "doc.on.doc")
                            }

                            Button {
                                openLogDirectory()
                            } label: {
                                Label("Open Folder", systemImage: "folder")
                            }

                            Button {
                                appModel.clearRecentDiagnostics()
                                exportStatus = "Recent diagnostics cleared"
                            } label: {
                                Label("Clear Recent", systemImage: "trash")
                            }

                            if let exportStatus {
                                Text(exportStatus)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                SectionSurface(title: "Privacy", systemImage: "lock.shield") {
                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 18, verticalSpacing: 10) {
                        GridRow {
                            Text("Telemetry")
                                .foregroundStyle(.secondary)
                            Text("None")
                        }

                        GridRow {
                            Text("File diagnostics")
                                .foregroundStyle(.secondary)
                            Text("Off by default")
                        }

                        GridRow {
                            Text("Log folder")
                                .foregroundStyle(.secondary)
                            Text("~/Library/Logs/Vibekube")
                                .font(.callout.monospaced())
                                .textSelection(.enabled)
                        }

                        GridRow {
                            Text("Sensitive data")
                                .foregroundStyle(.secondary)
                            Text("Secrets and credentials are redacted")
                        }
                    }
                }

                SectionSurface(title: "Maintenance", systemImage: "wrench.and.screwdriver") {
                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Local preferences")
                                .font(.headline)
                            Text("Reset saved navigation, namespace choices, kubeconfig path, appearance, debugging, logs, Secret, watch, and diagnostics settings.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()

                        Button(role: .destructive) {
                            showsResetLocalPreferencesConfirmation = true
                        } label: {
                            Label("Reset", systemImage: "arrow.counterclockwise")
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 820, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityIdentifier("settings.view")
        .onAppear {
            kubeconfigPathDraft = appModel.kubeconfigPathOverride ?? ""
            syncAISecretDrafts()
        }
        .onChange(of: appModel.kubeconfigPathOverride) { _, newValue in
            kubeconfigPathDraft = newValue ?? ""
        }
        .onChange(of: appModel.aiProviderSecrets) {
            syncAISecretDrafts()
        }
        .alert("Reset Local Preferences?", isPresented: $showsResetLocalPreferencesConfirmation) {
            Button("Reset", role: .destructive) {
                appModel.resetLocalPreferences()
                kubeconfigPathDraft = appModel.kubeconfigPathOverride ?? ""
                syncAISecretDrafts()
                exportStatus = "Local preferences reset"
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This resets Vibekube settings and saved navigation on this Mac. It does not delete diagnostics files, kubeconfig files, or cluster data.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Settings")
                .font(.largeTitle.weight(.semibold))
            Text("Local app behavior")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var aiSettingsSection: some View {
        SectionSurface(title: "AI", systemImage: "sparkles") {
            VStack(alignment: .leading, spacing: 14) {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 18, verticalSpacing: 12) {
                    GridRow {
                        Text("Provider shape")
                            .foregroundStyle(.secondary)

                        Picker("Provider shape", selection: aiProviderShapeBinding) {
                            ForEach(AIProviderShape.allCases) { shape in
                                Text(shape.title).tag(shape)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 360, alignment: .leading)
                    }

                    GridRow {
                        Text("Preset")
                            .foregroundStyle(.secondary)

                        Picker("Preset", selection: aiProviderPresetBinding) {
                            ForEach(AIProviderPreset.allCases) { preset in
                                Text(preset.title).tag(preset)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 220, alignment: .leading)
                    }

                    GridRow {
                        Text("Base URL")
                            .foregroundStyle(.secondary)

                        TextField("https://provider.example/v1", text: aiBaseURLBinding)
                            .textFieldStyle(.roundedBorder)
                            .font(.callout.monospaced())
                    }

                    GridRow {
                        Text("API key")
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 8) {
                            SecureField("Saved to Keychain", text: $aiAPIKeyDraft)
                                .textFieldStyle(.roundedBorder)

                            HStack(spacing: 8) {
                                Button {
                                    saveAISecrets()
                                } label: {
                                    Label("Save Secrets", systemImage: "key")
                                }
                                .disabled(!hasAISecretDraft)

                                Button(role: .destructive) {
                                    clearAISecrets()
                                } label: {
                                    Label("Clear", systemImage: "trash")
                                }
                                .disabled(!appModel.aiProviderSecrets.hasAPIKey && aiHeadersDraft.isEmpty && aiAPIKeyDraft.isEmpty)

                                if appModel.aiProviderSecrets.hasAPIKey {
                                    Label("Stored in Keychain", systemImage: "checkmark.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.green)
                                }

                                if let aiSecretStatus {
                                    Text(aiSecretStatus)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .controlSize(.small)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Extra headers")
                            .font(.headline)

                        Spacer()

                        Button {
                            aiHeadersDraft.append(AISecretHeader(name: "", value: ""))
                        } label: {
                            Label("Add Header", systemImage: "plus")
                        }
                        .controlSize(.small)
                    }

                    if aiHeadersDraft.isEmpty {
                        Text("Optional provider headers are saved in Keychain with the API key.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 8) {
                            ForEach($aiHeadersDraft) { $header in
                                HStack(spacing: 8) {
                                    TextField("Header name", text: $header.name)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.callout.monospaced())

                                    SecureField("Header value", text: $header.value)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.callout.monospaced())

                                    Button(role: .destructive) {
                                        aiHeadersDraft.removeAll { $0.id == header.id }
                                    } label: {
                                        Label("Remove", systemImage: "minus.circle")
                                            .labelStyle(.iconOnly)
                                    }
                                    .buttonStyle(.borderless)
                                    .help("Remove header")
                                }
                            }
                        }
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Button {
                            appModel.fetchAIModels()
                        } label: {
                            Label("Fetch Models", systemImage: "arrow.clockwise")
                        }
                        .disabled(!canFetchAIModels)

                        Button {
                            appModel.testAIProviderAvailability()
                        } label: {
                            Label("Test", systemImage: "bolt.badge.checkmark")
                        }
                        .disabled(!appModel.aiProviderSecrets.hasAPIKey || !appModel.aiProviderSettings.hasBaseURL)

                        aiAvailabilityLabel
                    }
                    .controlSize(.small)

                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 18, verticalSpacing: 10) {
                        GridRow {
                            Text("Model")
                                .foregroundStyle(.secondary)

                            Picker("Model", selection: aiModelBinding) {
                                Text(modelPlaceholderTitle).tag("")
                                ForEach(aiModels) { model in
                                    Text(model.displayName).tag(model.id)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(width: 360, alignment: .leading)
                            .disabled(aiModels.isEmpty)
                        }

                        GridRow {
                            Text("Status")
                                .foregroundStyle(.secondary)
                            Text(appModel.aiIsConfigured ? "Configured" : "Incomplete")
                                .foregroundStyle(appModel.aiIsConfigured ? .green : .secondary)
                        }
                    }

                    if case .failed(let message) = appModel.aiModelDiscoveryState {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    private var fileLoggingBinding: Binding<Bool> {
        Binding(
            get: { appModel.diagnosticsFileLoggingEnabled },
            set: { enabled in
                DispatchQueue.main.async {
                    appModel.setDiagnosticsFileLoggingEnabled(enabled)
                }
            }
        )
    }

    private var aiProviderShapeBinding: Binding<AIProviderShape> {
        Binding(
            get: { appModel.aiProviderSettings.shape },
            set: { shape in
                DispatchQueue.main.async {
                    appModel.setAIProviderShape(shape)
                }
            }
        )
    }

    private var aiProviderPresetBinding: Binding<AIProviderPreset> {
        Binding(
            get: { appModel.aiProviderSettings.preset },
            set: { preset in
                DispatchQueue.main.async {
                    appModel.setAIProviderPreset(preset)
                }
            }
        )
    }

    private var aiBaseURLBinding: Binding<String> {
        Binding(
            get: { appModel.aiProviderSettings.baseURLString },
            set: { baseURLString in
                DispatchQueue.main.async {
                    appModel.setAIBaseURLString(baseURLString)
                }
            }
        )
    }

    private var aiModelBinding: Binding<String> {
        Binding(
            get: { appModel.aiProviderSettings.selectedModelID ?? "" },
            set: { modelID in
                DispatchQueue.main.async {
                    appModel.setAISelectedModelID(modelID)
                }
            }
        )
    }

    private var aiModels: [AIModelInfo] {
        if case .loaded(let models) = appModel.aiModelDiscoveryState {
            return models
        }
        return []
    }

    private var modelPlaceholderTitle: String {
        switch appModel.aiModelDiscoveryState {
        case .idle:
            "Fetch models first"
        case .loading:
            "Loading models..."
        case .loaded:
            "Select model"
        case .failed:
            "Model list unavailable"
        }
    }

    private var hasAISecretDraft: Bool {
        !aiAPIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !aiHeadersDraft.isEmpty
    }

    private var canFetchAIModels: Bool {
        appModel.aiProviderSettings.hasBaseURL &&
            appModel.aiProviderSecrets.hasAPIKey &&
            appModel.aiModelDiscoveryState != .loading
    }

    private var aiAvailabilityLabel: some View {
        Group {
            switch appModel.aiAvailabilityState {
            case .unknown:
                Label("Not tested", systemImage: "circle")
                    .foregroundStyle(.secondary)
            case .checking:
                Label("Checking", systemImage: "clock")
                    .foregroundStyle(.secondary)
            case .available(let message):
                Label(message, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .unavailable(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
        .font(.caption)
        .lineLimit(2)
    }

    private var includeClusterNamesBinding: Binding<Bool> {
        Binding(
            get: { appModel.diagnosticsIncludeClusterNames },
            set: { enabled in
                DispatchQueue.main.async {
                    appModel.setDiagnosticsIncludeClusterNames(enabled)
                }
            }
        )
    }

    private var retentionBinding: Binding<Int> {
        Binding(
            get: { appModel.diagnosticsRetentionDays },
            set: { days in
                DispatchQueue.main.async {
                    appModel.setDiagnosticsRetentionDays(days)
                }
            }
        )
    }

    private var podLogLineLimitBinding: Binding<Int> {
        Binding(
            get: { appModel.podLogLineLimit },
            set: { lineLimit in
                DispatchQueue.main.async {
                    appModel.setPodLogLineLimit(lineLimit)
                }
            }
        )
    }

    private var defaultNamespaceBehaviorBinding: Binding<DefaultNamespaceBehavior> {
        Binding(
            get: { appModel.defaultNamespaceBehavior },
            set: { behavior in
                DispatchQueue.main.async {
                    appModel.setDefaultNamespaceBehavior(behavior)
                }
            }
        )
    }

    private var kubeconfigPathHasChanges: Bool {
        normalizedKubeconfigPathDraft != (appModel.kubeconfigPathOverride ?? "")
    }

    private var normalizedKubeconfigPathDraft: String {
        kubeconfigPathDraft
            .split(separator: ":", omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ":")
    }

    private var kubeconfigPathHelpText: String {
        if appModel.kubeconfigPathOverride == nil {
            "Using the default kubeconfig discovery. You can paste one path or a colon-separated KUBECONFIG list."
        } else {
            "Using a custom kubeconfig path. Apply reloads contexts immediately."
        }
    }

    private var resourceWatchesEnabledBinding: Binding<Bool> {
        Binding(
            get: { appModel.resourceWatchesEnabled },
            set: { enabled in
                DispatchQueue.main.async {
                    appModel.setResourceWatchesEnabled(enabled)
                }
            }
        )
    }

    private var tableDensityBinding: Binding<TableDensity> {
        Binding(
            get: { appModel.tableDensity },
            set: { density in
                DispatchQueue.main.async {
                    appModel.setTableDensity(density)
                }
            }
        )
    }

    private var appAppearanceBinding: Binding<AppAppearance> {
        Binding(
            get: { appModel.appAppearance },
            set: { appearance in
                DispatchQueue.main.async {
                    appModel.setAppAppearance(appearance)
                }
            }
        )
    }

    private var externalTerminalAppBinding: Binding<ExternalTerminalApp> {
        Binding(
            get: { appModel.externalTerminalApp },
            set: { terminalApp in
                DispatchQueue.main.async {
                    appModel.setExternalTerminalApp(terminalApp)
                }
            }
        )
    }

    private var secretRevealConfirmationBinding: Binding<Bool> {
        Binding(
            get: { appModel.secretRevealRequiresConfirmation },
            set: { requiresConfirmation in
                DispatchQueue.main.async {
                    appModel.setSecretRevealRequiresConfirmation(requiresConfirmation)
                }
            }
        )
    }

    private func copyDiagnostics() {
        Task {
            let text = await appModel.diagnosticsExportText()
            await MainActor.run {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                exportStatus = "Copied"
            }
        }
    }

    private func openLogDirectory() {
        let url = URL(fileURLWithPath: appModel.diagnosticsLogDirectoryPath, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }

    private func applyKubeconfigPathDraft() {
        appModel.setKubeconfigPathOverride(normalizedKubeconfigPathDraft.isEmpty ? nil : normalizedKubeconfigPathDraft)
    }

    private func resetKubeconfigPath() {
        kubeconfigPathDraft = ""
        appModel.setKubeconfigPathOverride(nil)
    }

    private func syncAISecretDrafts() {
        aiAPIKeyDraft = appModel.aiProviderSecrets.apiKey
        aiHeadersDraft = appModel.aiProviderSecrets.headers
    }

    private func saveAISecrets() {
        appModel.saveAIProviderSecrets(
            apiKey: aiAPIKeyDraft,
            headers: aiHeadersDraft.filter {
                !$0.normalizedName.isEmpty || !$0.normalizedValue.isEmpty
            }
        )
        aiSecretStatus = "Saved"
    }

    private func clearAISecrets() {
        appModel.clearAIProviderSecrets()
        aiAPIKeyDraft = ""
        aiHeadersDraft = []
        aiSecretStatus = "Cleared"
    }

    private func chooseKubeconfigFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.resolvesAliases = true
        panel.title = "Choose kubeconfig"
        panel.prompt = "Use"

        guard panel.runModal() == .OK else {
            return
        }

        kubeconfigPathDraft = panel.urls.map(\.path).joined(separator: ":")
    }
}
