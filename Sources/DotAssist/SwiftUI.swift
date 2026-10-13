#if os(iOS)
import SwiftUI

extension View {
    /// Ekranı asistana bildirir: ürün, kategori ve arama ekranlarında.
    ///
    /// Ekran her göründüğünde (geri dönüldüğünde de) ve içeriği değiştiğinde
    /// (ör. varyant seçildi) yeniden bildirilir.
    ///
    ///     ProductView(product)
    ///         .dotAssistScreen(.product(DotProduct(id: product.id)))
    public func dotAssistScreen(_ screen: DotScreen, url: String? = nil, title: String? = nil) -> some View {
        modifier(DotAssistScreenModifier(info: ScreenInfo(screen: screen, url: url, title: title)))
    }
}

private struct DotAssistScreenModifier: ViewModifier {
    let info: ScreenInfo

    /// Ekranın içeriği: değişmedikçe yeniden bildirme.
    private var key: String {
        let state = ScreenState.state(info, order: nil, cart: nil, user: nil)
        let data = try? JSONSerialization.data(withJSONObject: [state, info.url ?? ""], options: .sortedKeys)
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    func body(content: Content) -> some View {
        content
            .onAppear(perform: send)
            .onChange(of: key) { _ in send() }
    }

    private func send() {
        DotAssist.shared.setScreen(info.screen, url: info.url, title: info.title)
    }
}
#endif
