# Kubernetes Client Design

Status: Living design note, updated through the read-only release-hardening track.

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
- real Teleport-backed corporate cluster validation on a separate work machine
- certificate-authority pinned TLS for corporate clusters with non-public/internal certificates
- `/api` core version discovery
- `/apis` group discovery
- per-group/version API resource discovery
- namespace loading with a toolbar namespace selector
- generic resource list endpoints from discovery metadata
- generic resource detail endpoints from discovery metadata
- native read-only resource tables for common built-ins
- native read-only manifest inspector for selected resource rows
- basic HTTP status and Kubernetes `Status` error mapping
- connected/connecting/signing-in/error UI states
- mock `URLProtocol` coverage for `/version` success, auth failure, timeout/unavailable, cancellation, and malformed JSON
- opt-in kind integration test through `VIBEKUBE_RUN_KIND_INTEGRATION=1`

Remaining polish:

- mock discovery tests for multi-group edge cases

Client certificate note: URLSession needs a `SecIdentity` for mTLS. The current implementation imports the PEM certificate/key into a temporary keychain, uses the identity for the session challenge, and deletes the keychain afterward. This avoids polluting the login keychain. The Phase 11 credential-storage decision keeps this temporary-keychain approach for the current direct-distribution release because Vibekube does not persist app-owned secrets.

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

Implementation note: raw exec stdout is only decoded as `ExecCredential`; decoded credential material is not shown. Exec stderr may appear as a short user-facing failure hint, but it passes through the shared free-form redactor before display or diagnostics because providers can accidentally write sensitive material there.

## Teleport Behavior

Teleport-backed kubeconfigs commonly use `tsh` as the exec credential command. Vibekube should not preemptively run `tsh login` as a separate hard-coded command. Instead, it should run the kubeconfig exec command during connection and let `tsh` decide whether existing certificates are valid or whether browser SSO/MFA is required.

Expected UX:

- Context list shows Teleport-backed contexts as `Teleport exec auth (tsh)`.
- Connecting a Teleport context may open the browser through `tsh` when credentials are missing or expired.
- While the exec plugin is running, the app shows `Signing In`; when the plugin finishes, the app returns to `Connecting` while contacting the API and loading discovery.
- If the user cancels, the app returns to disconnected.
- If `tsh` is missing, show the kubeconfig `installHint` or a concise install message.

Manual validation completed: Vibekube can connect to real Teleport-backed dev and prod clusters from a separate work Mac through kubeconfig exec auth.

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

## Resource Lists

Resource list URLs are built from discovery metadata:

- core namespaced: `GET /api/{version}/namespaces/{namespace}/{resource}`
- core all-namespaces: `GET /api/{version}/{resource}`
- grouped namespaced: `GET /apis/{group}/{version}/namespaces/{namespace}/{resource}`
- grouped all-namespaces or cluster-scoped: `GET /apis/{group}/{version}/{resource}`

Current list behavior:

- New cluster connections start with `All Namespaces` selected so common resource lists show cluster-wide data by default.
- The selected namespace controls namespaced list requests.
- `All Namespaces` omits the namespace path segment for namespaced resources.
- Cluster-scoped resources ignore namespace selection.
- Table rows decode metadata plus safe summary fields from `spec`, `status`, event reason/type, and object type.
- Secret payload fields such as `data` and `stringData` are not decoded into row models, displayed, or searchable.
- Kubernetes list `metadata.continue` is decoded but not followed yet; pagination belongs in the next hardening slice.

## Resource Details

Resource detail URLs are built from the same discovery metadata:

- core namespaced: `GET /api/{version}/namespaces/{namespace}/{resource}/{name}`
- core cluster-scoped: `GET /api/{version}/{resource}/{name}`
- grouped namespaced: `GET /apis/{group}/{version}/namespaces/{namespace}/{resource}/{name}`
- grouped cluster-scoped: `GET /apis/{group}/{version}/{resource}/{name}`

Current detail behavior:

- Selecting a resource table row loads the full object if the discovered resource advertises the `get` verb.
- Detail requests are cached in memory by context, resource, namespace, and name.
- Namespaced detail requests prefer the row's `metadata.namespace`, which keeps `All Namespaces` list results accurate.
- If a namespaced row has no namespace while `All Namespaces` is selected, Vibekube does not guess and leaves the detail state idle.
- The manifest viewer renders a deterministic YAML-like view from the returned object. In the safe-mutations track, the YAML tab also supports a draft edit mode that can run server-side dry-run previews without applying changes.
- The manifest viewer includes line numbers, lightweight syntax highlighting, find navigation, copy-to-clipboard, and save/export.
- Secret manifests redact top-level `data`, `stringData`, and `binaryData` by default.
- Events, conditions, and relationships belong to the dedicated detail phase.

## References

- Kubernetes kubeconfig `ExecConfig` and `interactiveMode`: https://kubernetes.io/docs/reference/config-api/kubeconfig.v1/
- Kubernetes client-go credential plugin flow: https://kubernetes.io/docs/reference/access-authn-authz/authentication/
- Teleport Kubernetes access login flow: https://goteleport.com/docs/enroll-resources/kubernetes-access/manage-access/
