# Geliştirme notları (iç kullanım)

Müşteriye giden belge `README.md`. Bu dosya iç notlar.

## Nasıl çalışır

React Native SDK ile aynı model: widget bir WKWebView'da, mağazanın alan adıyla (`loadHTMLString(html, baseURL: https://<domain>/)`) çalışır. API'nin origin kontrolü web'deki gibi geçer; mobil için ayrı kapı yok. Widget tarafı RN ile ortak (`widget/src/core/app-host.js`, `platforms/app`).

| Dosya | Ne yapar | RN karşılığı |
|---|---|---|
| `DotAssist.swift` | Genel API, durum makinesi (loading/ready/unavailable/error, 20 sn zaman aşımı, 3/10/30/60 sn yeniden deneme, bekleyen `open`/`ask`), widget mesajları, kanca cevapları | `DotAssistProvider.tsx` |
| `WebHost.swift` | WKWebView, `messageHandlers.dotAssist`, gezinme yakalama, süreç çökmesi | `react-native-webview` prop'ları |
| `Overlay.swift` | Uygulamanın üstündeki pencere; gizli / launcher kutusu / tam ekran | `frame` stili |
| `ScreenState.swift` | Ekran → `__dotApp.state` ve adres | `screen.ts` |
| `Html.swift` | Sayfa | `html.ts` |
| `BridgeScript.swift` | WebView'daki köprü script'i (`window.__dotApp`) | `bridge.ts` |
| `SwiftUI.swift` | `.dotAssistScreen` | `useDotAssistScreen` |

## RN ve Android ile aynı kalması gerekenler

İki parça üç SDK'da **birebir aynı** ve her SDK kendi kopyasını taşıyor:

| Parça | iOS (bu repo) | `sales-agent-react-native` | `sales-agent-android` |
|---|---|---|---|
| Köprü script'i | `Sources/DotAssist/BridgeScript.swift` | `src/bridge.ts` | `dotassist/src/main/java/ai/dotassist/sdk/internal/BridgeScript.kt` |
| Ekran eşlemesi test vakaları | `Tests/DotAssistTests/Fixtures/screen.json` | `test/fixtures/screen.json` | `dotassist/src/test/resources/screen.json` |

Birini değiştirirseniz diğer ikisine de aynısını uygulayın, sonra üç SDK'nın testlerini koşun. Script'te yalnızca uygulamaya giden kanal (`post`) platforma göre seçiliyor; script'in kendisi üçünde aynı.

Köprünün `safeArea` mesajı iOS'ta yok sayılıyor: WKWebView `env(safe-area-inset-*)`'ı doğru bildiriyor, panel tam ekran ve iç boşluk yok.

## Pencere: iOS'a özgü kararlar

- **Ayrı pencere** (`OverlayWindow`, seviye `normal + 1`): asistan gezinme ve modal ekranlardan etkilenmesin diye. Kökteki boş alana gelen dokunuş alttaki pencereye geçer (`hitTest` → `nil`).
- **Anahtar pencere yalnızca panel açıkken olabilir** (`canBecomeKey` ← `allowsKey`). Kapalıyken klavye, durum çubuğu ve yön uygulamada kalır. Durum çubuğu ve yön kararları uygulamanın en üstteki ekranına yönlendirilir (`OverlayController`).
- ⚠ **`makeKey()` açılışta çağrılmıyor:** launcher'a dokunuş sürerken anahtar pencere değişince UIKit'in jest motoru çöküyordu. Mesaj kutusuna dokununca UIKit pencereyi kendisi anahtar yapıyor (klavye UI testinde doğrulandı).
- ⚠ **WKWebView ancak etkin sahne varken oluşturuluyor** (`attachWindow`). SwiftUI `App.init`'te (sahneden önce) oluşturulan WKWebView'a ilk dokunuşta çöküyordu: `-[UIGestureGraphEdge initWithLabel:sourceNode:targetNode:directed:]`, "Invalid parameter not satisfying: targetNode" (iOS 18.3 simülatör). `configure()` yalnızca ayarları saklıyor; sahne etkinleşince (`UIScene.didActivateNotification`) kurulup yükleniyor.
- **`presenter`:** panel açıkken uygulamanın sunduğu ekranlar panelin altında kalır (RN'de yoktu, orada WebView uygulamanın penceresinde). `onOpenUrl` gibi kancalarda bunun üzerinden sunulmalı.

## Güvenlik kuralları (üç SDK'da aynı)

Sayfa mağazanın origin'inde çalışıyor, uzaktan yüklenen bir script içeriyor ve imzalı üye kimliğini alıyor. Sayfaya (widget'a) tam güvenilmiyor:

