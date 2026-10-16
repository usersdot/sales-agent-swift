import XCTest

/// UÇTAN UCA: SDK'nın dört kancası gerçek dokunuşla.
///
/// Mock sunucu açık olmalı (`cd Example && npm run mock`) ve
/// `dot.config.json` → `mode: "mock"`. Widget'ın içi WebView'ın erişilebilirlik
/// ağacından bulunuyor (etiketler panelin Türkçe metinleri).
final class AssistantFlowTests: XCTestCase {
    private let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
        app.launch()
    }

    /// Widget içindeki öğe (WebView'da, etiketinde `label` geçen).
    private func web(_ label: String) -> XCUIElement {
        app.webViews.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", label)).firstMatch
    }

    /// Bulunamazsa ağacı döküp durur: widget metni değiştiyse etiket buradan okunur.
    @discardableResult
    private func wait(_ element: XCUIElement, _ what: String, timeout: TimeInterval = 10) -> XCUIElement {
        if !element.waitForExistence(timeout: timeout) {
            print(app.debugDescription)
            XCTFail("bulunamadı: \(what)")
        }
        return element
    }

    private var launcher: XCUIElement { web("Yataş'a sor") }

    /// Hazır olunca web launcher'ı görünür; panel kapalıyken klavye/odak uygulamada.
    func testLauncherAndKeyWindow() {
        wait(launcher, "launcher", timeout: 20)
        XCTAssertEqual(app.staticTexts["keyWindow"].label, "anahtar pencere: UIWindow")
        // Uygulamanın kendi düğmeleri asistan penceresinin altında da dokunulabilir.
        app.buttons["Frio Full Kenar Sıvı Geçirmez Alez, 1.199,90 TL"].tap()
        wait(app.buttons["Bu ürünü sor"], "uygulamanın ürün ekranı")
    }

    /// Ürün ekranı yalnızca kimlik veriyor; bağlam kartı katalogdan dolu. Sepete ekle → `onAddToCart`.
    func testContextCardAddToCart() {
        wait(launcher, "launcher", timeout: 20)
        app.buttons["Frio Full Kenar Sıvı Geçirmez Alez, 1.199,90 TL"].tap()
        launcher.tap()
        wait(web("1.299,90 TL"), "bağlam kartı (katalogdan fiyat)")
        web("Sepete ekle").tap()
        // Varyantlı ürün: seçici açılıyor, boyut seçilmeden "Sepete Ekle" pasif.
        wait(app.webViews.switches["180X200 cm"], "varyant seçici").tap()
        app.webViews.buttons["Sepete Ekle"].tap()
        sleep(2)
        app.webViews.buttons["Kapat"].firstMatch.tap()
        wait(app.buttons["Sepet (1)"], "uygulamanın sepeti (onAddToCart)").tap()
        // Kancaya seçilen varyantın kodu geldi.
        wait(app.staticTexts["1 adet · kod 1556426"], "seçilen varyant")
    }

    /// Soru → cevap; cevaptaki bağlantı → `onOpenUrl` (uyarı panelin ÜSTÜNDE, `presenter`);
    /// cevaptaki ürün → `onProductPress` (panel kapanır, uygulamanın ürün ekranı).
    func testAskLinkAndProductPress() {
        wait(launcher, "launcher", timeout: 20)
        launcher.tap()
        let field = wait(app.webViews.textViews["Mesajınızı yazın…"], "mesaj kutusu")
        field.tap()
        wait(app.keyboards.firstMatch, "klavye (asistan penceresi anahtar olabilmeli)", timeout: 5)
        field.typeText("alez önerir misin")
        app.webViews.buttons["Gönder"].tap()
        wait(web("mock sunucudan"), "cevap", timeout: 30) // ilk soru: soğuk WebView + oturum açılışı

        app.webViews.links["ürün sayfası"].tap()
        let alert = wait(app.alerts["Bağlantı"], "onOpenUrl uyarısı")
        XCTAssertTrue(alert.isHittable, "uyarı panelin altında kaldı")
        alert.buttons["Kapat"].tap()

        web("sonuç görüntüleniyor").tap()
        wait(web("Standart Alez"), "sonuç paneli").tap()
        wait(app.buttons["Tükendi"], "uygulamanın ürün ekranı (onProductPress)")
        XCTAssertTrue(app.buttons["Tükendi"].isHittable, "panel kapanmadı")
    }

    /// Sepet → sipariş: `trackOrder` (mock konsolunda `order_completed`).
    func testCheckout() {
        wait(launcher, "launcher", timeout: 20)
        app.buttons["Frio Full Kenar Sıvı Geçirmez Alez, 1.199,90 TL"].tap()
        app.buttons["Sepete ekle"].tap()
        app.buttons["Sepet (1)"].tap()
        app.buttons["Siparişi tamamla"].tap()
        wait(app.alerts["Sipariş alındı"], "sipariş uyarısı").buttons["Tamam"].tap()
        wait(app.staticTexts["Sepet boş. Asistandan da ürün ekleyebilirsiniz."], "boş sepet")
    }
}
