// La Casaca: manda las notificaciones al celu (web push con las claves VAPID de push_config).
// - Desde la base (header x-cron-secret): { users, title, body, url, tag } → a todos los celus de esos usuarios.
// - Prueba desde la app: { test_token } → al celu de quien la pide.
import webpush from "npm:web-push@3.6.7";
import { createClient } from "npm:@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-cron-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), { status, headers: { ...CORS, "Content-Type": "application/json" } });
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "método" }, 405);
  const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { data: cfg, error: cfgErr } = await sb.rpc("push_config");
  if (cfgErr || !cfg) return json({ error: "config" }, 500);

  const body = await req.json().catch(() => ({}));
  let rows: { endpoint: string; p256dh: string; auth: string }[] = [];
  let msg = { title: String(body.title || "La Casaca"), body: String(body.body || ""), url: String(body.url || "./"), tag: String(body.tag || "casaca") };
  if (body.test_token) {
    if (!UUID.test(String(body.test_token))) return json({ error: "token" }, 401);
    const r = await sb.rpc("fc_push_test_rows", { p_token: body.test_token });
    if (r.error) return json({ error: "token" }, 401);
    rows = r.data || [];
    msg = { title: "⚽ ¡Avisos activados!", body: "Así te van a llegar la convocatoria, los entrenamientos y los resultados.", url: "./", tag: "prueba" };
  } else {
    if (req.headers.get("x-cron-secret") !== cfg.secret) return json({ error: "no autorizado" }, 401);
    const users = Array.isArray(body.users) ? body.users.filter((u: unknown) => UUID.test(String(u))) : [];
    if (!users.length) return json({ sent: 0, total: 0 });
    const r = await sb.rpc("fc_push_rows", { p_users: users });
    if (r.error) return json({ error: r.error.message }, 500);
    rows = r.data || [];
  }

  webpush.setVapidDetails(cfg.subject, cfg.public, cfg.private);
  let sent = 0, gone = 0, failed = 0;
  await Promise.all(rows.map(async (x) => {
    try {
      await webpush.sendNotification({ endpoint: x.endpoint, keys: { p256dh: x.p256dh, auth: x.auth } }, JSON.stringify(msg), { TTL: 12 * 3600, urgency: "high" });
      sent++;
    } catch (e) {
      const code = (e as { statusCode?: number }).statusCode;
      if (code === 404 || code === 410) { await sb.rpc("fc_push_gone", { p_endpoint: x.endpoint }); gone++; }
      else { failed++; console.error("push", code, String(e)); }
    }
  }));
  return json({ sent, gone, failed, total: rows.length });
});