- **Tek sayfa:** ana çerçevede bizim yüklememiz dışında gezinme yok. Kullanıcının dokunduğu bağlantı uygulamaya gidiyor, kendiliğinden olan gezinme (script, yönlendirme) yok sayılıyor. Engellenemeyen bir gezinmede sayfa kaybedilmiş sayılıyor ve yeniden yükleniyor.
- **Köprü yalnızca mağaza origin'indeki ana sayfadan** mesaj kabul ediyor. Durum (kimlik dahil) yalnızca o sayfaya gönderiliyor.
- **Adres açma:** yalnızca `http`/`https` (`onOpenUrl`'e), `mailto:`/`tel:` (sistem). Uygulama bağlantıları, `intent:`, `file:` hiç açılmıyor.
- **Sayfanın verdiği değerler sınırlı:** launcher kutusu (480×240, pad ≤ 48), güvenli alan, sepet adedi (1–999), mesaj boyutu (256 KB).
- **Yeniden yüklemeden sonra eski kanca cevabı atılıyor** (`generation`): istek numaraları her sayfada 1'den başlıyor.
- **Yayın derlemesinde http yok** (`insecure`), WebView hata ayıklama yalnızca geliştirme derlemesinde.
- **Arka planda yeniden deneme yok**; en fazla 6 deneme, sonra ön plana dönüş ya da `open()`.

iOS'a özgü: iOS 17+ ayrı veri deposu (`WKWebsiteDataStore(forIdentifier:)`): uygulamanın kendi WebView'larındaki mağaza çerezleri ve localStorage'ı widget sayfasından görünmüyor. iOS 14–16'da paylaşılan depo (web'deki snippet'le aynı güven).

## Komutlar

```sh
# SDK birim testleri (ortak vakalar dahil), simülatörde
xcodebuild test -scheme DotAssist -destination 'platform=iOS Simulator,name=iPhone 16'
```

Örnek uygulama ve uçtan uca UI testleri: `Example/` (SDK'ya yerel paket olarak bağlı, mock sunucusu içinde; README'si orada). SDK'yı değiştirdikten sonra oradaki UI testlerini de koşun.

## Yayın (Swift Package Manager)

SPM'de ayrı bir paket deposu yok: paket bu git reposunun kendisi, sürüm git etiketi. SPM, kökteki `Package.swift`'i okuyor; `Example/` pakete dahil değil (yalnızca `Package.swift`'teki hedefler derleniyor).

**Bir kez:** repo müşterilerin erişebileceği yerde olmalı. GitHub → **Settings → General → Danger Zone → Change visibility → Public**. Gizli kalırsa her müşteriye repo erişimi vermek gerekir.

**Her sürüm:**

```sh
xcodebuild test -scheme DotAssist -destination 'platform=iOS Simulator,name=iPhone 16'
git tag 0.1.1                  # semver, önünde `v` YOK
git push origin 0.1.1
```

Etiket bir kez yayınlandıktan sonra taşınmamalı (müşterilerin `Package.resolved`'ı commit'i tutuyor); hata varsa yeni sürüm. README'deki `from: "0.1.0"` satırını güncel tut.

Müşteri: Xcode → **File → Add Package Dependencies** → `https://github.com/usersdot/sales-agent-swift` → ürün **DotAssist**. `Package.swift`'te paket adı URL'nin son parçası: `.product(name: "DotAssist", package: "sales-agent-swift")`.

İsteğe bağlı: https://swiftpackageindex.com/add-a-package (repo herkese açıkken) — paket aranabilir olur, belgeler oluşur.

CocoaPods eklenmedi: trunk 2026 sonunda salt okunur oluyor.

Lisans: Apache-2.0 (`LICENSE`, `NOTICE`). SPM lisansı repodaki `LICENSE`'tan okuyor.

⚠ App Store gizlilik bildirimi: SDK analiz olayları (ürün görüntüleme, sohbet etkileşimi) ve isteğe bağlı üye kimliği gönderiyor. Müşterilerin App Store "App Privacy" formu için bunu belgeleyen bir `PrivacyInfo.xcprivacy` (pakete kaynak olarak) eklenmesi önerilir; içeriği hukuk/gizlilik kararı.

## Henüz denenmedi

- Gerçek cihaz (yalnızca iOS 18.3 simülatör).
- iOS 14–16 (SDK hedefi 14; `canBecomeKey` iOS 15'ten önce yok sayılıyor, orada asistan penceresi kapalıyken de anahtar olabilir).
- iPad / birden fazla pencere (`attach(to:)`).
- Yatay ekran.
- Tükenen ürün → `navigate: true` → ürün ekranı yolu ve favori kalbi UI testinde yok.
