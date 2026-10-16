import Foundation

/// Asistana verilen ürün: web sitesindeki `product` değişkeniyle AYNI biçim.
///
/// YALNIZCA `id` YETER: ad, fiyat, görsel ve varyantlar web sitesinden beslenen
/// katalogdan tamamlanıyor. Verdiğiniz dolu alanlar katalogdakinin önüne geçiyor
/// (yalnızca bu ekranda, kataloğa YAZILMIYOR).
///
/// ⚠ `id` web sitesindeki ürün kimliği olmalı. Uygulamanın kendi iç kimliği
/// farklıysa burada web'dekine çevirin.
public struct DotProduct {
    /// ZORUNLU. Yoksa ürün görüntüleme olayı atılmaz.
    public var id: String
    /// Varyantları gruplayan ana kimlik. Bilinmiyorsa vermeyin.
    public var mainProductId: String?
    public var name: String?
    public var brand: String?
    public var sku: String?
    /// Liste (üstü çizili) fiyat.
    public var price: Double?
    /// Ödenen fiyat. İndirim yoksa vermeyin.
    public var discountedPrice: Double?
    /// 3 harf: `TRY`.
    public var currency: String?
    /// Web sitesindeki ürün adresi.
    public var url: String?
    public var image: String?
    public var stock: DotStock?
    /// Genelden özele: `["Ev", "Mutfak", "Tencere"]`.
    public var categories: [String]?
    public var description: String?
    /// Bu ürünün eksen değerleri: `["Renk": "Mavi", "Beden": "M"]`.
    public var attributes: [String: String]?
    /// Ek alanlar, olduğu gibi gönderilir (JSON'a çevrilebilir değerler).
    public var extra: [String: Any]

    public init(
        id: String,
        mainProductId: String? = nil,
        name: String? = nil,
        brand: String? = nil,
        sku: String? = nil,
        price: Double? = nil,
        discountedPrice: Double? = nil,
        currency: String? = nil,
        url: String? = nil,
        image: String? = nil,
        stock: DotStock? = nil,
        categories: [String]? = nil,
        description: String? = nil,
        attributes: [String: String]? = nil,
        extra: [String: Any] = [:]
    ) {
        self.id = id
        self.mainProductId = mainProductId
        self.name = name
        self.brand = brand
        self.sku = sku
        self.price = price
        self.discountedPrice = discountedPrice
        self.currency = currency
        self.url = url
        self.image = image
        self.stock = stock
        self.categories = categories
        self.description = description
        self.attributes = attributes
        self.extra = extra
    }
}

public enum DotStock: String {
    case inStock = "in_stock"
    case outOfStock = "out_of_stock"
    case preorder
}

/// Asistanın uygulamaya verdiği ürün (kart).
public struct DotCardProduct {
    public let id: String?
    public let mainProductId: String?
    public let sku: String?
    public let name: String?
    public let brand: String?
    public let price: Double?
    public let discountedPrice: Double?
    public let currency: String?
    public let url: String?
    public let image: String?
    /// Önerinin geldiği sohbet turu.
    public let messageRef: String?
    /// Widget'ın gönderdiği alanların tamamı.
    public let raw: [String: Any]

    init(json: [String: Any]) {
        raw = json
        id = Self.string(json["id"])
        mainProductId = Self.string(json["mainProductId"])
        sku = Self.string(json["sku"])
        name = Self.string(json["name"])
        brand = Self.string(json["brand"])
        price = Self.number(json["price"])
        discountedPrice = Self.number(json["discountedPrice"])
        currency = Self.string(json["currency"])
        url = Self.string(json["url"])
        image = Self.string(json["image"])
        messageRef = Self.string(json["messageRef"])
    }

    /// Kimlikler widget'tan sayı olarak da gelebiliyor.
    static func string(_ v: Any?) -> String? {
        if let s = v as? String { return s }
        if let n = v as? NSNumber { return n.stringValue }
        return nil
    }

    /// Fiyat sayı ya da düz sayı metni ("1199.9"). Biçimli metin ("1.199,90 TL") nil.
    static func number(_ v: Any?) -> Double? {
        if let n = v as? NSNumber { return n.doubleValue }
        if let s = v as? String { return Double(s) }
        return nil
    }
}

public struct DotCategoryItem {
    public var id: String
    public var position: Int?
    public var page: Int?

    public init(id: String, position: Int? = nil, page: Int? = nil) {
        self.id = id
        self.position = position
        self.page = page
    }
}

public struct DotCategory {
    /// ZORUNLU. Kategori kimliği ya da yolu.
    public var categoryRef: String
    public var name: String?
    public var url: String?
    public var path: String?
    /// Listedeki ürünler, sırasıyla.
    public var items: [DotCategoryItem]?
    public var itemCount: Int?
    public var sort: String?
    public var extra: [String: Any]

