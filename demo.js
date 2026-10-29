// La Casaca · equipo de ejemplo. Vive solo en este celu: responde como el servidor, pero no toca la base.
// Se carga recién cuando alguien toca "Probar con un equipo de ejemplo".
(function(){
  let seed = 20261031;
  const rnd = () => { seed |= 0; seed = seed + 0x6D2B79F5 | 0; let t = Math.imul(seed ^ seed >>> 15, 1 | seed); t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296; };
  const pick = (a) => a[Math.floor(rnd() * a.length)];
  const int = (a, b) => a + Math.floor(rnd() * (b - a + 1));
  const iso = (d) => new Date(d).toISOString();
  const day = (d) => { const x = new Date(d); return `${x.getFullYear()}-${String(x.getMonth() + 1).padStart(2, '0')}-${String(x.getDate()).padStart(2, '0')}`; };
  let n = 0; const id = (p) => `demo_${p}${++n}`;

  // El sábado pasado a las 15:30 y el próximo
  const now = new Date();
  const lastSat = new Date(now); lastSat.setHours(15, 30, 0, 0); lastSat.setDate(lastSat.getDate() - ((lastSat.getDay() + 1) % 7 || 7));
  const fecha = (k) => new Date(lastSat.getTime() + (k - 6) * 7 * 864e5); // fecha 6 = el sábado pasado
  const nextDate = new Date(now.getTime() + 3 * 864e5); nextDate.setHours(15, 30, 0, 0); // a 3 días, así se ve el aviso de convocatoria

  /* ---------- El equipo ---------- */
  const team = { id: 'demo', name: 'Los Halcones', emoji: '🦅', sport: 'futbol', players_on_field: 11, category: 'Liga de ejemplo · Primera',
    ratings_public: true, code: 'DEMO01', dt_code: 'DEMODT', kind: 'torneo', card_mode: 'staff', board_suggest: true, min_players: 14, league: true,
    pinned: { id: 'VguvE8aiWd4', title: 'Activación antes del partido', note: 'Hacela el viernes, 20 minutos', by: 'Profe Gus', at: iso(now) } };
  const P = [
    ['Tano', 1, 'ARQ', 'der'], ['Colo', 2, 'DEF', 'der'], ['Ruso', 6, 'DEF', 'izq'], ['Fede', 4, 'LAT', 'der'], ['Mati', 3, 'LAT', 'izq'],
    ['Pipa', 5, 'VOL', 'der'], ['Chino', 8, 'VOL', 'der'], ['Lucho', 10, 'ENG', 'izq'], ['Tomi', 7, 'EXT', 'der'], ['Nacho', 11, 'EXT', 'izq'],
    ['Polaco', 9, 'DEL', 'der'], ['Gordo', 12, 'ARQ', 'der'], ['Rama', 13, 'DEF', 'der'], ['Facu', 14, 'VOL', 'izq'], ['Juanchi', 19, 'DEL', 'der'],
    ['Beto', 16, 'LAT', 'der'], ['Santi', 18, 'VOL', 'der'], ['Mono', 20, 'DEL', 'izq']
  ];
  const members = P.map(([name, number, pos, foot], i) => {
    const gk = pos === 'ARQ', base = int(58, 84);
    const attrs = gk ? { ata: int(base - 8, base + 8), ref: int(base - 6, base + 10), pie: int(base - 15, base + 4), ubi: int(base - 6, base + 8) }
      : { vel: int(base - 12, base + 12), tec: int(base - 10, base + 10), fis: int(base - 10, base + 10), def: pos === 'DEF' || pos === 'LAT' || pos === 'VOL' ? int(base - 4, base + 12) : int(base - 25, base - 5) };
    Object.keys(attrs).forEach(k => attrs[k] = Math.max(40, Math.min(95, attrs[k])));
    const ov = Math.round(Object.values(attrs).reduce((a, b) => a + b, 0) / 4);
    return { id: 'm_' + name.toLowerCase(), name, role: 'jugador', plays: true, number, positions: [pos], foot, status: name === 'Beto' ? 'lesionado' : name === 'Santi' ? 'ausente' : 'ok',
      status_until: name === 'Beto' ? day(now.getTime() + 12 * 864e5) : null, status_note: name === 'Beto' ? 'Desgarro, vuelve en dos semanas' : name === 'Santi' ? 'De viaje' : null,
      claimed: !['Mono', 'Juanchi', 'Rama'].includes(name), active: true, overall: ov, attrs, guest: false, ext_player_id: 9000 + i, contact: null };
  });
  members.push({ id: 'm_dt', name: 'Profe Gus', role: 'dt', plays: false, number: null, positions: [], foot: null, status: 'ok', claimed: true, active: true, overall: null, attrs: {}, guest: false });
  members.push({ id: 'm_ayu', name: 'Lalo', role: 'ayudante', plays: false, number: null, positions: [], foot: null, status: 'ok', claimed: true, active: true, overall: null, attrs: {}, guest: false });
  members.push({ id: 'm_primo', name: 'Primo de Lucho', role: 'jugador', plays: true, number: 22, positions: ['DEL'], foot: 'der', status: 'ok', claimed: false, active: true, overall: 70, attrs: { vel: 74, tec: 70, fis: 68, def: 50 }, guest: true });
  const M = (name) => members.find(m => m.name === name);
  const squad = members.filter(m => m.plays && !m.guest);

  /* ---------- El torneo ---------- */
  const TEAMS = [['Los Halcones', 1], ['Deportivo Pinar', 2], ['Los Tilos', 3], ['Atlético Sur', 4], ['Club Parque', 5], ['Real Barrio', 6], ['Unión Norte', 7], ['La Fragata', 8]];
  const US = 1;
  const FIRST = ['Juan', 'Martín', 'Lucas', 'Mateo', 'Bruno', 'Franco', 'Tomás', 'Joaquín', 'Nicolás', 'Agustín', 'Bautista', 'Ignacio', 'Valentín', 'Lautaro', 'Santino', 'Facundo', 'Gonzalo', 'Ezequiel', 'Thiago', 'Iván'];
  const LAST = ['García', 'Pereyra', 'Sosa', 'Romero', 'Acosta', 'Benítez', 'Medina', 'Herrera', 'Aguirre', 'Giménez', 'Molina', 'Castro', 'Ojeda', 'Ríos', 'Luna', 'Ferreyra', 'Vera', 'Godoy', 'Ledesma', 'Peralta', 'Domínguez', 'Quiroga'];
  const rosters = {};
  TEAMS.forEach(([, tid]) => {
    if (tid === US) { rosters[tid] = squad.map(m => ({ id: m.ext_player_id, n: m.name === 'Tomi' ? 'Tomás Ferrari' : m.name + ' (Halcones)', nro: m.number, mid: m.id })); return; }
    const used = new Set(); rosters[tid] = Array.from({ length: 16 }, (_, k) => { let nm; do { nm = pick(FIRST) + ' ' + pick(LAST); } while (used.has(nm)); used.add(nm); return { id: tid * 100 + k, n: nm, nro: k === 0 ? 1 : k + 1 }; });
  });
  // Nombres "oficiales" de los nuestros, como figurarían en la planilla del torneo
  const REAL = { Tano: 'Gastón Tanoira', Colo: 'Federico Colombo', Ruso: 'Iván Petrov', Fede: 'Federico Ruiz', Mati: 'Matías Álvarez', Pipa: 'Pablo Pipino', Chino: 'Kevin Oshiro', Lucho: 'Luciano Ferraro',
    Tomi: 'Tomás Ferrari', Nacho: 'Ignacio Vidal', Polaco: 'Esteban Kowalski', Gordo: 'Rodrigo Gordillo', Rama: 'Ramiro Paz', Facu: 'Facundo Ibarra', Juanchi: 'Juan Cruz Ortiz', Beto: 'Alberto Núñez', Santi: 'Santiago Lagos', Mono: 'Marcos Monti' };
  rosters[US].forEach(p => { const m = members.find(x => x.id === p.mid); p.n = REAL[m.name]; });
  // Fixture todos contra todos (método del círculo): 7 fechas, y la 8 arranca la vuelta
  const ids = TEAMS.map(t => t[1]), rounds = [];
  for (let r = 0; r < 7; r++){
    const arr = [ids[0], ...ids.slice(1).map((_, i) => ids[1 + ((i + r) % 7)])], pairs = [];
    for (let i = 0; i < 4; i++) pairs.push(r % 2 ? [arr[7 - i], arr[i]] : [arr[i], arr[7 - i]]);
    rounds.push(pairs);
  }
  rounds.push(rounds[0].map(([a, b]) => [b, a]));
  const OURS = [[3, 1], [2, 2], [4, 2], [0, 1], [2, 0], [1, 2]]; // goles nuestros y del rival, fechas 1 a 6
  let ourK = 0;
  const lm = [];
  rounds.forEach((pairs, r) => {
    const k = r + 1, played = k <= 6, d = k <= 6 ? fecha(k) : k === 7 ? nextDate : new Date(nextDate.getTime() + 7 * 864e5);
    pairs.forEach(([h, a], j) => {
      const ours = h === US || a === US;
      let gh = null, ga = null;
      if (played){
        if (ours){ const [f, c] = OURS[ourK++]; [gh, ga] = h === US ? [f, c] : [c, f]; }
        else { gh = int(0, 4); ga = int(0, 3); }
      }
      const hora = ours ? '15:30' : ['11:00', '12:15', '14:15', '16:45'][j];
      lm.push({ id: 7000 + k * 10 + j, fecha: 'FECHA ' + k, n: k, day: day(d), hora, home: TEAMS[h - 1][0], away: TEAMS[a - 1][0], home_id: h, away_id: a,
        gh, ga, status: played ? 'FINA' : null, cancha: String(int(1, 12)) });
    });
  });
  // Planilla de cada partido jugado: quiénes jugaron, goles, tarjetas y figura
  const sheetSide = (tid, goals, k) => {
    let list = rosters[tid].slice();
    if (tid === US) list = list.filter(p => { const m = members.find(x => x.id === p.mid); return !(m.name === 'Beto' && k >= 5) && !(m.name === 'Santi' && k === 6) && !(['Mono', 'Juanchi'].includes(m.name) && k % 2); });
    list = list.slice(0, 14).map(p => ({ ...p }));
    const outfield = list.filter(p => p.nro !== 1 && p.nro !== 12);
    const w = (p) => tid === US ? ({ 9: 5, 10: 3, 11: 3, 7: 3, 19: 2, 8: 2, 20: 2 }[p.nro] || 0.6) : (p.nro >= 7 && p.nro <= 11 ? 3 : 1);
    for (let g = 0; g < goals; g++){ const tot = outfield.reduce((a, p) => a + w(p), 0); let x = rnd() * tot; const s = outfield.find(p => (x -= w(p)) <= 0) || outfield[0]; s.g = (s.g || 0) + 1; }
    const cards = rnd() < 0.7 ? int(1, 3) : 0;
    for (let c = 0; c < cards; c++){ const p = pick(outfield); p.am = Math.min(2, (p.am || 0) + 1); }
    if (rnd() < 0.12) pick(outfield).ro = 1;
    return list.map(p => { const o = { id: p.id, n: p.n, nro: p.nro }; if (p.g) o.g = p.g; if (p.am) o.am = p.am; if (p.ro) o.ro = p.ro; return o; });
  };
  lm.filter(m => m.status === 'FINA').forEach(m => {
    m.sheet = { h: sheetSide(m.home_id, m.gh, m.n), a: sheetSide(m.away_id, m.ga, m.n) };
    const win = m.gh >= m.ga ? m.sheet.h : m.sheet.a, best = win.filter(p => p.g).sort((a, b) => b.g - a.g)[0] || win[int(1, win.length - 1)];
    best.fig = true;
  });
  // Tabla, goleadores, figuras, valla, fair play y suspendidos
  const st = {}; TEAMS.forEach(([name, tid]) => st[tid] = { id: tid, name, pj: 0, pg: 0, pe: 0, pp: 0, gf: 0, gc: 0 });
  const pl = {}, cardsBy = {};
  lm.filter(m => m.status === 'FINA').forEach(m => {
    const h = st[m.home_id], a = st[m.away_id];
    h.pj++; a.pj++; h.gf += m.gh; h.gc += m.ga; a.gf += m.ga; a.gc += m.gh;
    if (m.gh > m.ga){ h.pg++; a.pp++; } else if (m.gh < m.ga){ a.pg++; h.pp++; } else { h.pe++; a.pe++; }
    [[m.sheet.h, m.home_id], [m.sheet.a, m.away_id]].forEach(([side, tid]) => side.forEach(p => {
      const o = pl[p.id] || (pl[p.id] = { id: p.id, name: p.n, team: st[tid].name, team_id: tid, pj: 0, goles: 0, amarillas: 0, azules: 0, rojas: 0, figura: 0, numero: p.nro });
      o.pj++; o.goles += p.g || 0; o.amarillas += p.am || 0; o.rojas += p.ro || 0; o.figura += p.fig ? 1 : 0;
      const c = cardsBy[tid] || (cardsBy[tid] = { am: 0, ro: 0 }); c.am += p.am || 0; c.ro += p.ro || 0;
    }));
  });
  const standings = Object.values(st).map(s => ({ ...s, dg: s.gf - s.gc, pts: s.pg * 3 + s.pe }))
    .sort((a, b) => b.pts - a.pts || b.dg - a.dg || b.gf - a.gf).map((s, i) => ({ pos: i + 1, ...s }));
  const all = Object.values(pl);
  const nextRival = (() => { const m = lm.find(x => x.n === 7 && (x.home_id === US || x.away_id === US)); return m.home_id === US ? m.away_id : m.home_id; })();
  const susp = all.filter(p => p.team_id === nextRival && p.goles).slice(0, 1).map(p => ({ name: p.name, team: p.team, team_id: p.team_id, fechas: 1 }))
    .concat(all.filter(p => p.rojas && p.team_id !== nextRival).slice(0, 1).map(p => ({ name: p.name, team: p.team, team_id: p.team_id, fechas: 2 })));
  const league = {
    site: 'liga-de-ejemplo.com', torneo_id: 1, torneo_name: 'Liga de ejemplo · Apertura', team_ext_id: US, team_ext_name: 'Los Halcones', last_sync: iso(lastSat.getTime() + 5 * 36e5), last_error: null,
    standings,
    players: all.filter(p => p.team_id === US).sort((a, b) => b.goles - a.goles).map(p => ({ id: p.id, name: p.name, pj: p.pj, goles: p.goles, amarillas: p.amarillas, azules: 0, rojas: p.rojas, figura: p.figura, numero: String(p.numero) })),
    scorers: all.filter(p => p.goles).sort((a, b) => b.goles - a.goles).slice(0, 25).map(p => ({ id: p.id, name: p.name, team: p.team, team_id: p.team_id, goles: p.goles })),
    figures: all.filter(p => p.figura).sort((a, b) => b.figura - a.figura).slice(0, 15).map(p => ({ name: p.name, team: p.team, team_id: p.team_id, figura: p.figura })),
    defense: standings.slice().sort((a, b) => a.gc - b.gc).map(s => ({ team: s.name, team_id: s.id, gc: s.gc, pj: s.pj })),
    fairplay: standings.map(s => ({ team: s.name, team_id: s.id, amarillas: (cardsBy[s.id] || {}).am || 0, azules: 0, rojas: (cardsBy[s.id] || {}).ro || 0, puntos: ((cardsBy[s.id] || {}).am || 0) + 3 * ((cardsBy[s.id] || {}).ro || 0) })).sort((a, b) => a.puntos - b.puntos),
    suspended: susp,
    matches: lm
  };

  /* ---------- Nuestros partidos, estadísticas y votos ---------- */
  const matches = [], stats = [], votes = [], callups = [];
  lm.filter(m => m.home_id === US || m.away_id === US).forEach(m => {
    const home = m.home_id === US, played = m.status === 'FINA';
    const x = { id: 'x' + m.n, opponent: home ? m.away : m.home, starts_at: iso(m.n <= 6 ? fecha(m.n) : m.n === 7 ? nextDate : nextDate.getTime() + 7 * 864e5),
      venue: 'Cancha ' + m.cancha, kind: 'oficial', goals_for: played ? (home ? m.gh : m.ga) : null, goals_against: played ? (home ? m.ga : m.gh) : null,
      difficulty: int(2, 4), notes: m.n === 7 ? 'Juegan con dos 9 de área. Ojo con la pelota parada.' : null, played, result_at: played ? iso(new Date(fecha(m.n)).getTime() + 2.5 * 36e5) : null,
      sort: m.n, dt_member: null, ext_id: m.id, fecha_label: 'Fecha ' + m.n };
    matches.push(x);
    if (!played) return;
    const side = home ? m.sheet.h : m.sheet.a, won = x.goals_for > x.goals_against, lost = x.goals_for < x.goals_against;
    side.forEach(p => {
      const mm = members.find(z => z.ext_player_id === p.id);
      const rate = Math.max(4, Math.min(9.5, (won ? 7 : lost ? 5.5 : 6.3) + (p.g || 0) * 0.8 + (p.fig ? 0.7 : 0) + (rnd() - 0.5) * 2));
      stats.push({ match_id: x.id, member_id: mm.id, played: true, goals: p.g || 0, assists: rnd() < 0.18 ? 1 : 0, yellow: p.am || 0, red: !!p.ro, by_self: false, official: true,
        note: null, self_rating: rnd() < 0.5 ? Math.round(rate * 2) / 2 : null, dt_rating: m.n === 6 && ['Facu', 'Rama'].includes(mm.name) ? null : Math.round(rate * 2) / 2 });
    });
    // Votos de la figura
    const voters = squad.filter(z => z.claimed).slice(0, 10), cands = side.map(p => members.find(z => z.ext_player_id === p.id).id);
    const fav = cands[(m.n * 3) % cands.length];
    voters.forEach(v => { const to = rnd() < 0.55 ? fav : pick(cands); if (to !== v.id) votes.push({ match_id: x.id, voter_id: v.id, voted_id: to }); });
  });
  // Un amistoso jugado, con un invitado
  matches.unshift({ id: 'x_am', opponent: 'Los del Barrio', starts_at: iso(fecha(1).getTime() - 7 * 864e5), venue: 'Plaza Mitre', kind: 'amistoso', goals_for: 4, goals_against: 4, difficulty: 2, notes: null, played: true, result_at: iso(fecha(1).getTime() - 7 * 864e5 + 3 * 36e5), sort: 0, dt_member: null, ext_id: null, fecha_label: null });
  squad.slice(0, 11).forEach((m, i) => stats.push({ match_id: 'x_am', member_id: m.id, played: true, goals: [0, 0, 0, 0, 0, 1, 0, 1, 1, 0, 1][i], assists: 0, yellow: 0, red: false, by_self: true, note: null, self_rating: null, dt_rating: 6 + (i % 3) * 0.5 }));
  stats.push({ match_id: 'x_am', member_id: 'm_primo', played: true, goals: 1, assists: 1, yellow: 0, red: false, by_self: false, note: null, self_rating: null, dt_rating: 7.5 });
  // Convocatoria del próximo: algunos van, otros dudan, otros no; "Tomi" (vos, como jugador) todavía no respondió
  const ans = { Tano: 'voy', Colo: 'voy', Ruso: 'voy', Fede: 'voy', Mati: 'duda', Pipa: 'voy', Chino: 'voy', Lucho: 'voy', Nacho: 'no_voy', Polaco: 'voy', Gordo: 'voy', Facu: 'voy', Beto: 'no_voy', Santi: 'no_voy', Rama: 'duda' };
  Object.entries(ans).forEach(([nm, a]) => callups.push({ match_id: 'x7', member_id: M(nm).id, answer: a, reason: a === 'no_voy' ? { Nacho: 'Cumpleaños de mi vieja', Beto: '🤕 Lesión', Santi: '✈️ De viaje' }[nm] : null }));

  // Pizarra: el 4-3-3 de siempre (Nacho no va: queda en rojo para que el DT lo vea)
  const slots = formationSlots('4-3-3');
  ['Tano', 'Fede', 'Colo', 'Ruso', 'Mati', 'Pipa', 'Chino', 'Lucho', 'Tomi', 'Polaco', 'Nacho'].forEach((nm, i) => slots[i].m = M(nm).id);
  const lineups = [{ id: 'l1', match_id: null, name: 'Equipo base', formation: '4-3-3', slots, notes: { [M('Polaco').id]: 'Presioná al central zurdo, sale mal', [M('Tomi').id]: 'Volvé a marcar al lateral' }, updated_at: iso(now) }];
  const tips = [
    { id: 'tip1', lineup_id: 'l1', member_id: M('Chino').id, body: 'Contra Club Parque jugaría con Facu de 5, recupera mucho y nos da aire.', formation: null, slots: null, likers: ['m_pipa', 'm_lucho', 'm_tano'], status: 'abierta', reply: null, created_at: iso(now.getTime() - 20 * 36e5), updated_at: iso(now) },
    { id: 'tip2', lineup_id: 'l1', member_id: M('Lucho').id, body: 'Si no está Nacho, pongamos a Juanchi arriba con el Polaco.', formation: '4-4-2',
      slots: formationSlots('4-4-2').map((s, i) => ({ ...s, m: ['Tano', 'Fede', 'Colo', 'Ruso', 'Mati', 'Tomi', 'Pipa', 'Chino', 'Lucho', 'Polaco', 'Juanchi'].map(x => M(x).id)[i] })),
      likers: ['m_polaco'], status: 'abierta', reply: null, created_at: iso(now.getTime() - 5 * 36e5), updated_at: iso(now) }
  ];

  /* ---------- Entrenamientos ---------- */
  const R = (typeof ROUTINES !== 'undefined' && ROUTINES.find(r => r.id === 'casa-piernas')) || null;
  const photo = (txt, bg) => 'data:image/svg+xml;utf8,' + encodeURIComponent(`<svg xmlns="http://www.w3.org/2000/svg" width="480" height="640"><rect width="100%" height="100%" fill="${bg}"/><text x="50%" y="46%" font-size="90" text-anchor="middle">💪</text><text x="50%" y="58%" font-family="sans-serif" font-size="30" fill="#fff" text-anchor="middle">${txt}</text></svg>`);
  const TR = { trainings: [
    { id: 'tr1', kind: 'casa', title: R ? R.name : 'Piernas en casa', details: 'Para llegar fuertes al sábado. Mandá la foto cuando lo termines.', starts_at: null, due_at: iso(now.getTime() + 2 * 864e5), venue: null, mandatory: true, proof: true, plan: R && typeof planOf === 'function' ? planOf(R) : null, created_at: iso(now.getTime() - 864e5) },
    { id: 'tr2', kind: 'cancha', title: 'Fútbol reducido y definición', details: 'Traigan pecheras. Arrancamos puntual.', starts_at: iso(new Date(now.getTime() + 864e5).setHours(20, 0, 0, 0)), due_at: null, venue: 'Club Parque, cancha 3', mandatory: false, proof: false, created_at: iso(now.getTime() - 2 * 864e5) },
    { id: 'tr3', kind: 'cancha', title: 'Físico y pelota parada', details: 'Córners y tiros libres.', starts_at: iso(new Date(now.getTime() - 5 * 864e5).setHours(20, 0, 0, 0)), due_at: null, venue: 'Club Parque, cancha 3', mandatory: false, proof: false, created_at: iso(now.getTime() - 8 * 864e5) }
  ], logs: [] };
  ['Pipa', 'Chino', 'Polaco', 'Colo', 'Lucho', 'Tano'].forEach((nm, i) => TR.logs.push({ training_id: 'tr1', member_id: M(nm).id, status: 'hecho', minutes: 30 + i * 3, note: i % 2 ? 'Completo' : null, photo: photo(nm, ['#0E7A3B', '#1D4ED8', '#B45309', '#7C3AED', '#BE123C', '#0F766E'][i]) }));
  TR.logs.push({ training_id: 'tr1', member_id: M('Beto').id, status: 'no_puedo', reason: '🤕 Lesión' });
  ['Tano', 'Colo', 'Pipa', 'Chino', 'Lucho', 'Polaco', 'Facu', 'Gordo'].forEach(nm => TR.logs.push({ training_id: 'tr2', member_id: M(nm).id, status: 'voy' }));
  squad.forEach((m, i) => { if (i < 13) TR.logs.push({ training_id: 'tr3', member_id: m.id, status: i % 5 === 4 ? 'ausente' : 'presente' }); });
  const RT = [];

  /* ---------- Quién sos en el ejemplo ---------- */
  let role = 'dt';
  const meId = () => role === 'dt' ? 'm_dt' : M('Tomi').id;
  const bundle = () => ({
    team: { ...team }, me: { id: meId(), role: role === 'dt' ? 'dt' : 'jugador' },
    members, matches, callups, lineups,
    stats: stats.map(s => ({ ...s })),
    votes: votes.map(v => ({ match_id: v.match_id, voted_id: v.voted_id, mine: v.voter_id === meId() }))
  });
  const no = (msg) => { throw new Error(msg); };
  const SOLO = 'Esto se hace con tu propia cuenta. Tocá «Crear mi cuenta» arriba.';
  const api = {
    fc_me: () => ({ user: { id: 'demo_user', nick: role === 'dt' ? 'Profe Gus' : 'Tomi', has_pin: true }, teams: [{ id: 'demo', name: team.name, emoji: team.emoji, role: role === 'dt' ? 'dt' : 'jugador', member_id: meId() }] }),
    fc_team: () => bundle(),
    fc_league: () => JSON.parse(JSON.stringify(league)),
    fc_league_refresh: () => no('En el ejemplo los datos ya están al día.'),
    fc_league_set: () => no(SOLO),
    fc_team_pin: (a) => { team.pinned = a.p ? { ...a.p, by: 'Profe Gus', at: iso(new Date()) } : null; return null; },
    fc_team_settings: (a) => { if (a.p.new_code || a.p.new_dt_code) no(SOLO); Object.assign(team, a.p); return null; },
    fc_team_create: () => no(SOLO), fc_join: () => no(SOLO), fc_leave: () => no(SOLO), fc_team_preview: () => no(SOLO),
    api_register: () => no(SOLO), api_login: () => no(SOLO), api_set_pin: () => no(SOLO),
    fc_push_subscribe: () => no(SOLO), fc_push_unsubscribe: () => null,
    fc_match_save: (a) => {
      let x = a.p_id && matches.find(y => y.id === a.p_id);
      if (!x){ x = { id: id('x'), opponent: 'Rival', starts_at: null, venue: null, kind: 'amistoso', goals_for: null, goals_against: null, difficulty: null, notes: null, played: false, result_at: null, sort: 99, dt_member: null, ext_id: null, fecha_label: null }; matches.push(x); }
      const p = a.p, was = x.played;
      for (const k of ['opponent', 'starts_at', 'venue', 'kind', 'notes', 'dt_member']) if (k in p) x[k] = p[k] === '' ? null : p[k];
      for (const k of ['goals_for', 'goals_against', 'difficulty']) if (k in p) x[k] = p[k] === '' || p[k] == null ? null : +p[k];
      if ('played' in p) x.played = p.played;
      if (x.played && !was) x.result_at = iso(new Date());
      matches.sort((a, b) => (a.starts_at ? new Date(a.starts_at) : 0) - (b.starts_at ? new Date(b.starts_at) : 0) || a.sort - b.sort);
      return x.id;
    },
    fc_match_delete: (a) => { const i = matches.findIndex(x => x.id === a.p_id); if (i >= 0) matches.splice(i, 1); return null; },
    fc_rsvp: (a) => { const mid = a.p_member || meId(); const i = callups.findIndex(c => c.match_id === a.p_match && c.member_id === mid); if (i >= 0) callups.splice(i, 1); if (a.p_answer) callups.push({ match_id: a.p_match, member_id: mid, answer: a.p_answer, reason: a.p_reason || null }); return null; },
    fc_stats_save: (a) => {
      let s = stats.find(z => z.match_id === a.p_match && z.member_id === a.p_member);
      if (!s){ s = { match_id: a.p_match, member_id: a.p_member, played: true, goals: 0, assists: 0, yellow: 0, red: false, by_self: a.p_member === meId(), note: null, self_rating: null, dt_rating: null }; stats.push(s); }
      for (const k of ['played', 'goals', 'assists', 'yellow', 'red', 'note']) if (k in a.p) s[k] = a.p[k];
      if ('self_rating' in a.p) s.self_rating = a.p.self_rating === '' ? null : a.p.self_rating;
      if ('dt_rating' in a.p) s.dt_rating = a.p.dt_rating === '' ? null : a.p.dt_rating;
      return null;
    },
    fc_vote: (a) => { const i = votes.findIndex(v => v.match_id === a.p_match && v.voter_id === meId()); if (i >= 0) votes.splice(i, 1); votes.push({ match_id: a.p_match, voter_id: meId(), voted_id: a.p_voted }); return null; },
    fc_member_save: (a) => {
      let m = a.p_id && members.find(z => z.id === a.p_id);
      if (!m){ m = { id: id('m'), name: a.p.name, role: 'jugador', plays: true, number: null, positions: [], foot: null, status: 'ok', status_until: null, status_note: null, claimed: false, active: true, overall: null, attrs: {}, guest: false }; members.push(m); }
      for (const [k, v] of Object.entries(a.p)) m[k] = k === 'number' || k === 'overall' ? (v === '' || v == null ? null : +v) : (v === '' ? null : v);
      return m.id;
    },
    fc_lineup_save: (a) => { let l = a.p_id && lineups.find(z => z.id === a.p_id); if (!l){ l = { id: id('l'), match_id: null }; lineups.unshift(l); } Object.assign(l, a.p, { updated_at: iso(new Date()) }); return l.id; },
    fc_lineup_delete: (a) => { const i = lineups.findIndex(l => l.id === a.p_id); if (i >= 0) lineups.splice(i, 1); return null; },
    fc_trainings_list: () => ({ trainings: TR.trainings.map(t => ({ ...t })), logs: TR.logs.map(l => ({ ...l, has_photo: !!l.photo, photo: undefined })) }),
    fc_training_save: (a) => { let t = a.p_id && TR.trainings.find(z => z.id === a.p_id); if (!t){ t = { id: id('t'), created_at: iso(new Date()) }; TR.trainings.unshift(t); } for (const [k, v] of Object.entries(a.p)) t[k] = v === '' ? null : v; return t.id; },
    fc_training_delete: (a) => { const i = TR.trainings.findIndex(t => t.id === a.p_training); if (i >= 0) TR.trainings.splice(i, 1); return null; },
    fc_training_log: (a) => {
      const mid = a.p_member || meId(), t = TR.trainings.find(z => z.id === a.p_training);
      let l = TR.logs.find(z => z.training_id === a.p_training && z.member_id === mid);
      if (a.p.status === 'hecho' && t.proof && !a.p.photo && !(l && l.photo)){ const e = new Error('Falta la foto de prueba'); e.code = 'FALTA_FOTO'; throw e; }
      if (!l){ l = { training_id: a.p_training, member_id: mid }; TR.logs.push(l); }
      for (const [k, v] of Object.entries(a.p)) l[k] = v === '' ? null : v;
      return null;
    },
    fc_proof: (a) => (TR.logs.find(z => z.training_id === a.p_training && z.member_id === a.p_member) || {}).photo || null,
    fc_routines_list: () => RT.filter(r => !r.archived),
    fc_routine_save: (a) => { let r = a.p_id && RT.find(z => z.id === a.p_id); if (!r){ r = { id: id('r') }; RT.push(r); } Object.assign(r, a.p); return r.id; },
    fc_board_tips: () => tips.map(t => ({ ...t, likes: t.likers.length, liked: t.likers.includes(meId()), likers: undefined })),
    fc_board_tip_save: (a) => { const t = { id: id('tip'), lineup_id: a.p_lineup, member_id: meId(), body: a.p_body || '', formation: a.p_formation, slots: a.p_slots, likers: [], status: 'abierta', reply: null, created_at: iso(new Date()), updated_at: iso(new Date()) }; tips.unshift(t); return t.id; },
    fc_board_tip_like: (a) => { const t = tips.find(x => x.id === a.p_tip); t.likers = t.likers.includes(meId()) ? t.likers.filter(x => x !== meId()) : [...t.likers, meId()]; return null; },
    fc_board_tip_status: (a) => { const t = tips.find(x => x.id === a.p_tip); t.status = a.p_status; if (a.p_reply != null) t.reply = a.p_reply; t.updated_at = iso(new Date()); return null; },
    fc_pickups: () => []
  };
  window.DEMO = {
    get role(){ return role; },
    setRole(r){ role = r === 'jugador' ? 'jugador' : 'dt'; },
    async rpc(fn, args){
      await new Promise(r => setTimeout(r, 60));
      if (!api[fn]) throw new Error('En el equipo de ejemplo esto no está disponible.');
      const out = api[fn](args || {});
      return out === undefined ? null : JSON.parse(JSON.stringify(out));
    }
  };
})();
