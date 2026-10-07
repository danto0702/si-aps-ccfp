/* Service Worker — SI-APS CCFP v6.0 — Anexo Técnico v7 Junio 2026 */
const CACHE = 'siaps-ccfp-v63';
const HTML = './SI-APS-CCFP.html';
const ASSETS = [
  HTML,
  './index.html',
  './manifest.json',
  './icono.png',
  './banner.png',
  './icon-192.png',
  './icon-512.png',
  // Leaflet para mapa geopunto (disponible offline después de primera carga)
  'https://unpkg.com/leaflet@1.9.4/dist/leaflet.css',
  'https://unpkg.com/leaflet@1.9.4/dist/leaflet.js'
  // Chart.js y SheetJS se cargan dinámicamente; se cachean en el primer uso online
];

self.addEventListener('install', e => {
  e.waitUntil(
    caches.open(CACHE)
      // Un recurso externo caído no debe impedir instalar la versión offline
      .then(c => Promise.all(ASSETS.map(a => c.add(a).catch(() => null))))
      .then(() => self.skipWaiting())
  );
});

// Ya NO se recargan las ventanas abiertas al activar: eso borraba el formulario que el
// profesional estuviera diligenciando. La nueva versión se aplica al reabrir la app.
self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys().then(keys =>
      Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))
    ).then(() => self.clients.claim())
  );
});

function guardar(req, resp) {
  // 'opaque' = scripts de CDN cargados sin CORS (Chart.js, SheetJS): también se guardan para uso offline
  if (resp && (resp.status === 200 || resp.type === 'opaque')) {
    const clone = resp.clone();
    caches.open(CACHE).then(c => c.put(req, clone));
  }
  return resp;
}

// Red con tiempo límite: con señal débil ("lie-fi") no dejar la app en blanco esperando
function redConLimite(req, ms) {
  return new Promise((resolve, reject) => {
    const t = setTimeout(() => reject(new Error('timeout')), ms);
    fetch(req).then(r => { clearTimeout(t); resolve(r); }, err => { clearTimeout(t); reject(err); });
  });
}

self.addEventListener('fetch', e => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  // Nunca cachear la API de Supabase (datos y sesión)
  if (url.hostname.endsWith('supabase.co')) return;

  // HTML principal (con o sin ?t=…): red primero con límite de 4 s, luego caché
  const esHtml = req.mode === 'navigate' || url.pathname.endsWith('SI-APS-CCFP.html') ||
                 url.pathname.endsWith('/si-aps-ccfp/') || url.pathname.endsWith('/si-aps-ccfp');
  if (esHtml && url.origin === self.location.origin) {
    e.respondWith(
      redConLimite(req, 4000)
        .then(resp => {
          if (resp && resp.status === 200 && url.pathname.endsWith('SI-APS-CCFP.html')) {
            const clone = resp.clone();
            caches.open(CACHE).then(c => c.put(HTML, clone));
          }
          return resp;
        })
        .catch(() => caches.match(req, {ignoreSearch: true}).then(r => r || caches.match(HTML)))
    );
    return;
  }
  // Tiles de OpenStreetMap: red primero, caché de respaldo
  if (url.hostname.includes('tile.openstreetmap.org')) {
    e.respondWith(fetch(req).then(r => guardar(req, r)).catch(() => caches.match(req)));
    return;
  }
  // Resto: caché primero, red de respaldo
  e.respondWith(
    caches.match(req).then(cached => cached || fetch(req).then(r => guardar(req, r)).catch(() => cached))
  );
});
