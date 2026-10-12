// Deploy with Supabase Edge Functions. Required secrets:
// SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, VAPID_PUBLIC_KEY,
// VAPID_PRIVATE_KEY, VAPID_SUBJECT (mailto:...).
// Disable legacy gateway JWT verification when using publishable keys; bearer token is verified below.
import { createClient } from 'npm:@supabase/supabase-js@2';
import webpush from 'npm:web-push@3.6.7';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const respond = (body: string, status: number) => new Response(body, { status, headers: corsHeaders });
const json = (data: unknown) => Response.json(data, { headers: corsHeaders });

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: corsHeaders });
  if (req.method !== 'POST') return respond('Method not allowed', 405);
  const auth = req.headers.get('Authorization') || '';
  if (!auth.startsWith('Bearer ')) return respond('Unauthorized', 401);
  const url = Deno.env.get('SUPABASE_URL')!;
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const admin = createClient(url, serviceKey);
  const { data: userData, error: userError } = await admin.auth.getUser(auth.slice(7));
  if (userError || !userData.user) return respond('Unauthorized', 401);
  let body: { reminder_id?: string };
  try { body = await req.json(); } catch { return respond('Invalid JSON', 400); }
  if (!body.reminder_id || !/^[0-9a-f-]{36}$/i.test(body.reminder_id))
    return respond('Invalid reminder', 400);
  const { data: reminder, error } = await admin.from('tefalei_reminders')
    .select('id,creator_id,recipients,title,created_at')
    .eq('id', body.reminder_id).maybeSingle();
  if (error || !reminder || reminder.creator_id !== userData.user.id)
    return respond('Not found', 404);
  // Limit to freshly created requests. Never accept arbitrary recipient IDs.
  if (Date.now() - Date.parse(reminder.created_at) > 120000)
    return respond('Expired request', 409);
  const recipients = [...new Set((reminder.recipients || []).filter((id: string) => id !== userData.user.id))];
  if (!recipients.length) return json({ delivered: 0 });
  const { data: subscriptions, error: subError } = await admin.from('tefalei_push_subscriptions')
    .select('user_id,endpoint,p256dh,auth_key').in('user_id', recipients);
  if (subError) return respond('Subscription lookup failed', 500);
  webpush.setVapidDetails(Deno.env.get('VAPID_SUBJECT')!,
    Deno.env.get('VAPID_PUBLIC_KEY')!, Deno.env.get('VAPID_PRIVATE_KEY')!);
  let delivered = 0;
  const isNudge = String(reminder.title).startsWith('📣 TOQUE:');
  for (const s of subscriptions || []) {
    try {
      await webpush.sendNotification(
        { endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth_key } },
        JSON.stringify({
          title: isNudge ? '📣 TeFalei: alguém te chamou' : 'TeFalei: novo lembrete',
          body: isNudge ? 'Alguém te deu um toque. Abre o TeFalei!' : 'Você recebeu um lembrete.',
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
  return json({ delivered });
});
