self.addEventListener('notificationclick',event=>{event.notification.close();event.waitUntil(self.clients.matchAll({type:'window',includeUncontrolled:true}).then(async windows=>{const own=windows.find(client=>new URL(client.url).origin===self.location.origin);if(own)return own.focus();return self.clients.openWindow('./');}));});
self.addEventListener('push',event=>{
 let payload={};try{payload=event.data?.json()||{}}catch{payload={body:event.data?.text()||''}}
 const title=String(payload.title||'TeFalei');
 const options={body:String(payload.body||'Você recebeu um novo aviso.'),tag:String(payload.tag||'tefalei-alert'),data:{url:'./'},renotify:true};
 event.waitUntil(self.registration.showNotification(title,options));
});
