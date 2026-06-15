import Foundation

struct KubeconfigLoadResult {
    var kubeconfig: Kubeconfig
    var requestedPaths: [KubeconfigSource]
    var existingSources: [KubeconfigSource]
    var issues: [String]

    var hasExistingSource: Bool {
        !existingSources.isEmpty
    }

    var issueSummary: String? {
        guard !issues.isEmpty else { return nil }
        return issues.joined(separator: "\n")
    }
}

struct KubeconfigLoader {
    private var environment: [String: String]
    private var fileManager: FileManager

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) {
        self.environment = environment
        self.fileManager = fileManager
    }

    func load() -> KubeconfigLoadResult {
        let sources = kubeconfigSources()
        var existingSources: [KubeconfigSource] = []
        var loadedConfigs: [Kubeconfig] = []
        var issues: [String] = []

        for source in sources {
            guard fileManager.fileExists(atPath: source.url.path) else {
                continue
            }

            existingSources.append(source)

            do {
                let rawKubeconfig = try String(contentsOf: source.url, encoding: .utf8)
                let parsed = try KubeconfigParser(source: source).parse(rawKubeconfig)
                loadedConfigs.append(parsed)
            } catch {
                issues.append("\(source.displayPath): \(error.localizedDescription)")
            }
        }

        return KubeconfigLoadResult(
            kubeconfig: merge(loadedConfigs),
            requestedPaths: sources,
            existingSources: existingSources,
            issues: issues
        )
    }

    func kubeconfigSources() -> [KubeconfigSource] {
        if let kubeconfig = environment["KUBECONFIG"], !kubeconfig.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return kubeconfig
                .split(separator: ":", omittingEmptySubsequences: true)
                .map { URL(fileURLWithPath: String($0), relativeTo: nil).standardizedFileURL }
                .map(KubeconfigSource.init(url:))
        }

        return [
            KubeconfigSource(url: fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".kube/config"))
        ]
    }

    private func merge(_ configs: [Kubeconfig]) -> Kubeconfig {
        var merged = Kubeconfig.empty
        var clusterNames = Set<String>()
        var contextNames = Set<String>()
        var userNames = Set<String>()

        for config in configs {
            if merged.apiVersion == nil {
                merged.apiVersion = config.apiVersion
            }
            if merged.kind == nil {
                merged.kind = config.kind
            }
            if merged.currentContext == nil || merged.currentContext?.isEmpty == true {
                merged.currentContext = config.currentContext
            }

            for cluster in config.clusters where !clusterNames.contains(cluster.name) {
                clusterNames.insert(cluster.name)
                merged.clusters.append(cluster)
            }

            for context in config.contexts where !contextNames.contains(context.name) {
                contextNames.insert(context.name)
                merged.contexts.append(context)
            }

            for user in config.users where !userNames.contains(user.name) {
                userNames.insert(user.name)
                merged.users.append(user)
            }
        }

        return merged
    }
}
