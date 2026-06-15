# Phase 4: Dashboard And Cluster Stats

Status: Started.

Goal: show a useful operational overview for the selected cluster.

## Current Progress

- [x] Phase plan exists.
- [x] Dashboard data model exists.
- [x] Node/pod/workload summaries load.
- [x] Recent events load.
- [x] Metrics API availability is detected.
- [x] Dashboard shows CPU/RAM usage through the Kubernetes Metrics API when available.
- [x] Dashboard UI handles event loading, empty, and error states.
- [x] Dashboard UI renders live healthy/warning/failed summary states.
- [x] Dashboard resource lists load together without cancelling sibling requests.
- [x] Dashboard avoids repeated snapshot recomputation during a single render.
- [x] Dashboard cancels irrelevant in-flight list loads when navigating away.

## Checkpoint Notes

- Dashboard Recent Events now loads the same Kubernetes Event resources used by the resource inspector, but without per-object filtering.
- Resource detail Events are object-specific; Dashboard Recent Events are cluster/namespace-scope operational feed.
- Dashboard health now derives from real resource lists: nodes, pods, workloads, PV/PVCs, and warning events.
- Dashboard render now computes the health snapshot once per SwiftUI pass instead of repeatedly walking the same resource arrays.
- Leaving Dashboard cancels in-flight dashboard-only list calls, while preserving a clicked resource if it was already loading.
- Dashboard Resource Usage now means actual CPU and memory usage from `metrics.k8s.io`, with allocatable node CPU/RAM used as capacity when node data is loaded.
- All Namespaces uses node-level metrics for cluster CPU/RAM; a selected namespace uses summed pod metrics for that namespace and shows capacity as unavailable until request/limit summaries exist.
- The old object-count panel is renamed Cluster Inventory so it is not confused with CPU/RAM resource usage.
- The dashboard still needs richer historical charts, drill-down links, and clearer handling for partial load failures.

## Product Reference Notes

- Aptakube emphasizes Workload Overview, failing pods/deployments, warning events, recent restarts, and CPU/memory metrics via the standard Kubernetes Metrics API: https://aptakube.com/ and https://aptakube.com/metrics
- Lens/OpenLens-style dashboards emphasize at-a-glance resources, CPU/memory, pod capacity, problems from events, workload overviews, logs, and live status updates: https://lenshq.io/blog/lens-kubernetes
- Kubernetes Dashboard defines the baseline expectation as application/resource overview, state/error visibility, and resource management: https://kubernetes.io/docs/tasks/access-application-cluster/web-ui-dashboard/

## Planned Dashboard Shape

- Health strip: cluster status, node readiness, pod health, warning events, restart pressure.
- Workload readiness: Deployments, StatefulSets, DaemonSets, Jobs, and CronJobs with ready/desired/current counts.
- Pod phase chart: Running, Pending, Failed, Succeeded, Unknown across selected scope.
- Warning trend: recent warnings by reason/source and noisy objects.
- Node capacity: readiness, pressure conditions, allocatable CPU/memory, and usage when Metrics API is available.
- Storage summary: PV/PVC bound/pending/lost states.
- Metrics fallback: graceful "metrics unavailable" state that does not look like a cluster failure.
- Drill-down: dashboard rows should open the relevant resource list or filtered detail route when available.

## Implementation Slices

### 4.1 Summary Models

- [x] Define `ClusterDashboardSnapshot`.
- [x] Define `NodeHealthSummary`.
- [x] Define `PodHealthSummary`.
- [x] Define `WorkloadHealthSummary`.
- [x] Define `StorageHealthSummary`.
- [x] Reuse Kubernetes event summaries for current Recent Events feed.
- [x] Define dashboard-specific event aggregation summary.
- [x] Define dashboard metrics load state and availability fallback.

### 4.2 Data Loading

- [x] Load Kubernetes version.
- [x] Load nodes and readiness.
- [x] Load namespaces.
- [x] Load pods across selected namespace scope.
- [x] Load deployments, statefulsets, daemonsets, jobs, and cronjobs.
- [x] Load recent events.
- [x] Load PV/PVC summary.
- [x] Try metrics API and gracefully degrade.

### 4.3 Health Computation

- [x] Compute node readiness.
- [x] Compute pod phase counts.
- [x] Compute restart warning counts.
- [x] Compute workload desired/current/ready state.
- [x] Identify warning events.
- [x] Add status taxonomy: healthy, progressing, warning, failed, unknown.

### 4.4 Dashboard UI

- [x] Cluster identity header.
- [x] Health summary strip.
- [x] Resource inventory summary.
- [x] Node readiness summary.
- [x] Workload summary.
- [x] Pod health summary.
- [x] Recent events list.
- [x] Recent warnings list with aggregation.
- [x] Storage summary.
- [x] CPU/RAM resource usage panel.
- [x] Metrics unavailable state.
- [x] Last updated indicator.
- [ ] Per-section load failure callouts.

Checkpoint: stop for visual review once demo cluster dashboard renders real data.

### 4.5 Tests

- [x] Health computation unit tests.
- [x] Dashboard view model tests.
- [x] Event list decoding coverage through resource list tests.
- [x] CPU/memory metrics quantity parsing tests.
- [x] Dashboard resource usage aggregation tests.
- [ ] Visual/manual demo cluster dashboard check.

## Acceptance Criteria

- [ ] Demo cluster dashboard visually shows version, nodes, pods, workloads, and warning events.
- [x] Demo cluster dashboard shows recent events.
- [ ] Dashboard links into related resources where routes exist.
- [x] Missing metrics does not look like a failure.
- [x] Refresh updates dashboard data.

## Validation Commands

```sh
dev/k8s/scripts/start.sh
kubectl get nodes
kubectl get pods -A
kubectl get events -A
xcodebuild -project vibekube.xcodeproj -scheme vibekube -destination 'platform=macOS' test
```
