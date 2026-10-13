import XCTest
@testable import DotAssist

/// Ortak vakalar: aynı dosya (`Fixtures/screen.json`) RN (`test/fixtures/screen.json`) ve
/// Android (`dotassist/src/test/resources/screen.json`) SDK'larında da var.
/// Bir vaka eklerseniz ya da değiştirirseniz üçüne birden uygulayın.
final class ScreenStateTests: XCTestCase {
    private struct Fixture {
        let origin: String
        let cases: [[String: Any]]
        let origins: [[String]]
    }

    private func fixture() throws -> Fixture {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "screen", withExtension: "json", subdirectory: "Fixtures"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        return Fixture(
            origin: try XCTUnwrap(json["origin"] as? String),
            cases: try XCTUnwrap(json["cases"] as? [[String: Any]]),
            origins: try XCTUnwrap(json["origins"] as? [[String]])
        )
    }

    func testSharedCases() throws {
        let f = try fixture()
        XCTAssertGreaterThan(f.cases.count, 10)
        for c in f.cases {
            let name = c["name"] as? String ?? "?"
            let screen = (c["screen"] as? [String: Any]).map(Self.screen)
            let order = (c["order"] as? [String: Any]).map(Self.order)
            let cart = (c["cart"] as? [String: Any]).map(Self.cart)
            let user = (c["user"] as? [String: Any]).map(Self.user)
            let expect = try XCTUnwrap(c["expect"] as? [String: Any])

            let state = ScreenState.state(screen, order: order, cart: cart, user: user)
            XCTAssertEqual(state as NSDictionary, expect["state"] as? NSDictionary, name)
            XCTAssertEqual(ScreenState.url(origin: f.origin, screen, order: order), expect["url"] as? String, name)
            let identity = ScreenState.identity(user).map { $0 as NSDictionary }
            XCTAssertEqual(identity, expect["identity"] as? NSDictionary, name)
        }
    }

    func testOrigins() throws {
        for pair in try fixture().origins {
            XCTAssertEqual(ScreenState.origin(of: pair[0]), pair[1])
        }
    }

    func testHtml() {
        let html = Html.build(pid: "abc\"><x", widgetSrc: "https://chat.dotassist.ai/widget/index.js", apiBase: nil, locale: "tr", test: true)
        XCTAssertTrue(html.contains("pid=\"abc&quot;>&lt;x\""))
        XCTAssertTrue(html.contains("var TEST = true;"))
        XCTAssertFalse(html.contains(" api=\""))
        XCTAssertFalse(html.contains("__TEST__"))
        XCTAssertTrue(html.contains("messageHandlers.dotAssist"))

        let withApi = Html.build(pid: "p", widgetSrc: "https://x/w.js", apiBase: "https://api.x", locale: "en", test: false)
        XCTAssertTrue(withApi.contains(" api=\"https://api.x\""))
        XCTAssertTrue(withApi.contains("<html lang=\"en\">"))
        XCTAssertTrue(withApi.contains("var TEST = false;"))
    }

    func testCardProductFromWidget() {
        let p = DotCardProduct(json: ["id": 42, "price": "1199.9", "discountedPrice": 999, "name": "Alez", "messageRef": "m1"])
        XCTAssertEqual(p.id, "42")
        XCTAssertEqual(p.price, 1199.9)
        XCTAssertEqual(p.discountedPrice, 999)
        XCTAssertEqual(p.messageRef, "m1")
        XCTAssertNil(DotCardProduct(json: ["price": "1.199,90 TL"]).price)
    }

    func testHex() {
        XCTAssertNotNil(UIColor(dotHex: "#131E29"))
        XCTAssertNotNil(UIColor(dotHex: "fff"))
        XCTAssertNil(UIColor(dotHex: "mavi"))
    }

    // MARK: - Fixture JSON → genel modeller

    private static let productKeys: Set = ["id", "mainProductId", "name", "brand", "sku", "price", "discountedPrice", "currency", "url", "image", "stock", "categories", "description", "attributes"]

    private static func screen(_ s: [String: Any]) -> ScreenInfo {
        let kind: DotScreen
        switch s["type"] as? String {
        case "product":
            let p = s["product"] as? [String: Any] ?? [:]
            kind = .product(DotProduct(
                id: p["id"] as? String ?? "",
                mainProductId: p["mainProductId"] as? String,
                name: p["name"] as? String,
                brand: p["brand"] as? String,
                sku: p["sku"] as? String,
                price: p["price"] as? Double,
                discountedPrice: p["discountedPrice"] as? Double,
                currency: p["currency"] as? String,
                url: p["url"] as? String,
                image: p["image"] as? String,
                stock: (p["stock"] as? String).flatMap(DotStock.init(rawValue:)),
                categories: p["categories"] as? [String],
                description: p["description"] as? String,
                attributes: p["attributes"] as? [String: String],
                extra: p.filter { !productKeys.contains($0.key) }
            ))
        case "category":
            let c = s["category"] as? [String: Any] ?? [:]
            kind = .category(DotCategory(
                categoryRef: c["categoryRef"] as? String ?? "",
                name: c["name"] as? String,
                url: c["url"] as? String,
                path: c["path"] as? String,
                items: (c["items"] as? [[String: Any]])?.map {
                    DotCategoryItem(id: $0["id"] as? String ?? "", position: $0["position"] as? Int, page: $0["page"] as? Int)
                },
                itemCount: c["itemCount"] as? Int,
                sort: c["sort"] as? String
            ))
        case "search":
            let q = s["search"] as? [String: Any] ?? [:]
            kind = .search(DotSearch(query: q["query"] as? String ?? "", resultCount: q["resultCount"] as? Int))
        case "cart": kind = .cart
        case "account": kind = .account
        case "other": kind = .other(name: s["name"] as? String)
        default: kind = .home
        }
        return ScreenInfo(screen: kind, url: s["url"] as? String, title: s["title"] as? String)
    }

    private static func order(_ o: [String: Any]) -> DotOrder {
        DotOrder(
            orderId: o["orderId"] as? String ?? "",
            total: o["total"] as? Double,
            currency: o["currency"] as? String,
            itemCount: o["itemCount"] as? Int,
            productIds: o["productIds"] as? [String],
            coupon: o["coupon"] as? String
        )
    }

    private static func cart(_ c: [String: Any]) -> DotCart {
        DotCart(total: c["total"] as? Double, itemCount: c["itemCount"] as? Int, currency: c["currency"] as? String)
    }

    private static func user(_ u: [String: Any]) -> DotUser {
        let p = u["user"] as? [String: Any]
        return DotUser(
            ref: u["ref"] as? String ?? "",
            exp: u["exp"] as? Int ?? 0,
            sig: u["sig"] as? String ?? "",
            profile: p.map { DotUserProfile(name: $0["name"] as? String, surname: $0["surname"] as? String, email: $0["email"] as? String, phone: $0["phone"] as? String) }
        )
    }
}
