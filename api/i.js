// Link de invitación para el grupo de WhatsApp: /i/CODIGO muestra el nombre y el escudo del equipo
// en la vista previa del mensaje y después abre la app con el código ya puesto.
const SB = 'https://ngwrtivemyjueiysqqum.supabase.co';
const KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5nd3J0aXZlbXlqdWVpeXNxcXVtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTAzNDAwNjYsImV4cCI6MjEwNTkxNjA2Nn0._BwHSn4LH2V59jk90e2VS_xO3csW9S_idaxqO81_X3s';
const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

module.exports = async (req, res) => {
  const code = String((req.query && req.query.c) || '').toUpperCase().replace(/[^A-Z0-9]/g, '').slice(0, 12);
  let t = null;
  if (code){
    try {
      const r = await fetch(SB + '/rest/v1/rpc/fc_team_preview', {
        method: 'POST',
        headers: { apikey: KEY, Authorization: 'Bearer ' + KEY, 'Content-Type': 'application/json' },
        body: JSON.stringify({ p_code: code }),
        signal: AbortSignal.timeout(3000)
      });
      if (r.ok) t = await r.json();
    } catch (e) {}
  }
  const host = 'https://' + (req.headers['x-forwarded-host'] || req.headers.host || 'lacasacadt.vercel.app');
  const to = '/' + (code ? '?e=' + code : '');
  const title = t ? `${t.emoji || '⚽'} Sumate a ${t.name}${t.staff ? ' (cuerpo técnico)' : ''}` : 'Sumate al equipo en La Casaca';
  const desc = t && t.staff
    ? 'Entrás como cuerpo técnico: convocatoria, pizarra, puntajes y entrenamientos del plantel.'
    : 'Entrá, tocá tu nombre en el plantel y listo. Confirmás si vas, ves la pizarra, tus goles y la tabla del torneo.';
  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  res.setHeader('Cache-Control', 'public, max-age=300, s-maxage=600');
  res.end(`<!doctype html><html lang="es-AR"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(title)}</title>
<meta name="description" content="${esc(desc)}">
<meta property="og:type" content="website">
<meta property="og:site_name" content="La Casaca">
<meta property="og:title" content="${esc(title)}">
<meta property="og:description" content="${esc(desc)}">
<meta property="og:url" content="${esc(host + '/i/' + code)}">
<meta property="og:image" content="${esc(host)}/icons/og.jpg">
<meta property="og:image:width" content="1200"><meta property="og:image:height" content="630">
<meta name="twitter:card" content="summary_large_image">
<meta http-equiv="refresh" content="0; url=${esc(to)}">
<script>location.replace(${JSON.stringify(to)});</script>
</head><body style="font-family:system-ui,sans-serif;text-align:center;padding:40px 16px">
<p><a href="${esc(to)}">Abrir La Casaca</a></p></body></html>`);
};
