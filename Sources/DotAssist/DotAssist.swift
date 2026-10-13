#if os(iOS)
import Combine
import UIKit

/// DOT ASSIST: alışveriş asistanı.
///
/// Widget, mağazanın alan adıyla yüklenen bir WebView'da sürekli çalışıyor:
/// sohbet ekranlar arasında korunuyor ve ekran olayları (ürün görüntüleme,
/// sipariş) panel kapalıyken de ölçülüyor. WebView uygulamanın üstündeki ayrı
/// bir pencerede: panel kapalıyken yalnızca sağ alttaki düğme kadar yer kaplıyor,
/// açılınca tam ekran.
///
///     DotAssist.configure(DotAssistOptions(pid: "…", domain: "www.magaza.com"))
///     DotAssist.shared.onProductPress = { product in … }
///     DotAssist.shared.setScreen(.product(DotProduct(id: "1556424")))
///
/// SwiftUI'da durum (`status`, `isOpen`, `theme`) `@ObservedObject` ile izlenebilir.
@MainActor
public final class DotAssist: ObservableObject {
    public static let shared = DotAssist()

    /// Uygulama açılırken bir kez (`AppDelegate` ya da SwiftUI `App.init`).
    public static func configure(_ options: DotAssistOptions) {
        shared.configure(options)
    }

    // MARK: - Durum

    @Published public private(set) var status: DotStatus = .loading {
        didSet { if status != oldValue { statusChanged() } }
    }

    /// Durumun nedeni: `ready` değilken dolu (bkz. `DotStatus`).
    @Published public private(set) var statusReason: String?

    @Published public private(set) var isOpen = false {
        didSet {
            guard isOpen != oldValue else { return }
            openChanged()
            if isOpen { onOpen?() } else { onClose?() }
        }
    }

    /// Panelden gelen marka rengi ve launcher metni (`ready` olunca).
    @Published public private(set) var theme: DotTheme?

    // MARK: - Uygulamanın kancaları

    /// Asistandaki ürüne dokunuldu. Verilmezse `url` tarayıcıda açılır.
    /// Uygulamanın ürün ekranına götürün. Panel önce kapanıyor.
    public var onProductPress: (@MainActor (DotCardProduct) -> Void)?
    /// Asistandan sepete ekleme. Verilmezse asistan ürün ekranına yönlendirir.
    public var onAddToCart: (@MainActor (DotAddToCartRequest) async throws -> DotHookResult)?
    /// Favori ekle/çıkar. Verilmezse yalnızca analize yazılır.
    public var onFavorite: (@MainActor (DotCardProduct, Bool) async throws -> DotHookResult)?
    /// Cevap içindeki bağlantı. Verilmezse sistem açar (`UIApplication.open`).
    /// Panel açık kalır: kendi ekranınızı açacaksanız `presenter` üzerinden sunun.
    public var onOpenUrl: (@MainActor (URL) -> Void)?
    public var onStatusChange: (@MainActor (DotStatus) -> Void)?
    public var onOpen: (@MainActor () -> Void)?
    public var onClose: (@MainActor () -> Void)?

    /// Giriş yapmış üye. Üye değişince (giriş/çıkış) WebView yeniden yüklenir:
    /// oturum kimliği widget'ın açılışta aldığı token'da. Aynı üyenin yenilenen
    /// imzası (süre uzadı) yalnızca gönderilir.
    public var user: DotUser? {
        didSet {
            if (oldValue?.ref ?? "") != (user?.ref ?? "") {
                load()
            } else if oldValue?.sig != user?.sig || oldValue?.exp != user?.exp {
                sendState()
            }
        }
    }

    /// Sağ alttaki düğmenin konumu ya da `.hidden`.
    public var launcher = DotLauncher() {
        didSet {
            controller?.launcher = launcher
            layout()
        }
    }

    // MARK: - İç durum

