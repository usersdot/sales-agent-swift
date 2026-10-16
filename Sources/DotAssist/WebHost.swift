#if os(iOS)
import UIKit
@preconcurrency import WebKit

/// Widget'ın çalıştığı WKWebView ve köprünün native ucu.
///
/// Widget → uygulama: `window.webkit.messageHandlers.dotAssist.postMessage(<JSON metni>)`
/// (köprüdeki `post`). Uygulama → widget: `__dotApp.receive(...)`, `evaluateJavaScript` ile.
///
/// GÜVENLİK: sayfa mağazanın origin'inde çalışıyor ve imzalı üye kimliği alıyor.
/// - Köprü mesajı yalnızca mağaza origin'indeki ana sayfadan kabul ediliyor.
/// - Sayfa tek: bizim yüklememiz dışında ana çerçevede hiçbir gezinmeye izin yok.
///   Kullanıcının dokunduğu bağlantı uygulamaya (`onOpenUrl`; şema süzgeci orada).
/// - iOS 17+: ayrı veri deposu. Uygulamanın kendi WebView'larındaki mağaza çerezleri
///   ve localStorage'ı bu sayfadan görünmüyor.
@MainActor
final class WebHost: NSObject {
    let webView: WKWebView

    var onMessage: (([String: Any]) -> Void)?
    /// Sayfa yüklendi: artık mesaj gönderilebilir.
    var onLoaded: (() -> Void)?
    var onOpenUrl: ((String) -> Void)?
    /// Web içerik süreci öldü (bellek baskısı): yeniden yüklenmeli.
    var onCrash: (() -> Void)?

    private(set) var loaded = false
    /// Bizim başlattığımız yüklemenin adresi: yalnızca ona izin var.
    private var expected: URL?
    /// Mağazanın origin'i: köprü mesajı ve gönderilen durum yalnızca bu origin'deki sayfaya.
    private let originScheme: String
    private let originHost: String
    private let originPort: Int

    /// Widget'ın mesajları birkaç KB; bunun üstü bozuk ya da kötü niyetli.
    private static let maxMessage = 256 * 1024
    /// iOS 17+ ayrı veri deposunun kimliği (sabit: localStorage uygulama yeniden açılınca da yerinde).
    private static let storeID = UUID(uuidString: "6F1B0D2E-5C3A-4E7B-9A21-D07A55157D01")!

    init(origin: String, inspectable: Bool) {
        let o = URLComponents(string: origin)
        originScheme = o?.scheme?.lowercased() ?? ""
        originHost = o?.host?.lowercased() ?? ""
        originPort = o?.port ?? (originScheme == "http" ? 80 : 443)

        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        // localStorage kalıcı: sohbete devam (`newChatOnPageChange: false`) uygulama yeniden açılınca da.
        if #available(iOS 17.0, *) {
            config.websiteDataStore = WKWebsiteDataStore(forIdentifier: Self.storeID)
        } else {
            config.websiteDataStore = .default()
        }
        config.dataDetectorTypes = []
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()

        config.userContentController.add(WeakMessageHandler(self), name: "dotAssist")
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.allowsBackForwardNavigationGestures = false
        // Bağlantıya uzun basınca sistem önizlemesi açmasın (gezinme kurallarının dışında yükler).
        webView.allowsLinkPreview = false
        #if DEBUG
        if #available(iOS 16.4, *) { webView.isInspectable = inspectable }
        #endif
    }

    func load(html: String, baseURL: URL?) {
        loaded = false
        expected = baseURL
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    /// `__dotApp.receive(msg)`. Sayfa yüklenmeden gelen mesaj atılır (yükleme bitince durum
    /// zaten gönderiliyor). Gönderildiyse `true`.
    @discardableResult
    func send(_ msg: [String: Any]) -> Bool {
        guard loaded, isStore(webView.url) else { return false }
        guard JSONSerialization.isValidJSONObject(msg),
              let data = try? JSONSerialization.data(withJSONObject: msg),
              var json = String(data: data, encoding: .utf8)
        else {
            assertionFailure("[dot-assist] JSON'a çevrilemeyen değer (NaN, Date, URL…): mesaj gönderilmedi")
            return false
        }
        // JSON'da geçerli, eski JS motorlarında kaynak kodda satır sonu sayılan iki karakter.
        json = json.replacingOccurrences(of: "\u{2028}", with: "\\u2028").replacingOccurrences(of: "\u{2029}", with: "\\u2029")
        webView.evaluateJavaScript("window.__dotApp&&window.__dotApp.receive(\(json));true;", completionHandler: nil)
        return true
    }

    private func isStore(_ url: URL?) -> Bool {
        guard let url, let host = url.host?.lowercased() else { return false }
        let scheme = url.scheme?.lowercased() ?? ""
        return scheme == originScheme && host == originHost && (url.port ?? (scheme == "http" ? 80 : 443)) == originPort
    }

    private func isStore(_ origin: WKSecurityOrigin) -> Bool {
        let port = origin.port == 0 ? (origin.protocol == "http" ? 80 : 443) : origin.port
        return origin.protocol.lowercased() == originScheme && origin.host.lowercased() == originHost && port == originPort
    }
}

extension WebHost: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        // Yalnızca widget sayfası: iframe'lerden (ör. ödeme, video) gelen mesaj köprüye girmesin.
        guard message.frameInfo.isMainFrame,
              isStore(message.frameInfo.securityOrigin),
              let text = message.body as? String,
              text.utf8.count <= Self.maxMessage,
              let data = text.data(using: .utf8),
              let msg = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              msg["type"] is String
        else { return }
        onMessage?(msg)
    }
}

extension WebHost: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard isStore(webView.url) else { return }
        loaded = true
        onLoaded?()
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        // Alt çerçeveler (ör. gömülü video) kendi içinde gezinebilir; yeni pencere `createWebViewWith`'te.
        guard navigationAction.targetFrame?.isMainFrame == true else { return decisionHandler(.allow) }
        // Bizim yüklememiz (`loadHTMLString`): bir kez.
        if let expected, navigationAction.request.url == expected {
            self.expected = nil
            return decisionHandler(.allow)
        }
        // Widget sayfası tek sayfa: ana çerçevede başka gezinme yok. Kullanıcının dokunduğu
        // bağlantı uygulamaya; kendiliğinden olan (script, yönlendirme) yok sayılıyor.
        if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
            onOpenUrl?(url.absoluteString)
        }
        decisionHandler(.cancel)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        loaded = false
        onCrash?()
    }
}

extension WebHost: WKUIDelegate {
    /// `target="_blank"`: yeni pencere yok, uygulamaya.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
            onOpenUrl?(url.absoluteString)
        }
        return nil
    }
}

/// `WKUserContentController` işleyiciyi güçlü tutuyor: WebHost ↔ WebView döngüsü olmasın.
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?

    init(_ target: WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}
#endif
