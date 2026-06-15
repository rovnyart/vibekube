# Phase 4: Dashboard And Cluster Stats

Status: Started.

Goal: show a useful operational overview for the selected cluster.

## Current Progress

- [x] Phase plan exists.
- [ ] Dashboard data model exists.
- [ ] Node/pod/workload summaries load.
- [x] Recent events load.
- [ ] Metrics API availability is detected.
- [x] Dashboard UI handles event loading, empty, and error states.
- [ ] Dashboard UI handles full healthy, warning, and error states.

## Checkpoint Notes

- Dashboard Recent Events now loads the same Kubernetes Event resources used by the resource inspector, but without per-object filtering.
- Resource detail Events are object-specific; Dashboard Recent Events are cluster/namespace-scope operational feed.
- The current dashboard still has placeholder-level cluster stats. The intended dashboard should become a dense operational view closer to OpenLens/Aptakube, with charts and drill-downs instead of generic API counters.

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

- [ ] Define `ClusterDashboardSnapshot`.
- [ ] Define `NodeHealthSummary`.
- [ ] Define `PodHealthSummary`.
- [ ] Define `WorkloadHealthSummary`.
- [x] Reuse Kubernetes event summaries for current Recent Events feed.
- [ ] Define dashboard-specific event aggregation summary.
- [ ] Define `MetricsAvailability`.

### 4.2 Data Loading

- [ ] Load Kubernetes version.
- [ ] Load nodes and readiness.
- [ ] Load namespaces.
- [ ] Load pods across selected namespace scope.
- [ ] Load deployments, statefulsets, daemonsets, jobs, and cronjobs.
- [x] Load recent events.
- [ ] Load PV/PVC summary.
- [ ] Try metrics API and gracefully degrade.

### 4.3 Health Computation

- [ ] Compute node readiness.
- [ ] Compute pod phase counts.
- [ ] Compute restart warning counts.
- [ ] Compute workload desired/current/ready state.
- [ ] Identify warning events.
- [ ] Add status taxonomy: healthy, progressing, warning, failed, unknown.

### 4.4 Dashboard UI

- [ ] Cluster identity header.
- [ ] Health summary strip.
- [ ] Node card/table.
- [ ] Workload summary.
- [ ] Pod health summary.
- [x] Recent events list.
- [ ] Recent warnings list with aggregation.
- [ ] Storage summary.
- [ ] Metrics unavailable state.
- [ ] Last updated indicator.

Checkpoint: stop for visual review once demo cluster dashboard renders real data.

### 4.5 Tests

- [ ] Health computation unit tests.
- [ ] Dashboard view model tests.
- [x] Event list decoding coverage through resource list tests.
- [ ] UI test for demo cluster dashboard if integration setup is available.

## Acceptance Criteria

- [ ] Demo cluster dashboard shows version, nodes, pods, workloads, and warning events.
- [x] Demo cluster dashboard shows recent events.
- [ ] Dashboard links into related resources where routes exist.
- [ ] Missing metrics does not look like a failure.
- [ ] Refresh updates dashboard data.

## Validation Commands

```sh
dev/k8s/scripts/start.sh
kubectl get nodes
kubectl get pods -A
kubectl get events -A
xcodebuild -project vibekube.xcodeproj -scheme vibekube -destination 'platform=macOS' test
```
