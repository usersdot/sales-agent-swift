import DotAssist
import SwiftUI

/// Dot Assist iOS SDK: örnek uygulama.
///
/// Mağaza (`pid`, `domain`) ve mod dışarıdan: `dot.config.json`. Varsayılan
/// Yataş Bedding, `mock` (`Example/` içinde `npm run mock` açık olmalı).
@main
struct DotAssistExampleApp: App {
    @StateObject private var model: AppModel

    init() {
        let store = StoreConfig.current
        let mock = StoreConfig.mockURL
        // Uygulama açılırken bir kez. Asistan kendi penceresinde, tüm ekranların üstünde.
        DotAssist.configure(store.isMock
            ? DotAssistOptions(pid: store.pid, domain: mock, test: true, inspectable: true, widgetSrc: mock + "/widget/index.js", apiBase: mock)
            : DotAssistOptions(pid: store.pid, domain: store.domain, test: true, inspectable: true))
        _model = StateObject(wrappedValue: AppModel())
    }

    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(model)
        }
    }
}
