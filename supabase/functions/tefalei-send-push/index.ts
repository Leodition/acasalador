// Deploy with Supabase Edge Functions. Required secrets:
// SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, VAPID_PUBLIC_KEY,
// VAPID_PRIVATE_KEY, VAPID_SUBJECT (mailto:...).
// JWT verification must remain enabled for this function.
import { createClient } from 'npm:@supabase/supabase-js@2';
import webpush from 'npm:web-push@3.6.7';

Deno.serve(async (req) => {
  if (req.method !== 'POST') return new Response('Method not allowed', { status: 405 });
  const auth = req.headers.get('Authorization') || '';
  if (!auth.startsWith('Bearer ')) return new Response('Unauthorized', { status: 401 });
  const url = Deno.env.get('SUPABASE_URL')!;
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const admin = createClient(url, serviceKey);
  const { data: userData, error: userError } = await admin.auth.getUser(auth.slice(7));
  if (userError || !userData.user) return new Response('Unauthorized', { status: 401 });
  let body: { reminder_id?: string };
  try { body = await req.json(); } catch { return new Response('Invalid JSON', { status: 400 }); }
  if (!body.reminder_id || !/^[0-9a-f-]{36}$/i.test(body.reminder_id))
    return new Response('Invalid reminder', { status: 400 });
  const { data: reminder, error } = await admin.from('tefalei_reminders')
    .select('id,creator_id,recipients,title,created_at')
    .eq('id', body.reminder_id).maybeSingle();
  if (error || !reminder || reminder.creator_id !== userData.user.id)
    return new Response('Not found', { status: 404 });
  // Limit to freshly created requests. Never accept arbitrary recipient IDs.
  if (Date.now() - Date.parse(reminder.created_at) > 120000)
    return new Response('Expired request', { status: 409 });
  const recipients = [...new Set((reminder.recipients || []).filter((id: string) => id !== userData.user.id))];
  if (!recipients.length) return Response.json({ delivered: 0 });
  const { data: subscriptions, error: subError } = await admin.from('tefalei_push_subscriptions')
    .select('user_id,endpoint,p256dh,auth_key').in('user_id', recipients);
  if (subError) return new Response('Subscription lookup failed', { status: 500 });
  webpush.setVapidDetails(Deno.env.get('VAPID_SUBJECT')!,
    Deno.env.get('VAPID_PUBLIC_KEY')!, Deno.env.get('VAPID_PRIVATE_KEY')!);
  let delivered = 0;
  const urgent = String(reminder.title).startsWith('🚨 AVISO URGENTE');
  for (const s of subscriptions || []) {
    try {
      await webpush.sendNotification(
        { endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth_key } },
        JSON.stringify({
          title: urgent ? '🚨 TeFalei: pedido urgente' : 'TeFalei: novo lembrete',
          body: urgent ? 'Alguém pediu ajuda. Abra o aplicativo.' : 'Você recebeu um lembrete.',
          tag: 'tefalei-' + reminder.id,
        }),
      );
      delivered++;
    } catch (e) {
      const status = (e as {statusCode?:number}).statusCode;
      if (status === 404 || status === 410)
        await admin.from('tefalei_push_subscriptions').delete()
          .eq('user_id', s.user_id).eq('endpoint', s.endpoint);
      else console.error('Push delivery error', status || String(e));
    }
  }
  return Response.json({ delivered });
});
