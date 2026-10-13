import Foundation

/// WebView'a yüklenen sayfa: köprü + widget. RN SDK'daki `html.ts`in karşılığı.
///
/// Sayfa `baseURL: https://<mağaza alan adı>/` ile yükleniyor: widget'ın API
/// istekleri o origin'den çıkıyor ve panelin izinli alan adı kontrolü web'deki
/// gibi geçiyor. Köprü `BridgeScript.swift`te (RN ve Android SDK'larında da aynısı).
enum Html {
    static let defaultWidgetSrc = "https://chat.dotassist.ai/widget/index.js"

    static func build(pid: String, widgetSrc: String, apiBase: String?, locale: String, test: Bool) -> String {
        let bridge = BridgeScript.source.replacingOccurrences(of: "__TEST__", with: test ? "true" : "false")
        let api = apiBase.map { " api=\"\(attr($0))\"" } ?? ""
        return "<!doctype html>"
            + "<html lang=\"\(attr(locale))\"><head>"
            + "<meta charset=\"utf-8\">"
            + "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1, maximum-scale=1, viewport-fit=cover\">"
            + "<style>html,body{margin:0;padding:0;background:transparent;}</style>"
            + "<script>\(bridge)</script>"
            + "<script id=\"dot\" async src=\"\(attr(widgetSrc))\" pid=\"\(attr(pid))\"\(api) "
            + "onload=\"window.__dotApp&&window.__dotApp.attach()\" "
            + "onerror=\"window.__dotApp&&window.__dotApp.post({type:'unavailable',data:{reason:'script'}})\"></script>"
            + "</head><body></body></html>"
    }

    static func attr(_ v: String) -> String {
        v.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
    }
}
