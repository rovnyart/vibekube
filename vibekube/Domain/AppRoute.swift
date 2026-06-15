import Foundation

struct AppRoute: Equatable {
    var clusterID: ClusterSummary.ID?
    var resource: ResourceNavigationItem

    static let initial = AppRoute(clusterID: nil, resource: .dashboard)

    var title: String {
        resource.title
    }
}
