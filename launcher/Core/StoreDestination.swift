import Foundation

public enum StoreDestination: String, CaseIterable, Identifiable, Sendable {
    case nsvault, romsns
    public var id: String { rawValue }
    public var title: String { self == .nsvault ? "NSVault" : "ROMsNS" }
    public var url: URL { URL(string: self == .nsvault ? "https://nsvault.me/" : "https://romsns.com/")! }
}
