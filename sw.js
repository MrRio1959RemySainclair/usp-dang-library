const C='usp-v4',A=['./','index.html','manifest.json','assets/vendor/supabase-2.45.4.js','assets/icons/icon-192.png','assets/icons/logo.png'];
self.addEventListener('install',e=>e.waitUntil(caches.open(C).then(c=>c.addAll(A)).catch(()=>{})));
self.addEventListener('message',e=>{if(e.data&&e.data.type=='SKIP_WAITING')self.skipWaiting()});
self.addEventListener('activate',e=>e.waitUntil(caches.keys().then(k=>Promise.all(k.filter(x=>x!=C).map(x=>caches.delete(x)))).then(()=>self.clients.claim())));
// Réseau d'abord, mais sans attendre indéfiniment : après 4 s on sert la copie en cache si elle existe.
const net=req=>fetch(req).then(r=>{if(r.ok){const c=r.clone();caches.open(C).then(x=>x.put(req,c))}return r});
self.addEventListener('fetch',e=>{const u=new URL(e.request.url);if(e.request.method!='GET'||u.origin!=location.origin)return;
 const nav=e.request.mode=='navigate';
 e.respondWith(caches.match(nav?'index.html':e.request).then(hit=>{
  const live=net(e.request);
  if(!hit)return live.catch(()=>nav?caches.match('./'):Response.error());
  const slow=new Promise(r=>setTimeout(()=>r(hit),4000));
  return Promise.race([live.catch(()=>hit),slow]);
 }))});
