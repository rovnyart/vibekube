# Phase 5: Resource Browsing

Status: Review checkpoint.

Goal: browse Kubernetes resources by group with sortable, filterable, namespace-aware native tables.

## Current Progress

- [x] Phase plan exists.
- [x] Generic resource identity exists.
- [x] Built-in resource list loaders exist.
- [ ] Generic discovered custom resource table browsing exists.
- [x] Tables support sorting/filtering.
- [x] Namespace scope works.
- [x] Selecting a row opens a read-only manifest inspector.

## Checkpoint Notes

- The app can now list discovered resources through generic Kubernetes list endpoints.
- Built-in navigation items route to a native table once their API resource is discovered.
- The table currently shows safe generic columns: name, namespace, kind, status, age, and labels.
- Selecting a table row opens the bottom detail inspector and loads the full Kubernetes object manifest.
- Toolbar search filters the current table.
- New cluster connections default to `All Namespaces` so workload lists are cluster-wide unless narrowed.
- Toolbar namespace selection reloads namespaced resources for the selected namespace or all namespaces.
- Secret payload fields are not decoded into list rows and are not searchable/displayed; Secret manifests redact top-level `data`, `stringData`, and `binaryData`.
- Kubernetes list pagination is followed with bounded page sizes for namespace discovery and generic resource tables.
- Slow resource lists show item/page progress and can be cancelled before all Kubernetes pages finish loading.
- Custom/discovered resources are visible in the API catalog, but dynamic custom-resource table navigation is still pending.

## Implementation Slices

### 5.1 Resource Identity And Store

- [x] Define `ResourceIdentity`.
- [x] Define `ResourceScope`.
- [x] Define `ResourceListQuery`.
- [x] Define `UnstructuredResource`.
- [x] Define common metadata extraction.
- [x] Add in-memory resource list state.

### 5.2 Built-In Resources

- [x] Pods.
- [x] Deployments.
- [x] ReplicaSets.
- [x] StatefulSets.
- [x] DaemonSets.
- [x] Jobs.
- [x] CronJobs.
- [x] Services.
- [x] Ingresses.
- [x] ConfigMaps.
- [x] Secrets.
- [x] PersistentVolumes.
- [x] PersistentVolumeClaims.
- [x] StorageClasses.
- [x] ServiceAccounts.
- [x] Roles.
- [x] RoleBindings.
- [x] ClusterRoles.
- [x] ClusterRoleBindings.
- [x] Nodes.
- [x] Namespaces.
- [x] Events.
- [ ] CRDs.

### 5.3 Generic Resource Lists

- [x] Build generic list endpoint from discovery metadata.
- [x] Support namespaced resources.
- [x] Support cluster-scoped resources.
- [x] Support pagination and continue tokens.
- [x] Add generic columns: name, namespace, status, age, labels.
- [ ] Add CRD/custom resource table navigation from the catalog.

### 5.4 Table UX

- [x] Native table with stable columns.
- [x] Column sorting.
- [x] Text search.
- [ ] Label filter.
- [ ] Status filter.
- [x] Namespace filter.
- [ ] Row context menu.
- [ ] Copy name, namespace/name, UID, labels, and JSON path.
- [x] Loading/empty/error states.
- [x] Cancellable loading progress for paginated lists.
- [x] Row selection.
- [x] Bottom detail inspector.

Checkpoint: stop after Pods, Deployments, Services, ConfigMaps, Secrets, and Events browse correctly.

### 5.5 Tests

- [x] Metadata extraction tests.
- [x] Resource list URL tests.
- [x] Resource detail URL tests.
- [x] Manifest rendering tests.
- [x] Secret manifest redaction tests.
- [ ] Filter/sort tests.
- [ ] Fixtures for common kinds.
- [ ] UI smoke test for resource table.

## Acceptance Criteria

- [x] User can browse common resource groups in the demo cluster.
- [ ] Tables stay readable in light and dark mode.
- [x] Unknown discovered resources are still visible in the API catalog.
- [x] Secret values are not exposed in list views.
- [x] Refresh and namespace switching work consistently.

## Validation Results

- [x] `xcodebuild -project vibekube.xcodeproj -scheme vibekube -destination 'platform=macOS' test -only-testing:vibekubeTests`
- [x] `VIBEKUBE_RUN_KIND_INTEGRATION=1 xcodebuild -project vibekube.xcodeproj -scheme vibekube -destination 'platform=macOS' test -only-testing:vibekubeTests/KubernetesClientIntegrationTests/connectsToCurrentKubeconfigWhenEnabled`
- [ ] Manual app review by user.

## Validation Commands

```sh
dev/k8s/scripts/start.sh
kubectl api-resources
kubectl get all -n vibekube-demo
xcodebuild -project vibekube.xcodeproj -scheme vibekube -destination 'platform=macOS' test
```
