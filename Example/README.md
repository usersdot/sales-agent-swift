# Örnek uygulama (iOS)

`DotAssist` Swift paketini bir mağaza uygulamasına kurulmuş hâliyle denemek için SwiftUI uygulaması (iOS 16). Varsayılan mağaza Yataş Bedding: iki ürün, ürün ve sepet ekranları, dört kanca. React Native ve Android örnekleriyle aynı uygulama.

SDK, bu reponun kökünden yerel Swift paketi olarak bağlı (`..`). Müşteri uygulamasında tek fark paketin adresi: yerel klasör yerine repo adresi (bkz. kökteki README).

## Çalıştırma

```sh
npm run mock                  # 1. terminal: mock sunucu, http://localhost:4185 (yalnızca Node, kurulum yok)
open DotAssistExample.xcodeproj
```

Mock, widget'ı yereldeki build'den verir: repo `dot-identity/widget`'ın yanındaysa oradan (`../../widget/dist/index.js`), değilse `WIDGET_FILE=/yol/index.js npm run mock`. Config canlı API'den salt okunur alınır; canlı sisteme hiçbir şey yazılmaz.

Mağaza: `DotAssistExample/dot.config.json` (`pid`, `domain`, `mode`). `mode: "live"` canlı widget ve API'yi kullanır, gerçek oturum ve olay yazar.

## Uçtan uca UI testleri

```sh
xcodebuild test -project DotAssistExample.xcodeproj -scheme DotAssistExample -destination 'platform=iOS Simulator,name=iPhone 16'
```

UI testleri (`DotAssistExampleUITests`) widget'ın içine gerçekten dokunuyor: launcher, bağlam kartı, varyant seçici + sepete ekle, soru, cevaptaki bağlantı (uyarı panelin üstünde mi), sonuç kartı → uygulamanın ürün ekranı, sipariş. Widget metinleri değişirse etiketler buradan güncellenir; bulunamayan adımda erişilebilirlik ağacı konsola dökülür.

## Dokunmadan test

Uygulama mock'un komut kanalını (`GET /__cmd`) saniyede bir okur:

```sh
npm run cmd -- open
npm run cmd -- ask "sıvı geçirmez alez önerir misin?"
npm run cmd -- product 1556424
npm run cmd -- history      # ya da close, cart, home
```

Kuyruk tek: aynı mock'a bağlı başka bir örnek (RN, Android) açıksa komutları o da kapar.

## Notlar

- Mock modunda sayfa `http://localhost:4185` üzerinden açılır; `Info.plist`'te yalnızca `NSAllowsLocalNetworking` var.
- `mock/` diğer iki SDK reposunun örneğindekiyle aynı sunucu; yalnızca `dot.config.json` ve katalog yolları farklı.
- Xcode projesi elle yazıldı (Xcode 16 klasör senkronlu biçim, `objectVersion = 77`): `DotAssistExample/` klasörüne eklenen dosya projeye kendiliğinden girer.
