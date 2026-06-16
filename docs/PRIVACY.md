# Vibekube Privacy

Vibekube is a local-first Kubernetes client. It does not send cluster data, kubeconfig data, diagnostics, logs, or AI context to any Vibekube server.

## Data Vibekube Reads

- kubeconfig files discovered from the normal Kubernetes environment and default kubeconfig path
- Kubernetes API responses from the selected cluster
- Kubernetes Pod logs requested by the user
- local user preferences stored through macOS app defaults

Vibekube uses kubeconfig credentials as provided by Kubernetes tooling. For exec auth, such as Teleport `tsh`, Vibekube runs the configured exec plugin and uses the returned Kubernetes credential in memory.

## Data Vibekube Stores

Vibekube stores local preferences such as the selected context, selected route, namespace selection, and diagnostics settings.

Optional diagnostics file logging is disabled by default. When enabled, diagnostics are written as redacted JSONL files to:

```text
~/Library/Logs/Vibekube
```

Diagnostics are retained for the configured number of days, currently 1-30 days, with a 50 MB total cap.

## Data Vibekube Does Not Store

- kubeconfig file contents
- bearer tokens
- client private keys
- decoded Secret values
- Pod log text from normal log viewing
- full resource YAML from normal browsing

The diagnostics export is generated on demand from an in-memory ring buffer plus app state. It is copied only when the user explicitly uses the export action.

## Redaction Policy

Diagnostics hash cluster/context identifiers by default. Cluster names are included only if the user enables that setting.

Diagnostics metadata redacts values that look like credentials, certificates, private keys, bearer tokens, passwords, or secrets. Resource names, namespaces, pod names, container names, Secret names, and Secret keys are logged as hashes where they are needed for debugging.

## Network Policy

Vibekube connects to Kubernetes API servers from the user kubeconfig. It does not currently contain telemetry, crash reporting, automatic update checks, or AI network requests.

If AI features are added later, they must be explicitly documented and must not send cluster data outside the machine without a separate user-controlled path.