    private var options: DotAssistOptions?
    private var origin = ""
    private var host: WebHost?
    private var controller: OverlayController?
    private var window: OverlayWindow?
    private weak var scene: UIWindowScene?
    /// Panel açılmadan önceki anahtar pencere: kapanınca klavye/odak ona döner.
    private weak var previousKeyWindow: UIWindow?

    private var screen: ScreenInfo?
    private var order: DotOrder?
    private var cart: DotCart?
    private var box: LauncherBox?

    /// Her yüklemede artıyor: eski yüklemenin zamanlayıcısı yenisini etkilemesin.
    private var generation = 0
    /// İlk yükleme yapıldı mı (sahne beklenirken `false`).
    private var started = false
    private var attempts = 0
    private var retry: DispatchWorkItem?
    /// Hazır değilken gelen açma isteği (`open`, `ask`, `openHistory`): `ready` gelince yapılır.
    private var pending: (method: String, args: [Any])?
    private var observers: [NSObjectProtocol] = []

    /// Widget hiç cevap vermezse (ağ yok, script yüklenmedi) `error`.
    private static let bootTimeout: TimeInterval = 20
    /// `error` durumunda yeniden deneme aralıkları; sonuncusu tekrarlanır.
    private static let retryDelays: [TimeInterval] = [3, 10, 30, 60]
    /// Bu nedenler kalıcı değil (ağ): `error` + yeniden deneme; diğerleri `unavailable`.
    private static let retryable: Set<String> = ["script", "config_error"]

    private static let reasonHint: [String: String] = [
        "script": "widget script'i indirilemedi (ağ / widgetSrc / yerel mock sunucu kapalı olabilir)",
        "config_error": "mağaza ayarları alınamadı (ağ yok ya da `domain` mağaza için izinli değil)",
        "timeout": "widget 20 sn içinde cevap vermedi",
        "collecting": "mağaza \"Veri Toplama\" modunda, asistan görünmez",
        "test_no_flag": "mağaza \"Test\" modunda, `test: true` verin",
        "host": "`domain` mağaza için izinli değil",
        "disabled": "asistan mağaza için kapalı",
    ]

    private init() {}

    // MARK: - Kurulum

