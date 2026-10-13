import Foundation

/// `setScreen(_:url:title:)` ile gelen ekran.
struct ScreenInfo {
    var screen: DotScreen
    var url: String?
    var title: String?
}

/// Uygulama ekranı → widget'ın gördüğü durum (`__dotApp.state`) ve adres.
///
/// RN SDK'daki `screen.ts`in birebir karşılığı. Üç SDK aynı vakaları koşuyor
/// (`Tests/DotAssistTests/Fixtures/screen.json`; aynı dosya RN ve Android SDK'larında da var).
/// Durumun anahtarları web'deki değişken adlarıyla aynı (`widget/src/platforms/app`).
enum ScreenState {
    static func pageType(_ screen: DotScreen) -> String {
        switch screen {
        case .home: return "home"
        case .product: return "product"
        case .category: return "category"
        case .search: return "search"
        case .cart: return "cart"
        case .account: return "account"
        case .other: return "other"
        }
    }

    static func state(_ info: ScreenInfo?, order: DotOrder?, cart: DotCart?, user: DotUser?) -> [String: Any] {
        var out: [String: Any] = [
            "pageType": order != nil ? "checkout" : info.map { pageType($0.screen) } ?? "other",
            "cart": cart.map { $0.json as Any } ?? NSNull(),
            "user": ["loggedIn": user.map { !$0.ref.isEmpty && !$0.sig.isEmpty } ?? false],
        ]
        if let title = info?.title, !title.isEmpty { out["title"] = title }
        if let order {
            out["order"] = order.json
            return out
        }
        switch info?.screen {
        case let .product(p)?: out["product"] = p.json
        case let .category(c)?: out["category"] = c.json
        case let .search(s)?: out["search"] = s.json
        default: break
        }
        return out
    }

    /// Ekranın adresi. Widget her yeni adreste sayfa olaylarını yeniden atar
    /// (`product_view`, `page_view`). Uygulama ekranın web karşılığını verdiyse
    /// o (analizde web sayfasıyla aynı görünür); yoksa `/__app/...`.
    ///
    /// Başka bir alan adındaki adres köprüde mağazanın alan adına taşınıyor
    /// (yalnızca yol): WebView başka origin'e `pushState` yapamaz.
    static func url(origin: String, _ info: ScreenInfo?, order: DotOrder?) -> String {
        let app = { (path: String) in origin + "/__app/" + path }
        if let order { return app("checkout/" + encodeURIComponent(order.orderId)) }
        guard let info else { return origin + "/" }
        if let url = info.url, !url.isEmpty { return url }
        switch info.screen {
        case .home:
            return origin + "/"
        case let .product(p):
            return nonEmpty(p.url) ?? app("product/" + encodeURIComponent(p.id))
        case let .category(c):
            return nonEmpty(c.url) ?? app("category/" + encodeURIComponent(c.categoryRef))
        case let .search(s):
            return app("search?q=" + encodeURIComponent(s.query))
        case let .other(name):
            return app(encodeURIComponent(nonEmpty(name) ?? "other"))
        case .cart:
            return app("cart")
        case .account:
            return app("account")
        }
    }

    /// `window.dotUser`: imzalı kimlik. Eksikse gönderilmez (sunucu zaten reddeder).
    static func identity(_ user: DotUser?) -> [String: Any]? {
        guard let user, !user.ref.isEmpty, !user.sig.isEmpty, user.exp != 0 else { return nil }
        return user.json
    }

    /// `www.teknosa.com`, `https://www.teknosa.com/` → `https://www.teknosa.com`.
    ///
    /// Açıkça `http://` yazılırsa korunuyor: YALNIZCA yerel geliştirme
    /// (örnek uygulamanın mock sunucusu). Mağaza alan adı her zaman https.
    static func origin(of domain: String) -> String {
        let raw = domain.trimmingCharacters(in: .whitespacesAndNewlines)
        let scheme = raw.lowercased().hasPrefix("http://") ? "http://" : "https://"
        var d = raw
        if let r = d.range(of: "^[a-zA-Z]+://", options: .regularExpression) { d.removeSubrange(r) }
        if let slash = d.firstIndex(of: "/") { d = String(d[..<slash]) }
        return scheme + d.lowercased()
    }

    /// JS `encodeURIComponent`: yalnızca `A-Z a-z 0-9 - _ . ! ~ * ' ( )` kaçışsız.
    static func encodeURIComponent(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: uriComponent) ?? s
    }

    private static let uriComponent: CharacterSet = {
        var set = CharacterSet()
        set.insert(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()")
        return set
    }()

    private static func nonEmpty(_ s: String?) -> String? {
        guard let s, !s.isEmpty else { return nil }
        return s
    }
}
