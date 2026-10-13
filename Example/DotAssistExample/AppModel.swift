import DotAssist
import SwiftUI

enum Route: Hashable {
    case product(String)
    case cart
}

struct CartLine: Identifiable {
    let product: Product
    let productId: String
    var quantity: Int
    var id: String { productId }
}

/// Uygulamanın durumu ve asistan kancaları: gerçek bir mağaza uygulamasının
/// yapacağı her şey burada.
@MainActor
final class AppModel: ObservableObject {
    @Published var path: [Route] = []
    @Published var cart: [CartLine] = [] {
        // Sepet özeti asistanın bağlamına.
        didSet { DotAssist.shared.setCart(DotCart(total: total, itemCount: count, currency: "TRY")) }
    }
    @Published var favorites: Set<String> = []

    var count: Int { cart.reduce(0) { $0 + $1.quantity } }
    var total: Double { cart.reduce(0) { $0 + Double($1.quantity) * ($1.product.discountedPrice ?? $1.product.price ?? 0) } }

    init() {
        let dot = DotAssist.shared

        // Asistandaki karta dokunuldu → uygulamanın ürün ekranı.
        dot.onProductPress = { [weak self] product in
            self?.openProduct(product.id)
        }

        dot.onAddToCart = { [weak self] req in
            // `productId` seçilen varyantın kodu (ör. 160X200 cm · Beyaz).
            guard let self, let product = Product.find(req.productId) ?? Product.find(req.product.id) else { return .failed }
            // Tükendi → asistan kullanıcıyı ürün ekranına götürür.
            if Product.stock(of: req.productId) == "out_of_stock" { return .failed(navigate: true) }
            self.add(product, productId: req.productId, quantity: req.quantity)
            return .ok
        }

        dot.onFavorite = { [weak self] product, on in
            guard let self, let id = product.id else { return .failed }
            if on { self.favorites.insert(id) } else { self.favorites.remove(id) }
            return .ok
        }

        // Panel açık kalıyor: uyarı asistanın üstünde sunulmalı (`presenter`).
        dot.onOpenUrl = { url in
            let alert = UIAlertController(title: "Bağlantı", message: url.absoluteString, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Kapat", style: .cancel))
            alert.addAction(UIAlertAction(title: "Tarayıcıda aç", style: .default) { _ in UIApplication.shared.open(url) })
            DotAssist.shared.presenter?.present(alert, animated: true)
        }
        dot.onStatusChange = { print("[dot] durum:", $0.rawValue) }

        startCommandChannel()
    }

    func openProduct(_ id: String?) {
        guard let product = Product.find(id) else { return }
        path = [.product(product.id)]
    }

    func add(_ product: Product, productId: String, quantity: Int) {
        if let i = cart.firstIndex(where: { $0.productId == productId }) {
            cart[i].quantity += quantity
        } else {
            cart.append(CartLine(product: product, productId: productId, quantity: quantity))
        }
    }

    func checkout() -> String {
        let orderId = "DEMO-\(Int(Date().timeIntervalSince1970 * 1000))"
        DotAssist.shared.trackOrder(DotOrder(
            orderId: orderId,
            total: total,
            currency: "TRY",
            itemCount: count,
            productIds: cart.map(\.productId)
        ))
        cart = []
        return orderId
    }

    // MARK: - Test komutları (yalnızca geliştirme + mock)

    /// Simülatöre dokunmadan denemek için mock sunucunun kuyruğu:
    ///
    ///     cd Example && npm run cmd -- ask "alez"
    ///
    /// Komutlar: open, close, history, ask <soru>, product <id>, cart, home.
    private func startCommandChannel() {
        #if DEBUG
        guard StoreConfig.current.isMock, let url = URL(string: StoreConfig.mockURL + "/__cmd") else { return }
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let (data, _) = try? await URLSession.shared.data(from: url),
                      let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
                else { continue }
                for c in list {
                    self?.run(c["cmd"] as? String ?? "", c["arg"] as? String ?? "")
                }
            }
        }
        #endif
    }

    private func run(_ cmd: String, _ arg: String) {
        let dot = DotAssist.shared
        switch cmd {
        case "open": dot.open()
        case "close": dot.close()
        case "history": dot.openHistory()
        case "ask": dot.ask(arg)
        case "product": openProduct(arg)
        case "cart": path = [.cart]
        case "home": path = []
        default: break
        }
    }
}
