# Vibekube Privacy

Vibekube is a local-first Kubernetes client. It does not send cluster data, kubeconfig data, diagnostics, logs, or AI context to any Vibekube server.

## Data Vibekube Reads

- kubeconfig files discovered from the normal Kubernetes environment and default kubeconfig path
- Kubernetes API responses from the selected cluster
- Kubernetes Pod logs requested by the user
- local user preferences stored through macOS app defaults
- optional AI provider settings entered by the user

Vibekube uses kubeconfig credentials as provided by Kubernetes tooling. For exec auth, such as Teleport `tsh`, Vibekube runs the configured exec plugin and uses the returned Kubernetes credential in memory.

## Data Vibekube Stores

Vibekube stores local preferences such as the selected context, selected route, namespace selection, and diagnostics settings.

These preferences are stored in macOS app defaults. The current preference set includes selected context/route/resource, namespace selections, diagnostics settings, kubeconfig path override, log buffer size, Secret reveal confirmation behavior, default namespace behavior, resource watch behavior, table density, appearance, external terminal preference, and non-secret AI provider settings such as provider shape, base URL, and selected model. Vibekube does not store kubeconfig contents, bearer tokens, client private keys, exec-auth returned credentials, decoded Secret values, Pod log text, full resource YAML, AI API keys, or AI custom header values in app defaults.

AI API keys and custom AI provider header values are stored in macOS Keychain when the user saves them in Settings. Clearing AI secrets or resetting local preferences deletes Vibekube's stored AI provider secret item from Keychain.

Client certificate/key material may be imported into a temporary keychain to create a `URLSession` client identity for mTLS, but that keychain is deleted when the session ends and is not a persistent credential store.

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

Diagnostics metadata and diagnostics messages redact values that look like credentials, certificates, private keys, bearer tokens, passwords, or secrets. User-visible Kubernetes API and exec-auth error messages pass through the same free-form redaction before display. Resource names, namespaces, pod names, container names, Secret names, and Secret keys are logged as hashes where they are needed for debugging.

## Network Policy

Vibekube connects to Kubernetes API servers from the user kubeconfig. It does not contain telemetry, crash reporting, or automatic update checks.

If AI provider settings are configured, Vibekube may contact the selected AI provider only when the user explicitly fetches models or tests availability. These settings calls send the provider API key and optional custom headers to the configured provider URL, but do not send Kubernetes resource data, logs, diagnostics, or kubeconfig data. Kubernetes context sharing for AI answers remains disabled until a separate redaction and consent path is implemented.

Vibekube does not automatically send crash reports or diagnostics. macOS may create system crash reports outside Vibekube's control, but Vibekube does not upload them. Any diagnostics export is local, redacted, and created only when the user explicitly uses the export action.

The current direct-distribution build is signed and notarized with hardened runtime, but App Sandbox remains disabled. The app needs normal user-file access to kubeconfig files and referenced certificate/key paths, outbound Kubernetes API network access, kubeconfig exec credential plugins, external-terminal `kubectl exec`, and `kubectl port-forward`. A sandboxed build would require a separate helper/file-access design and is not the current release target.

AI features must not send cluster data outside the machine without a separate user-controlled path.
