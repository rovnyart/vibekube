import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var exportStatus: String?

    private let logLineLimitOptions = [1_000, 5_000, 10_000, 20_000, 50_000]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                SectionSurface(title: "Kubernetes", systemImage: "shippingbox") {
                    VStack(alignment: .leading, spacing: 14) {
                        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 18, verticalSpacing: 12) {
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
            }
            .padding(20)
            .frame(maxWidth: 820, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityIdentifier("settings.view")
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
            set: { appModel.setDiagnosticsFileLoggingEnabled($0) }
        )
    }

    private var includeClusterNamesBinding: Binding<Bool> {
        Binding(
            get: { appModel.diagnosticsIncludeClusterNames },
            set: { appModel.setDiagnosticsIncludeClusterNames($0) }
        )
    }

    private var retentionBinding: Binding<Int> {
        Binding(
            get: { appModel.diagnosticsRetentionDays },
            set: { appModel.setDiagnosticsRetentionDays($0) }
        )
    }

    private var podLogLineLimitBinding: Binding<Int> {
        Binding(
            get: { appModel.podLogLineLimit },
            set: { appModel.setPodLogLineLimit($0) }
        )
    }

    private var defaultNamespaceBehaviorBinding: Binding<DefaultNamespaceBehavior> {
        Binding(
            get: { appModel.defaultNamespaceBehavior },
            set: { appModel.setDefaultNamespaceBehavior($0) }
        )
    }

    private var resourceWatchesEnabledBinding: Binding<Bool> {
        Binding(
            get: { appModel.resourceWatchesEnabled },
            set: { appModel.setResourceWatchesEnabled($0) }
        )
    }

    private var secretRevealConfirmationBinding: Binding<Bool> {
        Binding(
            get: { appModel.secretRevealRequiresConfirmation },
            set: { appModel.setSecretRevealRequiresConfirmation($0) }
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
}
