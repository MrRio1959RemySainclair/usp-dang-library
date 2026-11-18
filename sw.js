const C='usp-v9',A=['./','index.html','manifest.json','assets/supabase.js','assets/icons/logo.webp','assets/icons/logo-sm.webp','assets/icons/icon-192.png'];
// Activation immédiate : une nouvelle version remplace l'ancienne sans attendre
self.addEventListener('install',e=>{self.skipWaiting();e.waitUntil(caches.open(C).then(c=>c.addAll(A.map(u=>new Request(u,{cache:'reload'})))))});
self.addEventListener('message',e=>{if(e.data&&e.data.type=='SKIP_WAITING')self.skipWaiting()});
self.addEventListener('activate',e=>e.waitUntil(caches.keys().then(k=>Promise.all(k.filter(x=>x!=C).map(x=>caches.delete(x)))).then(()=>self.clients.claim())));
self.addEventListener('fetch',e=>{const r=e.request,u=new URL(r.url);if(r.method!='GET'||u.origin!=location.origin)return;
 if(r.mode=='navigate'){ // page : réseau d'abord (3 s max), sinon copie locale ; toujours mise à jour du cache
  e.respondWith((async()=>{const c=await caches.open(C),net=fetch(r),to=new Promise((_,j)=>setTimeout(j,3000));
   try{const x=await Promise.race([net,to]);if(x.ok)c.put(r,x.clone());return x}
   catch(_){const m=(await c.match(r,{ignoreSearch:true}))||(await c.match('./'));if(m){e.waitUntil(net.then(x=>{if(x.ok)c.put(r,x)}).catch(()=>{}));return m}return net}})());return}
 e.respondWith(caches.open(C).then(async c=>{const m=await c.match(r,{ignoreSearch:true}),n=fetch(r).then(x=>{if(x.ok)c.put(r,x.clone());return x});
  if(m){e.waitUntil(n.catch(()=>{}));return m}return n}))});
