/**
 * ÖRNEK UYGULAMANIN MOCK SUNUCUSU — http://localhost:4185
 *
 * Simülatörde canlı veriye dokunmadan SDK'yı denemek için:
 *   GET  /widget/index.js           yereldeki widget build'i (`widget/dist/index.js`)
 *   GET  /api/widget/:pid/config    canlı API'den SALT OKUNUR (mağazanın origin'iyle)
 *   GET  /api/widget/:pid/product   katalog — `DotAssistExample/yatas-products.json`
 *   diğer /api/widget/...           mock: oturum, olaylar, soru, geçmiş, karşılaştırma…
 *
 * Mağaza (`pid`, `domain`) dışarıdan: `dot.config.json`. Her istekte yeniden
 * okunuyor — dosyayı değiştirince sunucuyu yeniden başlatmak gerekmiyor.
 *
 * Canlı sisteme hiçbir yazma gitmiyor: oturum açılmıyor, olay ve soru
 * kaydedilmiyor, dot-sales'e soru gitmiyor. Gelen her istek konsola yazılıyor.
 *
 * Üç SDK reposunun örneğinde de aynı sunucu var (sales-agent-ios, -android,
 * -react-native); yalnızca `STORE_FILE` ve `CATALOG` yolları farklı. Widget,
 * repo `dot-identity/widget`'ın yanındaysa oradan; değilse `WIDGET_FILE=...`.
 */
const http = require('http');
const fs = require('fs');
const path = require('path');

const PORT = Number(process.env.PORT) || 4185;
const LIVE_API = process.env.LIVE_API || 'https://chat.dotassist.ai';
const WIDGET = process.env.WIDGET_FILE || path.join(__dirname, '../../../widget/dist/index.js');
const STORE_FILE = path.join(__dirname, '../DotAssistExample/dot.config.json');
const CATALOG = require('../DotAssistExample/yatas-products.json');
/** Canlı config `ORIGIN_NOT_ALLOWED` dönerse — alan adı panelde izinli olana kadar. */
const FALLBACK_CONFIG = path.join(__dirname, 'yatas-fallback-config.json');

