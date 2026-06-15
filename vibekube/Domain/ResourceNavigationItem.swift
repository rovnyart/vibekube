import Foundation

enum ResourceNavigationSection: String, CaseIterable, Identifiable {
    case overview
    case workloads
    case network
    case config
    case storage
    case accessControl
    case cluster
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview:
            "Overview"
        case .workloads:
            "Workloads"
        case .network:
            "Network"
        case .config:
            "Config"
        case .storage:
            "Storage"
        case .accessControl:
            "Access Control"
        case .cluster:
            "Cluster"
        case .custom:
            "Custom"
        }
    }
}

enum ResourceNavigationItem: String, CaseIterable, Identifiable, Hashable {
    case dashboard
    case pods
    case deployments
    case replicaSets
    case statefulSets
    case daemonSets
    case jobs
    case cronJobs
    case services
    case ingresses
    case configMaps
    case secrets
    case persistentVolumes
    case persistentVolumeClaims
    case storageClasses
    case serviceAccounts
    case roles
    case roleBindings
    case clusterRoles
    case clusterRoleBindings
    case nodes
    case namespaces
    case events
    case customResources
    case logs
    case aiAssistant
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard:
            "Dashboard"
        case .pods:
            "Pods"
        case .deployments:
            "Deployments"
        case .replicaSets:
            "ReplicaSets"
        case .statefulSets:
            "StatefulSets"
        case .daemonSets:
            "DaemonSets"
        case .jobs:
            "Jobs"
        case .cronJobs:
            "CronJobs"
        case .services:
            "Services"
        case .ingresses:
            "Ingresses"
        case .configMaps:
            "ConfigMaps"
        case .secrets:
            "Secrets"
        case .persistentVolumes:
            "PersistentVolumes"
        case .persistentVolumeClaims:
            "PersistentVolumeClaims"
        case .storageClasses:
            "StorageClasses"
        case .serviceAccounts:
            "ServiceAccounts"
        case .roles:
            "Roles"
        case .roleBindings:
            "RoleBindings"
        case .clusterRoles:
            "ClusterRoles"
        case .clusterRoleBindings:
            "ClusterRoleBindings"
        case .nodes:
            "Nodes"
        case .namespaces:
            "Namespaces"
        case .events:
            "Events"
        case .customResources:
            "Custom Resources"
        case .logs:
            "Logs"
        case .aiAssistant:
            "AI"
        case .settings:
            "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard:
            "gauge.with.dots.needle.bottom.50percent"
        case .pods:
            "shippingbox"
        case .deployments:
            "square.stack.3d.up"
        case .replicaSets:
            "rectangle.stack"
        case .statefulSets:
            "externaldrive.connected.to.line.below"
        case .daemonSets:
            "cpu"
        case .jobs:
            "checklist.checked"
        case .cronJobs:
            "clock.badge.checkmark"
        case .services:
            "point.3.connected.trianglepath.dotted"
        case .ingresses:
            "arrow.triangle.branch"
        case .configMaps:
            "doc.text"
        case .secrets:
            "key"
        case .persistentVolumes:
            "internaldrive"
        case .persistentVolumeClaims:
            "tray.and.arrow.down"
        case .storageClasses:
            "archivebox"
        case .serviceAccounts:
            "person.crop.circle.badge.checkmark"
        case .roles:
            "person.text.rectangle"
        case .roleBindings:
            "link.badge.plus"
        case .clusterRoles:
            "person.2.badge.gearshape"
        case .clusterRoleBindings:
            "link.circle"
        case .nodes:
            "server.rack"
        case .namespaces:
            "folder"
        case .events:
            "waveform.path.ecg"
        case .customResources:
            "square.grid.3x3"
        case .logs:
            "terminal"
        case .aiAssistant:
            "sparkles"
        case .settings:
            "gearshape"
        }
    }

    var section: ResourceNavigationSection {
        switch self {
        case .dashboard, .logs, .aiAssistant, .settings:
            .overview
        case .pods, .deployments, .replicaSets, .statefulSets, .daemonSets, .jobs, .cronJobs:
            .workloads
        case .services, .ingresses:
            .network
        case .configMaps, .secrets:
            .config
        case .persistentVolumes, .persistentVolumeClaims, .storageClasses:
            .storage
        case .serviceAccounts, .roles, .roleBindings, .clusterRoles, .clusterRoleBindings:
            .accessControl
        case .nodes, .namespaces, .events:
            .cluster
        case .customResources:
            .custom
        }
    }

    static func items(in section: ResourceNavigationSection) -> [ResourceNavigationItem] {
        allCases.filter { $0.section == section }
    }
}
