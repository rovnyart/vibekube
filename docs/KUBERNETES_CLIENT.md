# Kubernetes Client Design

Status: Draft, updated during Phase 2.

This document captures client behavior that should stay true across implementation phases. The most important rule: Vibekube should behave like `kubectl` and established clients wherever kubeconfig semantics already define the right thing.

## Authentication Support Matrix

| Kubeconfig auth method | Phase 1 parse/display | Phase 2 connection target | Notes |
| --- | --- | --- | --- |
| Bearer token | Supported | Supported | Never log or display token values. |
| Client certificate/key data | Supported | Supported | Currently imported into a temporary keychain to create a URLSession client identity. |
| Client certificate/key paths | Supported | Supported | Paths are resolved relative to the kubeconfig source file. |
| `exec` credential plugin | Supported | Supported | Required for Teleport, EKS, GKE, Azure, and many corporate clusters. |
| Legacy `auth-provider` | Visible as unsupported | Deferred | Keep visible with a useful message. |
| Basic auth | Visible as unsupported | Deferred | Deprecated/rare; do not prioritize. |

## Current Phase 2 Checkpoint

Vibekube now builds a native client configuration from the selected kubeconfig context, calls `/version`, discovers APIs, and loads namespaces with `URLSession`.

Implemented:

- certificate-authority data and file paths
- bearer token auth
- client certificate/key data and file paths
- exec credential plugin execution
- Teleport `tsh` support through the kubeconfig exec path
- `/api` core version discovery
- `/apis` group discovery
- per-group/version API resource discovery
- namespace loading with a toolbar namespace selector
- basic HTTP status and Kubernetes `Status` error mapping
- connected/connecting/error UI states
- opt-in kind integration test through `VIBEKUBE_RUN_KIND_INTEGRATION=1`

Not implemented yet:

- resource object list APIs
- YAML detail loading
- watch/streaming updates
- dedicated signing-in UI for long-running exec auth
- manual validation against a real Teleport-backed corporate kubeconfig

Client certificate note: URLSession needs a `SecIdentity` for mTLS. The current implementation imports the PEM certificate/key into a temporary keychain, uses the identity for the session challenge, and deletes the keychain afterward. This avoids polluting the login keychain, but it uses deprecated `SecKeychain` APIs; revisit the long-term packaging/security approach in Phase 11.

## Exec Credential Plugins

Kubeconfig `user.exec` entries are a standard Kubernetes credential plugin mechanism. Vibekube should execute the configured command rather than special-casing a vendor login command. That means Teleport support comes from honoring kubeconfig entries such as `command: tsh` with `args: ["kube", "credentials", ...]`.

Phase 2 implementation behavior:

- Resolve the executable from either an absolute path, the app process `PATH`, or common macOS developer paths such as `/opt/homebrew/bin`.
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

Implementation note: raw exec stdout is only decoded as `ExecCredential`; stderr is discarded and not shown in UI errors because providers can accidentally write sensitive material there. User-facing errors name the command and failure class without echoing command output.

## Teleport Behavior

Teleport-backed kubeconfigs commonly use `tsh` as the exec credential command. Vibekube should not preemptively run `tsh login` as a separate hard-coded command. Instead, it should run the kubeconfig exec command during connection and let `tsh` decide whether existing certificates are valid or whether browser SSO/MFA is required.

Expected UX:

- Context list shows Teleport-backed contexts as `Teleport exec auth (tsh)`.
- Connecting a Teleport context may open the browser through `tsh` when credentials are missing or expired.
- While the exec plugin is running, the app currently shows `Connecting`; add a dedicated signing-in state in a later UX polish slice.
- If the user cancels, the app returns to disconnected.
- If `tsh` is missing, show the kubeconfig `installHint` or a concise install message.

Manual validation still needed: test this on a machine with a real Teleport kubeconfig and expired/missing `tsh` credentials to confirm browser SSO/MFA opens from the GUI app process.

## API Discovery

Vibekube discovers the selected cluster after a successful `/version` call:

- `GET /api` for core API versions
- `GET /apis` for grouped APIs
- `GET /api/{version}` for core resources
- `GET /apis/{group}/{version}` for grouped resources
- `GET /api/v1/namespaces` for namespace scope

Discovery metadata is held in memory per context for now. It powers dashboard counts, namespace selection, the grouped API resource catalog, and scope hints in the resource sidebar.

Per-group resource discovery is lenient: if one aggregated API group is unavailable, Vibekube keeps the rest of discovery results instead of failing the whole connection. Cancellation still stops discovery immediately when the user switches context or disconnects.

Namespace loading is also soft-fail. If the user can connect and discover APIs but cannot list namespaces, Vibekube keeps the cluster connected, records the namespace access error, and leaves the selector with `All Namespaces` plus the kubeconfig context namespace.

## References

- Kubernetes kubeconfig `ExecConfig` and `interactiveMode`: https://kubernetes.io/docs/reference/config-api/kubeconfig.v1/
- Kubernetes client-go credential plugin flow: https://kubernetes.io/docs/reference/access-authn-authz/authentication/
- Teleport Kubernetes access login flow: https://goteleport.com/docs/enroll-resources/kubernetes-access/manage-access/
