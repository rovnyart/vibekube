# Kubernetes Client Design

Status: Draft, updated during Phase 2.

This document captures client behavior that should stay true across implementation phases. The most important rule: Vibekube should behave like `kubectl` and established clients wherever kubeconfig semantics already define the right thing.

## Authentication Support Matrix

| Kubeconfig auth method | Phase 1 parse/display | Phase 2 connection target | Notes |
| --- | --- | --- | --- |
| Bearer token | Supported | Supported | Never log or display token values. |
| Client certificate/key data | Supported | Supported | Currently imported into a temporary keychain to create a URLSession client identity. |
| Client certificate/key paths | Supported | Supported | Paths are resolved relative to the kubeconfig source file. |
| `exec` credential plugin | Supported | Next Phase 2 slice | Required for Teleport, EKS, GKE, Azure, and many corporate clusters. |
| Legacy `auth-provider` | Visible as unsupported | Deferred | Keep visible with a useful message. |
| Basic auth | Visible as unsupported | Deferred | Deprecated/rare; do not prioritize. |

## Current Phase 2 Checkpoint

Vibekube now builds a native client configuration from the selected kubeconfig context and calls `/version` with `URLSession`.

Implemented:

- certificate-authority data and file paths
- bearer token auth
- client certificate/key data and file paths
- basic HTTP status and Kubernetes `Status` error mapping
- connected/connecting/error UI states
- opt-in kind integration test through `VIBEKUBE_RUN_KIND_INTEGRATION=1`

Not implemented yet:

- `/api` and `/apis` discovery
- namespace/resource list APIs
- exec credential execution
- Teleport browser SSO/MFA through `tsh`

Client certificate note: URLSession needs a `SecIdentity` for mTLS. The current implementation imports the PEM certificate/key into a temporary keychain, uses the identity for the session challenge, and deletes the keychain afterward. This avoids polluting the login keychain, but it uses deprecated `SecKeychain` APIs; revisit the long-term packaging/security approach in Phase 11.

## Exec Credential Plugins

Kubeconfig `user.exec` entries are a standard Kubernetes credential plugin mechanism. Vibekube should execute the configured command rather than special-casing a vendor login command. That means Teleport support comes from honoring kubeconfig entries such as `command: tsh` with `args: ["kube", "credentials", ...]`.

Phase 2 implementation requirements:

- Resolve the executable from either an absolute path or the app process `PATH`.
- If the executable is missing, show `installHint` when kubeconfig provides one.
- Run the command with:
  - the host environment
  - `exec.env` entries from kubeconfig
  - `KUBERNETES_EXEC_INFO` when `provideClusterInfo` is true
- Respect `interactiveMode`:
  - `Never`: run non-interactively
  - `IfAvailable`: run and allow user-visible browser/device flows
  - `Always`: require a user-initiated connection attempt
- Decode returned `ExecCredential` JSON for bearer token or client certificate/key data.
- Cache credentials per context/user/cluster until `expirationTimestamp`.
- Re-run the exec plugin when credentials expire or the API returns `401 Unauthorized`.
- Redact stdout/stderr and decoded credentials from logs and UI errors.
- Allow cancellation when the user switches context or disconnects.

## Teleport Behavior

Teleport-backed kubeconfigs commonly use `tsh` as the exec credential command. Vibekube should not preemptively run `tsh login` as a separate hard-coded command. Instead, it should run the kubeconfig exec command during connection and let `tsh` decide whether existing certificates are valid or whether browser SSO/MFA is required.

Expected UX:

- Context list shows Teleport-backed contexts as `Teleport exec auth (tsh)`.
- Connecting a Teleport context may open the browser through `tsh` when credentials are missing or expired.
- While the exec plugin is running, the app should show a clear signing-in state.
- If the user cancels, the app returns to disconnected.
- If `tsh` is missing, show the kubeconfig `installHint` or a concise install message.

## References

- Kubernetes kubeconfig `ExecConfig` and `interactiveMode`: https://kubernetes.io/docs/reference/config-api/kubeconfig.v1/
- Kubernetes client-go credential plugin flow: https://kubernetes.io/docs/reference/access-authn-authz/authentication/
- Teleport Kubernetes access login flow: https://goteleport.com/docs/enroll-resources/kubernetes-access/manage-access/
