#if os(iOS)
import UIKit
@preconcurrency import WebKit

/// Widget'ın çalıştığı WKWebView ve köprünün native ucu.
///
/// Widget → uygulama: `window.webkit.messageHandlers.dotAssist.postMessage(<JSON metni>)`
/// (köprüdeki `post`). Uygulama → widget: `__dotApp.receive(...)`, `evaluateJavaScript` ile.
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
    /// İlk yükleme bitene kadar gezinmeye izin var; sonrası uygulamaya (`onOpenUrl`).
    private var initial = true

    init(inspectable: Bool) {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        // localStorage kalıcı: sohbete devam (`newChatOnPageChange: false`) uygulama yeniden açılınca da.
        config.websiteDataStore = .default()
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
        if #available(iOS 16.4, *) { webView.isInspectable = inspectable }
    }

    func load(html: String, baseURL: URL?) {
        loaded = false
        initial = true
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    /// `__dotApp.receive(msg)`. Sayfa yüklenmeden gelen mesaj atılır (yükleme bitince durum zaten gönderiliyor).
    func send(_ msg: [String: Any]) {
        guard loaded,
              JSONSerialization.isValidJSONObject(msg),
              let data = try? JSONSerialization.data(withJSONObject: msg),
              var json = String(data: data, encoding: .utf8)
        else { return }
        // JSON'da geçerli, eski JS motorlarında kaynak kodda satır sonu sayılan iki karakter.
        json = json.replacingOccurrences(of: "\u{2028}", with: "\\u2028").replacingOccurrences(of: "\u{2029}", with: "\\u2029")
        webView.evaluateJavaScript("window.__dotApp&&window.__dotApp.receive(\(json));true;", completionHandler: nil)
    }
}

extension WebHost: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        // Yalnızca widget sayfası: iframe'lerden (ör. ödeme, video) gelen mesaj köprüye girmesin.
        guard message.frameInfo.isMainFrame,
              let text = message.body as? String,
              let data = text.data(using: .utf8),
              let msg = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              msg["type"] is String
        else { return }
        onMessage?(msg)
    }
}

extension WebHost: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loaded = true
        initial = false
        onLoaded?()
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard !initial, navigationAction.targetFrame?.isMainFrame != false, let url = navigationAction.request.url else {
            return decisionHandler(.allow)
        }
        if ["about", "data", "blob"].contains(url.scheme?.lowercased() ?? "") { return decisionHandler(.allow) }
        // Widget sayfası tek sayfa: başka her gezinme uygulamaya.
        onOpenUrl?(url.absoluteString)
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
        if let url = navigationAction.request.url { onOpenUrl?(url.absoluteString) }
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
