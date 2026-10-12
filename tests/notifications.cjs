const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const html=fs.readFileSync(require('node:path').join(__dirname,'..','index.html'),'utf8');
const script=html.match(/<script>([\s\S]*?)<\/script>/)[1];new vm.Script(script);
let clock=Date.parse('2026-10-12T12:00:00Z');class Clock extends Date{static now(){return clock}}
const storage=new Map(),state={cloudReminders:[{id:'a',creator_id:'partner',title:'Primeiro',created_at:'2026-10-12'},{id:'b',creator_id:'partner',title:'Segundo',created_at:'2026-10-12'}]};
const ctx={state,Date:Clock,reminderUserId:()=> 'me',reminderVisible:()=>true,localStorage:{getItem:k=>storage.get(k)||null,setItem:(k,v)=>storage.set(k,v)},currentFeature:'notificacoes',page:()=>{},esc:x=>String(x)};vm.createContext(ctx);
vm.runInContext(script.slice(script.indexOf('let showArchivedNotifications='),script.indexOf('function configuracoes()')),ctx);
assert.equal(ctx.notificationInbox().unread.length,2);ctx.markNotificationRead('a');assert.equal(ctx.notificationInbox().unread.length,1);assert.equal(ctx.notificationInbox().archived.length,1);assert(!ctx.centralNotificacoes().includes('Primeiro'));
ctx.toggleArchivedNotifications(true);assert(ctx.centralNotificacoes().includes('Primeiro'));assert(!ctx.centralNotificacoes().includes('Marcar como lida'));assert(!ctx.centralNotificacoes().includes('30 dias'));
clock+=29*86400000;ctx.markAllNotificationsRead();assert.equal(ctx.notificationInbox().archived.length,2);
clock+=86400000;assert.equal(ctx.notificationInbox().archived.length,1);assert.equal(ctx.notificationInbox().unread.length,0);ctx.markAllNotificationsRead();assert.equal(ctx.notificationInbox().archived.length,1);assert.equal(state.cloudReminders.length,2);
console.log('PASS: read archives immediately; all-read preserves dates; expiry does not revive notifications or delete requests');
let deletes=0,confirmed=false,message;const shop={demoMode:false,shopState:{shopping:[{id:'rice',title:'Arroz'}]},confirm:m=>{message=m;return confirmed},shopRel:()=> 'rel',loadShop:async()=>{},notify:()=>{},sb:{from:()=>({delete:()=>{deletes++;return{eq:()=>({eq:async()=>({error:null})})}}})}};vm.createContext(shop);
vm.runInContext(script.slice(script.indexOf('async function shopDelete('),script.indexOf('const shoppingCategories=')),shop);
(async()=>{await shop.shopDelete('tefalei_shopping_items','rice');assert.equal(deletes,0);assert(message.includes('Arroz'));confirmed=true;await shop.shopDelete('tefalei_shopping_items','rice');assert.equal(deletes,1);console.log('PASS: cancelled deletion does not reach database; confirmed deletion runs once')})().catch(e=>{console.error(e);process.exitCode=1});
