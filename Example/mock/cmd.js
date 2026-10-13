/**
 * Örnek uygulamaya komut gönderir (mock sunucunun test kanalı).
 *
 *   npm run cmd -- open
 *   npm run cmd -- ask "sıvı geçirmez alez"
 *   npm run cmd -- product 1556424
 *   npm run cmd -- history | close | cart | home
 */
const [cmd, ...rest] = process.argv.slice(2);
if (!cmd) {
  console.log('kullanım: npm run cmd -- <open|close|ask|history|product|cart|home> [değer]');
  process.exit(1);
}
fetch('http://localhost:' + (process.env.PORT || 4185) + '/__cmd', {
  method: 'POST',
  headers: { 'content-type': 'application/json' },
  body: JSON.stringify({ cmd, arg: rest.join(' ') }),
})
  .then((r) => r.json())
  .then(() => console.log('gönderildi:', cmd, rest.join(' ')))
  .catch((e) => console.error('mock sunucuya ulaşılamadı:', e.message));
