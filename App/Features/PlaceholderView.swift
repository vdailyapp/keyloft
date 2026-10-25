import SwiftUI

/// Mục sidebar tạm cho T25; T26–T28 thay bằng view thật của từng feature.
struct PlaceholderView: View {
    let title: String

    var body: some View {
        ContentUnavailableView(
            title, systemImage: "puzzlepiece.extension",
            description: Text("Tính năng này được lắp ở task UI kế tiếp."))
    }
}

enum SidebarItem: String, CaseIterable, Identifiable {
    case accounts = "Accounts"
    case providers = "Providers"
    case secrets = "Secrets"
    case health = "Health"
    case audit = "Audit"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .accounts: "person.2"
        case .providers: "appclip"
        case .secrets: "lock.shield"
        case .health: "heart.text.square"
        case .audit: "doc.text.magnifyingglass"
        }
    }

    @ViewBuilder
    var view: some View {
        PlaceholderView(title: rawValue)
    }
}
