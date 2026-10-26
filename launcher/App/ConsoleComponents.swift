import SwiftUI
import Network
import Combine
import iSwitchCore

@MainActor
enum DevicePresentation {
    static var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    static var name: String { isPad ? "iPad" : "iPhone" }
    static var systemName: String { isPad ? "iPadOS" : "iOS" }
    static var icon: String { isPad ? "ipad" : "iphone" }
}

@MainActor
final class ConsoleStatus: ObservableObject {
    @Published var battery = UIDevice.current.batteryLevel
    @Published var charging = false
    @Published var networkSymbol = "wifi.slash"
    @Published var networkLabel = "Offline"
    private let monitor = NWPathMonitor()
    private var observations: [AnyCancellable] = []
    init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        for name in [UIDevice.batteryLevelDidChangeNotification, UIDevice.batteryStateDidChangeNotification] {
            NotificationCenter.default.publisher(for: name).receive(on: RunLoop.main).sink { [weak self] _ in
                self?.refreshBattery()
            }.store(in: &observations)
        }
        refreshBattery()
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            let wifi = path.usesInterfaceType(.wifi)
            Task { @MainActor in
                self?.networkSymbol = connected ? (wifi ? "wifi" : "cellularbars") : "wifi.slash"
                self?.networkLabel = connected ? (wifi ? "Wi-Fi connected" : "Network connected") : "Offline"
            }
        }
        monitor.start(queue: DispatchQueue(label: "iSwitch.network-status"))
    }
    deinit { monitor.cancel() }
    private func refreshBattery() {
        battery = UIDevice.current.batteryLevel
        charging = [.charging, .full].contains(UIDevice.current.batteryState)
    }
    var batterySymbol: String {
        if charging { return "battery.100percent.bolt" }
        return battery > 0.8 ? "battery.100percent" : battery > 0.55 ? "battery.75percent" : battery > 0.3 ? "battery.50percent" : battery > 0.1 ? "battery.25percent" : "battery.0percent"
    }
}

enum ConsoleAction: String, CaseIterable, Identifiable {
    case chat, shop, controllers, cards, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .chat: "Chat"
        case .shop: "Store"
        case .controllers: "Controllers"
        case .cards: "Game Library"
        case .settings: "System Settings"
        }
    }
    var identifier: String { "dock-" + (self == .cards ? "sources" : rawValue) }
    var color: Color {
        switch self {
        case .chat: Color(red: 0.89, green: 0.48, blue: 0.13)
        case .shop: Color(red: 0.90, green: 0.29, blue: 0.24)
        default: Color(white: 0.65)
        }
    }
}

/// Vector controls follow the proportions of the Switch 2 system menu.
struct ConsoleSymbol: View {
    @Environment(\.colorScheme) private var scheme
    let action: ConsoleAction
    private var color: Color {
        guard scheme == .light else { return action.color }
        // Preserve each menu icon's identity while keeping it legible on light glass.
        switch action {
        case .chat: return Color(red: 0.67, green: 0.30, blue: 0.02)
        case .shop: return Color(red: 0.78, green: 0.20, blue: 0.16)
        default: return Color(white: 0.35)
        }
    }
    var body: some View {
        GeometryReader { geometry in
            let s = geometry.size.width
            ZStack {
                if action == .chat {
                    Rectangle().stroke(color, lineWidth: s * 0.052).frame(width: s * 0.47, height: s * 0.47)
                    Text("C").font(.system(size: s * 0.35, weight: .heavy)).foregroundStyle(color)
                } else {
                    Image(systemName: symbol).font(.system(size: s * 0.57, weight: .regular)).foregroundStyle(color)
                }
            }.frame(width: s, height: s)
        }.accessibilityHidden(true)
    }
    private var symbol: String {
        switch action {
        case .shop: "bag"
        case .controllers: ReSwitchBrand.controllerSymbol
        case .cards: ReSwitchBrand.librarySymbol
        case .settings: "gearshape"
        default: "circle"
        }
    }
}
