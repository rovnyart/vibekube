import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var exportStatus: String?
    @State private var kubeconfigPathDraft = ""
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
        }
        .onChange(of: appModel.kubeconfigPathOverride) { _, newValue in
            kubeconfigPathDraft = newValue ?? ""
        }
        .alert("Reset Local Preferences?", isPresented: $showsResetLocalPreferencesConfirmation) {
            Button("Reset", role: .destructive) {
                appModel.resetLocalPreferences()
                kubeconfigPathDraft = appModel.kubeconfigPathOverride ?? ""
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