    public init(
        categoryRef: String,
        name: String? = nil,
        url: String? = nil,
        path: String? = nil,
        items: [DotCategoryItem]? = nil,
        itemCount: Int? = nil,
        sort: String? = nil,
        extra: [String: Any] = [:]
    ) {
        self.categoryRef = categoryRef
        self.name = name
        self.url = url
        self.path = path
        self.items = items
        self.itemCount = itemCount
        self.sort = sort
        self.extra = extra
    }
}

public struct DotSearch {
    public var query: String
    public var resultCount: Int?
    public var extra: [String: Any]

    public init(query: String, resultCount: Int? = nil, extra: [String: Any] = [:]) {
        self.query = query
        self.resultCount = resultCount
        self.extra = extra
    }
}

public struct DotCart {
    public var total: Double?
    public var itemCount: Int?
    public var currency: String?

    public init(total: Double? = nil, itemCount: Int? = nil, currency: String? = nil) {
        self.total = total
        self.itemCount = itemCount
        self.currency = currency
    }
}

public struct DotOrder {
    /// ZORUNLU. Aynı sipariş bir kez sayılır.
    public var orderId: String
    public var total: Double?
    public var currency: String?
    public var itemCount: Int?
    public var productIds: [String]?
    public var coupon: String?

    public init(
        orderId: String,
        total: Double? = nil,
        currency: String? = nil,
        itemCount: Int? = nil,
        productIds: [String]? = nil,
        coupon: String? = nil
    ) {
        self.orderId = orderId
        self.total = total
        self.currency = currency
        self.itemCount = itemCount
        self.productIds = productIds
        self.coupon = coupon
    }
}

/// Giriş yapmış üye: mağazanın SUNUCUSUNDA imzalanmış kimlik.
///
///     sig = HMAC-SHA256(paylaşılanSır, "\(ref).\(exp)")
///
/// Sır uygulamaya GÖMÜLMEZ: imzayı mağazanın API'si üretir, uygulama oradan
/// alıp buraya verir. İmzasız kimlik sunucuda reddedilir, asistan anonim çalışır.
public struct DotUser {
    public var ref: String
    /// Unix saniye.
    public var exp: Int
    public var sig: String
    /// Opsiyonel kişisel bilgiler, yalnızca açıkça vermek isterseniz.
    public var profile: DotUserProfile?

    public init(ref: String, exp: Int, sig: String, profile: DotUserProfile? = nil) {
        self.ref = ref
        self.exp = exp
        self.sig = sig
        self.profile = profile
    }
}

public struct DotUserProfile {
    public var name: String?
    public var surname: String?
    public var email: String?
    public var phone: String?

    public init(name: String? = nil, surname: String? = nil, email: String? = nil, phone: String? = nil) {
        self.name = name
        self.surname = surname
        self.email = email
        self.phone = phone
    }
}

/// Uygulamanın o anki ekranı. Adres ve başlık `setScreen(_:url:title:)` ile verilir.
public enum DotScreen {
    case home
    case product(DotProduct)
    case category(DotCategory)
    case search(DotSearch)
    case cart
    case account
    case other(name: String?)
}

/// - `loading`: widget yükleniyor
/// - `ready`: asistan kullanılabilir, düğme görünür
/// - `unavailable`: bu mağaza için kapalı (veri toplama/test modu, alan adı izni, pasif)
/// - `error`: yüklenemedi (ağ). SDK kendiliğinden yeniden dener.
///
/// Neden (`statusReason`):
/// - `script`: widget indirilemedi (ağ), `error`
/// - `config_error`: mağaza ayarları alınamadı (ağ ya da izinsiz `domain`), `error`
/// - `timeout`: 20 sn içinde cevap yok, `error`
/// - `test_no_flag`: mağaza Test modunda, `test` verilmemiş
/// - `collecting`: mağaza Veri Toplama modunda
/// - `host`: `domain` mağaza için izinli değil
/// - `disabled`: asistan mağaza için kapalı
public enum DotStatus: String {
    case loading
    case ready
    case unavailable
    case error
}

/// Sepete ekleme isteği. `productId` eklenecek kod (seçilen varyantınki).
public struct DotAddToCartRequest {
    public let product: DotCardProduct
    public let productId: String
    public let quantity: Int
}

/// Sepet/favori kancalarının cevabı.
///
/// - `.ok`: başarılı
/// - `.failed`: başarısız. Sepette asistan ürün ekranına yönlendirir (`onProductPress`).
/// - `.failed(navigate: false)`: başarısız, yönlendirme yok
public struct DotHookResult {
    public let ok: Bool
    public let navigate: Bool?

