# Dot Assist: iOS SDK

Web sitenizdeki Dot Assist alışveriş asistanını iOS uygulamanıza ekler.

Uygulamadaki asistan web sitenizdekinin aynısıdır:

- sohbet ve ürün önerileri,
- ürün karşılaştırma ve benzer ürünler,
- beden ve renk seçimi,
- asistandan sepete ekleme,
- sohbet geçmişi.

Panelde yaptığınız görünüm ve metin ayarları uygulamaya da kendiliğinden yansır. Uygulamaya ayrıca tasarım yapmanız gerekmez.

SwiftUI ve UIKit uygulamalarında çalışır.

---

## İçindekiler

1. [Başlamadan önce](#1-başlamadan-önce)
2. [Kurulum](#2-kurulum)
3. [Asistanı uygulamaya ekleyin](#3-asistanı-uygulamaya-ekleyin)
4. [Ürün ekranını bildirin](#4-ürün-ekranını-bildirin)
5. [Asistandan ürüne gitme ve sepete ekleme](#5-asistandan-ürüne-gitme-ve-sepete-ekleme)
6. [Sepet ve sipariş](#6-sepet-ve-sipariş)
7. [Diğer ekranlar (isteğe bağlı)](#7-diğer-ekranlar-isteğe-bağlı)
8. [Asistan düğmesi](#8-asistan-düğmesi)
9. [Giriş yapmış üye (isteğe bağlı)](#9-giriş-yapmış-üye-isteğe-bağlı)
10. [Test etme](#10-test-etme)
11. [Sorun giderme](#11-sorun-giderme)
12. [Başvuru: tüm seçenekler](#12-başvuru-tüm-seçenekler)

---

## 1. Başlamadan önce

Usersdot ekibinden iki bilgi alın:

| Bilgi | Örnek | Ne işe yarar |
|---|---|---|
| **pid** | `a1b2c3d4e5f6a7b8c9d0e1f2` | Mağazanızın asistan kimliği. Web sitenizdeki kurulum kodunda da aynı değer var. |
| **domain** | `www.magaza.com` | Web sitenizin alan adı. Asistan bu adres üzerinden çalışır. |

**Gereksinimler**

- iOS 14 ve üzeri.
- Xcode 15 ve üzeri.

---

## 2. Kurulum

Swift Package Manager ile:

1. Xcode'da **File → Add Package Dependencies…**
2. Paket adresini yazın: `https://github.com/usersdot/sales-agent-swift`
   Sürüm kuralı: **Up to Next Major Version**, `0.1.0`.
3. **DotAssist** kütüphanesini uygulama hedefinize ekleyin.

`Package.swift` kullanıyorsanız:

```swift
dependencies: [
    .package(url: "https://github.com/usersdot/sales-agent-swift", from: "0.1.0"),
],
targets: [
    .target(name: "Uygulamam", dependencies: [.product(name: "DotAssist", package: "sales-agent-swift")]),
]
```

Başka bir paket ya da ayar gerekmez.

---

## 3. Asistanı uygulamaya ekleyin

Uygulama açılırken bir kez `DotAssist.configure` çağırın.

**SwiftUI:**

```swift
import DotAssist
import SwiftUI

@main
struct MagazaApp: App {
    init() {
        DotAssist.configure(DotAssistOptions(pid: "SIZE_VERILEN_PID", domain: "www.magaza.com"))
    }

    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
```

**UIKit:**

```swift
import DotAssist

func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: …) -> Bool {
    DotAssist.configure(DotAssistOptions(pid: "SIZE_VERILEN_PID", domain: "www.magaza.com"))
    return true
}
```

Bu kadarla:

- sağ altta asistan düğmesi görünür,
- düğmeye dokununca asistan tam ekran açılır,
- sohbet ekranlar arasında korunur; asistanı kapatıp açınca kaldığı yerden devam eder.

Asistan uygulamanızın üstündeki ayrı bir katmanda durur. Gezinme yapınızda değişiklik yapmanız gerekmez. Düğmenin dışındaki alanlar uygulamanıza dokunmaya devam eder.

---

## 4. Ürün ekranını bildirin

Kullanıcı bir ürün ekranındayken asistana o ürünü söyleyin. Asistan o ürün hakkında konuşur ve ürünü panelin üstünde gösterir.

**Yalnızca ürün kimliği yeter.** Ad, fiyat, görsel, stok ve beden/renk seçenekleri web sitenizden alınır.

**SwiftUI:**

```swift
struct ProductView: View {
    let product: Product

    var body: some View {
        ScrollView { /* ürün ekranınız */ }
            .dotAssistScreen(.product(DotProduct(id: product.id)))
    }
}
```

Ekran her göründüğünde (geri dönüldüğünde de) asistana yeniden bildirilir.

**UIKit:**

```swift
override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    DotAssist.shared.setScreen(.product(DotProduct(id: product.id)))
}
```

### ⚠ Ürün kimliği web sitenizdekiyle aynı olmalı

Asistan ürünü web sitenizdeki kimliğiyle tanır. Örneğin web'deki ürün adresi `www.magaza.com/frio-alez-p-1556424` ise kimlik `1556424`'tür.

Uygulamanız ürünlere farklı bir kimlik veriyorsa, asistana web'deki karşılığını verin. Aksi halde asistan ürünü bulamaz.

### Web sitenizde olmayan bir ürün

Ürün yalnızca uygulamada satılıyorsa diğer bilgileri de siz verin:

```swift
.dotAssistScreen(.product(DotProduct(
    id: "APP-123",
    name: "Frio Alez 160x200",
    price: 1299.9,           // liste fiyatı
    discountedPrice: 1199.9, // indirimli fiyat (indirim yoksa yazmayın)
    currency: "TRY",
    url: "https://www.magaza.com/frio-alez-p-1556424",
    image: "https://…/frio.jpg"
)))
```

Verdiğiniz bilgiler yalnızca o ekranda kullanılır. Uygulama, web sitenizdeki ürün bilgilerini değiştirmez.

---

## 5. Asistandan ürüne gitme ve sepete ekleme

Asistan ürün önerdiğinde kullanıcı karta dokunabilir ya da "Sepete ekle"ye basabilir. Bu işlemleri uygulamanızın kendi ekranlarına ve sepetine bağlayın. `configure`'dan sonra, bir kez:

```swift
let dot = DotAssist.shared

// Karta dokunuldu → uygulamanın ürün ekranını açın
dot.onProductPress = { product in
    router.openProduct(id: product.id)
}

// "Sepete ekle" → uygulamanın sepetine ekleyin
dot.onAddToCart = { request in
    do {
        try await cart.add(request.productId, quantity: request.quantity)
        return .ok      // eklendi
    } catch {
        return .failed  // eklenemedi → asistan kullanıcıyı ürün ekranına götürür
    }
}
```

- **`onProductPress`:** Asistan kendini kapatır ve bu fonksiyonu çağırır. Ürün ekranınız asistanın altında kalmaz. Sohbet kaybolmaz.
- **`onAddToCart`:** `productId`, kullanıcının seçtiği beden ya da rengin kodudur. Doğrudan sepetinize ekleyebilirsiniz.
  - `.ok` döndürürseniz asistan "Sepete eklendi" der.
  - `.failed` döndürürseniz (örneğin ürün tükendi) asistan kullanıcıyı ürün ekranına yönlendirir.
  - Yönlendirme istemiyorsanız `.failed(navigate: false)` döndürün.
  - Hata fırlatırsanız `.failed` sayılır.

Bu fonksiyonlar ana iş parçacığında (`@MainActor`) çağrılır; arayüzünüzü doğrudan güncelleyebilirsiniz.

**Bu fonksiyonları vermezseniz:**

| Vermediğiniz | Ne olur |
|---|---|
| `onProductPress` | Ürün, web sitenizde tarayıcıda açılır. |
| `onAddToCart` | "Sepete ekle"ye basılınca kullanıcı ürün ekranına yönlendirilir (`onProductPress`). |

### Favoriler (isteğe bağlı)

Asistandaki kalp düğmesini uygulamanızın favorilerine bağlayabilirsiniz:

```swift
dot.onFavorite = { product, on in
    guard let id = product.id else { return .failed }
    if on { try await favorites.add(id) } else { try await favorites.remove(id) }
    return .ok
}
```

### Cevaplardaki bağlantılar (isteğe bağlı)

Asistanın cevabındaki bir bağlantıya dokunulduğunda varsayılan olarak tarayıcı açılır. Bağlantıyı uygulamanızda açmak isterseniz aşağıdaki gibi yapın. Buraya yalnızca `http`/`https` adresler gelir. E-posta (`mailto:`) ve telefon (`tel:`) bağlantılarını sistem açar. Başka uygulamaları açan bağlantılar güvenlik için hiç açılmaz.

```swift
dot.onOpenUrl = { url in
    let safari = SFSafariViewController(url: url)
    DotAssist.shared.presenter?.present(safari, animated: true)
}
```

> **Asistan açıkken ekran sunmak:** asistan uygulamanızın üstünde durur. Asistan açıkken kendi ekranınızdan sunduğunuz bir şey (uyarı, tarayıcı) asistanın **altında** kalır. Bunun için `DotAssist.shared.presenter` kullanın: asistan açıksa asistanın, kapalıysa uygulamanızın en üstteki ekranını verir.

---

## 6. Sepet ve sipariş

Bunlar isteğe bağlıdır ama asistanın satışa etkisini ölçmek için önerilir.

```swift
// Sepet değiştiğinde
DotAssist.shared.setCart(DotCart(total: 2399.8, itemCount: 2, currency: "TRY"))

// Sipariş tamamlandığında: sipariş başına bir kez
DotAssist.shared.trackOrder(DotOrder(
    orderId: "S-10023",
    total: 2399.8,
    currency: "TRY",
    itemCount: 2,
    productIds: ["1556424", "1098542"]
))
```

---

## 7. Diğer ekranlar (isteğe bağlı)

Kullanıcının uygulamada nerede olduğunu bildirirseniz, asistanın ölçümleri web sitenizdekiyle aynı ayrıntıda olur:

```swift
.dotAssistScreen(.home)
.dotAssistScreen(.category(DotCategory(categoryRef: "alez", name: "Alez")))
.dotAssistScreen(.search(DotSearch(query: "yastık", resultCount: 42)))
.dotAssistScreen(.cart)
.dotAssistScreen(.account)
.dotAssistScreen(.other(name: "kampanyalar"))
```

UIKit'te aynı değerleri `DotAssist.shared.setScreen(…)` ile verin.

Her ekrana web'deki karşılığının adresini de verebilirsiniz: `.dotAssistScreen(.category(…), url: "https://www.magaza.com/alez")`. Böylece raporlarda uygulama ve web aynı sayfa olarak görünür.

---

## 8. Asistan düğmesi

Sağ alttaki düğme web sitenizdekinin aynısıdır: ikon, şekil, renk ve yazı paneldeki ayarlardan gelir. Panelde değişiklik yapınca uygulama güncellemesi gerekmez.

Düğme yalnızca asistan kullanılabilir olduğunda görünür. Asistan açıkken gizlenir.

### Konumunu değiştirmek

Ekranın altında bir sekme çubuğu varsa düğmeyi yukarı alın:

```swift
DotAssist.shared.launcher = DotLauncher(bottom: 70)            // güvenli alanın 70 birim üstü
DotAssist.shared.launcher = DotLauncher(bottom: 70, side: 20)  // ve sağdan 20
```

`bottom` alt güvenli alandan (ana ekran çubuğunun üstü) ölçülür, varsayılan 24.

> Düğmenin uygulamadaki boyutu web sitenizden ayrı ayarlanabilir; örneğin uygulamada biraz daha küçük olabilir. Bunun için Usersdot ekibine yazın, uygulamanızda değişiklik gerekmez.

### Kendi düğmeniz

Hazır düğme yerine kendi düğmenizi kullanabilirsiniz:

```swift
DotAssist.shared.launcher = .hidden

struct AskButton: View {
    @ObservedObject private var dot = DotAssist.shared

    var body: some View {
        if dot.status == .ready { // asistan kullanılamıyorsa gösterme
            Button("Asistana sor") { dot.open() }
        }
    }
}
```

Kendi düğmenizden bir soruyla da açabilirsiniz:

```swift
DotAssist.shared.ask("Bu ürün makinede yıkanır mı?") // asistanı açar ve soruyu gönderir
DotAssist.shared.openHistory()                      // geçmiş sohbetler
```

Asistan henüz hazır değilken bu fonksiyonlar çağrılırsa istek kaybolmaz; asistan hazır olunca açılır.

---

## 9. Giriş yapmış üye (isteğe bağlı)

Asistanın giriş yapmış kullanıcıyı tanıması (örneğin adıyla karşılaması) için üyeyi asistana tanıtabilirsiniz.

Güvenlik için üye bilgisi **sizin sunucunuzda** imzalanır. Gizli anahtar uygulamaya kesinlikle konmaz.

**1. Sunucunuzda** (Usersdot'un size verdiği gizli anahtarla):

```js
// Node.js örneği
const crypto = require('crypto');

const ref = 'uye-123';                                  // üyenin sizdeki kimliği
const exp = Math.floor(Date.now() / 1000) + 60 * 60;    // 1 saat geçerli
const sig = crypto.createHmac('sha256', GIZLI_ANAHTAR).update(`${ref}.${exp}`).digest('base64url');
// { ref, exp, sig } değerlerini uygulamaya gönderin
```

**2. Uygulamada:**

```swift
DotAssist.shared.user = DotUser(ref: ref, exp: exp, sig: sig)
// Ad gibi bilgileri de göndermek isterseniz:
DotAssist.shared.user = DotUser(ref: ref, exp: exp, sig: sig, profile: DotUserProfile(name: "Ayşe"))

// Çıkış yapınca
DotAssist.shared.user = nil
```

- Üye değişince (giriş ya da çıkış) asistan yeni bir sohbetle başlar.
- İmzanın süresi dolmadan sunucunuzdan yenisini alıp verin. Aynı üyenin imzası yenilenince sohbet kesilmez.
- İmza geçersizse asistan yine çalışır, yalnızca kullanıcıyı tanımaz.

> İmza `base64url` biçiminde olmalı (Node.js'te `.digest('base64url')`). Başka dillerde: HMAC-SHA256 sonucunu base64 yapıp `+`→`-`, `/`→`_` çevirin ve sondaki `=`'leri silin.

---

## 10. Test etme

Asistanı canlıya açmadan önce yalnızca kendi cihazlarınızda görmek için Usersdot ekibinden mağazanızı **Test** moduna almasını isteyin ve geliştirme sürümünde `test` verin:

```swift
#if DEBUG
let test = true
#else
let test = false
#endif
DotAssist.configure(DotAssistOptions(pid: "…", domain: "…", test: test))
```

Test modunda asistan yalnızca `test` verilen uygulamalarda görünür; mağaza yayındaki kullanıcılara görünmez.

Asistanın durumunu görmek için:

```swift
DotAssist.shared.onStatusChange = { status in
    print(status, DotAssist.shared.statusReason ?? "")
}
```

Geliştirme sürümünde (`DEBUG`) asistan kullanılamadığında nedeni Xcode konsoluna da yazılır.

Kontrol listesi:

- [ ] Düğme sağ altta görünüyor.
- [ ] Düğmeye dokununca asistan tam ekran açılıyor, sağ üstteki × ile kapanıyor.
- [ ] Bir ürün ekranında asistanı açınca o ürün üstte görünüyor.
- [ ] Asistandaki bir ürüne dokununca uygulamanın ürün ekranı açılıyor.
- [ ] Asistandan "Sepete ekle" uygulamanın sepetine ekliyor.
- [ ] Mesaj kutusuna dokununca klavye açılıyor ve mesaj kutusu görünür kalıyor.
- [ ] Asistan kapalıyken uygulamanın kendi yazı alanları ve düğmeleri normal çalışıyor.

---

## 11. Sorun giderme

| Belirti | Neden ve çözüm |
|---|---|
| Düğme hiç görünmüyor | `status` ve `statusReason` değerlerine bakın (aşağıdaki satırlar). |
| `unavailable` · `test_no_flag` | Mağaza Test modunda. Geliştirme sürümünde `test: true` verin. |
| `unavailable` · `host` | `domain` mağazanız için izinli değil. Usersdot'un verdiği alan adını birebir yazın (örn. `www.magaza.com`). |
| `unavailable` · `collecting` ya da `disabled` | Asistan mağazanız için henüz açılmamış. Usersdot ekibine yazın. |
| `error` · `config_error` | Mağaza ayarları alınamadı. İnternet bağlantısını, `pid` ve `domain` değerlerini kontrol edin. |
| `error` · `script` ya da `timeout` | İnternet bağlantısı yok ya da asistan yüklenemedi. |
| `error` (her neden) | SDK kendiliğinden yeniden dener: birkaç saniye sonra, sonra daha seyrek ve uygulama ön plana gelince. Kalıcıysa yukarıdaki satırlara bakın. |
| Asistan açılıyor ama ürün üstte görünmüyor | Ürün ekranında `.dotAssistScreen` / `setScreen` çağrılıyor mu ve kimlik web'dekiyle aynı mı, kontrol edin ([Bölüm 4](#4-ürün-ekranını-bildirin)). |
| Asistan açıkken uygulamanın uyarısı/ekranı görünmüyor | Asistanın altında kalıyor. `DotAssist.shared.presenter` üzerinden sunun ([Bölüm 5](#cevaplardaki-bağlantılar-isteğe-bağlı)). |
| Düğme sekme çubuğunun üstüne biniyor | `DotLauncher(bottom: 70)` ile yukarı alın ([Bölüm 8](#8-asistan-düğmesi)). |

---

## 12. Başvuru: tüm seçenekler

### `DotAssistOptions`

| Alan | Zorunlu | Açıklama |
|---|---|---|
| `pid` | ✔ | Size verilen mağaza kimliği. |
| `domain` | ✔ | Web sitenizin alan adı, örn. `www.magaza.com`. |
| `test` | | Test modu ([Bölüm 10](#10-test-etme)). |
| `locale` | | Arayüz dili, varsayılan `tr`. |
| `backgroundColor` | | Asistan açılırken görünen zemin rengi, varsayılan `#ffffff`. |
| `inspectable` | | Safari Web Inspector ile incelenebilir (iOS 16.4+). Yalnızca geliştirmede açın. |

### `DotAssist.shared`

| | |
|---|---|
| `status` | `.loading` (yükleniyor), `.ready` (hazır), `.unavailable` (mağaza için kapalı), `.error` (yüklenemedi, yeniden denenir) |
| `statusReason` | Durumun nedeni ([Bölüm 11](#11-sorun-giderme)) |
| `isOpen` | Asistan açık mı |
| `theme` | Paneldeki marka rengi (`primary`, `primaryColor`) ve düğme yazısı (`label`) |
| `open()` / `close()` / `toggle()` | Asistanı aç / kapat |
| `ask(_:)` | Asistanı açıp soruyu gönderir |
| `openHistory()` | Geçmiş sohbetler |
| `newChat()` | Yeni sohbet |
| `setScreen(_:url:title:)` | Ekranı bildir |
| `setCart(_:)` | Sepet özeti |
| `trackOrder(_:)` | Sipariş tamamlandı |
| `user` | Giriş yapmış üye ([Bölüm 9](#9-giriş-yapmış-üye-isteğe-bağlı)) |
| `launcher` | Düğme konumu ya da `.hidden` ([Bölüm 8](#8-asistan-düğmesi)) |
| `presenter` | Asistanın üstünde ekran sunmak için ([Bölüm 5](#cevaplardaki-bağlantılar-isteğe-bağlı)) |
| `attach(to:)` | Birden fazla pencereli (iPad) uygulamalarda asistanın görüneceği sahne |
| `onProductPress` | Asistandaki ürüne dokunuldu. |
| `onAddToCart` | Asistandan sepete ekle. `.ok` / `.failed` döndürün. |
| `onFavorite` | Kalp düğmesi. |
| `onOpenUrl` | Cevaptaki bağlantı (yalnızca `http`/`https`). |
| `onOpen` / `onClose` | Asistan açıldı / kapandı. |
| `onStatusChange` | Asistanın durumu değişti. |

`status`, `isOpen` ve `theme` SwiftUI'da `@ObservedObject var dot = DotAssist.shared` ile izlenebilir.

### `.dotAssistScreen(_:url:title:)`

Ekran türleri: `.home`, `.product`, `.category`, `.search`, `.cart`, `.account`, `.other(name:)` ([Bölüm 4](#4-ürün-ekranını-bildirin) ve [Bölüm 7](#7-diğer-ekranlar-isteğe-bağlı)).

---

**Yardım:** Kurulumda takıldığınız bir yer olursa Usersdot ekibine yazın.

**Lisans:** Apache-2.0 ([LICENSE](LICENSE)).
