//
//  vibekubeTests.swift
//  vibekubeTests
//
//  Created by art on 27.05.2026.
//

import Foundation
import Testing
@testable import vibekube

struct vibekubeTests {

    @MainActor
    @Test func appModelSelectsFirstClusterByDefault() {
        let model = AppModel(clusters: ClusterSummary.preview)

        #expect(model.selectedClusterID == "kind-vibekube-dev")
        #expect(model.selectedResource == .dashboard)
    }

    @MainActor
    @Test func appModelRestoresRouteFromPreferences() {
        let model = AppModel(
            clusters: ClusterSummary.preview,
            userPreferences: InMemoryUserPreferences(
                selectedContextID: "staging",
                selectedResourceID: ResourceNavigationItem.services.rawValue,
                selectedNamespaceByContextID: ["staging": "payments"]
            )
        )

        #expect(model.route == AppRoute(clusterID: "staging", resource: .services))
        #expect(model.selectedClusterID == "staging")
        #expect(model.selectedResource == .services)
        #expect(model.selectedNamespaceSelection == "payments")
    }

    @MainActor
    @Test func appModelUsesContextNamespaceDefaultWhenConfigured() async throws {
        let model = AppModel(
            clusters: ClusterSummary.preview,
            connectionService: SucceedingConnectionService(),
            userPreferences: InMemoryUserPreferences(defaultNamespaceBehavior: .contextNamespace),
            loadedKubeconfig: kubeconfig()
        )

        model.connectSelectedCluster()
        try await waitForConnectionState(model, .connected)

        #expect(model.selectedNamespaceSelection == "vibekube-demo")
        #expect(model.selectedNamespaceTitle == "vibekube-demo")
    }

    @MainActor
    @Test func appModelKeepsSavedNamespaceOverDefaultBehavior() async throws {
        let model = AppModel(
            clusters: ClusterSummary.preview,
            connectionService: SucceedingConnectionService(),
            userPreferences: InMemoryUserPreferences(
                selectedNamespaceByContextID: ["kind-vibekube-dev": "custom"],
                defaultNamespaceBehavior: .contextNamespace
            ),
            loadedKubeconfig: kubeconfig()
        )

        model.connectSelectedCluster()
        try await waitForConnectionState(model, .connected)

        #expect(model.selectedNamespaceSelection == "custom")
    }

    @MainActor
    @Test func appModelUpdatesDefaultNamespaceBehaviorSetting() {
        let model = AppModel(clusters: ClusterSummary.preview)

        #expect(model.defaultNamespaceBehavior == .allNamespaces)
        #expect(model.selectedNamespaceSelection == AppModel.allNamespacesSelection)

        model.setDefaultNamespaceBehavior(.contextNamespace)

        #expect(model.defaultNamespaceBehavior == .contextNamespace)
        #expect(model.selectedNamespaceSelection == "vibekube-demo")
    }

    @MainActor
    @Test func appModelUpdatesTableDensitySetting() {
        let model = AppModel(clusters: ClusterSummary.preview)

        #expect(model.tableDensity == .comfortable)

        model.setTableDensity(.compact)
        #expect(model.tableDensity == .compact)

        model.setTableDensity(.spacious)
        #expect(model.tableDensity == .spacious)
    }

    @MainActor
    @Test func appModelUpdatesAppAppearanceSetting() {
        let model = AppModel(clusters: ClusterSummary.preview)

        #expect(model.appAppearance == .system)

        model.setAppAppearance(.dark)
        #expect(model.appAppearance == .dark)

        model.setAppAppearance(.light)
        #expect(model.appAppearance == .light)
    }

    @MainActor
    @Test func appModelUpdatesExternalTerminalAppSetting() {
        let model = AppModel(clusters: ClusterSummary.preview)

        #expect(model.externalTerminalApp == .terminal)

        model.setExternalTerminalApp(.ghostty)
        #expect(model.externalTerminalApp == .ghostty)

        model.setExternalTerminalApp(.warp)
        #expect(model.externalTerminalApp == .warp)
    }

    @MainActor
    @Test func appModelResetsLocalPreferences() {
        let model = AppModel(
            clusters: ClusterSummary.preview,
            userPreferences: InMemoryUserPreferences(
                selectedContextID: "staging",
                selectedResourceID: ResourceNavigationItem.services.rawValue,
                selectedNamespaceByContextID: ["staging": "payments"],
                diagnosticsFileLoggingEnabled: true,
                diagnosticsIncludeClusterNames: true,
                diagnosticsRetentionDays: 14,
                podLogLineLimit: 20_000,
                secretRevealRequiresConfirmation: false,
                defaultNamespaceBehavior: .contextNamespace,
                resourceWatchesEnabled: false,
                kubeconfigPathOverride: "/tmp/custom-kubeconfig",
                tableDensity: .compact,
                appAppearance: .dark,
                externalTerminalApp: .ghostty
            )
        )

        model.resetLocalPreferences()

        #expect(model.selectedClusterID == "kind-vibekube-dev")
        #expect(model.selectedResource == .dashboard)
        #expect(model.selectedNamespaceSelection == AppModel.allNamespacesSelection)
        #expect(model.diagnosticsFileLoggingEnabled == false)
        #expect(model.diagnosticsIncludeClusterNames == false)
        #expect(model.diagnosticsRetentionDays == 7)
        #expect(model.podLogLineLimit == AppModel.defaultPodLogLineLimit)
        #expect(model.secretRevealRequiresConfirmation == true)
        #expect(model.defaultNamespaceBehavior == .allNamespaces)
        #expect(model.resourceWatchesEnabled == true)
        #expect(model.kubeconfigPathOverride == nil)
        #expect(model.tableDensity == .comfortable)
        #expect(model.appAppearance == .system)
        #expect(model.externalTerminalApp == .terminal)
    }

    @MainActor
    @Test func appModelReloadsKubeconfigWhenPathOverrideChanges() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let first = directory.appendingPathComponent("first.yaml")
        let second = directory.appendingPathComponent("second.yaml")
        try testKubeconfig(named: "first", server: "https://first.example.com")
            .write(to: first, atomically: true, encoding: .utf8)
        try testKubeconfig(named: "second", server: "https://second.example.com")
            .write(to: second, atomically: true, encoding: .utf8)

        let model = AppModel(
            clusters: [],
            kubeconfigState: .notLoaded,
            kubeconfigLoader: KubeconfigLoader(environment: ["KUBECONFIG": first.path]),
            userPreferences: InMemoryUserPreferences()
        )

        model.reloadKubeconfig()
        #expect(model.clusters.map(\.id) == ["first"])

        model.setKubeconfigPathOverride(second.path)

