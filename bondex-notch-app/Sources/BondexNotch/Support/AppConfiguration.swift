import Foundation

enum AppConfiguration {
    private static let fallbackCheckoutURL = URL(
        string: "https://bondex-notch.bondeth.site/checkout/"
    )!

    static var checkoutURL: URL {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "BondexCheckoutURL") as? String,
              let url = URL(string: value),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "")
        else {
            return fallbackCheckoutURL
        }
        return url
    }
}
