const C='usp-v6',A=['./','index.html','manifest.json','assets/supabase.js','assets/icons/logo.webp','assets/icons/logo-sm.webp','assets/icons/icon-192.png'];
self.addEventListener('install',e=>e.waitUntil(caches.open(C).then(c=>c.addAll(A.map(u=>new Request(u,{cache:'reload'}))))));
self.addEventListener('message',e=>{if(e.data&&e.data.type=='SKIP_WAITING')self.skipWaiting()});
self.addEventListener('activate',e=>e.waitUntil(caches.keys().then(k=>Promise.all(k.filter(x=>x!=C).map(x=>caches.delete(x)))).then(()=>self.clients.claim())));
// Affichage immédiat depuis le cache, mise à jour en arrière-plan
self.addEventListener('fetch',e=>{const r=e.request,u=new URL(r.url);if(r.method!='GET'||u.origin!=location.origin)return;
e.respondWith(caches.open(C).then(c=>c.match(r,{ignoreSearch:true}).then(m=>{const n=fetch(r).then(x=>{if(x.ok)c.put(r,x.clone());return x}).catch(()=>m);return m||n})))});