    public static let ok = DotHookResult(ok: true, navigate: nil)
    public static let failed = DotHookResult(ok: false, navigate: nil)
    public static func failed(navigate: Bool) -> DotHookResult { DotHookResult(ok: false, navigate: navigate) }
}

public struct DotTheme {
    /// Widget'ın marka rengi (panelden), `#RRGGBB`.
    public let primary: String?
    /// Launcher metni (panelden).
    public let label: String?
}

public struct DotAssistOptions {
    /// Kurulum kodundaki `pid`.
    public var pid: String
    /// Mağazanın web alan adı, `www.teknosa.com`. Panelde izinli alan adlarında
    /// olmalı; WebView bu adres üzerinden çalışır.
    public var domain: String
    /// Test modu. Panelde mod "Test" iken asistan yalnızca bununla görünür.
    public var test: Bool
    /// Arayüz dili (`<html lang>`).
    public var locale: String
    /// Açık panelin zemin rengi (yüklenirken görünür).
    public var backgroundColor: String
    /// Safari Web Inspector ile incelenebilir WebView (iOS 16.4+). Yalnızca geliştirmede.
    public var inspectable: Bool
    /// Geliştirme: farklı bir widget paketi.
    public var widgetSrc: String?
    /// Geliştirme: farklı bir API kökü.
    public var apiBase: String?

    public init(
        pid: String,
        domain: String,
        test: Bool = false,
        locale: String = "tr",
        backgroundColor: String = "#ffffff",
        inspectable: Bool = false,
        widgetSrc: String? = nil,
        apiBase: String? = nil
    ) {
        self.pid = pid
        self.domain = domain
        self.test = test
        self.locale = locale
        self.backgroundColor = backgroundColor
        self.inspectable = inspectable
        self.widgetSrc = widgetSrc
        self.apiBase = apiBase
    }
}

/// Sağ alttaki asistan düğmesi: web sitesindekinin AYNISI (paneldeki ikon, şekil,
/// boyut, renk, rozet, metin).
public struct DotLauncher {
    /// `false`: düğme yok, kendi düğmenizden `open()`.
    public var visible: Bool
    /// Güvenli alanın altından uzaklık (pt). Sekme çubuğu varsa onun yüksekliğini ekleyin.
    public var bottom: Double
    /// Yan kenardan uzaklık (pt).
    public var side: Double

    public init(visible: Bool = true, bottom: Double = 24, side: Double = 16) {
        self.visible = visible
        self.bottom = bottom
        self.side = side
    }

    public static let hidden = DotLauncher(visible: false)
}

// MARK: - JSON (köprüye giden biçim)

/// Boş alanlar gönderilmez; `extra` en altta, tanımlı alanlar onun önüne geçer.
private func compact(_ extra: [String: Any], _ fields: [String: Any?]) -> [String: Any] {
    // `extra` uygulamadan serbest değer: JSON'a çevrilemeyen (Date, URL, NaN…) atılıyor.
    var out = extra.filter { JSONSerialization.isValidJSONObject([$0.value]) }
    for (k, v) in fields {
        guard let v else { continue }
        // NaN / sonsuz JSON'da yok: `JSONSerialization` istisna fırlatırdı.
        if let d = v as? Double, !d.isFinite { continue }
        out[k] = v
    }
    return out
}

extension DotProduct {
    var json: [String: Any] {
        compact(extra, [
            "id": id,
            "mainProductId": mainProductId,
            "name": name,
            "brand": brand,
            "sku": sku,
            "price": price,
            "discountedPrice": discountedPrice,
            "currency": currency,
            "url": url,
            "image": image,
            "stock": stock?.rawValue,
            "categories": categories,
            "description": description,
            "attributes": attributes,
        ])
    }
}

extension DotCategory {
    var json: [String: Any] {
        compact(extra, [
            "categoryRef": categoryRef,
            "name": name,
            "url": url,
            "path": path,
            "items": items?.map { compact([:], ["id": $0.id, "position": $0.position, "page": $0.page]) },
            "itemCount": itemCount,
            "sort": sort,
        ])
    }
}

extension DotSearch {
    var json: [String: Any] {
        compact(extra, ["query": query, "resultCount": resultCount])
    }
}

extension DotCart {
    var json: [String: Any] {
        compact([:], ["total": total, "itemCount": itemCount, "currency": currency])
    }
}

extension DotOrder {
    var json: [String: Any] {
        compact([:], [
            "orderId": orderId,
            "total": total,
            "currency": currency,
            "itemCount": itemCount,
            "productIds": productIds,
            "coupon": coupon,
        ])
    }
}

extension DotUser {
    var json: [String: Any] {
        compact([:], [
            "ref": ref,
            "exp": exp,
            "sig": sig,
            "user": profile.map { p in
                compact([:], ["name": p.name, "surname": p.surname, "email": p.email, "phone": p.phone])
            },
        ])
    }
}
