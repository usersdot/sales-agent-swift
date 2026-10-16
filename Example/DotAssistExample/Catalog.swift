import DotAssist
import Foundation

/// Mağaza ayarı. İki uygulama, iki dosya:
/// - `DotAssistExample` → `dot.config.json` (`mode: mock`): widget ve API yereldeki mock
///   sunucudan (`Example/` içinde `npm run mock`). Canlı sisteme hiçbir şey yazılmaz.
/// - `DotAssistExampleLive` (`DOT_LIVE`) → `dot.config.live.json` (`mode: live`): canlı widget
///   ve API (`chat.dotassist.ai`). ⚠ Gerçek oturum, olay ve soru yazar.
struct StoreConfig: Decodable {
    let pid: String
    let domain: String
    let mode: String?

    static let current: StoreConfig = {
        #if DOT_LIVE
        let name = "dot.config.live"
        #else
        let name = "dot.config"
        #endif
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(StoreConfig.self, from: data)
        else { fatalError("\(name).json okunamadı") }
        return config
    }()

    var isMock: Bool { mode != "live" }

    /// Simülatörde bilgisayar `localhost`.
    static let mockURL = "http://localhost:4185"
}

/// UYGULAMANIN KENDİ KATALOĞU: Yataş Bedding'den iki örnek ürün.
///
/// Uygulama bunları KENDİ ekranlarını çizmek için kullanıyor. Asistana yalnızca kimliği
/// veriyor (`ProductView`); ad, fiyat, görsel ve varyantları asistan mağazanın web
/// sitesinden beslenen katalogdan alıyor (mock'ta bu dosyadan). Kimlikler web sitesindekiyle aynı.
struct Product: Decodable, Identifiable, Hashable {
    struct Variant: Decodable, Hashable {
        let id: String
        let label: String?
        let stock: String?
    }

    let id: String
    let name: String
    let brand: String?
    let price: Double?
    let discountedPrice: Double?
    let currency: String?
    let url: String?
    let image: String?
    let stock: String?
    let description: String?
    let attributes: [String: String]?
    let variants: [Variant]?

    var soldOut: Bool { stock == "out_of_stock" }

    static let all: [Product] = {
        guard let url = Bundle.main.url(forResource: "yatas-products", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else { return [] }
        return (try? JSONDecoder().decode([Product].self, from: data)) ?? []
    }()

    /// Ürün ya da varyant kimliğiyle.
    static func find(_ id: String?) -> Product? {
        guard let id else { return nil }
        return all.first { $0.id == id || ($0.variants ?? []).contains { $0.id == id } }
    }

    /// Kimliğin (ürün ya da varyant) stok durumu.
    static func stock(of id: String) -> String? {
        let product = find(id)
        return product?.variants?.first { $0.id == id }?.stock ?? product?.stock
    }
}

func priceText(_ value: Double?) -> String {
    let f = NumberFormatter()
    f.locale = Locale(identifier: "tr_TR")
    f.numberStyle = .decimal
    f.minimumFractionDigits = 2
    f.maximumFractionDigits = 2
    return (f.string(from: NSNumber(value: value ?? 0)) ?? "0") + " TL"
}