    public func configure(_ options: DotAssistOptions) {
        self.options = options
        origin = ScreenState.origin(of: options.domain)

        if observers.isEmpty {
            let center = NotificationCenter.default
            observers.append(center.addObserver(forName: UIScene.didActivateNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.window == nil, self.attachWindow(), !self.started else { return }
                    self.load()
                }
            })
            // Ön plana dönünce ağ hatası hemen yeniden denensin.
            observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.status == .error else { return }
                    self.load()
                }
            })
        }

        // Etkin sahne yoksa (SwiftUI `App.init`, `application(_:didFinishLaunchingWithOptions:)`)
        // kurulum ve yükleme sahne etkinleşince.
        guard attachWindow() else { return }
        controller?.openBackground = UIColor(dotHex: options.backgroundColor) ?? .white
        load()
    }

    /// Birden fazla pencereli (iPad) uygulamalar: asistanın görüneceği sahne.
    /// Verilmezse ilk etkin sahne kullanılır.
    public func attach(to scene: UIWindowScene) {
        guard scene !== window?.windowScene else { return }
        window?.isHidden = true
        window = nil
        self.scene = scene
        if attachWindow(), !started { load() }
    }

    /// Katman penceresi ve WebView. WebView ancak etkin bir sahne varken oluşturuluyor:
    /// uygulama açılışında (sahneden önce) oluşturulan WKWebView'a ilk dokunuşta UIKit'in
    /// jest motoru çöküyor (iOS 18, `UIGestureGraphEdge`: "Invalid parameter not satisfying: targetNode").
    ///
    /// - Returns: pencere hazır mı.
    @discardableResult
    private func attachWindow() -> Bool {
        if window != nil { return true }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let options,
              let target = scene
                ?? scenes.first(where: { $0.activationState == .foregroundActive })
                ?? scenes.first(where: { $0.activationState == .foregroundInactive })
        else { return false }

        if host == nil {
            let web = WebHost(inspectable: options.inspectable)
            web.onMessage = { [weak self] in self?.handle($0) }
            web.onLoaded = { [weak self] in self?.sendState() }
            web.onOpenUrl = { [weak self] in self?.openUrl($0) }
            web.onCrash = { [weak self] in self?.load() }
            host = web
            let c = OverlayController(content: web.webView)
            c.launcher = launcher
            c.openBackground = UIColor(dotHex: options.backgroundColor) ?? .white
            controller = c
        }

        let w = OverlayWindow(windowScene: target)
        w.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.normal.rawValue + 1)
        w.backgroundColor = .clear
        w.rootViewController = controller
        w.isHidden = false
        window = w
        layout()
        return true
    }

    // MARK: - Yükleme ve durum

    /// Yeni yükleme (ilk kurulum, üye değişimi, çökme, yeniden deneme): durum baştan.
    private func load() {
        guard let options, let host else { return }
        started = true
        generation += 1
        let gen = generation
        retry?.cancel()
        retry = nil
        statusReason = nil
        status = .loading
        isOpen = false
        box = nil
        layout()

        // Yalnızca hâlâ yükleniyorsa: `ready` sonrası tetiklenip nedeni `timeout` yazmasın.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.bootTimeout) { [weak self] in
            guard let self, self.generation == gen, self.status == .loading else { return }
            self.statusReason = "timeout"
            self.status = .error
        }

        let html = Html.build(
            pid: options.pid,
            widgetSrc: options.widgetSrc ?? Html.defaultWidgetSrc,
            apiBase: options.apiBase,
            locale: options.locale,
            test: options.test
        )
        host.load(html: html, baseURL: URL(string: origin + "/" + (options.test ? "?dot=true" : "")))
    }

    private func statusChanged() {
        onStatusChange?(status)
        if status == .ready { attempts = 0 }
        if status == .unavailable { pending = nil }
        #if DEBUG
        if status == .error || status == .unavailable {
            let hint = statusReason.map { " (\($0)): " + (Self.reasonHint[$0] ?? "") } ?? ""
            print("[dot-assist] \(status.rawValue)\(hint)")
        }
        #endif

        // AĞ HATASINDA KENDİLİĞİNDEN YENİDEN DENE: artan aralıkla. Mağazada kapalıysa (`unavailable`) denenmiyor.
        retry?.cancel()
        retry = nil
        if status == .error {
            let delays = Self.retryDelays
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.attempts += 1
                self.load()
            }
            retry = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delays[min(attempts, delays.count - 1)], execute: work)
        }
        layout()
    }

    private func openChanged() {
        if isOpen {
            // Klavye bu pencereye gelebilsin: yazı alanına dokununca UIKit anahtar yapıyor.
            // ⚠ `makeKey()` burada ÇAĞRILMIYOR: launcher'a dokunuş sürerken anahtar pencere
            // değişince UIKit'in jest motoru çöküyor (iOS 18, `UIGestureGraphEdge`).
            previousKeyWindow = appWindows.first { $0.isKeyWindow }
            window?.allowsKey = true
        } else {
            window?.allowsKey = false
            if window?.isKeyWindow == true { (previousKeyWindow ?? appWindows.first)?.makeKey() }
        }
        layout()
    }

    /// Sahnedeki uygulama pencereleri (asistanınki hariç).
    private var appWindows: [UIWindow] {
        window?.windowScene?.windows.filter { $0 !== window && !$0.isHidden } ?? []
    }

    private func layout() {
        guard let controller else { return }
        if isOpen {
            controller.mode = .open
        } else if launcher.visible, status == .ready, let box {
            controller.mode = .launcher(box)
        } else {
            controller.mode = .hidden
        }
    }

    /// Asistanın ÜSTÜNDE ekran sunmak için (uyarı, tarayıcı, giriş ekranı).
    ///
    /// Asistan uygulamanın üstündeki ayrı bir pencerede: panel açıkken uygulamanın
    /// kendi ekranından sunulan her şey panelin ALTINDA kalır. Panel açıkken asistanın,
    /// kapalıyken uygulamanın en üstteki ekranını verir.
    ///
    ///     DotAssist.shared.presenter?.present(SFSafariViewController(url: url), animated: true)
    public var presenter: UIViewController? {
        guard let controller else { return nil }
        var top: UIViewController? = isOpen ? controller : controller.host
        while let presented = top?.presentedViewController, !presented.isBeingDismissed { top = presented }
        return top
    }

    // MARK: - Uygulama → widget

    private func sendState() {
        host?.send([
            "type": "state",
            "state": ScreenState.state(screen, order: order, cart: cart, user: user),
            "user": ScreenState.identity(user) ?? NSNull(),
            "url": ScreenState.url(origin: origin, screen, order: order),
        ])
    }

    private func call(_ method: String, _ args: [Any] = []) {
        host?.send(["type": "call", "method": method, "args": args])
    }

    /// Paneli açan çağrılar. Hazırsa hemen; yükleniyorsa ya da ağ hatasındaysa
    /// istek saklanıyor (hatada yeniden deneme de hemen başlıyor) ve `ready`
    /// gelince yapılıyor. Mağazada kapalıysa (`unavailable`) hiçbir şey olmuyor.
    private func show(_ method: String, _ args: [Any] = []) {
        switch status {
        case .ready:
            isOpen = true
            call(method, args)
        case .unavailable:
            return
        case .loading:
            pending = (method, args)
        case .error:
            pending = (method, args)
            attempts = 0
            load()
        }
    }

    // MARK: - Genel API

    public func open() { show("open") }

    public func close() {
        isOpen = false
        call("close")
    }

    public func toggle() { isOpen ? close() : open() }

    /// Paneli açıp soruyu gönderir.
    public func ask(_ question: String) {
        guard !question.isEmpty else { return }
        show("ask", [question])
    }

    public func openHistory() { show("openHistory") }

    public func newChat() { call("newChat") }

    /// Ekran değişti: ürün/kategori/arama bilgisini asistana verir. Ekran her
    /// göründüğünde çağırın (`viewDidAppear`, SwiftUI'da `.dotAssistScreen`).
    ///
    /// - Parameters:
    ///   - url: ekranın web sitesindeki karşılığı. Analizde web sayfasıyla aynı görünür.
    ///   - title: ekran başlığı.
    public func setScreen(_ screen: DotScreen, url: String? = nil, title: String? = nil) {
        self.screen = ScreenInfo(screen: screen, url: url, title: title)
        order = nil
        sendState()
    }

    /// Sepet özeti: asistan bağlamında kullanılır.
    public func setCart(_ cart: DotCart?) {
        self.cart = cart
        sendState()
    }

    /// Sipariş tamamlandı: satışa dönüşüm ölçümü. Sipariş başına bir kez.
    public func trackOrder(_ order: DotOrder) {
        guard !order.orderId.isEmpty else { return }
        self.order = order
        sendState()
    }

    // MARK: - Widget → uygulama

    private func handle(_ m: [String: Any]) {
        let type = m["type"] as? String ?? ""
        let data = m["data"] as? [String: Any] ?? [:]
        let id = m["id"]
        switch type {
        case "ready":
            let t = data["theme"] as? [String: Any] ?? [:]
            theme = DotTheme(primary: t["primary"] as? String, label: t["label"] as? String)
            statusReason = nil
            status = .ready
            // Hazır değilken istenen açma şimdi.
            if let job = pending {
                pending = nil
                isOpen = true
                call(job.method, job.args)
            }
        case "unavailable":
            let reason = data["reason"] as? String ?? "unavailable"
            statusReason = reason
            // Script/config alınamadı = çoğunlukla ağ, mağaza kapalı DEĞİL: yeniden denenir.
            status = Self.retryable.contains(reason) ? .error : .unavailable
            isOpen = false
        case "open":
            isOpen = true
        case "close":
            isOpen = false
        case "launcher":
            let w = (data["width"] as? NSNumber)?.doubleValue ?? 0
            let h = (data["height"] as? NSNumber)?.doubleValue ?? 0
            if w > 0, h > 0 {
                box = LauncherBox(
                    width: w,
                    height: h,
                    pad: (data["pad"] as? NSNumber)?.doubleValue ?? 0,
                    left: data["pos"] as? String == "bottom-left"
                )
                layout()
            }
        case "productPress":
            let product = DotCardProduct(json: data)
            if let press = onProductPress {
                // Uygulamanın ürün ekranı panelin ALTINDA açılmasın.
                close()
                press(product)
            } else if let url = product.url {
                openUrl(url)
            }
        case "openUrl":
            if let url = data["url"] as? String { openUrl(url) }
        case "addToCart":
            guard let hook = onAddToCart else {
                // Kanca yok → asistan ürün ekranına yönlendiriyor (`productPress`).
                return reply(id, DotHookResult.failed(navigate: true), navigateOnFail: true)
            }
            let quantity = (data["quantity"] as? NSNumber)?.intValue ?? 0
            let req = DotAddToCartRequest(
                product: DotCardProduct(json: data["product"] as? [String: Any] ?? [:]),
                productId: DotCardProduct.string(data["productId"]) ?? "",
                quantity: quantity > 0 ? quantity : 1
            )
            respond(id, navigateOnFail: true) { try await hook(req) }
        case "favorite":
            guard let hook = onFavorite else {
                return reply(id, DotHookResult.failed(navigate: false), navigateOnFail: false)
            }
            let product = DotCardProduct(json: data["product"] as? [String: Any] ?? [:])
            let on = data["on"] as? Bool ?? false
            respond(id, navigateOnFail: false) { try await hook(product, on) }
        default:
            break
        }
    }

    /// Kanca cevabını widget'a döndür. Hata fırlatırsa başarısız sayılır.
    private func respond(_ id: Any?, navigateOnFail: Bool, _ run: @escaping @MainActor () async throws -> DotHookResult) {
        Task { @MainActor [weak self] in
            let result = (try? await run()) ?? .failed
            self?.reply(id, result, navigateOnFail: navigateOnFail)
        }
    }

    /// Başarısızlıkta `navigate` verilmediyse `navigateOnFail`: sepette `true`, widget ürün ekranına yönlendirir.
    private func reply(_ id: Any?, _ result: DotHookResult, navigateOnFail: Bool) {
        var value: [String: Any] = ["ok": result.ok]
        if let n = result.navigate {
            value["navigate"] = n
        } else if !result.ok {
            value["navigate"] = navigateOnFail
        }
        host?.send(["type": "result", "id": id ?? NSNull(), "value": value])
    }

    private func openUrl(_ raw: String) {
        guard let url = URL(string: raw) else { return }
        if let handler = onOpenUrl {
            handler(url)
        } else {
            UIApplication.shared.open(url)
        }
    }
}

extension DotTheme {
    /// `primary` → `UIColor`.
    public var primaryColor: UIColor? { primary.flatMap { UIColor(dotHex: $0) } }
}

extension UIColor {
    /// `#RGB`, `#RRGGBB`, `#RRGGBBAA`.
    convenience init?(dotHex: String) {
        var s = dotHex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        if s.count == 6 { s += "ff" }
        guard s.count == 8, let v = UInt64(s, radix: 16) else { return nil }
        self.init(
            red: CGFloat((v >> 24) & 0xff) / 255,
            green: CGFloat((v >> 16) & 0xff) / 255,
            blue: CGFloat((v >> 8) & 0xff) / 255,
            alpha: CGFloat(v & 0xff) / 255
        )
    }
}
#endif