        #expect(model.kubeconfigPathOverride == second.path)
        #expect(model.clusters.map(\.id) == ["second"])
        #expect(model.selectedClusterID == "second")
    }

    @MainActor
    @Test func appModelIgnoresInvalidRestoredRouteResource() {
        let model = AppModel(
            clusters: ClusterSummary.preview,
            userPreferences: InMemoryUserPreferences(
                selectedContextID: "missing",
                selectedResourceID: "not-a-resource"
            )
        )

        #expect(model.selectedClusterID == "kind-vibekube-dev")
        #expect(model.selectedResource == .dashboard)
    }

    @MainActor
    @Test func appModelResetsToDashboardWhenClusterChanges() {
        let model = AppModel(clusters: ClusterSummary.preview)

        model.selectResource(.pods)
        model.selectCluster(id: "staging")

        #expect(model.route == AppRoute(clusterID: "staging", resource: .dashboard))
    }

    @MainActor
    @Test func appModelRequestsSearchFocusForCommands() {
        let model = AppModel(clusters: ClusterSummary.preview)

        #expect(model.searchFocusRequestID == 0)
        model.focusSearchField()

        #expect(model.searchFocusRequestID == 1)
    }

    @MainActor
    @Test func appModelStartsAndStopsPortForwardSession() async throws {
        let portForwardService = RecordingPortForwardService()
        let model = AppModel(
            clusters: ClusterSummary.preview,
            connectionService: SucceedingConnectionService(),
            portForwardService: portForwardService,
            localPortChecker: RecordingLocalPortChecker(),
            loadedKubeconfig: kubeconfig()
        )
        let target = KubernetesPortForwardTargetSummary(
            resourceKind: "service",
            resourceName: "echo-web",
            namespace: "vibekube-demo",
            portName: "http",
            localPort: 10080,
            remotePort: 80,
            protocolName: "TCP"
        )

        model.connectSelectedCluster()
        try await waitForConnectionState(model, .connected)

        model.startPortForward(target: target)
        try await waitForPortForwardSession(model, status: .running(processIdentifier: 4242))

        #expect(portForwardService.requests == [
            KubernetesPortForwardRequest(
                contextName: "kind-vibekube-dev",
                namespace: "vibekube-demo",
                resourceKind: "service",
                resourceName: "echo-web",
                localPort: 10080,
                remotePort: 80,
                kubeconfigPath: nil
            )
        ])
        #expect(model.portForwardSessions.first?.localURLString == "http://127.0.0.1:10080")

        let session = try #require(model.portForwardSessions.first)
        model.stopPortForward(sessionID: session.id)

        #expect(portForwardService.handles.first?.stopped == true)
        #expect(model.portForwardSessions.first?.status == .stopped)

        portForwardService.terminateFirst(
            KubernetesPortForwardTermination(
                exitCode: 15,
                userStopped: false,
                message: nil
            )
        )
        try await waitForPortForwardSession(model, status: .stopped)
        #expect(model.portForwardSessions.first?.status == .stopped)
    }

    @MainActor
    @Test func appModelStopsAllPortForwardSessionsForAppTermination() async throws {
        let portForwardService = RecordingPortForwardService()
        let model = AppModel(
            clusters: ClusterSummary.preview,
            connectionService: SucceedingConnectionService(),
            portForwardService: portForwardService,
            localPortChecker: RecordingLocalPortChecker(),
            loadedKubeconfig: kubeconfig()
        )
        let firstTarget = KubernetesPortForwardTargetSummary(
            resourceKind: "service",
            resourceName: "echo-web",
            namespace: "vibekube-demo",
            portName: "http",
            localPort: 10080,
            remotePort: 80,
            protocolName: "TCP"
        )
        let secondTarget = KubernetesPortForwardTargetSummary(
            resourceKind: "pod",
            resourceName: "echo-web-abc",
            namespace: "vibekube-demo",
            portName: "http",
            localPort: 18080,
            remotePort: 8080,
            protocolName: "TCP"
        )

        model.connectSelectedCluster()
        try await waitForConnectionState(model, .connected)

        model.startPortForward(target: firstTarget)
        model.startPortForward(target: secondTarget)
        try await waitUntil("two port-forward sessions running") {
            portForwardService.handles.count == 2 &&
                model.portForwardSessions.filter(\.isActive).count == 2
        }

        model.stopAllPortForwardSessions()

        for handle in portForwardService.handles {
            #expect(handle.stopped)
        }
        #expect(model.portForwardSessions.allSatisfy { $0.status == .stopped })
    }

    @MainActor
    @Test func appModelKeepsFailedPortForwardSessionVisible() async throws {
        let portForwardService = TerminatingPortForwardService(
            termination: KubernetesPortForwardTermination(
                exitCode: 127,
                userStopped: false,
                message: "env: kubectl: No such file or directory"
            )
        )
        let model = AppModel(
            clusters: ClusterSummary.preview,
            connectionService: SucceedingConnectionService(),
            portForwardService: portForwardService,
            localPortChecker: RecordingLocalPortChecker(),
            loadedKubeconfig: kubeconfig()
        )
        let target = KubernetesPortForwardTargetSummary(
            resourceKind: "service",
            resourceName: "echo-web",
            namespace: "vibekube-demo",
            portName: "http",
            localPort: 10080,
            remotePort: 80,
            protocolName: "TCP"
        )

        model.connectSelectedCluster()
        try await waitForConnectionState(model, .connected)

        model.startPortForward(target: target)
        try await waitForPortForwardSession(
            model,
            status: .failed("kubectl exited with code 127: env: kubectl: No such file or directory")
        )

        #expect(model.portForwardSession(for: target)?.isActive == false)
    }

    @MainActor
    @Test func appModelExplainsPortForwardStreamingProtocolFailures() async throws {
        let portForwardService = TerminatingPortForwardService(
            termination: KubernetesPortForwardTermination(
                exitCode: 1,
                userStopped: false,
                message: "error upgrading connection: websocket: bad handshake"
            )
        )
        let model = AppModel(
            clusters: ClusterSummary.preview,
            connectionService: SucceedingConnectionService(),
            portForwardService: portForwardService,
            localPortChecker: RecordingLocalPortChecker(),
            loadedKubeconfig: kubeconfig()
        )
        let target = KubernetesPortForwardTargetSummary(
            resourceKind: "service",
            resourceName: "echo-web",
            namespace: "vibekube-demo",
            portName: "http",
            localPort: 10080,
            remotePort: 80,
            protocolName: "TCP"
        )

        model.connectSelectedCluster()
        try await waitForConnectionState(model, .connected)

        model.startPortForward(target: target)
        try await waitUntil("port-forward streaming explanation") {
            guard case .failed(let message) = model.portForwardSession(for: target)?.status else {
                return false
            }
            return message.contains("Streaming connection failed.") &&
                message.contains("WebSocket/SPDY upgrades") &&
                message.contains("websocket: bad handshake")
        }
    }

    @MainActor
    @Test func appModelFailsPortForwardWhenLocalPortIsInUse() async throws {
        let portForwardService = RecordingPortForwardService()
        let localPortChecker = RecordingLocalPortChecker(unavailablePorts: [10080])
        let model = AppModel(
            clusters: ClusterSummary.preview,
            connectionService: SucceedingConnectionService(),
            portForwardService: portForwardService,
            localPortChecker: localPortChecker,
            loadedKubeconfig: kubeconfig()
        )
        let target = KubernetesPortForwardTargetSummary(
            resourceKind: "service",
            resourceName: "echo-web",
            namespace: "vibekube-demo",
            portName: "http",
            localPort: 10080,
            remotePort: 80,
            protocolName: "TCP"
        )

        model.connectSelectedCluster()
        try await waitForConnectionState(model, .connected)

        model.startPortForward(target: target)

        #expect(localPortChecker.checkedPorts == [10080])
        #expect(portForwardService.requests.isEmpty)
        #expect(model.portForwardSession(for: target)?.status == .failed("Local port 10080 is already in use."))
    }

    @Test func kubectlPortForwardEnvironmentIncludesCommonHomebrewPaths() {
        let request = KubernetesPortForwardRequest(
            contextName: "kind-vibekube-dev",
            namespace: "vibekube-demo",
            resourceKind: "service",
            resourceName: "echo-web",
            localPort: 10080,
            remotePort: 80,
            kubeconfigPath: nil
        )
        let environment = KubectlPortForwardService.environment(
            for: request,
            baseEnvironment: ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
        )

        #expect(environment["PATH"]?.contains("/usr/local/bin") == true)
        #expect(environment["PATH"]?.contains("/opt/homebrew/bin") == true)
    }

    @MainActor
    @Test func appModelLaunchesPodExecInExternalTerminal() async throws {
        let execLauncher = RecordingExecLauncher()
        let model = AppModel(
            clusters: ClusterSummary.preview,
            connectionService: SucceedingConnectionService(),
            execLauncher: execLauncher,
            loadedKubeconfig: kubeconfig()
        )
        let pod = try podResource(name: "echo-web-abc", namespace: "vibekube-demo")

        model.connectSelectedCluster()
        try await waitForConnectionState(model, .connected)

        model.openPodExec(for: pod, containerName: "web")
        try await waitUntil("exec launch request") {
            execLauncher.requests.count == 1
        }

        #expect(execLauncher.requests == [
            KubernetesExecLaunchRequest(
                contextName: "kind-vibekube-dev",
                namespace: "vibekube-demo",
                podName: "echo-web-abc",
                containerName: "web",
                command: ["/bin/sh"],
                kubeconfigPath: nil,
                terminalApp: .terminal
            )
        ])
    }

    @MainActor
    @Test func appModelRecordsPodExecLaunchHistory() async throws {
        let execLauncher = RecordingExecLauncher()
        let model = AppModel(
            clusters: ClusterSummary.preview,
            connectionService: SucceedingConnectionService(),
            execLauncher: execLauncher,
            loadedKubeconfig: kubeconfig()
        )
        let pod = try podResource(name: "echo-web-abc", namespace: "vibekube-demo")

        model.connectSelectedCluster()
        try await waitForConnectionState(model, .connected)

        model.openPodExec(for: pod, containerName: "web", command: KubernetesExecCommandChoice.ash.command)
        try await waitUntil("exec launch history opened") {
            if case .opened = model.execLaunches.first?.status {
                return true
            }
            return false
        }

        let launch = try #require(model.execLaunches.first)
        #expect(launch.contextID == "kind-vibekube-dev")
        #expect(launch.namespace == "vibekube-demo")
        #expect(launch.podName == "echo-web-abc")
        #expect(launch.containerName == "web")
        #expect(launch.command == ["/bin/ash"])
        #expect(launch.displayTarget == "echo-web-abc / web")
        #expect(launch.displayCommand == "/bin/ash")

        model.clearExecLaunchHistory()
        #expect(model.execLaunches.isEmpty)
    }

    @MainActor
    @Test func appModelClearsPodExecLaunchHistoryForOnePod() async throws {
        let execLauncher = RecordingExecLauncher()
        let model = AppModel(
            clusters: ClusterSummary.preview,
            connectionService: SucceedingConnectionService(),
            execLauncher: execLauncher,
            loadedKubeconfig: kubeconfig()
        )
        let firstPod = try podResource(name: "echo-web-abc", namespace: "vibekube-demo")
        let secondPod = try podResource(name: "echo-web-def", namespace: "vibekube-demo")

        model.connectSelectedCluster()
        try await waitForConnectionState(model, .connected)

        model.openPodExec(for: firstPod, containerName: "web")
        model.openPodExec(for: secondPod, containerName: "web")
        try await waitUntil("two exec launches opened") {
            model.execLaunches.count == 2 &&
                model.execLaunches.allSatisfy { launch in
                    if case .opened = launch.status {
                        return true
                    }
                    return false
                }
        }

        model.clearExecLaunchHistory(for: firstPod)

        #expect(model.execLaunches.map(\.podName) == ["echo-web-def"])
    }

    @MainActor
    @Test func appModelRecordsFailedPodExecLaunchHistory() async throws {
        let model = AppModel(
            clusters: ClusterSummary.preview,
            connectionService: SucceedingConnectionService(),
            execLauncher: FailingExecLauncher(error: ExecLaunchTestError(message: "terminal denied automation")),
            loadedKubeconfig: kubeconfig()
        )
        let pod = try podResource(name: "echo-web-abc", namespace: "vibekube-demo")

        model.connectSelectedCluster()
        try await waitForConnectionState(model, .connected)

        model.openPodExec(for: pod, containerName: "web")
        try await waitUntil("failed exec launch history") {
            if case .failed("terminal denied automation") = model.execLaunches.first?.status {
                return true
            }
            return false
        }

        #expect(model.execLaunchErrorMessage == "terminal denied automation")
    }

    @MainActor
    @Test func appModelExplainsExecRBACFailures() async throws {
        let model = AppModel(
            clusters: ClusterSummary.preview,
            connectionService: SucceedingConnectionService(),
            execLauncher: FailingExecLauncher(
                error: ExecLaunchTestError(
                    message: "Error from server (Forbidden): pods \"echo-web-abc\" is forbidden: User \"dev\" cannot create resource \"pods/exec\""
                )
            ),
            loadedKubeconfig: kubeconfig()
        )
        let pod = try podResource(name: "echo-web-abc", namespace: "vibekube-demo")

        model.connectSelectedCluster()
        try await waitForConnectionState(model, .connected)

        model.openPodExec(for: pod, containerName: "web")
        try await waitUntil("exec rbac explanation") {
            guard case .failed(let message) = model.execLaunches.first?.status else {
                return false
            }
            return message.contains("RBAC denied exec.") &&
                message.contains("pods/exec") &&
                message.contains("Error from server (Forbidden)")
        }

        #expect(model.execLaunchErrorMessage?.contains("RBAC denied exec.") == true)
    }

    @MainActor
    @Test func appModelLaunchesSelectedPodExecShell() async throws {
        let execLauncher = RecordingExecLauncher()
        let model = AppModel(
            clusters: ClusterSummary.preview,
            connectionService: SucceedingConnectionService(),
            execLauncher: execLauncher,
            loadedKubeconfig: kubeconfig()
        )
        let pod = try podResource(name: "echo-web-abc", namespace: "vibekube-demo")

        model.connectSelectedCluster()
        try await waitForConnectionState(model, .connected)

        model.openPodExec(for: pod, containerName: "web", command: KubernetesExecCommandChoice.bash.command)
        try await waitUntil("exec launch request") {
            execLauncher.requests.count == 1
        }

        #expect(execLauncher.requests.first?.command == ["/bin/bash"])
    }

    @Test func kubernetesExecCommandChoicesExposeCommonShells() {
        #expect(KubernetesExecCommandChoice.allCases.map(\.title) == [
            "/bin/sh",
            "/bin/bash",
            "/bin/ash",
            "/bin/zsh"
        ])
        #expect(KubernetesExecCommandChoice.sh.command == ["/bin/sh"])
    }

    @MainActor
    @Test func appModelUsesPreferredTerminalAppForPodExec() async throws {
        let execLauncher = RecordingExecLauncher()
        let model = AppModel(
            clusters: ClusterSummary.preview,
            connectionService: SucceedingConnectionService(),
            execLauncher: execLauncher,
            userPreferences: InMemoryUserPreferences(externalTerminalApp: .iTerm2),
            loadedKubeconfig: kubeconfig()
        )
        let pod = try podResource(name: "echo-web-abc", namespace: "vibekube-demo")

        model.connectSelectedCluster()
        try await waitForConnectionState(model, .connected)

        model.openPodExec(for: pod, containerName: "web")
        try await waitUntil("exec launch request") {
            execLauncher.requests.count == 1
        }

        #expect(execLauncher.requests.first?.terminalApp == .iTerm2)
    }

    @Test func terminalExecLauncherBuildsKubectlExecCommand() {
        let command = TerminalKubernetesExecLauncher.shellCommand(
            for: KubernetesExecLaunchRequest(
                contextName: "kind-vibekube-dev",
                namespace: "vibekube-demo",
                podName: "echo-web-abc",
                containerName: "web",
                command: ["/bin/sh"],
                kubeconfigPath: "/Users/art/.kube/config",
                terminalApp: .terminal
            )
        )

        #expect(command.contains("export PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"))
        #expect(command.contains("export KUBECONFIG='/Users/art/.kube/config'"))
        #expect(command.contains("'kubectl' '--context' 'kind-vibekube-dev' '-n' 'vibekube-demo' 'exec' '-it' 'echo-web-abc' '-c' 'web' '--' '/bin/sh'"))
    }

    @MainActor
    @Test func appModelNavigatesToKnownOwnerResource() async throws {
        let model = AppModel(
            clusters: ClusterSummary.preview,
            connectionService: WatchableWorkloadsConnectionService(),
            resourceListService: SucceedingResourceListService(),
            loadedKubeconfig: kubeconfig()
        )

        model.connectSelectedCluster()
        try await waitForConnectionState(model, .connected)

        let owner = KubernetesOwnerReferenceSummary(
            kind: "Deployment",
            name: "echo-web",
            controller: true
        )
        model.navigateToOwner(owner, namespace: "vibekube-demo")

        try await waitForResourceList(model, .deployments)

        #expect(ResourceNavigationItem.navigationItem(forOwnerKind: "ReplicaSet") == .replicaSets)
        #expect(ResourceNavigationItem.navigationItem(forOwnerKind: "Widget") == nil)
        #expect(model.selectedResource == .deployments)
        #expect(model.selectedNamespaceSelection == "vibekube-demo")
        #expect(model.searchText == "")
        #expect(model.resourceNameFilter?.title == "Deployments for Deployment/echo-web")
        #expect(model.resourceNameFilter?.detail == "echo-web")
        #expect(model.resourceNameFilter?.targetResource == .deployments)
        #expect(model.searchFocusRequestID == 0)

        guard case .loaded(let snapshot) = model.resourceListState(for: .deployments) else {
            Issue.record("Expected loaded deployment list")
            return
        }

        #expect(snapshot.query.resource.name == "deployments")
        #expect(snapshot.query.namespaceSelection == "vibekube-demo")
    }

    @MainActor
    @Test func appModelNavigatesToNamedResource() async throws {
        let model = AppModel(
            clusters: ClusterSummary.preview,
            connectionService: WatchableWorkloadsConnectionService(),
            resourceListService: SucceedingResourceListService(),
            loadedKubeconfig: kubeconfig()
        )

        model.connectSelectedCluster()
        try await waitForConnectionState(model, .connected)
        model.searchText = "old search"

        model.navigateToResource(
            .services,
            name: "echo-web",
            namespace: "vibekube-demo",
            sourceTitle: "Ingress/echo-web"
        )

        try await waitForResourceList(model, .services)

        #expect(model.selectedResource == .services)
        #expect(model.selectedNamespaceSelection == "vibekube-demo")
        #expect(model.searchText == "")
        #expect(model.resourceLabelFilter == nil)
        #expect(model.resourceOwnerFilter == nil)
        #expect(model.resourceNameFilter?.title == "Services for Ingress/echo-web")
        #expect(model.resourceNameFilter?.detail == "echo-web")
        #expect(model.resourceNameFilter?.targetResource == .services)
        #expect(model.searchFocusRequestID == 0)

        guard case .loaded(let snapshot) = model.resourceListState(for: .services) else {
            Issue.record("Expected loaded service list")
            return
        }

        #expect(snapshot.query.resource.name == "services")
        #expect(snapshot.query.namespaceSelection == "vibekube-demo")

        model.selectResource(.pods)
        #expect(model.searchText == "")
        #expect(model.resourceNameFilter == nil)
    }

    @MainActor
    @Test func appModelNavigatesToPodsWithLabelFilter() async throws {
        let model = AppModel(
            clusters: ClusterSummary.preview,
            connectionService: WatchableWorkloadsConnectionService(),
            resourceListService: SucceedingResourceListService(),
            loadedKubeconfig: kubeconfig()
        )

        model.connectSelectedCluster()
        try await waitForConnectionState(model, .connected)
        model.searchText = "old search"

        let selector = KubernetesLabelSelectorSummary(matchLabels: [
            "app.kubernetes.io/name": "echo-web"
        ])
        model.navigateToPods(
            matching: selector,
            sourceTitle: "Deployment/echo-web",
            namespace: "vibekube-demo"
        )

        try await waitForResourceList(model, .pods)

        #expect(model.selectedResource == .pods)
        #expect(model.selectedNamespaceSelection == "vibekube-demo")
        #expect(model.searchText == "")
        #expect(model.resourceLabelFilter?.title == "Pods for Deployment/echo-web")
        #expect(model.resourceLabelFilter?.detail == "app.kubernetes.io/name=echo-web")

        guard case .loaded(let snapshot) = model.resourceListState(for: .pods) else {
            Issue.record("Expected loaded pod list")
            return
        }

        #expect(snapshot.query.resource.name == "pods")
        #expect(snapshot.query.namespaceSelection == "vibekube-demo")

        model.clearResourceLabelFilter()
        #expect(model.resourceLabelFilter == nil)
    }

    @MainActor
    @Test func appModelNavigatesToOwnedJobsWithOwnerFilter() async throws {
        let model = AppModel(
            clusters: ClusterSummary.preview,
            connectionService: WatchableWorkloadsConnectionService(),
            resourceListService: SucceedingResourceListService(),
            loadedKubeconfig: kubeconfig()
        )

        model.connectSelectedCluster()
        try await waitForConnectionState(model, .connected)
        model.searchText = "old search"

        let owner = KubernetesOwnerReferenceSummary(
            kind: "CronJob",
            name: "tiny-heartbeat",
            controller: true
        )
        model.navigateToOwnedResources(
            owner: owner,
            targetResource: .jobs,
            sourceTitle: "CronJob/tiny-heartbeat",
            namespace: "vibekube-demo"
        )

        try await waitForResourceList(model, .jobs)

        #expect(model.selectedResource == .jobs)
        #expect(model.selectedNamespaceSelection == "vibekube-demo")
        #expect(model.searchText == "")
        #expect(model.resourceLabelFilter == nil)
        #expect(model.resourceOwnerFilter?.title == "Jobs for CronJob/tiny-heartbeat")
        #expect(model.resourceOwnerFilter?.detail == "CronJob/tiny-heartbeat")
        #expect(model.resourceOwnerFilter?.targetResource == .jobs)

        guard case .loaded(let snapshot) = model.resourceListState(for: .jobs) else {
            Issue.record("Expected loaded job list")
            return
        }

        #expect(snapshot.query.resource.name == "jobs")
        #expect(snapshot.query.namespaceSelection == "vibekube-demo")

        model.clearResourceOwnerFilter()
        #expect(model.resourceOwnerFilter == nil)
    }

    @MainActor
    @Test func appModelNavigatesToOwnedReplicaSetsWithOwnerFilter() async throws {
        let model = AppModel(
            clusters: ClusterSummary.preview,
            connectionService: WatchableWorkloadsConnectionService(),
            resourceListService: SucceedingResourceListService(),
            loadedKubeconfig: kubeconfig()
        )

        model.connectSelectedCluster()
        try await waitForConnectionState(model, .connected)

        let owner = KubernetesOwnerReferenceSummary(
            kind: "Deployment",
            name: "echo-web",
            controller: true
        )
        model.navigateToOwnedResources(
            owner: owner,
            targetResource: .replicaSets,
            sourceTitle: "Deployment/echo-web",
            namespace: "vibekube-demo"
        )

        try await waitForResourceList(model, .replicaSets)

        #expect(model.selectedResource == .replicaSets)
        #expect(model.selectedNamespaceSelection == "vibekube-demo")
        #expect(model.searchText == "")
        #expect(model.resourceOwnerFilter?.title == "ReplicaSets for Deployment/echo-web")
        #expect(model.resourceOwnerFilter?.detail == "Deployment/echo-web")
        #expect(model.resourceOwnerFilter?.targetResource == .replicaSets)

        guard case .loaded(let snapshot) = model.resourceListState(for: .replicaSets) else {
            Issue.record("Expected loaded ReplicaSet list")
            return
        }

        #expect(snapshot.query.resource.name == "replicasets")
        #expect(snapshot.query.namespaceSelection == "vibekube-demo")
    }

    @MainActor
    @Test func appModelBuildsCopyableRouteIdentity() async throws {
        let model = AppModel(
            clusters: ClusterSummary.preview,
            connectionService: SucceedingConnectionService(),
            loadedKubeconfig: kubeconfig()
        )

        model.connectSelectedCluster()
        try await waitForConnectionState(model, .connected)
        model.selectResource(.pods)

        let identity = model.selectedRouteIdentityText ?? ""
        #expect(identity.contains("Context: kind-vibekube-dev"))
        #expect(identity.contains("Route: Pods"))
        #expect(identity.contains("API: v1/pods"))
        #expect(identity.contains("Namespace: All Namespaces"))
    }

    @MainActor
    @Test func appModelConnectsAndDisconnectsSelectedCluster() {
        let model = AppModel(clusters: ClusterSummary.preview)

        model.connectSelectedCluster()
        #expect(model.selectedConnectionState == .connected)

        model.disconnectSelectedCluster()
        #expect(model.selectedConnectionState == .disconnected)
    }

    @MainActor
    @Test func appModelConnectsWithConnectionService() async throws {
        let model = AppModel(
            clusters: ClusterSummary.preview,
            connectionService: SucceedingConnectionService(),
            loadedKubeconfig: kubeconfig()
        )

        model.connectSelectedCluster()
        #expect(model.selectedConnectionState == .connecting)

        try await waitForConnectionState(model, .connected)

        #expect(model.selectedConnectionState == .connected)
        #expect(model.selectedCluster?.kubernetesVersion == "v1.30.0")
        #expect(model.selectedDiscovery?.resourceCount == 4)
        #expect(model.selectedNamespaceSelection == AppModel.allNamespacesSelection)
        #expect(model.selectedNamespaceTitle == "All Namespaces")
        #expect(model.namespaceSelectionOptions.contains(AppModel.allNamespacesSelection))
        #expect(model.namespaceSelectionOptions.contains("vibekube-demo"))
        #expect(model.connectionErrorMessage == nil)
    }

    @MainActor
    @Test func appModelShowsExecAuthProgressWhileConnecting() async throws {
        let model = AppModel(
            clusters: ClusterSummary.preview,
            connectionService: ProgressReportingConnectionService(),
            loadedKubeconfig: kubeconfig()
        )

        model.connectSelectedCluster()
        try await waitForConnectionState(model, .authenticating)

        #expect(model.connectionProgressMessage == "Signing in with tsh.")
        #expect(model.connectionErrorMessage == nil)

        try await waitForConnectionState(model, .connected)

        #expect(model.connectionProgressMessage == nil)
    }

    @MainActor
    @Test func appModelMapsConnectionFailures() async throws {
        let model = AppModel(
            clusters: ClusterSummary.preview,
            connectionService: FailingConnectionService(),
            loadedKubeconfig: kubeconfig()
        )

        model.connectSelectedCluster()
        try await waitForConnectionState(model, .unauthorized)

        #expect(model.selectedConnectionState == .unauthorized)
        #expect(model.connectionErrorMessage == "Nope")
    }

    @MainActor
    @Test func appModelLoadsResourceListForSelectedResource() async throws {
        let model = AppModel(
            clusters: ClusterSummary.preview,
            connectionService: SucceedingConnectionService(),
            resourceListService: SucceedingResourceListService(),
            loadedKubeconfig: kubeconfig()
        )

        model.connectSelectedCluster()
        try await waitForConnectionState(model, .connected)

        model.selectResource(.pods)
        try await waitForResourceList(model, .pods)

        guard case .loaded(let snapshot) = model.resourceListState(for: .pods) else {
            Issue.record("Expected loaded resource list")
            return
        }

        #expect(snapshot.items.map(\.displayName) == ["web-0"])
        #expect(snapshot.items.first?.displayNamespace == "vibekube-demo")
        #expect(snapshot.query.namespaceSelection == AppModel.allNamespacesSelection)
    }

    @MainActor
    @Test func appModelLoadsDashboardResourceListsTogether() async throws {
        let recorder = DashboardResourceListRecorder()
        let model = AppModel(
            clusters: ClusterSummary.preview,
            connectionService: DashboardConnectionService(),
            resourceListService: DashboardResourceListService(recorder: recorder),
            loadedKubeconfig: kubeconfig()
        )

        model.connectSelectedCluster()

        for _ in 0..<20 {
            if await recorder.count == AppModel.dashboardResourceItems.count {
                break
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }

        let requestedNames = await recorder.resourceNames()
        let expectedNames = Set(AppModel.dashboardResourceItems.map { dashboardAPIResource(for: $0).name })
        #expect(Set(requestedNames) == expectedNames)

        for item in AppModel.dashboardResourceItems {
            guard case .loaded = model.resourceListState(for: item) else {
                Issue.record("Expected \(item.title) to be loaded")
                continue
            }
        }
    }

    @MainActor
    @Test func appModelKeepsDashboardLoadsWhenNavigatingAway() async throws {
        let recorder = DashboardResourceListRecorder()
        let model = AppModel(
            clusters: ClusterSummary.preview,
            connectionService: DashboardConnectionService(),
            resourceListService: DashboardResourceListService(
                recorder: recorder,
                delayNanoseconds: 50_000_000
            ),
            loadedKubeconfig: kubeconfig()
        )

        model.connectSelectedCluster()
        for _ in 0..<20 {
            if model.selectedConnectionState == .connected {
                break
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }

        model.selectResource(.pods)

        for _ in 0..<40 {
            if await recorder.count == AppModel.dashboardResourceItems.count {
                break
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }

        let requestedNames = await recorder.resourceNames()
        let expectedNames = Set(AppModel.dashboardResourceItems.map { dashboardAPIResource(for: $0).name })
        #expect(Set(requestedNames) == expectedNames)
        #expect(model.selectedResource == .pods)
    }

    @MainActor
    @Test func appModelLoadsResourceDetailForSelectedRow() async throws {
        let model = AppModel(
            clusters: ClusterSummary.preview,
            connectionService: SucceedingConnectionService(),
            resourceListService: SucceedingResourceListService(),
            resourceDetailService: SucceedingResourceDetailService(),
            loadedKubeconfig: kubeconfig()
        )

        model.connectSelectedCluster()
        try await waitForConnectionState(model, .connected)

        model.selectResource(.pods)
        try await waitForResourceList(model, .pods)

        guard case .loaded(let snapshot) = model.resourceListState(for: .pods),
              let row = snapshot.items.first else {
            Issue.record("Expected loaded resource row")
            return
        }

        model.loadResourceDetail(for: .pods, row: row)
        try await waitForResourceDetail(model, resource: .pods, row: row)

        guard case .loaded(let detail) = model.resourceDetailState(for: .pods, row: row) else {
            Issue.record("Expected loaded resource detail")
            return
        }

        #expect(detail.query.name == "web-0")
        #expect(detail.query.namespace == "vibekube-demo")
        #expect(detail.yaml.contains("kind: Pod"))
        #expect(detail.yaml.contains("name: web-0"))
        #expect(detail.yaml.contains("namespace: vibekube-demo"))

        let environment = try #require(detail.summary.environment.first)
        #expect(environment.envFrom.isEmpty)
        #expect(environment.variables.contains {
            $0.name == "APP_MODE" &&
                $0.literalValue == "demo" &&
                $0.source?.kind == .configMapKeyRef &&
                $0.source?.name == "web-config" &&
                $0.source?.key == "APP_MODE"
        })
        #expect(environment.variables.filter { $0.name == "PUBLIC_GREETING" }.count == 1)
        #expect(environment.variables.contains {
            $0.name == "PUBLIC_GREETING" &&
                $0.literalValue == "hello-from-configmap" &&
                $0.source?.kind == .configMapKeyRef &&
                $0.source?.name == "web-config" &&
                $0.source?.key == "PUBLIC_GREETING"
        })
        #expect(environment.variables.contains {
            $0.name == "EXTRA_API_TOKEN" &&
                $0.literalValue == nil &&
                $0.source?.kind == .secretKeyRef &&
                $0.source?.name == "web-secrets" &&
                $0.source?.key == "API_TOKEN"
        })
        #expect(!environment.variables.contains { $0.name == "EXTRA_db-password" })
    }

    @MainActor
    @Test func appModelLoadsResourceEventsForSelectedDetail() async throws {
        let model = AppModel(
            clusters: ClusterSummary.preview,
            connectionService: SucceedingConnectionService(),
            resourceListService: SucceedingResourceListService(),
            resourceDetailService: SucceedingResourceDetailService(),
            resourceEventService: SucceedingResourceEventService(),
            loadedKubeconfig: kubeconfig()
        )

        model.connectSelectedCluster()
        try await waitForConnectionState(model, .connected)

        model.selectResource(.pods)
        try await waitForResourceList(model, .pods)

        guard case .loaded(let listSnapshot) = model.resourceListState(for: .pods),
              let row = listSnapshot.items.first else {
            Issue.record("Expected loaded resource row")
            return
        }

        model.loadResourceDetail(for: .pods, row: row)
        try await waitForResourceDetail(model, resource: .pods, row: row)

        guard case .loaded(let detail) = model.resourceDetailState(for: .pods, row: row) else {
            Issue.record("Expected loaded resource detail")
            return
        }

        model.loadResourceEvents(for: detail)
        try await waitForResourceEvents(model, detail: detail)

        guard case .loaded(let events) = model.resourceEventsState(for: detail) else {
            Issue.record("Expected loaded resource events")
            return
        }

        #expect(events.query.involvedName == "web-0")
        #expect(events.query.involvedUID == "pod-uid")
        #expect(events.events.map(\.reason) == ["Pulled"])
    }

    @MainActor
    @Test func appModelLoadsPodLogsForSelectedPod() async throws {
        let model = AppModel(
            clusters: ClusterSummary.preview,
            connectionService: SucceedingConnectionService(),
            resourceListService: SucceedingResourceListService(),
            logService: SucceedingLogService(),
            loadedKubeconfig: kubeconfig()
        )

        model.connectSelectedCluster()
        try await waitForConnectionState(model, .connected)

        model.selectResource(.pods)
        try await waitForResourceList(model, .pods)

        guard case .loaded(let listSnapshot) = model.resourceListState(for: .pods),
              let pod = listSnapshot.items.first else {
            Issue.record("Expected pod row")
            return
        }

        model.loadPodLogs(for: pod, containerName: "web")
        try await waitForPodLogs(model, pod: pod, containerName: "web")

        guard case .loaded(let logSnapshot) = model.podLogState(for: pod, containerName: "web") else {
            Issue.record("Expected loaded pod logs")
            return
        }

        #expect(logSnapshot.query.namespace == "vibekube-demo")
        #expect(logSnapshot.query.podName == "web-0")
        #expect(logSnapshot.query.containerName == "web")
        #expect(logSnapshot.text.contains("hello from web-0"))
    }

    @MainActor
    @Test func appModelLoadsPodLogsWithSinceSeconds() async throws {
        let model = AppModel(
            clusters: ClusterSummary.preview,
            connectionService: SucceedingConnectionService(),
            resourceListService: SucceedingResourceListService(),
            logService: SinceLogService(),
            loadedKubeconfig: kubeconfig()
        )

        model.connectSelectedCluster()
        try await waitForConnectionState(model, .connected)

        model.selectResource(.pods)
        try await waitForResourceList(model, .pods)

        guard case .loaded(let listSnapshot) = model.resourceListState(for: .pods),
              let pod = listSnapshot.items.first else {
            Issue.record("Expected pod row")
            return
        }

        model.loadPodLogs(for: pod, containerName: "web", tailLines: 1_000, sinceSeconds: 900)
        try await waitForPodLogs(model, pod: pod, containerName: "web", tailLines: 1_000, sinceSeconds: 900)

        guard case .loaded(let logSnapshot) = model.podLogState(
            for: pod,
            containerName: "web",
            tailLines: 1_000,
            sinceSeconds: 900
        ) else {
            Issue.record("Expected loaded pod logs")
            return
        }

        #expect(logSnapshot.query.tailLines == 1_000)
        #expect(logSnapshot.query.sinceSeconds == 900)
        #expect(logSnapshot.text.contains("recent line"))
    }

    @MainActor
    @Test func appModelStripsANSISequencesFromPodLogs() async throws {
        let model = AppModel(
            clusters: ClusterSummary.preview,
            connectionService: SucceedingConnectionService(),
            resourceListService: SucceedingResourceListService(),
            logService: ANSILogService(),
            loadedKubeconfig: kubeconfig()
        )

        model.connectSelectedCluster()
        try await waitForConnectionState(model, .connected)

        model.selectResource(.pods)
        try await waitForResourceList(model, .pods)

        guard case .loaded(let listSnapshot) = model.resourceListState(for: .pods),
              let pod = listSnapshot.items.first else {
            Issue.record("Expected pod row")
            return
        }

        model.loadPodLogs(for: pod, containerName: "web")
        try await waitForPodLogs(model, pod: pod, containerName: "web")

        guard case .loaded(let logSnapshot) = model.podLogState(for: pod, containerName: "web") else {
            Issue.record("Expected loaded pod logs")
            return
        }

        #expect(logSnapshot.text == "2026-06-15T10:01:00Z error plain ok")

        let downloadedText = try await model.podLogsText(for: pod, containerName: "web", tailLines: nil)
        #expect(downloadedText == "2026-06-15T10:01:00Z error plain ok")
    }

    @MainActor
    @Test func appModelInfersMissingPodKindAndLoadsLogs() async throws {
        let model = AppModel(
            clusters: ClusterSummary.preview,
            connectionService: SucceedingConnectionService(),
            resourceListService: MissingKindPodResourceListService(),
            logService: SucceedingLogService(),
            loadedKubeconfig: kubeconfig()
        )

        model.connectSelectedCluster()
        try await waitForConnectionState(model, .connected)

        model.selectResource(.pods)
        try await waitForResourceList(model, .pods)

        guard case .loaded(let listSnapshot) = model.resourceListState(for: .pods),
              let pod = listSnapshot.items.first else {
            Issue.record("Expected pod row")
            return
        }

        #expect(pod.displayKind == "Pod")

        model.loadPodLogs(for: pod, containerName: "web")
        try await waitForPodLogs(model, pod: pod, containerName: "web")

        guard case .loaded(let logSnapshot) = model.podLogState(for: pod, containerName: "web") else {
            Issue.record("Expected loaded pod logs")
            return
        }

        #expect(logSnapshot.query.podName == "web-0")
        #expect(logSnapshot.text.contains("hello from web-0"))
    }

    @MainActor
    @Test func appModelStreamsPodLogs() async throws {
        let model = AppModel(
            clusters: ClusterSummary.preview,
            connectionService: SucceedingConnectionService(),
            resourceListService: SucceedingResourceListService(),
            logService: SucceedingLogService(),
            loadedKubeconfig: kubeconfig()
        )

        model.connectSelectedCluster()
        try await waitForConnectionState(model, .connected)

        model.selectResource(.pods)
        try await waitForResourceList(model, .pods)

        guard case .loaded(let listSnapshot) = model.resourceListState(for: .pods),
              let pod = listSnapshot.items.first else {
            Issue.record("Expected pod row")
            return
        }

        model.loadPodLogs(for: pod, containerName: "web")
        try await waitForPodLogs(model, pod: pod, containerName: "web")

        model.loadPodLogs(for: pod, containerName: "web", follow: true)
        try await waitUntil("streaming pod logs appended") {
            if case .loaded(let snapshot) = model.podLogState(for: pod, containerName: "web", follow: true) {
                return snapshot.text.contains("still running")
            }
            return false
        }

        guard case .loaded(let logSnapshot) = model.podLogState(for: pod, containerName: "web", follow: true) else {
            Issue.record("Expected streaming pod logs")
            return
        }

        #expect(logSnapshot.query.follow)
        #expect(logSnapshot.query.tailLines == 200)
        #expect(logSnapshot.text.contains("hello from web-0"))
        #expect(logSnapshot.text.contains("still running"))
        #expect(logSnapshot.text.components(separatedBy: "hello from web-0").count == 2)
    }

    @MainActor
    @Test func appModelCapsLivePodLogBuffer() async throws {
        let model = AppModel(
            clusters: ClusterSummary.preview,
            connectionService: SucceedingConnectionService(),
            resourceListService: SucceedingResourceListService(),
            logService: BufferingLogService(),
            loadedKubeconfig: kubeconfig(),
            podLogLineLimit: 3
        )

        model.connectSelectedCluster()
        try await waitForConnectionState(model, .connected)

        model.selectResource(.pods)
        try await waitForResourceList(model, .pods)

        guard case .loaded(let listSnapshot) = model.resourceListState(for: .pods),
              let pod = listSnapshot.items.first else {
            Issue.record("Expected pod row")
            return
        }

        model.loadPodLogs(for: pod, containerName: "web", follow: true)
        try await waitUntil("streaming pod logs capped") {
            if case .loaded(let snapshot) = model.podLogState(for: pod, containerName: "web", follow: true) {
                return snapshot.text.contains("line 6")
            }
            return false
        }

        guard case .loaded(let logSnapshot) = model.podLogState(for: pod, containerName: "web", follow: true) else {
            Issue.record("Expected streaming pod logs")
            return
        }

        #expect(logSnapshot.lines == ["line 4", "line 5", "line 6", ""])
        #expect(!logSnapshot.text.contains("line 1"))
    }

    @MainActor
    @Test func appModelRecapsLoadedPodLogsWhenBufferLimitChanges() async throws {
        let model = AppModel(
            clusters: ClusterSummary.preview,
            connectionService: SucceedingConnectionService(),
            resourceListService: SucceedingResourceListService(),
            logService: BufferingLogService(),
            loadedKubeconfig: kubeconfig(),
            podLogLineLimit: 6
        )

        model.connectSelectedCluster()
        try await waitForConnectionState(model, .connected)

        model.selectResource(.pods)
        try await waitForResourceList(model, .pods)

        guard case .loaded(let listSnapshot) = model.resourceListState(for: .pods),
              let pod = listSnapshot.items.first else {
            Issue.record("Expected pod row")
            return
        }

        model.loadPodLogs(for: pod, containerName: "web", follow: true)
        try await waitUntil("streaming pod logs loaded") {
            if case .loaded(let snapshot) = model.podLogState(for: pod, containerName: "web", follow: true) {
                return snapshot.text.contains("line 6")
            }
            return false
        }

        model.setPodLogLineLimit(3)

        guard case .loaded(let logSnapshot) = model.podLogState(for: pod, containerName: "web", follow: true) else {
            Issue.record("Expected streaming pod logs")
            return
        }

        #expect(model.podLogLineLimit == 3)
        #expect(logSnapshot.lines == ["line 4", "line 5", "line 6", ""])
    }

    @MainActor
    @Test func appModelAppliesPodWatchAddedEvents() async throws {
        let model = AppModel(
            clusters: ClusterSummary.preview,
            connectionService: SucceedingConnectionService(),
            resourceListService: WatchingPodResourceListService(),
            loadedKubeconfig: kubeconfig()
        )

        model.connectSelectedCluster()
        try await waitForConnectionState(model, .connected)

        model.selectResource(.pods)
        try await waitUntil("watched pod appears") {
            guard case .loaded(let snapshot) = model.resourceListState(for: .pods) else {
                return false
            }
            return snapshot.items.contains { $0.displayName == "heartbeat-1" }
        }

        guard case .loaded(let snapshot) = model.resourceListState(for: .pods) else {
            Issue.record("Expected watched pod list")
            return
        }

        #expect(snapshot.items.map(\.displayName).contains("web-0"))
        #expect(snapshot.items.map(\.displayName).contains("heartbeat-1"))
    }

    @MainActor
    @Test func appModelAppliesDeploymentWatchAddedEvents() async throws {
        let model = AppModel(
            clusters: ClusterSummary.preview,
            connectionService: WatchableWorkloadsConnectionService(),
            resourceListService: WatchingDeploymentResourceListService(),
            loadedKubeconfig: kubeconfig()
        )

        model.connectSelectedCluster()
        try await waitForConnectionState(model, .connected)

        model.selectResource(.deployments)
        try await waitUntil("watched deployment appears") {
            guard case .loaded(let snapshot) = model.resourceListState(for: .deployments) else {
                return false
            }
            return snapshot.items.contains { $0.displayName == "api" }
        }

        guard case .loaded(let snapshot) = model.resourceListState(for: .deployments) else {
            Issue.record("Expected watched deployment list")
            return
        }

        #expect(snapshot.items.map(\.displayName).contains("web"))
        #expect(snapshot.items.map(\.displayName).contains("api"))
        #expect(model.resourceWatchStatus(for: .deployments) != nil)
    }

    @MainActor
    @Test func appModelRelistsWhenWatchResourceVersionExpires() async throws {
        let resourceListService = ExpiringWatchResourceListService()
        let model = AppModel(
            clusters: ClusterSummary.preview,
            connectionService: SucceedingConnectionService(),
            resourceListService: resourceListService,
            loadedKubeconfig: kubeconfig()
        )

        model.connectSelectedCluster()
        try await waitForConnectionState(model, .connected)

        model.selectResource(.pods)
        try await waitUntil("watch relisted after expired resource version") {
            guard case .loaded(let snapshot) = model.resourceListState(for: .pods) else {
                return false
            }
            return snapshot.resourceVersion == "21" &&
                snapshot.items.contains { $0.displayName == "relisted-0" } &&
                snapshot.items.contains { $0.displayName == "after-relist" }
        }

        #expect(resourceListService.watchedResourceVersions() == ["10", "20"])
    }

    @MainActor
    @Test func appModelKeepsReconnectingTransientResourceWatchFailures() async throws {
        let resourceListService = TransientFailingWatchResourceListService()
        let model = AppModel(
            clusters: ClusterSummary.preview,
            connectionService: SucceedingConnectionService(),
            resourceListService: resourceListService,
            loadedKubeconfig: kubeconfig()
        )

        model.connectSelectedCluster()
        try await waitForConnectionState(model, .connected)

        model.selectResource(.pods)
        try await waitUntil(
            "watch retries past transient failure budget",
            attempts: 120,
            sleepNanoseconds: 50_000_000
        ) {
            resourceListService.watchCallCount() >= 4
        }

        guard let status = model.resourceWatchStatus(for: .pods) else {
            Issue.record("Expected resource watch status")
            return
        }

        if case .failed = status {
            Issue.record("Transient watch failures should keep reconnecting instead of failing permanently")
        }
    }

    @MainActor
    @Test func appModelShowsReconnectingStatusAfterTransientResourceWatchFailure() async throws {
        let resourceListService = TransientFailingWatchResourceListService()
        let model = AppModel(
            clusters: ClusterSummary.preview,
            connectionService: SucceedingConnectionService(),
            resourceListService: resourceListService,
            loadedKubeconfig: kubeconfig()
        )

        model.connectSelectedCluster()
        try await waitForConnectionState(model, .connected)

        model.selectResource(.pods)
        try await waitUntil("watch enters reconnecting status") {
            if case .reconnecting = model.resourceWatchStatus(for: .pods) {
                return true
            }
            return false
        }

        guard case .reconnecting(let state) = model.resourceWatchStatus(for: .pods) else {
            Issue.record("Expected reconnecting watch status")
            return
        }

        #expect(state.attempt == 2)
        #expect(state.message == "The request timed out.")
        #expect(resourceListService.watchCallCount() == 1)
    }

    @MainActor
    @Test func appModelCanDisableResourceWatches() async throws {
        let resourceListService = TransientFailingWatchResourceListService()
        let model = AppModel(
            clusters: ClusterSummary.preview,
            connectionService: SucceedingConnectionService(),
            resourceListService: resourceListService,
            userPreferences: InMemoryUserPreferences(resourceWatchesEnabled: false),
            loadedKubeconfig: kubeconfig()
        )

        model.connectSelectedCluster()
        try await waitForConnectionState(model, .connected)

        model.selectResource(.pods)
        try await waitForResourceList(model, .pods)
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(!model.resourceWatchesEnabled)
        #expect(resourceListService.watchCallCount() == 0)
        #expect(model.resourceWatchStatus(for: .pods) == nil)
    }

    @MainActor
    @Test func appModelResumesActiveResourceWatchWhenEnabled() async throws {
        let resourceListService = TransientFailingWatchResourceListService()
        let model = AppModel(
            clusters: ClusterSummary.preview,
            connectionService: SucceedingConnectionService(),
            resourceListService: resourceListService,
            userPreferences: InMemoryUserPreferences(resourceWatchesEnabled: false),
            loadedKubeconfig: kubeconfig()
        )

        model.connectSelectedCluster()
        try await waitForConnectionState(model, .connected)

        model.selectResource(.pods)
        try await waitForResourceList(model, .pods)
        #expect(resourceListService.watchCallCount() == 0)

        model.setResourceWatchesEnabled(true)

        try await waitUntil("resource watch resumes") {
            resourceListService.watchCallCount() >= 1
        }

        #expect(model.resourceWatchesEnabled)
        #expect(model.resourceWatchStatus(for: .pods) != nil)
    }

    @MainActor
    @Test func appModelRefreshesOpenPodDetailWhenWatchUpdatesResourceVersion() async throws {
        let detailService = VersionedPodDetailService()
        let model = AppModel(
            clusters: ClusterSummary.preview,
            connectionService: SucceedingConnectionService(),
            resourceListService: ModifyingPodResourceListService(),
            resourceDetailService: detailService,
            loadedKubeconfig: kubeconfig()
        )

        model.connectSelectedCluster()
        try await waitForConnectionState(model, .connected)

        model.selectResource(.pods)
        try await waitForResourceList(model, .pods)

        guard case .loaded(let firstSnapshot) = model.resourceListState(for: .pods),
              let initialRow = firstSnapshot.items.first(where: { $0.displayName == "web-0" }) else {
            Issue.record("Expected initial pod row")
            return
        }

        model.loadResourceDetail(for: .pods, row: initialRow)
        try await waitForResourceDetail(model, resource: .pods, row: initialRow)

        guard case .loaded(let initialDetail) = model.resourceDetailState(for: .pods, row: initialRow) else {
            Issue.record("Expected initial pod detail")
            return
        }
        #expect(initialDetail.summary.resourceVersion == "10")

        try await waitUntil("watched pod version appears") {
            guard case .loaded(let snapshot) = model.resourceListState(for: .pods),
                  let updatedRow = snapshot.items.first(where: { $0.displayName == "web-0" }) else {
                return false
            }
            return updatedRow.metadata.resourceVersion == "11"
        }

        guard case .loaded(let updatedSnapshot) = model.resourceListState(for: .pods),
              let updatedRow = updatedSnapshot.items.first(where: { $0.displayName == "web-0" }) else {
            Issue.record("Expected updated pod row")
            return
        }

        try await waitUntil("pod detail refreshed for watched version") {
            guard case .loaded(let detail) = model.resourceDetailState(for: .pods, row: updatedRow) else {
                return false
            }
            return detail.summary.resourceVersion == "11"
        }

        #expect(await detailService.callCount() >= 2)
    }

    @MainActor
    @Test func appModelRefreshesOpenDeploymentDetailWhenWatchUpdatesResourceVersion() async throws {
        let detailService = VersionedDeploymentDetailService()
        let model = AppModel(
            clusters: ClusterSummary.preview,
            connectionService: WatchableWorkloadsConnectionService(),
            resourceListService: ModifyingDeploymentResourceListService(),
            resourceDetailService: detailService,
            loadedKubeconfig: kubeconfig()
        )

        model.connectSelectedCluster()
        try await waitForConnectionState(model, .connected)

        model.selectResource(.deployments)
        try await waitForResourceList(model, .deployments)

        guard case .loaded(let firstSnapshot) = model.resourceListState(for: .deployments),
              let initialRow = firstSnapshot.items.first(where: { $0.displayName == "web" }) else {
            Issue.record("Expected initial deployment row")
            return
        }

        model.loadResourceDetail(for: .deployments, row: initialRow)
        try await waitForResourceDetail(model, resource: .deployments, row: initialRow)

        guard case .loaded(let initialDetail) = model.resourceDetailState(for: .deployments, row: initialRow) else {
            Issue.record("Expected initial deployment detail")
            return
        }
        #expect(initialDetail.summary.resourceVersion == "20")

        try await waitUntil("watched deployment version appears") {
            guard case .loaded(let snapshot) = model.resourceListState(for: .deployments),
                  let updatedRow = snapshot.items.first(where: { $0.displayName == "web" }) else {
                return false
            }
            return updatedRow.metadata.resourceVersion == "21"
        }

        guard case .loaded(let updatedSnapshot) = model.resourceListState(for: .deployments),
              let updatedRow = updatedSnapshot.items.first(where: { $0.displayName == "web" }) else {
            Issue.record("Expected updated deployment row")
            return
        }

        try await waitUntil("deployment detail refreshed for watched version") {
            guard case .loaded(let detail) = model.resourceDetailState(for: .deployments, row: updatedRow) else {
                return false
            }
            return detail.summary.resourceVersion == "21"
        }

        #expect(await detailService.callCount() >= 2)
    }

    @MainActor
    @Test func appModelRefreshesOpenDetailFromSelectedResourceWatch() async throws {
        let resourceListService = DetailWatchingPodResourceListService()
        let detailService = DetailWatchPodDetailService()
        let model = AppModel(
            clusters: ClusterSummary.preview,
            connectionService: WatchableWorkloadsConnectionService(),
            resourceListService: resourceListService,
            resourceDetailService: detailService,
            loadedKubeconfig: kubeconfig()
        )

        model.connectSelectedCluster()
        try await waitForConnectionState(model, .connected)

        model.selectResource(.pods)
        try await waitForResourceList(model, .pods)

        guard case .loaded(let firstSnapshot) = model.resourceListState(for: .pods),
              let initialRow = firstSnapshot.items.first(where: { $0.displayName == "web-0" }) else {
            Issue.record("Expected initial pod row")
            return
        }

        model.loadResourceDetail(for: .pods, row: initialRow)
        try await waitForResourceDetail(model, resource: .pods, row: initialRow)

        guard case .loaded(let initialDetail) = model.resourceDetailState(for: .pods, row: initialRow) else {
            Issue.record("Expected initial pod detail")
            return
        }
        #expect(initialDetail.summary.resourceVersion == "30")

        try await waitUntil("pod detail refreshed from selected resource watch") {
            guard case .loaded(let detail) = model.resourceDetailState(for: .pods, row: initialRow) else {
                return false
            }
            return detail.summary.resourceVersion == "31"
        }

        guard case .loaded(let unchangedListSnapshot) = model.resourceListState(for: .pods),
              let unchangedRow = unchangedListSnapshot.items.first(where: { $0.displayName == "web-0" }) else {
            Issue.record("Expected unchanged pod row")
            return
        }
        #expect(unchangedRow.metadata.resourceVersion == "30")
        #expect(await detailService.callCount() >= 2)
        #expect(resourceListService.detailWatchNames().contains("web-0"))
    }

    @MainActor
    @Test func appModelCoalescesBurstWatchDetailRefreshes() async throws {
        let detailService = CoalescedPodDetailService()
        let model = AppModel(
            clusters: ClusterSummary.preview,
            connectionService: WatchableWorkloadsConnectionService(),
            resourceListService: BurstingPodResourceListService(),
            resourceDetailService: detailService,
            loadedKubeconfig: kubeconfig()
        )

        model.connectSelectedCluster()
        try await waitForConnectionState(model, .connected)

        model.selectResource(.pods)
        try await waitForResourceList(model, .pods)

        guard case .loaded(let firstSnapshot) = model.resourceListState(for: .pods),
              let initialRow = firstSnapshot.items.first(where: { $0.displayName == "web-0" }) else {
            Issue.record("Expected initial pod row")
            return
        }

        model.loadResourceDetail(for: .pods, row: initialRow)
        try await waitForResourceDetail(model, resource: .pods, row: initialRow)

        try await waitUntil("burst watch reached latest list version") {
            guard case .loaded(let snapshot) = model.resourceListState(for: .pods),
                  let updatedRow = snapshot.items.first(where: { $0.displayName == "web-0" }) else {
                return false
            }
            return updatedRow.metadata.resourceVersion == "12"
        }

        try await waitUntil("burst watch refreshed detail once for latest version") {
            guard case .loaded(let detail) = model.resourceDetailState(for: .pods, row: initialRow) else {
                return false
            }
            return detail.summary.resourceVersion == "12"
        }

        #expect(await detailService.callCount() == 2)
    }

    @MainActor
    @Test func appModelDownloadsAllPreviousPodLogs() async throws {
        let model = AppModel(
            clusters: ClusterSummary.preview,
            connectionService: SucceedingConnectionService(),
            resourceListService: SucceedingResourceListService(),
            logService: AllPreviousLogService(),
            loadedKubeconfig: kubeconfig()
        )

        model.connectSelectedCluster()
        try await waitForConnectionState(model, .connected)

        model.selectResource(.pods)
        try await waitForResourceList(model, .pods)

        guard case .loaded(let listSnapshot) = model.resourceListState(for: .pods),
              let pod = listSnapshot.items.first else {
            Issue.record("Expected pod row")
            return
        }

        let text = try await model.podLogsText(
            for: pod,
            containerName: "web",
            timestamps: true,
            previous: true,
            tailLines: nil
        )

        #expect(text.contains("previous crash"))
    }

    @MainActor
    @Test func appModelRevealsEnvSecretValue() async throws {
        let model = AppModel(
            clusters: ClusterSummary.preview,
            connectionService: SucceedingConnectionService(),
            resourceDetailService: SucceedingResourceDetailService(),
            loadedKubeconfig: kubeconfig()
        )

        model.connectSelectedCluster()
        try await waitForConnectionState(model, .connected)

        model.revealEnvSecretValue(
            namespace: "vibekube-demo",
            secretName: "web-secrets",
            key: "db-password"
        )
        try await waitForEnvSecretValue(model, namespace: "vibekube-demo", secretName: "web-secrets", key: "db-password")

        guard case .loaded(let value) = model.envSecretValueState(
            namespace: "vibekube-demo",
            secretName: "web-secrets",
            key: "db-password"
        ) else {
            Issue.record("Expected revealed secret env value")
            return
        }

        #expect(value == "test-password")
    }

    @MainActor
    @Test func appModelStoresSecretRevealConfirmationPreference() {
        let model = AppModel(
            clusters: ClusterSummary.preview,
            connectionService: SucceedingConnectionService(),
            loadedKubeconfig: kubeconfig()
        )

        #expect(model.secretRevealRequiresConfirmation)

        model.setSecretRevealRequiresConfirmation(false)
        #expect(!model.secretRevealRequiresConfirmation)

        model.setSecretRevealRequiresConfirmation(true)
        #expect(model.secretRevealRequiresConfirmation)
    }

    @Test func resourceNavigationGroupsWorkloads() {
        #expect(ResourceNavigationItem.pods.section == .workloads)
        #expect(ResourceNavigationItem.deployments.section == .workloads)
        #expect(ResourceNavigationItem.services.section == .network)
    }

}

