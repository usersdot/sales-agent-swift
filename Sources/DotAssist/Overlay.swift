#if os(iOS)
import UIKit

/// Widget'ın bildirdiği launcher kutusu (`launcher` mesajı).
struct LauncherBox: Equatable {
    var width: CGFloat
    var height: CGFloat
    /// Launcher'ın kutu kenarına uzaklığı (gölge payı).
    var pad: CGFloat
    var left: Bool
}

/// WebView'ın o anki hâli.
enum OverlayMode: Equatable {
    /// Görünmez ama çalışıyor: ekran olayları panel kapalıyken de ölçülüyor.
    case hidden
    /// Panel kapalı: WebView launcher boyutunda şeffaf bir kutu, widget'ın kendi düğmesi köşesinde.
    case launcher(LauncherBox)
    /// Panel açık: tam ekran.
    case open
}

/// UYGULAMANIN ÜSTÜNDEKİ PENCERE: asistan sayfa geçişlerinden ve sunulan
/// ekranlardan (modal) etkilenmesin diye uygulamanın penceresinde değil, kendi
/// penceresinde. Kökteki boş alana gelen dokunuş alttaki pencereye geçiyor.
final class OverlayWindow: UIWindow {
    /// Yalnızca panel açıkken anahtar pencere. Kapalıyken klavye, durum çubuğu
    /// ve yön kararları uygulamanın penceresinde kalmalı.
    var allowsKey = false

    override var canBecomeKey: Bool { allowsKey }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === rootViewController?.view ? nil : hit
    }
}

/// Katman penceresinin kökü. Durum çubuğu ve yön kararlarını panel kapalıyken
/// uygulamanın en üstteki ekranına bırakıyor.
final class OverlayController: UIViewController {
    let container = UIView()
    private let content: UIView

    var mode: OverlayMode = .hidden {
        didSet {
            guard mode != oldValue else { return }
            view.setNeedsLayout()
            setNeedsStatusBarAppearanceUpdate()
        }
    }

    var launcher = DotLauncher() {
        didSet { view.setNeedsLayout() }
    }

    var openBackground: UIColor = .white

    init(content: UIView) {
        self.content = content
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) kullanılmıyor")
    }

    override func loadView() {
        let root = UIView()
        root.backgroundColor = .clear
        container.backgroundColor = .clear
        container.clipsToBounds = true
        content.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(content)
        root.addSubview(container)
        view = root
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        apply()
    }

    private func apply() {
        let bounds = view.bounds
        let safe = view.safeAreaInsets
        switch mode {
        case .open:
            container.frame = bounds
            container.backgroundColor = openBackground
            container.alpha = 1
            container.isUserInteractionEnabled = true
        case let .launcher(box):
            let w = box.width + box.pad * 2
            let h = box.height + box.pad * 2
            // Launcher kutunun içinde `pad` kadar içeride: kenar uzaklığı launcher'ın kendisine göre.
            let maxY = bounds.height - safe.bottom - CGFloat(launcher.bottom) + box.pad
            let x = box.left
                ? safe.left + CGFloat(launcher.side) - box.pad
                : bounds.width - safe.right - CGFloat(launcher.side) + box.pad - w
            container.frame = CGRect(x: x, y: maxY - h, width: w, height: h)
            container.backgroundColor = .clear
            container.alpha = 1
            container.isUserInteractionEnabled = true
        case .hidden:
            container.frame = bounds
            container.backgroundColor = .clear
            // 0'dan büyük olsa dokunuş alırdı; 0'da UIKit dokunuşu atlıyor, WebView çalışmaya devam ediyor.
            container.alpha = 0
            container.isUserInteractionEnabled = false
        }
        container.accessibilityElementsHidden = mode == .hidden
        content.frame = container.bounds
    }

    // MARK: - Durum çubuğu ve yön: uygulamanınki

    /// Uygulamanın en üstteki ekranı (bu pencerenin dışında).
    var host: UIViewController? {
        let windows = view.window?.windowScene?.windows.filter { !($0 is OverlayWindow) && !$0.isHidden } ?? []
        var vc = (windows.first { $0.isKeyWindow } ?? windows.first)?.rootViewController
        while let presented = vc?.presentedViewController, !presented.isBeingDismissed { vc = presented }
        return vc
    }

    private func resolve(_ vc: UIViewController?, _ child: (UIViewController) -> UIViewController?) -> UIViewController? {
        var cur = vc
        while let c = cur, let next = child(c), next !== c { cur = next }
        return cur
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        if mode == .open { return .darkContent }
        return resolve(host, { $0.childForStatusBarStyle })?.preferredStatusBarStyle ?? .default
    }

    override var prefersStatusBarHidden: Bool {
        if mode == .open { return false }
        return resolve(host, { $0.childForStatusBarHidden })?.prefersStatusBarHidden ?? false
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        host?.supportedInterfaceOrientations ?? .all
    }
}
#endif
