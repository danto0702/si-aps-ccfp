/* Service Worker — SI-APS CCFP v2.6 */
const CACHE = 'siaps-ccfp-v23';
const ASSETS = [
  './SI-APS-CCFP.html',
  './manifest.json',
  './icono.png',
  './banner.png',
  // Leaflet para mapa geopunto (disponible offline después de primera carga)
  'https://unpkg.com/leaflet@1.9.4/dist/leaflet.css',
  'https://unpkg.com/leaflet@1.9.4/dist/leaflet.js'
  // Chart.js y SheetJS se cargan dinámicamente; se cachean en el primer uso online
];

self.addEventListener('install', e => {
  e.waitUntil(
    caches.open(CACHE)
      .then(c => c.addAll(ASSETS))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys().then(keys =>
      Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))
    ).then(() => self.clients.claim())
    .then(() => self.clients.matchAll({type: 'window', includeUncontrolled: true}))
    .then(clients => clients.forEach(c => c.navigate(c.url)))
  );
});

self.addEventListener('fetch', e => {
  if (e.request.method !== 'GET') return;
  // HTML principal: red primero para garantizar actualizaciones inmediatas
  if (e.request.url.endsWith('SI-APS-CCFP.html') || e.request.url.endsWith('/si-aps-ccfp/') || e.request.url.endsWith('/si-aps-ccfp')) {
    e.respondWith(
      fetch(e.request).then(resp => {
        if (resp && resp.status === 200) {
          const clone = resp.clone();
          caches.open(CACHE).then(c => c.put(e.request, clone));
        }
        return resp;
      }).catch(() => caches.match(e.request))
    );
    return;
  }
  // Tiles de OpenStreetMap: red primero, caché de respaldo
  if (e.request.url.includes('tile.openstreetmap.org')) {
    e.respondWith(
      fetch(e.request).then(resp => {
        if (resp && resp.status === 200) {
          const clone = resp.clone();
          caches.open(CACHE).then(c => c.put(e.request, clone));
        }
        return resp;
      }).catch(() => caches.match(e.request))
    );
    return;
  }
  // Resto: caché primero, red de respaldo
  e.respondWith(
    caches.match(e.request).then(cached => {
      if (cached) return cached;
      return fetch(e.request).then(resp => {
        if (resp && resp.status === 200) {
          const clone = resp.clone();
          caches.open(CACHE).then(c => c.put(e.request, clone));
        }
        return resp;
      }).catch(() => cached);
    })
  );
});