@MainActor
private func waitForConnectionState(
    _ model: AppModel,
    _ state: ConnectionState
) async throws {
    try await waitUntil("connection state \(state.rawValue)") {
        model.selectedConnectionState == state
    }
}

@MainActor
private func waitForResourceList(
    _ model: AppModel,
    _ resource: ResourceNavigationItem
) async throws {
    try await waitUntil("\(resource.title) list loaded") {
        if case .loaded = model.resourceListState(for: resource) {
            return true
        }
        return false
    }
}

private func testKubeconfig(named name: String, server: String) -> String {
    """
    current-context: \(name)
    clusters:
    - name: \(name)
      cluster:
        server: \(server)
    contexts:
    - name: \(name)
      context:
        cluster: \(name)
        user: \(name)-user
    users:
    - name: \(name)-user
      user:
        token: \(name)-token
    """
}

private func podResource(name: String, namespace: String) throws -> KubernetesUnstructuredResource {
    try JSONDecoder().decode(
        KubernetesUnstructuredResource.self,
        from: Data(
            """
            {
              "apiVersion": "v1",
              "kind": "Pod",
              "metadata": {
                "name": "\(name)",
                "namespace": "\(namespace)"
              },
              "spec": {
                "containers": [
                  {
                    "name": "web",
                    "image": "nginx"
                  }
                ]
              }
            }
            """.utf8
        )
    )
}