function store() {
  const s = JSON.parse(fs.readFileSync(STORE_FILE, 'utf8'));
  return {
    pid: String(s.pid || ''),
    domain: String(s.domain || ''),
    site: 'https://' + String(s.domain || '').replace(/^https?:\/\//, ''),
    appTheme: s.appTheme && typeof s.appTheme === 'object' ? s.appTheme : null,
  };
}

/**
 * `dot.config.json` → `appTheme`: panele yazmadan önce uygulamaya özel temayı
 * (`theme.app`) denemek için. Config'teki temaya `app` bloğu olarak ekleniyor;
 * panelde yazılacak değer AYNISI.
 */
function withAppTheme(text, appTheme) {
  if (!appTheme) return text;
  try {
    const d = JSON.parse(text);
    const r = d && 'resultMessage' in d ? d.result : d;
    if (!r) return text;
    const put = (x) => {
      if (x && typeof x === 'object') x.theme = Object.assign({}, x.theme, { app: Object.assign({}, x.theme && x.theme.app, appTheme) });
    };
    put(r);
    (r.widgets || []).forEach(put);
    return JSON.stringify(d);
  } catch (e) {
    return text;
  }
}

/** Asistanın kartı — katalogdaki ürünün düz alanları (dot-sales kartı gibi). */
function card(p) {
  return { id: p.id, mainProductId: p.mainProductId, name: p.name, brand: p.brand, price: p.price, discountedPrice: p.discountedPrice, currency: p.currency, url: p.url, image: p.image };
}

function send(res, status, body, type) {
  res.writeHead(status, {
    'content-type': type || 'application/json; charset=utf-8',
    'cache-control': 'no-store',
    'access-control-allow-origin': '*',
    'access-control-allow-headers': '*',
    'access-control-allow-methods': 'GET,POST,DELETE,OPTIONS',
  });
  res.end(typeof body === 'string' ? body : JSON.stringify(body));
}

function readBody(req) {
  return new Promise((resolve) => {
    let s = '';
    req.on('data', (d) => (s += d));
    req.on('end', () => {
      try {
        resolve(s ? JSON.parse(s) : {});
      } catch (e) {
        resolve({});
      }
    });
  });
}

const t = () => new Date().toTimeString().slice(0, 8);

/** Uyarı her config isteğinde değil, bir kez. */
let warnedOrigin = false;

async function proxyConfig(req, res, url, s) {
  try {
    const r = await fetch(LIVE_API + url.pathname + url.search, { headers: { origin: s.site, referer: s.site + '/' } });
    const text = await r.text();
    if (r.status === 403 && /ORIGIN_NOT_ALLOWED/.test(text) && fs.existsSync(FALLBACK_CONFIG)) {
      if (!warnedOrigin) {
        warnedOrigin = true;
        console.log(`${t()}  config   ⚠ canlı API ${s.site} için ORIGIN_NOT_ALLOWED döndü — yedek config veriliyor (mock/yatas-fallback-config.json).`);
        console.log(`           Gerçek config için panelde/DB'de tenant'ın security.allowedOrigins listesine "${s.site}" eklenmeli.`);
      }
      const fallback = JSON.stringify({ result: JSON.parse(fs.readFileSync(FALLBACK_CONFIG, 'utf8')), resultMessage: { type: 'success', code: 200 } });
      return send(res, 200, withAppTheme(fallback, s.appTheme));
    }
    console.log(`${t()}  config   ← canlı (${r.status}, ${s.site})${s.appTheme ? ' + theme.app ' + JSON.stringify(s.appTheme) : ''}`);
    send(res, r.status, withAppTheme(text, s.appTheme));
  } catch (e) {
    console.log(`${t()}  config   ✗ canlı API'ye ulaşılamadı: ${e.message}`);
    send(res, 502, { error: { code: 'MOCK_PROXY' } });
  }
}

/**
 * TEST KANALI — simülatöre dokunmadan komut (`npm run cmd -- open`).
 * Uygulama geliştirme modunda `GET /__cmd`'yi saniyede bir okuyor (`App.tsx`).
 * iOS'ta `simctl openurl` her seferinde onay penceresi açtığı için bu yol.
 */
let commands = [];

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://localhost');
  const p = url.pathname;
  if (req.method === 'OPTIONS') return send(res, 204, '');

  if (p === '/__cmd') {
    if (req.method === 'POST') {
      const c = await readBody(req);
      commands.push(c);
      console.log(`${t()}  komut    ${JSON.stringify(c)}`);
      return send(res, 200, { queued: commands.length });
    }
    const out = commands;
    commands = [];
    return send(res, 200, out);
  }

  if (p === '/widget/index.js') {
    let js;
    try {
      js = fs.readFileSync(WIDGET, 'utf8');
    } catch (e) {
      console.log(`${t()}  widget   ✗ ${WIDGET} yok — "cd widget && npm run build:dev"`);
      return send(res, 404, '/* widget yok */', 'text/javascript');
    }
    if (js.indexOf('__dotApp') === -1) console.log(`${t()}  widget   ⚠ bu build uygulama modunu içermiyor — "cd widget && npm run build:dev"`);
    return send(res, 200, js, 'text/javascript; charset=utf-8');
  }

  const m = p.match(/^\/api\/widget\/([^/]+)\/(.+)$/);
  if (!m) return send(res, 200, 'Dot Assist örnek uygulama mock sunucusu', 'text/plain; charset=utf-8');
  const action = m[2];
  const s = store();
  if (decodeURIComponent(m[1]) !== s.pid) console.log(`${t()}  ⚠ istek pid'i (${m[1]}) dot.config.json'dakinden (${s.pid}) farklı`);

  if (action === 'config' && req.method === 'GET') return proxyConfig(req, res, url, s);

  /** Bizim katalog (`dashboard_products`) — API'deki `GET /product` ile aynı cevap. */
  if (action === 'product' && req.method === 'GET') {
    const id = url.searchParams.get('productId');
    const product = CATALOG.find((x) => x.id === id) || null;
    console.log(`${t()}  product  ${id} → ${product ? product.name + ' (katalogdan)' : 'katalogda yok'}`);
    return send(res, 200, { result: { product }, resultMessage: { type: 'success', code: 200 } });
  }

  const body = req.method === 'POST' ? await readBody(req) : {};

  if (action === 'session') {
    console.log(`${t()}  session  (mock)${body.userRef ? ' üye=' + body.userRef : ''}`);
    return send(res, 200, { token: 'mock-token', expiresIn: 900 });
  }
  if (action === 'events') {
    const list = (body.events || []).map((e) => e.n + (e.p && (e.p.id || e.p.orderId) ? '(' + (e.p.id || e.p.orderId) + ')' : ''));
    const platform = (body.ctx && body.ctx.platform) || '-';
    // API'de `ctx.platform: 'app'` → ürün/kategori kataloğa YAZILMAZ (`is_app_product_sync` yoksa).
    const sync = platform === 'app' && list.some((n) => /^(product|category)_view/.test(n)) ? '  [katalog yazımı: kapalı]' : '';
    console.log(`${t()}  events   ${list.join(', ')}  · platform=${platform}${sync}`);
    return send(res, 200, {});
  }
  if (action === 'ask') {
    console.log(`${t()}  ask      "${body.question}"`);
    return send(res, 200, {
      answer: `"${body.question}" için Yataş Bedding'den önerilerim aşağıda. (Bu cevap mock sunucudan geliyor.) Ayrıntılar için [ürün sayfası](${CATALOG[0].url}).`,
      messageId: 'mock-' + Date.now(),
      conversationId: body.conversationId || 'mock-conv-1',
      products: CATALOG.map(card),
    });
  }
  if (action === 'similar') {
    console.log(`${t()}  similar  ${body.productId || ''}`);
    return send(res, 200, { products: CATALOG.filter((x) => x.id !== body.productId).map(card) });
  }
  if (action === 'compare') {
    console.log(`${t()}  compare  ${(body.productIds || []).join(', ')}`);
    return send(res, 200, { comparison: null, missing: [] });
  }
  if (action.indexOf('conversations') === 0) return send(res, 200, { items: [] });

  console.log(`${t()}  ${action.padEnd(8)} (mock, boş cevap)`);
  return send(res, 200, {});
});

server.listen(PORT, () => {
  const s = store();
  console.log(`Mock sunucu: http://localhost:${PORT}`);
  console.log(`Mağaza: ${s.domain} · pid ${s.pid}  (dot.config.json)`);
  console.log(`Config: ${LIVE_API} (origin ${s.site}) · katalog: DotAssistExample/yatas-products.json (${CATALOG.length} ürün)`);
  console.log(`Widget: ${WIDGET}`);
});
