# Phase 2: Kubernetes API Connectivity And Discovery

Status: Review checkpoint.

Goal: connect to the selected cluster, authenticate safely, and discover available Kubernetes APIs.

## Current Progress

- [x] Phase plan exists.
- [x] API client protocol exists.
- [x] TLS/auth from kubeconfig works for CA data/path, bearer token, and client certificate/key data/path.
- [x] `/version` request works.
- [ ] API discovery works.
- [ ] Namespaces load.
- [x] Connection errors are mapped to user-facing states.
- [x] Exec auth is documented as a first-class connection path.

## Checkpoint Notes

- The app now connects to the selected context through a native `URLSession` client and calls `/version`.
- The demo `kind-vibekube-dev` context has been validated through an opt-in integration test using the local kubeconfig.
- Client certificate auth is implemented by importing the PEM certificate/key into a temporary keychain to create a `SecIdentity` for URLSession mTLS. The keychain is deleted when the request delegate is deallocated.
- `SecKeychain` APIs are deprecated but still available on macOS; revisit a cleaner long-term identity strategy during Phase 11 hardening.
- Exec credential plugins, including Teleport `tsh`, remain parsed and visible but are intentionally not executed yet. That is the next meaningful auth slice.
- The dashboard shows the connected Kubernetes version; discovery, stats, namespaces, and resources are still pending.

## Implementation Slices

### 2.1 Client Foundation

- [x] Define `KubernetesAPIClient`.
- [ ] Define `KubernetesRequest`.
- [x] Define Kubernetes client error mapping.
- [x] Define Kubernetes `Status` decoding model.
- [ ] Add URL builder for core and grouped APIs.
- [x] Add URL builder for simple API paths.
- [x] Add cancellation support when switching contexts.

### 2.2 TLS And Auth

- [x] Support certificate-authority data.
- [x] Support certificate-authority file paths.
- [x] Support bearer token auth.
- [x] Support client certificate/key auth.
- [ ] Support Kubernetes exec credential plugins.
- [ ] Support Teleport `tsh` kube credentials via exec auth.
- [x] Represent unsupported auth-provider cases cleanly.
- [x] Represent exec auth as planned with clear UI.
- [x] Ensure secrets are redacted in logs/errors.

Checkpoint: stop before adding any complex auth helper dependency.

### 2.2a Exec Credential Plugins And Teleport

- [ ] Resolve exec commands from absolute paths or `PATH`.
- [ ] Show kubeconfig `installHint` when an exec command is missing.
- [ ] Run the configured `user.exec.command` with args and env.
- [ ] Pass `KUBERNETES_EXEC_INFO` when `provideClusterInfo` is true.
- [ ] Respect `interactiveMode` (`Never`, `IfAvailable`, `Always`).
- [ ] Decode `ExecCredential` v1 and v1beta1 JSON.
- [ ] Apply returned bearer token credentials.
- [ ] Apply returned client certificate/key credentials if feasible.
- [ ] Cache exec credentials until `expirationTimestamp`.
- [ ] Re-run exec auth on expiry or `401 Unauthorized`.
- [ ] Let Teleport `tsh` open browser SSO/MFA when credentials are missing or expired.
- [ ] Show signing-in/cancel/error UI for exec-auth flows.
- [ ] Redact exec stdout/stderr and decoded credential material.

### 2.3 Discovery APIs

- [x] Implement `/version`.
- [ ] Implement `/api`.
- [ ] Implement `/apis`.
- [ ] Implement resource discovery for each group/version.
- [ ] Persist discovered resource metadata in memory.
- [ ] Detect namespaced vs cluster-scoped resources.
- [ ] Detect verbs available from discovery data.

### 2.4 Namespace Loading

- [ ] Load namespaces.
- [ ] Display namespace selector in toolbar.
- [ ] Support `All namespaces`.
- [ ] Persist selected namespace per context.
- [ ] Handle permission-denied namespace list.

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
- [ ] Kubernetes `Status` decoding tests.
- [ ] Mock server tests for `/version` and discovery.
- [x] Integration test against kind where practical.

## Acceptance Criteria

- [x] Selecting the demo context connects successfully.
- [x] Toolbar shows connected status and dashboard shows Kubernetes version.
- [ ] API groups/resources are discovered.
- [ ] Namespaces are available in the selector.
- [x] Bad auth, offline server, and certificate failures are understandable.
- [ ] Teleport-backed kubeconfigs can trigger `tsh` login/browser auth through exec credentials.

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
