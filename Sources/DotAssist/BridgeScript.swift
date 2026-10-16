/// KÖPRÜ: WebView'da widget'tan ÖNCE çalışan script (`window.__dotApp`).
/// Widget tarafı: `widget/src/core/app-host.js`.
///
/// ⚠ AYNI SCRIPT DİĞER İKİ SDK'DA DA VAR:
///   React Native `sales-agent-react-native/src/bridge.ts`
///   Android `sales-agent-android/dotassist/src/main/java/ai/dotassist/sdk/internal/BridgeScript.kt`
/// Burada bir değişiklik yaparsanız aynısını onlara da uygulayın. Üç SDK'nın
/// widget'la aynı mesajları konuşması gerekiyor. Uygulamaya giden kanal (`post`)
/// üçünü de tanıyor; script bu yüzden üçünde birebir aynı kalabiliyor.
///
/// Sayfa `baseUrl: https://<mağaza alan adı>/` ile yükleniyor: widget'ın API
/// istekleri o origin'den çıkıyor ve panelin izinli alan adı kontrolü web'deki
/// gibi geçiyor. API'de mobil için ayrı bir kapı YOK.
///
///   state      uygulamanın ekranı (pageType, product, cart…)
///   post       widget → uygulama (`productPress`, `open`, `close`…)
///   request    widget → uygulama, cevap bekler (`addToCart`, `favorite`)
///   receive    uygulama → widget (`state`, `call`, `result`, `repaint`),
///              native taraf JS çalıştırarak çağırıyor
///
/// Uygulamaya giden kanal (`post`), ilk bulunan:
///   React Native  window.ReactNativeWebView.postMessage
///   iOS           window.webkit.messageHandlers.dotAssist.postMessage
///   Android       window.dotAssistAndroid.postMessage
/// Mesaj her zaman JSON METNİ.
///
/// `__TEST__` yer tutucusu `true`/`false` ile değiştiriliyor.
///
/// ⚠ ROTA BİLDİRİMİ: widget `pushState`'i yakalıyor ama sonra "DOM değişsin"
/// diye bekliyor (en fazla 1.5 sn, `route-watch.js`). Boş sayfada hiçbir şey
/// değişmediği için her ekran geçişi 1.5 sn gecikirdi; gezinmeden ~100 ms sonra
/// küçük bir DOM değişikliği yapılıyor.
///
/// GÜVENLİ ALAN (`safeArea`, sayfa → uygulama): widget açık paneli
/// `env(safe-area-inset-…)` kadar içeri çekiyor. Android WebView'lar bu değeri
/// sürüme göre farklı bildiriyor (ör. Chrome 113: üst = durum çubuğu, alt = 0).
/// Sayfanın gördüğü değer (CSS px) bildiriliyor; Android ve RN yalnızca EKSİĞİ
/// tamamlıyor, iOS yok sayıyor. Ölçüm `<html>`in padding'i üzerinden:
/// widget `position: fixed` olduğu için etkilenmiyor ve stil widget yüklenmeden
/// veriliyor (widget'ın rota izleyicisi tetiklenmesin).
///
/// YENİDEN ÇİZİM (`repaint`, uygulama → sayfa): Android'de WebView başka bir
/// aktivitenin penceresine taşınınca (ör. ekran döndürüldü) sayfa değişene kadar
/// yeni kare üretmiyor, panel boş beyaz kalıyor. `<html>` stilinde görünmez bir
/// değişiklik kare üretiyor. Öznitelik değişikliği: widget'ın gözlemcileri yalnızca
/// eleman ekleme/çıkarmayı izliyor.
///
/// ES5: eski Android WebView'larında da çalışmalı.
enum BridgeScript {
    static let source = #"""
(function () {
  var TEST = __TEST__;
  var seq = 0;
  var pending = {};

  function post(m) {
    try {
      var s = JSON.stringify(m);
      var rn = window.ReactNativeWebView;
      if (rn) return rn.postMessage(s);
      var wk = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.dotAssist;
      if (wk) return wk.postMessage(s);
      var an = window.dotAssistAndroid;
      if (an) an.postMessage(s);
    } catch (e) {}
  }

  function assistant() {
    var w = window.dot && window.dot.widget;
    if (!w) return null;
    for (var k in w) {
      if (Object.prototype.hasOwnProperty.call(w, k) && w[k] && w[k].type === 'assistant') return w[k];
    }
    return null;
  }

  function navigate(url) {
    try {
      var u = new URL(url, location.href);
      var next = new URL(u.origin === location.origin ? u.href : location.origin + u.pathname + u.search);
      if (TEST && !next.searchParams.has('dot')) next.searchParams.set('dot', 'true');
      if (next.href === location.href) return;
      history.pushState(null, '', next.href);
      setTimeout(function () {
        var b = document.body;
        if (!b) return;
        var n = document.createComment('nav');
        b.appendChild(n);
        b.removeChild(n);
      }, 100);
    } catch (e) {}
  }

  var root = document.documentElement;
  root.style.padding = 'env(safe-area-inset-top, 0px) env(safe-area-inset-right, 0px) env(safe-area-inset-bottom, 0px) env(safe-area-inset-left, 0px)';
  var safe = '';

  function safeArea() {
    try {
      var s = getComputedStyle(root);
      var v = {
        top: parseFloat(s.paddingTop) || 0,
        right: parseFloat(s.paddingRight) || 0,
        bottom: parseFloat(s.paddingBottom) || 0,
        left: parseFloat(s.paddingLeft) || 0
      };
      var key = v.top + ',' + v.right + ',' + v.bottom + ',' + v.left;
      if (key === safe) return;
      safe = key;
      post({ type: 'safeArea', data: v });
    } catch (e) {}
  }

  window.addEventListener('resize', safeArea);

  var host = window.__dotApp = {
    v: 1,
    state: {},
    post: post,
    request: function (type, data) {
      return new Promise(function (resolve) {
        var id = ++seq;
        pending[id] = resolve;
        post({ type: type, id: id, data: data });
        setTimeout(function () {
          if (!pending[id]) return;
          delete pending[id];
          resolve({ ok: false, navigate: false });
        }, 30000);
      });
    },
    receive: function (m) {
      if (!m || typeof m !== 'object') return;
      if (m.type === 'result') {
        var fn = pending[m.id];
        if (fn) { delete pending[m.id]; fn(m.value); }
        return;
      }
      if (m.type === 'state') {
        host.state = m.state || {};
        window.dotUser = m.user || null;
        if (m.url) navigate(m.url);
        return;
      }
      if (m.type === 'repaint') {
        root.style.outline = root.style.outline ? '' : '1px solid transparent';
        return;
      }
      if (m.type === 'call') {
        var a = assistant();
        if (a && typeof a[m.method] === 'function') {
          try { a[m.method].apply(null, m.args || []); } catch (e) {}
        }
      }
    },
    /** Widget script'i yüklendi — olayları dinle. */
    attach: function () {
      safeArea();
      var dot = window.dot;
      if (!dot || typeof dot.on !== 'function') {
        post({ type: 'unavailable', data: { reason: 'script' } });
        return;
      }
      dot.on('ready', function (e) {
        if (!e || e.type !== 'assistant') return;
        var w = dot.widget && dot.widget[e.slug];
        var c = (w && w.config) || {};
        var theme = c.theme || {};
        var colors = theme.colors || {};
        var texts = c.texts || c.strings || {};
        post({ type: 'ready', data: {
          slug: e.slug,
          theme: {
            primary: colors.primary || theme.brandColor || theme.primary || theme.primaryColor || null,
            label: (texts.launcher && texts.launcher.label) || texts.launcherLabel || null
          }
        } });
      });
      dot.on('rejected', function (e) { post({ type: 'unavailable', data: { reason: (e && e.reason) || 'rejected' } }); });
      dot.on('collecting', function (e) { post({ type: 'unavailable', data: { reason: (e && e.reason) || 'collecting' } }); });
    }
  };

  /** Widget'ın kendi bağlantıları kökte yakalanıyor (`root.js`); bu, `window.open` için. */
  window.open = function (url) {
    try { if (url) post({ type: 'openUrl', data: { url: new URL(String(url), location.href).href } }); } catch (e) {}
    return { closed: false, close: function () {}, focus: function () {} };
  };

  post({ type: 'boot' });
})();
"""#
}
