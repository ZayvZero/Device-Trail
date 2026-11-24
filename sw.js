// Device Trail offline helper. Keeps a copy of the app and its scanner libraries on the phone,
// so the page still opens with no signal. Team data never goes through here; that stays live.
const CACHE = "device-trail-app-v1";
const LIBS = /^https:\/\/(cdn\.jsdelivr\.net|fonts\.googleapis\.com|fonts\.gstatic\.com)\//;

self.addEventListener("install", e => { self.skipWaiting(); });
self.addEventListener("activate", e => {
  e.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))).then(() => self.clients.claim()));
});

self.addEventListener("fetch", e => {
  const req = e.request;
  if (req.method !== "GET") return;
  const url = new URL(req.url);
  // The app page: newest copy when online, saved copy when not
  if (req.mode === "navigate" && url.origin === self.location.origin) {
    e.respondWith(fetch(req).then(res => {
      if (res.ok) { const copy = res.clone(); caches.open(CACHE).then(c => c.put("./", copy)); }
      return res;
    }).catch(() => caches.match("./")));
    return;
  }
  // Scanner and database libraries are pinned versions, so a saved copy is fine
  if (LIBS.test(req.url)) {
    e.respondWith(caches.match(req).then(hit => hit || fetch(req).then(res => {
      if (res.ok || res.type === "opaque") { const copy = res.clone(); caches.open(CACHE).then(c => c.put(req, copy)); }
      return res;
    })));
  }
});