@MainActor
private func waitForResourceDetail(
    _ model: AppModel,
    resource: ResourceNavigationItem,
    row: KubernetesUnstructuredResource
) async throws {
    try await waitUntil("\(resource.title) detail loaded") {
        if case .loaded = model.resourceDetailState(for: resource, row: row) {
            return true
        }
        return false
    }
}

@MainActor
private func waitForResourceEvents(
    _ model: AppModel,
    detail: ResourceDetailSnapshot
) async throws {
    try await waitUntil("resource events loaded") {
        if case .loaded = model.resourceEventsState(for: detail) {
            return true
        }
        return false
    }
}

@MainActor
private func waitForPodLogs(
    _ model: AppModel,
    pod: KubernetesUnstructuredResource,
    containerName: String?,
    tailLines: Int? = 200,
    sinceSeconds: Int? = nil,
    follow: Bool = false
) async throws {
    try await waitUntil("pod logs loaded") {
        if case .loaded = model.podLogState(
            for: pod,
            containerName: containerName,
            tailLines: tailLines,
            sinceSeconds: sinceSeconds,
            follow: follow
        ) {
            return true
        }
        return false
    }
}

@MainActor
private func waitForPortForwardSession(
    _ model: AppModel,
    status: PortForwardSession.Status
) async throws {
    try await waitUntil("port-forward session \(status)") {
        model.portForwardSessions.contains { $0.status == status }
    }
}

