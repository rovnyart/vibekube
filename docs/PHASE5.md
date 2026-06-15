# Phase 5: Resource Browsing

Status: Not started.

Goal: browse Kubernetes resources by group with sortable, filterable, namespace-aware native tables.

## Current Progress

- [x] Phase plan exists.
- [ ] Generic resource identity exists.
- [ ] Built-in resource list loaders exist.
- [ ] Generic discovered resource browsing exists.
- [ ] Tables support sorting/filtering.
- [ ] Namespace scope works.

## Implementation Slices

### 5.1 Resource Identity And Store

- [ ] Define `ResourceIdentity`.
- [ ] Define `ResourceScope`.
- [ ] Define `ResourceListQuery`.
- [ ] Define `UnstructuredResource`.
- [ ] Define common metadata extraction.
- [ ] Add in-memory `ResourceStore`.

### 5.2 Built-In Resources

- [ ] Pods.
- [ ] Deployments.
- [ ] ReplicaSets.
- [ ] StatefulSets.
- [ ] DaemonSets.
- [ ] Jobs.
- [ ] CronJobs.
- [ ] Services.
- [ ] Ingresses.
- [ ] ConfigMaps.
- [ ] Secrets.
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
- [ ] Events.
- [ ] CRDs.

### 5.3 Generic Resource Lists

- [ ] Build generic list endpoint from discovery metadata.
- [ ] Support namespaced resources.
- [ ] Support cluster-scoped resources.
- [ ] Support pagination and continue tokens.
- [ ] Add generic columns: name, namespace, status, age, labels.
- [ ] Add CRD/custom resource navigation.

### 5.4 Table UX

- [ ] Native table with stable columns.
- [ ] Column sorting.
- [ ] Text search.
- [ ] Label filter.
- [ ] Status filter.
- [ ] Namespace filter.
- [ ] Row context menu.
- [ ] Copy name, namespace/name, UID, labels, and JSON path.
- [ ] Loading/empty/error states.

Checkpoint: stop after Pods, Deployments, Services, ConfigMaps, Secrets, and Events browse correctly.

### 5.5 Tests

- [ ] Metadata extraction tests.
- [ ] Resource list URL tests.
- [ ] Filter/sort tests.
- [ ] Fixtures for common kinds.
- [ ] UI smoke test for resource table.

## Acceptance Criteria

- [ ] User can browse common resource groups in the demo cluster.
- [ ] Tables stay readable in light and dark mode.
- [ ] Unknown discovered resources are still visible.
- [ ] Secret values are not exposed in list views.
- [ ] Refresh and namespace switching work consistently.

## Validation Commands

```sh
dev/k8s/scripts/start.sh
kubectl api-resources
kubectl get all -n vibekube-demo
xcodebuild -project vibekube.xcodeproj -scheme vibekube -destination 'platform=macOS' test
```
