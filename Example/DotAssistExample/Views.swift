import DotAssist
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack(path: $model.path) {
            HomeView()
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case let .product(id):
                        if let product = Product.find(id) { ProductView(product: product) }
                    case .cart:
                        CartView()
                    }
                }
        }
        .tint(Color(red: 0.07, green: 0.12, blue: 0.16))
    }
}

/// Asistanın durumu: geliştirirken görmek için.
struct StatusRow: View {
    @ObservedObject private var dot = DotAssist.shared

    var body: some View {
        let store = StoreConfig.current
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text("Asistan:")
                Text(dot.status.rawValue).bold().foregroundColor(.primary)
                if let reason = dot.statusReason { Text("(\(reason))") }
                Text("· mod: \(store.isMock ? "mock" : "live")")
                if let color = dot.theme?.primaryColor {
                    Circle().fill(Color(color)).frame(width: 10, height: 10)
                }
            }
            Text("\(store.domain) · pid \(store.pid.prefix(8))…")
            // UI testi: panel kapalıyken klavye ve odak uygulamada kalmalı.
            Text("anahtar pencere: " + keyWindowName).accessibilityIdentifier("keyWindow")
        }
        .font(.caption)
        .foregroundColor(.secondary)
    }
}

private var keyWindowName: String {
    let ws = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
    return ws.first { $0.isKeyWindow }.map { String(describing: type(of: $0)) } ?? "none"
}

struct CartButton: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Button("Sepet (\(model.count))") { model.path.append(.cart) }
            .fontWeight(.semibold)
    }
}

struct HomeView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List {
            Section { StatusRow() }
            Section("Ürünler") {
                ForEach(Product.all) { p in
                    NavigationLink(value: Route.product(p.id)) {
                        HStack(spacing: 12) {
                            Thumb(url: p.image).frame(width: 64, height: 64)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(p.name).font(.subheadline.weight(.semibold))
                                Text(priceText(p.discountedPrice ?? p.price)).font(.subheadline.bold())
                                if p.soldOut { Text("Tükendi").font(.caption).foregroundColor(.red) }
                            }
                        }
                    }
                }
            }
            Section("Kendi düğmenizle") {
                Button("Asistanı aç") { DotAssist.shared.open() }
                Button("Soru sor") { DotAssist.shared.ask("Sıvı geçirmez alez önerir misin?") }
                Button("Geçmiş") { DotAssist.shared.openHistory() }
            }
        }
        .navigationTitle("Yataş Bedding · örnek")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { CartButton() }
        .dotAssistScreen(.home)
    }
}

struct ProductView: View {
    @EnvironmentObject private var model: AppModel
    let product: Product

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                StatusRow()
                // Kare çerçeve; görsel taşmasın diye içinde doldur-kırp.
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(Thumb(url: product.image))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                Text(product.name).font(.title3.bold())
                HStack(alignment: .firstTextBaseline) {
                    Text(priceText(product.discountedPrice ?? product.price)).bold()
                    if product.discountedPrice != nil {
                        Text(priceText(product.price)).font(.footnote).strikethrough().foregroundColor(.secondary)
                    }
                }
                if let attrs = product.attributes {
                    Text(attrs.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: " · "))
                        .font(.subheadline).foregroundColor(.secondary)
                }
                if model.favorites.contains(product.id) {
                    Text("♥ Favorilerinizde").font(.footnote).foregroundColor(.red)
                }
                Text(product.description ?? "").font(.subheadline).foregroundColor(.secondary)
                HStack {
                    Button(product.soldOut ? "Tükendi" : "Sepete ekle") {
                        model.add(product, productId: product.id, quantity: 1)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(product.soldOut)
                    Button("Bu ürünü sor") { DotAssist.shared.ask("Bu alez makinede yıkanır mı?") }
                        .buttonStyle(.bordered)
                }
            }
            .padding()
            .padding(.bottom, 100)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { CartButton() }
        // YALNIZCA KİMLİK: ad, fiyat, görsel ve varyantlar mağazanın kataloğundan.
        .dotAssistScreen(.product(DotProduct(id: product.id)))
    }
}

struct CartView: View {
    @EnvironmentObject private var model: AppModel
    @State private var placed: String?

    var body: some View {
        List {
            Section { StatusRow() }
            if model.cart.isEmpty {
                Text("Sepet boş. Asistandan da ürün ekleyebilirsiniz.").foregroundColor(.secondary)
            }
            ForEach(model.cart) { line in
                VStack(alignment: .leading) {
                    Text(line.product.name).font(.subheadline.weight(.semibold))
                    Text("\(line.quantity) adet · kod \(line.productId)").font(.caption).foregroundColor(.secondary)
                }
            }
            if !model.cart.isEmpty {
                Section {
                    Text("Toplam: \(priceText(model.total))").bold()
                    Button("Siparişi tamamla") { placed = model.checkout() }
                }
            }
        }
        .navigationTitle("Sepet")
        .dotAssistScreen(.cart)
        .alert("Sipariş alındı", isPresented: Binding(get: { placed != nil }, set: { if !$0 { placed = nil } })) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text(placed ?? "")
        }
    }
}

struct Thumb: View {
    let url: String?

    var body: some View {
        AsyncImage(url: url.flatMap(URL.init(string:))) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Color(.secondarySystemBackground)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
