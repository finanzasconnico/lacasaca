-- La Casaca: planilla de cada partido del torneo (goles, tarjetas y figura de los dos equipos).
-- Con eso salen el resumen de cada fecha y el informe de cada rival. Se puede correr más de una vez.
-- Solo se guardan nombre, número y lo que pasó en la cancha: nada de DNI ni datos personales.

alter table fc_league_matches add column if not exists sheet jsonb;
alter table fc_league_matches add column if not exists sheet_at timestamptz;

create or replace function _fc_league_sheet_row(d jsonb) returns jsonb
language sql immutable as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'id', (d->'torneoEquipoJugador'->'jugador'->>'id')::int,
    'n', trim(d->'torneoEquipoJugador'->'jugador'->>'nombre'),
    'nro', nullif(d->>'nroCamiseta','')::int,
    'g', nullif(coalesce((d->>'goles')::int, 0), 0),
    'am', nullif(coalesce((d->>'cantTam')::int, 0), 0),
    'az', nullif(coalesce((d->>'cantTaz')::int, 0), 0),
    'ro', nullif(coalesce((d->>'cantTro')::int, 0), 0),
    'fig', case when d->>'figura' = 'S' then true end));
$$;

-- Planilla de un partido: {"h": [...], "a": [...]} con los que jugaron de local y de visitante.
create or replace function _fc_league_sheet(j jsonb) returns jsonb
language sql immutable as $$
  select jsonb_build_object('h', coalesce((select jsonb_agg(_fc_league_sheet_row(d) order by (d->>'goles')::int desc nulls last, d->>'nroCamiseta')
                                           from jsonb_array_elements(coalesce(j->'equipo1'->'detallePartido', '[]')) d where coalesce((d->>'pj')::int, 0) > 0), '[]'),
                            'a', coalesce((select jsonb_agg(_fc_league_sheet_row(d) order by (d->>'goles')::int desc nulls last, d->>'nroCamiseta')
                                           from jsonb_array_elements(coalesce(j->'equipo2'->'detallePartido', '[]')) d where coalesce((d->>'pj')::int, 0) > 0), '[]'));
$$;

do $$ declare d text; begin
  d := pg_get_functiondef('fc_league_process'::regproc);
  if position('sheet:' in d) = 0 then
    -- Después de traer el fixture, pide la planilla de los partidos terminados que falten (o de los últimos días, por si la corrigen).
    d := replace(d, '      touched := array_append(touched, q.team_id);',
'      touched := array_append(touched, q.team_id);
      perform _fc_league_get(l, ''partido/partidos/'' || m.ext_id, ''sheet:'' || m.ext_id)
      from (select m.ext_id from fc_league_matches m
            where m.team_id = q.team_id and m.status = ''FINA''
              and (m.sheet is null or (m.day >= current_date - 4 and m.sheet_at < now() - interval ''1 hour''))
              and not exists (select 1 from fc_league_reqs r where r.team_id = q.team_id and r.kind = ''sheet:'' || m.ext_id and not r.done)
            order by m.day desc nulls last limit 60) m;');
    d := replace(d, '    elsif q.kind = ''partidos'' then',
'    elsif q.kind like ''sheet:%'' then
      update fc_league_matches set sheet = _fc_league_sheet(j), sheet_at = now()
      where team_id = q.team_id and ext_id = substr(q.kind, 7)::int;
    elsif q.kind = ''partidos'' then');
    execute d;
  end if;
  d := pg_get_functiondef('fc_league'::regproc);
  if position('sheet' in d) = 0 then
    d := replace(d, '''status'', m.status, ''cancha'', m.cancha)', '''status'', m.status, ''cancha'', m.cancha, ''sheet'', m.sheet)');
    execute d;
  end if;
end $$;
revoke all on function _fc_league_sheet(jsonb), _fc_league_sheet_row(jsonb) from public, anon, authenticated;

-- Pide ya las planillas de lo que se jugó hasta ahora.
select count(*) pedidas from (
  select _fc_league_get(l, 'partido/partidos/' || m.ext_id, 'sheet:' || m.ext_id)
  from fc_leagues l join fc_league_matches m on m.team_id = l.team_id
  where m.status = 'FINA' and m.sheet is null) s;