@MainActor
private func waitForEnvSecretValue(
    _ model: AppModel,
    namespace: String?,
    secretName: String?,
    key: String?
) async throws {
    try await waitUntil("env secret value loaded") {
        if case .loaded = model.envSecretValueState(namespace: namespace, secretName: secretName, key: key) {
            return true
        }
        return false
    }
}

@MainActor
private func waitUntil(
    _ description: String,
    attempts: Int = 60,
    sleepNanoseconds: UInt64 = 5_000_000,
    condition: @escaping @MainActor () -> Bool
) async throws {
    for _ in 0..<attempts {
        if condition() {
            return
        }
        try await Task.sleep(nanoseconds: sleepNanoseconds)
    }

    Issue.record("Timed out waiting for \(description)")
}

private struct SucceedingConnectionService: KubernetesConnectionServicing {
    func connect(
        contextName: String,
        kubeconfig: Kubeconfig,
        progress: @escaping @Sendable (KubernetesConnectionProgress) async -> Void
    ) async throws -> KubernetesConnectionSnapshot {
        KubernetesConnectionSnapshot(
            version: KubernetesVersion(
                major: "1",
                minor: "30",
                gitVersion: "v1.30.0",
                gitCommit: nil,
                platform: nil
            ),
            discovery: KubernetesDiscoverySnapshot(
                coreVersions: ["v1"],
                groups: [],
                resourceLists: [
                    KubernetesAPIResourceList(
                        groupVersion: "v1",
                        resources: [
                            KubernetesAPIResource(name: "pods", singularName: "", namespaced: true, kind: "Pod", verbs: ["get", "list", "watch"], shortNames: nil, categories: nil),
                            KubernetesAPIResource(name: "configmaps", singularName: "", namespaced: true, kind: "ConfigMap", verbs: ["get"], shortNames: nil, categories: nil),
                            KubernetesAPIResource(name: "secrets", singularName: "", namespaced: true, kind: "Secret", verbs: ["get"], shortNames: nil, categories: nil),
                            KubernetesAPIResource(name: "events", singularName: "", namespaced: true, kind: "Event", verbs: ["list"], shortNames: nil, categories: nil)
                        ]
                    )
                ],
                namespaceDiscovery: .loaded([
                    KubernetesNamespaceSummary(name: "default", phase: "Active"),
                    KubernetesNamespaceSummary(name: "vibekube-demo", phase: "Active")
                ])
            )
        )
    }
}

