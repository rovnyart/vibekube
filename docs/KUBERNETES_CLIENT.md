# Kubernetes Client Design

Status: Draft, updated during Phase 1.

This document captures client behavior that should stay true across implementation phases. The most important rule: Vibekube should behave like `kubectl` and established clients wherever kubeconfig semantics already define the right thing.

## Authentication Support Matrix

| Kubeconfig auth method | Phase 1 parse/display | Phase 2 connection target | Notes |
| --- | --- | --- | --- |
| Bearer token | Supported | Supported | Never log or display token values. |
| Client certificate/key data | Supported | Supported if feasible in first pass | Use in-memory TLS identity where possible. |
| Client certificate/key paths | Supported | Supported if feasible in first pass | Preserve paths and avoid copying secrets. |
| `exec` credential plugin | Supported | Supported | Required for Teleport, EKS, GKE, Azure, and many corporate clusters. |
| Legacy `auth-provider` | Visible as unsupported | Deferred | Keep visible with a useful message. |
| Basic auth | Visible as unsupported | Deferred | Deprecated/rare; do not prioritize. |

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
