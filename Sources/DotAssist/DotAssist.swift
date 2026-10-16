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
    /// Cevap içindeki bağlantı. Yalnızca `http`/`https` adresler gelir (`SFSafariViewController`
    /// ile açılabilir); `mailto:` ve `tel:` sistemle açılır, diğer şemalar (uygulama
    /// bağlantıları vb.) hiç açılmaz. Verilmezse sistem açar (`UIApplication.open`).
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
    /// Uygulama ön planda mı: arka planda yeniden deneme yok.
    private var foreground = true
    /// Açılış süresinin dolacağı an: arka planda dolduysa ön plana dönünce yeniden yüklenir.
    private var bootDeadline: Date?
    /// Son gönderilen durum: aynısı tekrar gönderilmiyor (her `viewDidAppear`'da `setScreen`).
    private var lastState: NSDictionary?
    /// Hazır değilken gelen açma isteği (`open`, `ask`, `openHistory`): `ready` gelince yapılır.
    private var pending: (method: String, args: [Any])?
    private var observers: [NSObjectProtocol] = []

    /// Widget hiç cevap vermezse (ağ yok, script yüklenmedi) `error`.
    private static let bootTimeout: TimeInterval = 20
    /// `error` durumunda yeniden deneme aralıkları; sonuncusu tekrarlanır.
    private static let retryDelays: [TimeInterval] = [3, 10, 30, 60]
    /// Bu kadar denemeden sonra kendiliğinden deneme durur (yanlış ayarlı mağaza her
    /// dakika sayfa yüklemesin). Ön plana dönüş ya da `open()` yeniden başlatır.
    private static let maxAttempts = 6
    /// Sayfanın bildirdiği launcher kutusu için üst sınırlar (pt): dev bir kutu uygulamanın
    /// tüm dokunuşlarını almasın.
    private static let maxLauncher = (width: 480.0, height: 240.0, pad: 48.0)
    private static let maxQuantity = 999
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
        "insecure": "yayın derlemesinde http adres (domain / widgetSrc / apiBase) kullanılamaz",
        "crash": "WebView'ın içerik süreci kapandı; yeniden yükleniyor",
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
            // Ön plana dönünce ağ hatası (ya da arka planda dolan açılış süresi) hemen yeniden denensin.
            observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.foreground = true
                    let expired = self.status == .loading && (self.bootDeadline.map { $0 < Date() } ?? false)
                    guard self.started, self.status == .error || expired else { return }
                    self.attempts = 0
                    self.load()
                }
            })
            // Arka planda yeniden deneme yok.
            observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.foreground = false
                    self.retry?.cancel()
                    self.retry = nil
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
            let web = WebHost(origin: origin, inspectable: options.inspectable)
            web.onMessage = { [weak self] in self?.handle($0) }
            web.onLoaded = { [weak self] in self?.sendState() }
            web.onOpenUrl = { [weak self] in self?.openUrl($0) }
            // İçerik süreci kapandı (iOS arka planda sık yapıyor): yükleme beklemeli yeniden
            // denemeyle, ön plandayken (çök-yükle döngüsü ve arka planda ağ trafiği olmasın).
            web.onCrash = { [weak self] in self?.fail("crash") }
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
        lastState = nil
        isOpen = false
        box = nil

        #if !DEBUG
        // Yayın derlemesinde düz http: ağdaki herkes mağaza origin'ine script sokabilirdi.
        if origin.hasPrefix("http:") || Self.isHttp(options.widgetSrc) || Self.isHttp(options.apiBase) {
            print("[dot-assist] " + (Self.reasonHint["insecure"] ?? ""))
            statusReason = "insecure"
            status = .unavailable
            return
        }
        #endif
        statusReason = nil
        status = .loading
        layout()

        // Yalnızca hâlâ yükleniyorsa: `ready` sonrası tetiklenip nedeni `timeout` yazmasın.
        // Arka planda dolarsa dokunulmuyor: ön plana dönünce yeniden yükleniyor.
        bootDeadline = Date().addingTimeInterval(Self.bootTimeout)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.bootTimeout) { [weak self] in
            guard let self, self.generation == gen, self.status == .loading, self.foreground else { return }
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

        retry?.cancel()
        retry = nil
        if status == .error { scheduleRetry() }
        layout()
    }

    /// AĞ HATASINDA KENDİLİĞİNDEN YENİDEN DENE: artan aralıkla, yalnızca ön plandayken ve
    /// `maxAttempts` kez. Mağazada kapalıysa (`unavailable`) denenmiyor.
    private func scheduleRetry() {
        retry?.cancel()
        retry = nil
        guard foreground, attempts < Self.maxAttempts else { return }
        let delays = Self.retryDelays
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.attempts += 1
            self.load()
        }
        retry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delays[min(attempts, delays.count - 1)], execute: work)
    }

    /// Yükleme bozuldu (içerik süreci kapandı): `error` + yeniden deneme.
    private func fail(_ reason: String) {
        generation += 1
        statusReason = reason
        isOpen = false
        if status == .error { scheduleRetry() } else { status = .error }
    }

    private static func isHttp(_ url: String?) -> Bool {
        url?.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("http:") == true
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
        guard let host else { return }
        let msg: [String: Any] = [
            "type": "state",
            "state": ScreenState.state(screen, order: order, cart: cart, user: user),
            "user": ScreenState.identity(user) ?? NSNull(),
            "url": ScreenState.url(origin: origin, screen, order: order),
        ]
        let dict = msg as NSDictionary
        if let lastState, lastState.isEqual(to: msg) { return }
        if host.send(msg) { lastState = dict }
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
            let max = Self.maxLauncher
            if w > 0, h > 0, w <= max.width, h <= max.height {
                box = LauncherBox(
                    width: w,
                    height: h,
                    pad: min(Swift.max((data["pad"] as? NSNumber)?.doubleValue ?? 0, 0), max.pad),
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
            let q = (data["quantity"] as? NSNumber)?.doubleValue ?? 1
            let quantity = q.isFinite ? Int(min(Swift.max(q, 1), Double(Self.maxQuantity))) : 1
            let req = DotAddToCartRequest(
                product: DotCardProduct(json: data["product"] as? [String: Any] ?? [:]),
                productId: DotCardProduct.string(data["productId"]) ?? "",
                quantity: quantity
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
        let gen = generation
        Task { @MainActor [weak self] in
            let result = (try? await run()) ?? .failed
            // Bu arada sayfa yeniden yüklendiyse cevap yeni sayfadaki aynı numaralı isteğe gitmesin.
            guard let self, self.generation == gen else { return }
            self.reply(id, result, navigateOnFail: navigateOnFail)
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

    /// Sayfadan gelen adres (cevaptaki bağlantı, ürün adresi). Sayfaya güvenilmiyor: yalnızca
    /// web, e-posta ve telefon. Uygulama bağlantıları (uygulamanın kendisininkiler de) açılmıyor.
    private func openUrl(_ raw: String) {
        guard let url = URL(string: raw), let scheme = url.scheme?.lowercased() else { return }
        let web = (scheme == "http" || scheme == "https") && !(url.host ?? "").isEmpty
        guard web || scheme == "mailto" || scheme == "tel" else {
            #if DEBUG
            print("[dot-assist] açılmayan bağlantı şeması: \(scheme)")
            #endif
            return
        }
        if web, let handler = onOpenUrl {
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