private struct ProgressReportingConnectionService: KubernetesConnectionServicing {
    func connect(
        contextName: String,
        kubeconfig: Kubeconfig,
        progress: @escaping @Sendable (KubernetesConnectionProgress) async -> Void
    ) async throws -> KubernetesConnectionSnapshot {
        await progress(.resolvingExecCredential(command: "tsh"))
        try await Task.sleep(nanoseconds: 50_000_000)
        return KubernetesConnectionSnapshot(
            version: KubernetesVersion(
                major: "1",
                minor: "30",
                gitVersion: "v1.30.0",
                gitCommit: nil,
                platform: nil
            )
        )
    }
}

private final class RecordingLocalPortChecker: LocalPortChecking {
    private let unavailablePorts: Set<Int>
    var checkedPorts: [Int] = []

    init(unavailablePorts: Set<Int> = []) {
        self.unavailablePorts = unavailablePorts
    }

    func isLocalPortAvailable(_ port: Int) -> Bool {
        checkedPorts.append(port)
        return !unavailablePorts.contains(port)
    }
}

private final class RecordingPortForwardService: KubernetesPortForwardServicing {
    var requests: [KubernetesPortForwardRequest] = []
    var handles: [RecordingPortForwardHandle] = []
    var terminations: [@Sendable (KubernetesPortForwardTermination) -> Void] = []

    func startPortForward(
        request: KubernetesPortForwardRequest,
        onTermination: @escaping @Sendable (KubernetesPortForwardTermination) -> Void
    ) async throws -> KubernetesPortForwardHandle {
        let handle = RecordingPortForwardHandle(processIdentifier: 4242)
        requests.append(request)
        handles.append(handle)
        terminations.append(onTermination)
        return handle
    }

    func terminateFirst(_ termination: KubernetesPortForwardTermination) {
        terminations.first?(termination)
    }
}

private final class RecordingPortForwardHandle: KubernetesPortForwardHandle {
    let processIdentifier: Int32?
    var stopped = false

    init(processIdentifier: Int32?) {
        self.processIdentifier = processIdentifier
    }

    func stop() {
        stopped = true
    }
}

private final class TerminatingPortForwardService: KubernetesPortForwardServicing {
    let termination: KubernetesPortForwardTermination

    init(termination: KubernetesPortForwardTermination) {
        self.termination = termination
    }

    func startPortForward(
        request: KubernetesPortForwardRequest,
        onTermination: @escaping @Sendable (KubernetesPortForwardTermination) -> Void
    ) async throws -> KubernetesPortForwardHandle {
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000)
            onTermination(termination)
        }
        return RecordingPortForwardHandle(processIdentifier: 4242)
    }
}

private final class RecordingExecLauncher: KubernetesExecLaunching {
    var requests: [KubernetesExecLaunchRequest] = []

    nonisolated func launchExec(request: KubernetesExecLaunchRequest) async throws {
        await MainActor.run {
            requests.append(request)
        }
    }
}

private struct FailingExecLauncher: KubernetesExecLaunching {
    var error: Error

    nonisolated func launchExec(request: KubernetesExecLaunchRequest) async throws {
        throw error
    }
}

private struct ExecLaunchTestError: LocalizedError {
    var message: String

    var errorDescription: String? {
        message
    }
}

private struct WatchableWorkloadsConnectionService: KubernetesConnectionServicing {
    func connect(
        contextName: String,
        kubeconfig: Kubeconfig,
        progress: @escaping @Sendable (KubernetesConnectionProgress) async -> Void
    ) async throws -> KubernetesConnectionSnapshot {
        KubernetesConnectionSnapshot(
            version: KubernetesVersion(
                major: "1",
                minor: "30",
                gitVersion: "v1.30.0",
                gitCommit: nil,
                platform: nil
            ),
            discovery: KubernetesDiscoverySnapshot(
                coreVersions: ["v1"],
                groups: [
                    KubernetesAPIGroup(
                        name: "apps",
                        versions: [
                            KubernetesGroupVersion(groupVersion: "apps/v1", version: "v1")
                        ],
                        preferredVersion: KubernetesGroupVersion(groupVersion: "apps/v1", version: "v1")
                    ),
                    KubernetesAPIGroup(
                        name: "batch",
                        versions: [
                            KubernetesGroupVersion(groupVersion: "batch/v1", version: "v1")
                        ],
                        preferredVersion: KubernetesGroupVersion(groupVersion: "batch/v1", version: "v1")
                    ),
                    KubernetesAPIGroup(
                        name: "networking.k8s.io",
                        versions: [
                            KubernetesGroupVersion(groupVersion: "networking.k8s.io/v1", version: "v1")
                        ],
                        preferredVersion: KubernetesGroupVersion(groupVersion: "networking.k8s.io/v1", version: "v1")
                    )
                ],
                resourceLists: [
                    KubernetesAPIResourceList(
                        groupVersion: "v1",
                        resources: [
                            KubernetesAPIResource(name: "pods", singularName: "", namespaced: true, kind: "Pod", verbs: ["get", "list", "watch"], shortNames: nil, categories: nil),
                            KubernetesAPIResource(name: "services", singularName: "", namespaced: true, kind: "Service", verbs: ["get", "list", "watch"], shortNames: nil, categories: nil)
                        ]
                    ),
                    KubernetesAPIResourceList(
                        groupVersion: "apps/v1",
                        resources: [
                            KubernetesAPIResource(name: "deployments", singularName: "", namespaced: true, kind: "Deployment", verbs: ["get", "list", "watch"], shortNames: nil, categories: nil),
                            KubernetesAPIResource(name: "replicasets", singularName: "", namespaced: true, kind: "ReplicaSet", verbs: ["get", "list", "watch"], shortNames: nil, categories: nil)
                        ]
                    ),
                    KubernetesAPIResourceList(
                        groupVersion: "batch/v1",
                        resources: [
                            KubernetesAPIResource(name: "jobs", singularName: "", namespaced: true, kind: "Job", verbs: ["get", "list", "watch"], shortNames: nil, categories: nil),
                            KubernetesAPIResource(name: "cronjobs", singularName: "", namespaced: true, kind: "CronJob", verbs: ["get", "list", "watch"], shortNames: nil, categories: nil)
                        ]
                    ),
                    KubernetesAPIResourceList(
                        groupVersion: "networking.k8s.io/v1",
                        resources: [
                            KubernetesAPIResource(name: "ingresses", singularName: "", namespaced: true, kind: "Ingress", verbs: ["get", "list", "watch"], shortNames: nil, categories: nil)
                        ]
                    )
                ],
                namespaceDiscovery: .loaded([
                    KubernetesNamespaceSummary(name: "default", phase: "Active"),
                    KubernetesNamespaceSummary(name: "vibekube-demo", phase: "Active")
                ])
            )
        )
    }
}

private struct DashboardConnectionService: KubernetesConnectionServicing {
    func connect(
        contextName: String,
        kubeconfig: Kubeconfig,
        progress: @escaping @Sendable (KubernetesConnectionProgress) async -> Void
    ) async throws -> KubernetesConnectionSnapshot {
        KubernetesConnectionSnapshot(
            version: KubernetesVersion(
                major: "1",
                minor: "30",
                gitVersion: "v1.30.0",
                gitCommit: nil,
                platform: nil
            ),
            discovery: KubernetesDiscoverySnapshot(
                coreVersions: ["v1"],
                groups: [],
                resourceLists: [
                    KubernetesAPIResourceList(
                        groupVersion: "v1",
                        resources: AppModel.dashboardResourceItems
                            .map(dashboardAPIResource(for:))
                            .filter { resource in
                                ["nodes", "pods", "persistentvolumes", "persistentvolumeclaims", "events"].contains(resource.name)
                            }
                    ),
                    KubernetesAPIResourceList(
                        groupVersion: "apps/v1",
                        resources: AppModel.dashboardResourceItems
                            .map(dashboardAPIResource(for:))
                            .filter { resource in
                                ["deployments", "statefulsets", "daemonsets"].contains(resource.name)
                            }
                    ),
                    KubernetesAPIResourceList(
                        groupVersion: "batch/v1",
                        resources: AppModel.dashboardResourceItems
                            .map(dashboardAPIResource(for:))
                            .filter { resource in
                                ["jobs", "cronjobs"].contains(resource.name)
                            }
                    )
                ],
                namespaceDiscovery: .loaded([
                    KubernetesNamespaceSummary(name: "default", phase: "Active")
                ])
            )
        )
    }
}

private actor DashboardResourceListRecorder {
    private var names: [String] = []

    var count: Int {
        names.count
    }

    func record(_ name: String) {
        names.append(name)
    }

    func resourceNames() -> [String] {
        names
    }
}

private struct DashboardResourceListService: KubernetesResourceListServicing {
    let recorder: DashboardResourceListRecorder
    var delayNanoseconds: UInt64 = 2_000_000

    func listResources(
        contextName: String,
        kubeconfig: Kubeconfig,
        resource: KubernetesDiscoveredResource,
        namespace: String?
    ) async throws -> KubernetesUnstructuredResourceList {
        try await Task.sleep(nanoseconds: delayNanoseconds)
        try Task.checkCancellation()
        await recorder.record(resource.name)

        return KubernetesUnstructuredResourceList(
            apiVersion: resource.groupVersion,
            kind: "\(resource.kind)List",
            metadata: nil,
            items: []
        )
    }
}

private struct SucceedingResourceListService: KubernetesResourceListServicing {
    func listResources(
        contextName: String,
        kubeconfig: Kubeconfig,
        resource: KubernetesDiscoveredResource,
        namespace: String?
    ) async throws -> KubernetesUnstructuredResourceList {
        try JSONDecoder().decode(
            KubernetesUnstructuredResourceList.self,
            from: Data(
                """
                {
                  "items": [
                    {
                      "apiVersion": "v1",
                      "kind": "Pod",
                      "metadata": {
                        "name": "web-0",
                        "namespace": "\(namespace ?? "vibekube-demo")"
                      },
                      "status": {
                        "phase": "Running"
                      }
                    }
                  ]
                }
                """.utf8
            )
        )
    }
}

private struct WatchingPodResourceListService: KubernetesResourceListServicing {
    func listResources(
        contextName: String,
        kubeconfig: Kubeconfig,
        resource: KubernetesDiscoveredResource,
        namespace: String?
    ) async throws -> KubernetesUnstructuredResourceList {
        try JSONDecoder().decode(
            KubernetesUnstructuredResourceList.self,
            from: Data(
                """
                {
                  "metadata": {
                    "resourceVersion": "10"
                  },
                  "items": [
                    {
                      "apiVersion": "v1",
                      "kind": "Pod",
                      "metadata": {
                        "name": "web-0",
                        "namespace": "\(namespace ?? "vibekube-demo")",
                        "uid": "web-uid",
                        "resourceVersion": "10"
                      },
                      "status": {
                        "phase": "Running"
                      }
                    }
                  ]
                }
                """.utf8
            )
        )
    }

