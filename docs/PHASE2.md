# Phase 2: Kubernetes API Connectivity And Discovery

Status: Review checkpoint.

Goal: connect to the selected cluster, authenticate safely, and discover available Kubernetes APIs.

## Current Progress

- [x] Phase plan exists.
- [x] API client protocol exists.
- [x] TLS/auth from kubeconfig works for CA data/path, bearer token, and client certificate/key data/path.
- [x] Kubernetes exec credential plugins run and resolve into native credentials.
- [x] `/version` request works.
- [x] API discovery works.
- [x] Namespaces load.
- [x] Connection errors are mapped to user-facing states.
- [x] Exec auth is documented as a first-class connection path.

## Checkpoint Notes

- The app now connects to the selected context through a native `URLSession` client and calls `/version`.
- The demo `kind-vibekube-dev` context has been validated through an opt-in integration test using the local kubeconfig.
- Client certificate auth is implemented by importing the PEM certificate/key into a temporary keychain to create a `SecIdentity` for URLSession mTLS. The keychain is deleted when the request delegate is deallocated.
- `SecKeychain` APIs are deprecated but still available on macOS; revisit a cleaner long-term identity strategy during Phase 11 hardening.
- Exec credential plugins now run from kubeconfig, decode `ExecCredential`, and cache returned credentials until expiry.
- Teleport-backed contexts should now invoke `tsh` through the standard exec path and can let `tsh` open browser SSO/MFA. This still needs manual validation on a real corporate Teleport kubeconfig.
- The dashboard now shows connected Kubernetes version plus discovered API group/resource/namespace counts.
- Custom Resources opens a grouped API resource catalog backed by discovery metadata.
- Static resource navigation items now show whether their API resource is namespaced or cluster-scoped after discovery.
- Namespace selection is available in the toolbar once connected, including `All Namespaces`.
- Namespace discovery follows Kubernetes list pagination so large clusters do not silently truncate namespace options.
- Real resource object tables, YAML views, logs, and rich dashboard health stats are still pending.

## Implementation Slices

### 2.1 Client Foundation

- [x] Define `KubernetesAPIClient`.
- [ ] Define `KubernetesRequest`.
- [x] Define Kubernetes client error mapping.
- [x] Define Kubernetes `Status` decoding model.
- [x] Add URL builder for core and grouped APIs.
- [x] Add URL builder for simple API paths.
- [x] Add cancellation support when switching contexts.

### 2.2 TLS And Auth

- [x] Support certificate-authority data.
- [x] Support certificate-authority file paths.
- [x] Support bearer token auth.
- [x] Support client certificate/key auth.
- [x] Support Kubernetes exec credential plugins.
- [x] Support Teleport `tsh` kube credentials via exec auth.
- [x] Represent unsupported auth-provider cases cleanly.
- [x] Represent exec auth as planned with clear UI.
- [x] Ensure secrets are redacted in logs/errors.

Checkpoint: stop before adding any complex auth helper dependency.

### 2.2a Exec Credential Plugins And Teleport

- [x] Resolve exec commands from absolute paths or `PATH`.
- [x] Search common macOS developer paths such as `/opt/homebrew/bin` for GUI-launched app sessions.
- [x] Show kubeconfig `installHint` when an exec command is missing.
- [x] Run the configured `user.exec.command` with args and env.
- [x] Pass `KUBERNETES_EXEC_INFO` when `provideClusterInfo` is true.
- [x] Respect `interactiveMode` (`Never`, `IfAvailable`, `Always`).
- [x] Decode `ExecCredential` v1 and v1beta1 JSON.
- [x] Apply returned bearer token credentials.
- [x] Apply returned client certificate/key credentials if feasible.
- [x] Cache exec credentials until `expirationTimestamp`.
- [x] Re-run exec auth on expiry or `401 Unauthorized`.
- [x] Let Teleport `tsh` open browser SSO/MFA when credentials are missing or expired.
- [ ] Show signing-in/cancel/error UI for exec-auth flows.
- [x] Redact exec stdout/stderr and decoded credential material.

### 2.3 Discovery APIs

- [x] Implement `/version`.
- [x] Implement `/api`.
- [x] Implement `/apis`.
- [x] Implement resource discovery for each group/version.
- [x] Persist discovered resource metadata in memory.
- [x] Detect namespaced vs cluster-scoped resources.
- [x] Detect verbs available from discovery data.

### 2.4 Namespace Loading

- [x] Load namespaces.
- [x] Display namespace selector in toolbar.
- [x] Support `All namespaces`.
- [x] Persist selected namespace per context in memory.
- [x] Handle permission-denied namespace list.

### 2.5 UI Connection Flow

- [x] Connect on selected context.
- [x] Show connecting state.
- [x] Show connected state with cluster version.
- [x] Show unauthorized state.
- [x] Show unavailable state.
- [x] Show certificate error state.
- [x] Add retry action.
- [x] Disconnect/cancel on context switch.

### 2.6 Tests

- [x] Request URL unit tests.
- [x] Exec credential decoding, process runner, cache, and config tests.
- [ ] Kubernetes `Status` decoding tests.
- [x] Discovery decoding and navigation mapping tests.
- [ ] Mock server tests for `/version` and discovery.
- [x] Integration test against kind where practical.

## Acceptance Criteria

- [x] Selecting the demo context connects successfully.
- [x] Toolbar shows connected status and dashboard shows Kubernetes version.
- [x] API groups/resources are discovered.
- [x] Namespaces are available in the selector.
- [x] Bad auth, offline server, and certificate failures are understandable.
- [ ] Teleport-backed kubeconfigs can trigger `tsh` login/browser auth through exec credentials. Implemented; awaiting manual validation on a corporate Teleport kubeconfig.

## Validation Results

- [x] `xcodebuild -project vibekube.xcodeproj -scheme vibekube -destination 'platform=macOS' test -only-testing:vibekubeTests`
- [x] `VIBEKUBE_RUN_KIND_INTEGRATION=1 xcodebuild -project vibekube.xcodeproj -scheme vibekube -destination 'platform=macOS' test -only-testing:vibekubeTests/KubernetesClientIntegrationTests/connectsToCurrentKubeconfigWhenEnabled`
- [x] `xcodebuild -project vibekube.xcodeproj -scheme vibekube -destination 'platform=macOS' test -only-testing:vibekubeUITests/vibekubeUITests/testShellLaunches`
- [ ] Manual app review by user.

## Validation Commands

```sh
dev/k8s/scripts/start.sh
kubectl version
kubectl api-resources
xcodebuild -project vibekube.xcodeproj -scheme vibekube -destination 'platform=macOS' test
VIBEKUBE_RUN_KIND_INTEGRATION=1 xcodebuild -project vibekube.xcodeproj -scheme vibekube -destination 'platform=macOS' test -only-testing:vibekubeTests/KubernetesClientIntegrationTests/connectsToCurrentKubeconfigWhenEnabled
xcodebuild -project vibekube.xcodeproj -scheme vibekube -destination 'platform=macOS' test -only-testing:vibekubeUITests/vibekubeUITests/testShellLaunches
```
