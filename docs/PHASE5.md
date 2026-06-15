# Phase 5: Resource Browsing

Status: Review checkpoint.

Goal: browse Kubernetes resources by group with sortable, filterable, namespace-aware native tables.

## Current Progress

- [x] Phase plan exists.
- [x] Generic resource identity exists.
- [x] Built-in resource list loaders exist.
- [ ] Generic discovered custom resource browsing exists.
- [x] Tables support sorting/filtering.
- [x] Namespace scope works.

## Checkpoint Notes

- The app can now list discovered resources through generic Kubernetes list endpoints.
- Built-in navigation items route to a native table once their API resource is discovered.
- The table currently shows safe generic columns: name, namespace, kind, status, age, and labels.
- Toolbar search filters the current table.
- Toolbar namespace selection reloads namespaced resources for the selected namespace or all namespaces.
- Secret payload fields are not decoded into list rows and are not searchable/displayed.
- Pagination tokens are decoded but follow-up page loading is not implemented yet.
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
- [ ] ReplicaSets.
- [ ] StatefulSets.
- [ ] DaemonSets.
- [ ] Jobs.
- [ ] CronJobs.
- [x] Services.
- [ ] Ingresses.
- [x] ConfigMaps.
- [x] Secrets.
- [ ] PersistentVolumes.
- [ ] PersistentVolumeClaims.
- [ ] StorageClasses.
- [ ] ServiceAccounts.
- [ ] Roles.
- [ ] RoleBindings.
- [ ] ClusterRoles.
- [ ] ClusterRoleBindings.
- [ ] Nodes.
- [ ] Namespaces.
- [x] Events.
- [ ] CRDs.

### 5.3 Generic Resource Lists

- [x] Build generic list endpoint from discovery metadata.
- [x] Support namespaced resources.
- [x] Support cluster-scoped resources.
- [ ] Support pagination and continue tokens.
- [x] Add generic columns: name, namespace, status, age, labels.
- [ ] Add CRD/custom resource navigation.

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

Checkpoint: stop after Pods, Deployments, Services, ConfigMaps, Secrets, and Events browse correctly.

### 5.5 Tests

- [x] Metadata extraction tests.
- [x] Resource list URL tests.
- [ ] Filter/sort tests.
- [ ] Fixtures for common kinds.
- [ ] UI smoke test for resource table.

## Acceptance Criteria

- [x] User can browse common resource groups in the demo cluster.
- [ ] Tables stay readable in light and dark mode.
- [ ] Unknown discovered resources are still visible.
- [x] Secret values are not exposed in list views.
- [x] Refresh and namespace switching work consistently.

## Validation Results

- [x] `xcodebuild -project vibekube.xcodeproj -scheme vibekube -destination 'platform=macOS' test -only-testing:vibekubeTests`
- [x] `VIBEKUBE_RUN_KIND_INTEGRATION=1 xcodebuild -project vibekube.xcodeproj -scheme vibekube -destination 'platform=macOS' test -only-testing:vibekubeTests/KubernetesClientIntegrationTests/connectsToCurrentKubeconfigWhenEnabled`
- [x] `xcodebuild -project vibekube.xcodeproj -scheme vibekube -destination 'platform=macOS' test -only-testing:vibekubeUITests/vibekubeUITests/testShellLaunches`
- [ ] Manual app review by user.

## Validation Commands

```sh
dev/k8s/scripts/start.sh
kubectl api-resources
kubectl get all -n vibekube-demo
xcodebuild -project vibekube.xcodeproj -scheme vibekube -destination 'platform=macOS' test
```