    func watchResources(
        contextName: String,
        kubeconfig: Kubeconfig,
        resource: KubernetesDiscoveredResource,
        namespace: String?,
        resourceVersion: String?
    ) -> AsyncThrowingStream<KubernetesWatchEvent<KubernetesUnstructuredResource>, Error> {
        AsyncThrowingStream { continuation in
            #expect(resource.name == "pods")
            #expect(resourceVersion == "10")

            do {
                let pod = try JSONDecoder().decode(
                    KubernetesUnstructuredResource.self,
                    from: Data(
                        """
                        {
                          "apiVersion": "v1",
                          "kind": "Pod",
                          "metadata": {
                            "name": "heartbeat-1",
                            "namespace": "\(namespace ?? "vibekube-demo")",
                            "uid": "heartbeat-uid",
                            "resourceVersion": "11"
                          },
                          "status": {
                            "phase": "Succeeded"
                          }
                        }
                        """.utf8
                    )
                )
                continuation.yield(
                    KubernetesWatchEvent(
                        type: .added,
                        object: pod
                    )
                )
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }
}

private struct WatchingDeploymentResourceListService: KubernetesResourceListServicing {
    func listResources(
        contextName: String,
        kubeconfig: Kubeconfig,
        resource: KubernetesDiscoveredResource,
        namespace: String?
    ) async throws -> KubernetesUnstructuredResourceList {
        #expect(resource.name == "deployments")
        return try JSONDecoder().decode(
            KubernetesUnstructuredResourceList.self,
            from: Data(
                """
                {
                  "metadata": {
                    "resourceVersion": "20"
                  },
                  "items": [
                    {
                      "apiVersion": "apps/v1",
                      "kind": "Deployment",
                      "metadata": {
                        "name": "web",
                        "namespace": "\(namespace ?? "vibekube-demo")",
                        "uid": "web-deploy-uid",
                        "resourceVersion": "20"
                      },
                      "spec": {
                        "replicas": 2
                      },
                      "status": {
                        "readyReplicas": 2,
                        "replicas": 2
                      }
                    }
                  ]
                }
                """.utf8
            )
        )
    }

    func watchResources(
        contextName: String,
        kubeconfig: Kubeconfig,
        resource: KubernetesDiscoveredResource,
        namespace: String?,
        resourceVersion: String?
    ) -> AsyncThrowingStream<KubernetesWatchEvent<KubernetesUnstructuredResource>, Error> {
        AsyncThrowingStream { continuation in
            #expect(resource.name == "deployments")
            #expect(resourceVersion == "20")

            do {
                let deployment = try JSONDecoder().decode(
                    KubernetesUnstructuredResource.self,
                    from: Data(
                        """
                        {
                          "apiVersion": "apps/v1",
                          "kind": "Deployment",
                          "metadata": {
                            "name": "api",
                            "namespace": "\(namespace ?? "vibekube-demo")",
                            "uid": "api-deploy-uid",
                            "resourceVersion": "21"
                          },
                          "spec": {
                            "replicas": 1
                          },
                          "status": {
                            "readyReplicas": 1,
                            "replicas": 1
                          }
                        }
                        """.utf8
                    )
                )
                continuation.yield(
                    KubernetesWatchEvent(
                        type: .added,
                        object: deployment
                    )
                )
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }
}

private final class ExpiringWatchResourceListService: KubernetesResourceListServicing {
    private let lock = NSLock()
    private var listCallCount = 0
    private var watchedVersions: [String] = []

    func listResources(
        contextName: String,
        kubeconfig: Kubeconfig,
        resource: KubernetesDiscoveredResource,
        namespace: String?
    ) async throws -> KubernetesUnstructuredResourceList {
        let callCount = incrementListCallCount()
        let resourceVersion = callCount == 1 ? "10" : "20"
        let podName = callCount == 1 ? "web-0" : "relisted-0"

        return try JSONDecoder().decode(
            KubernetesUnstructuredResourceList.self,
            from: Data(
                """
                {
                  "metadata": {
                    "resourceVersion": "\(resourceVersion)"
                  },
                  "items": [
                    {
                      "apiVersion": "v1",
                      "kind": "Pod",
                      "metadata": {
                        "name": "\(podName)",
                        "namespace": "\(namespace ?? "vibekube-demo")",
                        "uid": "\(podName)-uid",
                        "resourceVersion": "\(resourceVersion)"
                      },
                      "status": {
                        "phase": "Running"
                      }
                    }
                  ]
                }
                """.utf8
            )
        )
    }

    func watchResources(
        contextName: String,
        kubeconfig: Kubeconfig,
        resource: KubernetesDiscoveredResource,
        namespace: String?,
        resourceVersion: String?
    ) -> AsyncThrowingStream<KubernetesWatchEvent<KubernetesUnstructuredResource>, Error> {
        let watchedVersion = resourceVersion ?? "-"
        appendWatchedResourceVersion(watchedVersion)

        return AsyncThrowingStream { continuation in
            if watchedVersion == "10" {
                continuation.yield(
                    KubernetesWatchEvent(
                        type: .error,
                        object: nil,
                        status: KubernetesStatus(
                            kind: "Status",
                            apiVersion: "v1",
                            status: "Failure",
                            message: "too old resource version",
                            reason: "Gone",
                            code: 410
                        )
                    )
                )
                continuation.finish()
                return
            }

            do {
                let pod = try JSONDecoder().decode(
                    KubernetesUnstructuredResource.self,
                    from: Data(
                        """
                        {
                          "apiVersion": "v1",
                          "kind": "Pod",
                          "metadata": {
                            "name": "after-relist",
                            "namespace": "\(namespace ?? "vibekube-demo")",
                            "uid": "after-relist-uid",
                            "resourceVersion": "21"
                          },
                          "status": {
                            "phase": "Running"
                          }
                        }
                        """.utf8
                    )
                )
                continuation.yield(
                    KubernetesWatchEvent(
                        type: .added,
                        object: pod
                    )
                )
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }

    func watchedResourceVersions() -> [String] {
        lock.withLock {
            watchedVersions
        }
    }

    private func incrementListCallCount() -> Int {
        lock.withLock {
            listCallCount += 1
            return listCallCount
        }
    }

    private func appendWatchedResourceVersion(_ resourceVersion: String) {
        lock.withLock {
            watchedVersions.append(resourceVersion)
        }
    }
}

private final class TransientFailingWatchResourceListService: KubernetesResourceListServicing {
    private let lock = NSLock()
    private var watchCalls = 0

    func listResources(
        contextName: String,
        kubeconfig: Kubeconfig,
        resource: KubernetesDiscoveredResource,
        namespace: String?
    ) async throws -> KubernetesUnstructuredResourceList {
        try JSONDecoder().decode(
            KubernetesUnstructuredResourceList.self,
            from: Data(
                """
                {
                  "metadata": {
                    "resourceVersion": "10"
                  },
                  "items": [
                    {
                      "apiVersion": "v1",
                      "kind": "Pod",
                      "metadata": {
                        "name": "web-0",
                        "namespace": "\(namespace ?? "vibekube-demo")",
                        "uid": "web-uid",
                        "resourceVersion": "10"
                      },
                      "status": {
                        "phase": "Running"
                      }
                    }
                  ]
                }
                """.utf8
            )
        )
    }

    func watchResources(
        contextName: String,
        kubeconfig: Kubeconfig,
        resource: KubernetesDiscoveredResource,
        namespace: String?,
        resourceVersion: String?
    ) -> AsyncThrowingStream<KubernetesWatchEvent<KubernetesUnstructuredResource>, Error> {
        incrementWatchCallCount()
        return AsyncThrowingStream { continuation in
            continuation.finish(throwing: KubernetesClientError.unavailable("The request timed out."))
        }
    }

    func watchCallCount() -> Int {
        lock.withLock {
            watchCalls
        }
    }

    private func incrementWatchCallCount() {
        lock.withLock {
            watchCalls += 1
        }
    }
}

private struct ModifyingPodResourceListService: KubernetesResourceListServicing {
    func listResources(
        contextName: String,
        kubeconfig: Kubeconfig,
        resource: KubernetesDiscoveredResource,
        namespace: String?
    ) async throws -> KubernetesUnstructuredResourceList {
        try JSONDecoder().decode(
            KubernetesUnstructuredResourceList.self,
            from: Data(
                """
                {
                  "metadata": {
                    "resourceVersion": "10"
                  },
                  "items": [
                    {
                      "apiVersion": "v1",
                      "kind": "Pod",
                      "metadata": {
                        "name": "web-0",
                        "namespace": "\(namespace ?? "vibekube-demo")",
                        "uid": "web-uid",
                        "resourceVersion": "10"
                      },
                      "status": {
                        "phase": "Running"
                      }
                    }
                  ]
                }
                """.utf8
            )
        )
    }

    func watchResources(
        contextName: String,
        kubeconfig: Kubeconfig,
        resource: KubernetesDiscoveredResource,
        namespace: String?,
        resourceVersion: String?
    ) -> AsyncThrowingStream<KubernetesWatchEvent<KubernetesUnstructuredResource>, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try await Task.sleep(nanoseconds: 100_000_000)
                    let pod = try JSONDecoder().decode(
                        KubernetesUnstructuredResource.self,
                        from: Data(
                            """
                            {
                              "apiVersion": "v1",
                              "kind": "Pod",
                              "metadata": {
                                "name": "web-0",
                                "namespace": "\(namespace ?? "vibekube-demo")",
                                "uid": "web-uid",
                                "resourceVersion": "11"
                              },
                              "status": {
                                "phase": "Running"
                              }
                            }
                            """.utf8
                        )
                    )
                    continuation.yield(
                        KubernetesWatchEvent(
                            type: .modified,
                            object: pod
                        )
                    )
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

private struct ModifyingDeploymentResourceListService: KubernetesResourceListServicing {
    func listResources(
        contextName: String,
        kubeconfig: Kubeconfig,
        resource: KubernetesDiscoveredResource,
        namespace: String?
    ) async throws -> KubernetesUnstructuredResourceList {
        #expect(resource.name == "deployments")
        return try JSONDecoder().decode(
            KubernetesUnstructuredResourceList.self,
            from: Data(
                """
                {
                  "metadata": {
                    "resourceVersion": "20"
                  },
                  "items": [
                    {
                      "apiVersion": "apps/v1",
                      "kind": "Deployment",
                      "metadata": {
                        "name": "web",
                        "namespace": "\(namespace ?? "vibekube-demo")",
                        "uid": "web-deploy-uid",
                        "resourceVersion": "20"
                      },
                      "spec": {
                        "replicas": 2
                      },
                      "status": {
                        "readyReplicas": 2,
                        "replicas": 2
                      }
                    }
                  ]
                }
                """.utf8
            )
        )
    }

    func watchResources(
        contextName: String,
        kubeconfig: Kubeconfig,
        resource: KubernetesDiscoveredResource,
        namespace: String?,
        resourceVersion: String?
    ) -> AsyncThrowingStream<KubernetesWatchEvent<KubernetesUnstructuredResource>, Error> {
        AsyncThrowingStream { continuation in
            #expect(resource.name == "deployments")
            #expect(resourceVersion == "20")

            Task {
                do {
                    try await Task.sleep(nanoseconds: 100_000_000)
                    let deployment = try JSONDecoder().decode(
                        KubernetesUnstructuredResource.self,
                        from: Data(
                            """
                            {
                              "apiVersion": "apps/v1",
                              "kind": "Deployment",
                              "metadata": {
                                "name": "web",
                                "namespace": "\(namespace ?? "vibekube-demo")",
                                "uid": "web-deploy-uid",
                                "resourceVersion": "21"
                              },
                              "spec": {
                                "replicas": 3
                              },
                              "status": {
                                "readyReplicas": 3,
                                "replicas": 3
                              }
                            }
                            """.utf8
                        )
                    )
                    continuation.yield(
                        KubernetesWatchEvent(
                            type: .modified,
                            object: deployment
                        )
                    )
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

private final class DetailWatchingPodResourceListService: KubernetesResourceListServicing, KubernetesResourceDetailWatchServicing {
    private let lock = NSLock()
    private var watchedNames: [String] = []

    func listResources(
        contextName: String,
        kubeconfig: Kubeconfig,
        resource: KubernetesDiscoveredResource,
        namespace: String?
    ) async throws -> KubernetesUnstructuredResourceList {
        #expect(resource.name == "pods")
        return try JSONDecoder().decode(
            KubernetesUnstructuredResourceList.self,
            from: Data(
                """
                {
                  "metadata": {
                    "resourceVersion": "30"
                  },
                  "items": [
                    {
                      "apiVersion": "v1",
                      "kind": "Pod",
                      "metadata": {
                        "name": "web-0",
                        "namespace": "\(namespace ?? "vibekube-demo")",
                        "uid": "web-uid",
                        "resourceVersion": "30"
                      },
                      "status": {
                        "phase": "Running"
                      }
                    }
                  ]
                }
                """.utf8
            )
        )
    }

    func watchResource(
        contextName: String,
        kubeconfig: Kubeconfig,
        resource: KubernetesDiscoveredResource,
        namespace: String?,
        name: String,
        resourceVersion: String?
    ) -> AsyncThrowingStream<KubernetesWatchEvent<KubernetesUnstructuredResource>, Error> {
        appendWatchedName(name)

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    try await Task.sleep(nanoseconds: 100_000_000)
                    let pod = try JSONDecoder().decode(
                        KubernetesUnstructuredResource.self,
                        from: Data(
                            """
                            {
                              "apiVersion": "v1",
                              "kind": "Pod",
                              "metadata": {
                                "name": "web-0",
                                "namespace": "\(namespace ?? "vibekube-demo")",
                                "uid": "web-uid",
                                "resourceVersion": "31"
                              },
                              "status": {
                                "phase": "Running"
                              }
                            }
                            """.utf8
                        )
                    )
                    continuation.yield(
                        KubernetesWatchEvent(
                            type: .modified,
                            object: pod
                        )
                    )
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func detailWatchNames() -> [String] {
        lock.withLock {
            watchedNames
        }
    }

    private func appendWatchedName(_ name: String) {
        lock.withLock {
            watchedNames.append(name)
        }
    }
}

private struct BurstingPodResourceListService: KubernetesResourceListServicing {
    func listResources(
        contextName: String,
        kubeconfig: Kubeconfig,
        resource: KubernetesDiscoveredResource,
        namespace: String?
    ) async throws -> KubernetesUnstructuredResourceList {
        #expect(resource.name == "pods")
        return try JSONDecoder().decode(
            KubernetesUnstructuredResourceList.self,
            from: Data(
                """
                {
                  "metadata": {
                    "resourceVersion": "10"
                  },
                  "items": [
                    {
                      "apiVersion": "v1",
                      "kind": "Pod",
                      "metadata": {
                        "name": "web-0",
                        "namespace": "\(namespace ?? "vibekube-demo")",
                        "uid": "web-uid",
                        "resourceVersion": "10"
                      },
                      "status": {
                        "phase": "Running"
                      }
                    }
                  ]
                }
                """.utf8
            )
        )
    }

    func watchResources(
        contextName: String,
        kubeconfig: Kubeconfig,
        resource: KubernetesDiscoveredResource,
        namespace: String?,
        resourceVersion: String?
    ) -> AsyncThrowingStream<KubernetesWatchEvent<KubernetesUnstructuredResource>, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try await Task.sleep(nanoseconds: 100_000_000)
                    for version in ["11", "12"] {
                        let pod = try JSONDecoder().decode(
                            KubernetesUnstructuredResource.self,
                            from: Data(
                                """
                                {
                                  "apiVersion": "v1",
                                  "kind": "Pod",
                                  "metadata": {
                                    "name": "web-0",
                                    "namespace": "\(namespace ?? "vibekube-demo")",
                                    "uid": "web-uid",
                                    "resourceVersion": "\(version)"
                                  },
                                  "status": {
                                    "phase": "Running"
                                  }
                                }
                                """.utf8
                            )
                        )
                        continuation.yield(
                            KubernetesWatchEvent(
                                type: .modified,
                                object: pod
                            )
                        )
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

private actor VersionedPodDetailService: KubernetesResourceDetailServicing {
    private var calls = 0

    func resourceDetail(
        contextName: String,
        kubeconfig: Kubeconfig,
        resource: KubernetesDiscoveredResource,
        namespace: String?,
        name: String
    ) async throws -> KubernetesResourceDetail {
        calls += 1
        let resourceVersion = calls == 1 ? "10" : "11"
        return try JSONDecoder().decode(
            KubernetesResourceDetail.self,
            from: Data(
                """
                {
                  "apiVersion": "\(resource.groupVersion)",
                  "kind": "\(resource.kind)",
                  "metadata": {
                    "name": "\(name)",
                    "namespace": "\(namespace ?? "vibekube-demo")",
                    "uid": "web-uid",
                    "resourceVersion": "\(resourceVersion)"
                  },
                  "status": {
                    "phase": "Running"
                  }
                }
                """.utf8
            )
        )
    }

    func callCount() -> Int {
        calls
    }
}

private actor CoalescedPodDetailService: KubernetesResourceDetailServicing {
    private var calls = 0

    func resourceDetail(
        contextName: String,
        kubeconfig: Kubeconfig,
        resource: KubernetesDiscoveredResource,
        namespace: String?,
        name: String
    ) async throws -> KubernetesResourceDetail {
        calls += 1
        let resourceVersion = calls == 1 ? "10" : "12"
        return try JSONDecoder().decode(
            KubernetesResourceDetail.self,
            from: Data(
                """
                {
                  "apiVersion": "\(resource.groupVersion)",
                  "kind": "\(resource.kind)",
                  "metadata": {
                    "name": "\(name)",
                    "namespace": "\(namespace ?? "vibekube-demo")",
                    "uid": "web-uid",
                    "resourceVersion": "\(resourceVersion)"
                  },
                  "status": {
                    "phase": "Running"
                  }
                }
                """.utf8
            )
        )
    }

    func callCount() -> Int {
        calls
    }
}

private actor DetailWatchPodDetailService: KubernetesResourceDetailServicing {
    private var calls = 0

    func resourceDetail(
        contextName: String,
        kubeconfig: Kubeconfig,
        resource: KubernetesDiscoveredResource,
        namespace: String?,
        name: String
    ) async throws -> KubernetesResourceDetail {
        calls += 1
        let resourceVersion = calls == 1 ? "30" : "31"
        return try JSONDecoder().decode(
            KubernetesResourceDetail.self,
            from: Data(
                """
                {
                  "apiVersion": "\(resource.groupVersion)",
                  "kind": "\(resource.kind)",
                  "metadata": {
                    "name": "\(name)",
                    "namespace": "\(namespace ?? "vibekube-demo")",
                    "uid": "web-uid",
                    "resourceVersion": "\(resourceVersion)"
                  },
                  "status": {
                    "phase": "Running"
                  }
                }
                """.utf8
            )
        )
    }

    func callCount() -> Int {
        calls
    }
}

private actor VersionedDeploymentDetailService: KubernetesResourceDetailServicing {
    private var calls = 0

    func resourceDetail(
        contextName: String,
        kubeconfig: Kubeconfig,
        resource: KubernetesDiscoveredResource,
        namespace: String?,
        name: String
    ) async throws -> KubernetesResourceDetail {
        calls += 1
        let resourceVersion = calls == 1 ? "20" : "21"
        return try JSONDecoder().decode(
            KubernetesResourceDetail.self,
            from: Data(
                """
                {
                  "apiVersion": "\(resource.groupVersion)",
                  "kind": "\(resource.kind)",
                  "metadata": {
                    "name": "\(name)",
                    "namespace": "\(namespace ?? "vibekube-demo")",
                    "uid": "web-deploy-uid",
                    "resourceVersion": "\(resourceVersion)"
                  },
                  "spec": {
                    "replicas": \(resourceVersion == "20" ? 2 : 3)
                  },
                  "status": {
                    "readyReplicas": \(resourceVersion == "20" ? 2 : 3),
                    "replicas": \(resourceVersion == "20" ? 2 : 3)
                  }
                }
                """.utf8
            )
        )
    }

    func callCount() -> Int {
        calls
    }
}

private struct MissingKindPodResourceListService: KubernetesResourceListServicing {
    func listResources(
        contextName: String,
        kubeconfig: Kubeconfig,
        resource: KubernetesDiscoveredResource,
        namespace: String?
    ) async throws -> KubernetesUnstructuredResourceList {
        try JSONDecoder().decode(
            KubernetesUnstructuredResourceList.self,
            from: Data(
                """
                {
                  "items": [
                    {
                      "metadata": {
                        "name": "web-0",
                        "namespace": "\(namespace ?? "vibekube-demo")"
                      },
                      "status": {
                        "phase": "Running"
                      }
                    }
                  ]
                }
                """.utf8
            )
        )
    }
}

private struct SucceedingResourceDetailService: KubernetesResourceDetailServicing {
    func resourceDetail(
        contextName: String,
        kubeconfig: Kubeconfig,
        resource: KubernetesDiscoveredResource,
        namespace: String?,
        name: String
    ) async throws -> KubernetesResourceDetail {
        if resource.name == "configmaps" {
            return try JSONDecoder().decode(
                KubernetesResourceDetail.self,
                from: Data(
                    """
                    {
                      "apiVersion": "v1",
                      "kind": "ConfigMap",
                      "metadata": {
                        "name": "\(name)",
                        "namespace": "\(namespace ?? "vibekube-demo")"
                      },
                      "data": {
                        "APP_MODE": "demo",
                        "PUBLIC_GREETING": "hello-from-configmap"
                      }
                    }
                    """.utf8
                )
            )
        }

        if resource.name == "secrets" {
            return try JSONDecoder().decode(
                KubernetesResourceDetail.self,
                from: Data(
                    """
                    {
                      "apiVersion": "v1",
                      "kind": "Secret",
                      "metadata": {
                        "name": "\(name)",
                        "namespace": "\(namespace ?? "vibekube-demo")"
                      },
                      "data": {
                        "API_TOKEN": "dGVzdC10b2tlbg==",
                        "db-password": "dGVzdC1wYXNzd29yZA=="
                      },
                      "type": "Opaque"
                    }
                    """.utf8
                )
            )
        }

        let namespaceLine = namespace.map { #""namespace": "\#($0)","# } ?? ""
        let specLine = resource.name == "pods" ?
            """
            ,
                  "spec": {
                    "containers": [
                      {
                        "name": "web",
                        "image": "nginx:1.27-alpine",
                        "env": [
                          {
                            "name": "PUBLIC_GREETING",
                            "valueFrom": {
                              "configMapKeyRef": {
                                "name": "web-config",
                                "key": "PUBLIC_GREETING"
                              }
                            }
                          }
                        ],
                        "envFrom": [
                          {
                            "configMapRef": {
                              "name": "web-config"
                            }
                          },
                          {
                            "prefix": "EXTRA_",
                            "secretRef": {
                              "name": "web-secrets"
                            }
                          }
                        ]
                      }
                    ]
                  }
            """ : ""
        return try JSONDecoder().decode(
            KubernetesResourceDetail.self,
            from: Data(
                """
                {
                  "apiVersion": "\(resource.groupVersion)",
                  "kind": "\(resource.kind)",
                  "metadata": {
                    "name": "\(name)",
                    \(namespaceLine)
                    "uid": "pod-uid",
                    "labels": {
                      "app": "web"
                    }
                  },
                  "status": {
                    "phase": "Running"
                  }
                  \(specLine)
                }
                """.utf8
            )
        )
    }
}

private struct SucceedingResourceEventService: KubernetesResourceEventServicing {
    func resourceEvents(
        contextName: String,
        kubeconfig: Kubeconfig,
        eventsResource: KubernetesDiscoveredResource,
        namespace: String?,
        involvedKind: String,
        involvedName: String,
        involvedUID: String?
    ) async throws -> KubernetesResourceEventList {
        #expect(eventsResource.name == "events")
        #expect(namespace == "vibekube-demo")
        #expect(involvedKind == "Pod")
        #expect(involvedName == "web-0")
        #expect(involvedUID == "pod-uid")

        return try JSONDecoder().decode(
            KubernetesResourceEventList.self,
            from: Data(
                """
                {
                  "items": [
                    {
                      "apiVersion": "v1",
                      "kind": "Event",
                      "metadata": {
                        "name": "web-0.pulled",
                        "namespace": "vibekube-demo",
                        "uid": "event-pulled",
                        "creationTimestamp": "2026-06-15T10:01:00Z"
                      },
                      "type": "Normal",
                      "reason": "Pulled",
                      "message": "Container image is present.",
                      "count": 1,
                      "lastTimestamp": "2026-06-15T10:01:00Z",
                      "involvedObject": {
                        "kind": "Pod",
                        "name": "web-0",
                        "namespace": "vibekube-demo",
                        "uid": "pod-uid"
                      },
                      "source": {
                        "component": "kubelet"
                      }
                    }
                  ]
                }
                """.utf8
            )
        )
    }
}

private struct SucceedingLogService: KubernetesLogServicing {
    func podLogs(
        contextName: String,
        kubeconfig: Kubeconfig,
        namespace: String,
        podName: String,
        options: KubernetesPodLogOptions
    ) async throws -> String {
        #expect(contextName == "kind-vibekube-dev")
        #expect(namespace == "vibekube-demo")
        #expect(podName == "web-0")
        #expect(options.container == "web")
        #expect(options.tailLines == 200)
        #expect(options.sinceSeconds == nil)
        #expect(options.timestamps == true)
        #expect(options.follow == false)

        return "2026-06-15T10:01:00Z hello from web-0"
    }

    func podLogStream(
        contextName: String,
        kubeconfig: Kubeconfig,
        namespace: String,
        podName: String,
        options: KubernetesPodLogOptions
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            #expect(contextName == "kind-vibekube-dev")
            #expect(namespace == "vibekube-demo")
            #expect(podName == "web-0")
            #expect(options.container == "web")
            #expect(options.follow == true)
            #expect(options.tailLines == 0)
            #expect(options.sinceSeconds == nil)

            continuation.yield("2026-06-15T10:01:01Z still running\n")
            continuation.finish()
        }
    }
}

private struct SinceLogService: KubernetesLogServicing {
    func podLogs(
        contextName: String,
        kubeconfig: Kubeconfig,
        namespace: String,
        podName: String,
        options: KubernetesPodLogOptions
    ) async throws -> String {
        #expect(contextName == "kind-vibekube-dev")
        #expect(namespace == "vibekube-demo")
        #expect(podName == "web-0")
        #expect(options.container == "web")
        #expect(options.tailLines == 1_000)
        #expect(options.sinceSeconds == 900)
        #expect(options.timestamps == true)
        #expect(options.follow == false)

        return "2026-06-15T10:14:00Z recent line"
    }

    func podLogStream(
        contextName: String,
        kubeconfig: Kubeconfig,
        namespace: String,
        podName: String,
        options: KubernetesPodLogOptions
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}

private struct ANSILogService: KubernetesLogServicing {
    func podLogs(
        contextName: String,
        kubeconfig: Kubeconfig,
        namespace: String,
        podName: String,
        options: KubernetesPodLogOptions
    ) async throws -> String {
        "2026-06-15T10:01:00Z \u{001B}[31merror\u{001B}[0m plain \u{001B}[1;32mok\u{001B}[0m"
    }

    func podLogStream(
        contextName: String,
        kubeconfig: Kubeconfig,
        namespace: String,
        podName: String,
        options: KubernetesPodLogOptions
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}

private struct BufferingLogService: KubernetesLogServicing {
    func podLogs(
        contextName: String,
        kubeconfig: Kubeconfig,
        namespace: String,
        podName: String,
        options: KubernetesPodLogOptions
    ) async throws -> String {
        ""
    }

    func podLogStream(
        contextName: String,
        kubeconfig: Kubeconfig,
        namespace: String,
        podName: String,
        options: KubernetesPodLogOptions
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            for index in 1...6 {
                continuation.yield("line \(index)\n")
            }
            continuation.finish()
        }
    }
}

private struct AllPreviousLogService: KubernetesLogServicing {
    func podLogs(
        contextName: String,
        kubeconfig: Kubeconfig,
        namespace: String,
        podName: String,
        options: KubernetesPodLogOptions
    ) async throws -> String {
        #expect(contextName == "kind-vibekube-dev")
        #expect(namespace == "vibekube-demo")
        #expect(podName == "web-0")
        #expect(options.container == "web")
        #expect(options.previous == true)
        #expect(options.tailLines == nil)
        #expect(options.sinceSeconds == nil)
        #expect(options.timestamps == true)
        #expect(options.follow == false)

        return "2026-06-15T10:00:59Z previous crash"
    }

    func podLogStream(
        contextName: String,
        kubeconfig: Kubeconfig,
        namespace: String,
        podName: String,
        options: KubernetesPodLogOptions
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}

private struct FailingConnectionService: KubernetesConnectionServicing {
    func connect(
        contextName: String,
        kubeconfig: Kubeconfig,
        progress: @escaping @Sendable (KubernetesConnectionProgress) async -> Void
    ) async throws -> KubernetesConnectionSnapshot {
        throw KubernetesClientError.unauthorized("Nope")
    }
}

private func kubeconfig() -> Kubeconfig {
    Kubeconfig(
        apiVersion: "v1",
        kind: "Config",
        clusters: [],
        contexts: [],
        users: [],
        currentContext: nil
    )
}

private func dashboardAPIResource(for item: ResourceNavigationItem) -> KubernetesAPIResource {
    let definition: (name: String, kind: String, namespaced: Bool)
    switch item {
    case .nodes:
        definition = ("nodes", "Node", false)
    case .pods:
        definition = ("pods", "Pod", true)
    case .deployments:
        definition = ("deployments", "Deployment", true)
    case .statefulSets:
        definition = ("statefulsets", "StatefulSet", true)
    case .daemonSets:
        definition = ("daemonsets", "DaemonSet", true)
    case .jobs:
        definition = ("jobs", "Job", true)
    case .cronJobs:
        definition = ("cronjobs", "CronJob", true)
    case .persistentVolumes:
        definition = ("persistentvolumes", "PersistentVolume", false)
    case .persistentVolumeClaims:
        definition = ("persistentvolumeclaims", "PersistentVolumeClaim", true)
    case .events:
        definition = ("events", "Event", true)
    default:
        definition = (item.rawValue, item.title, true)
    }

    return KubernetesAPIResource(
        name: definition.name,
        singularName: "",
        namespaced: definition.namespaced,
        kind: definition.kind,
        verbs: ["get", "list"],
        shortNames: nil,
        categories: nil
    )
}
