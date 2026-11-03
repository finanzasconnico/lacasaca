-- La Casaca: entrar con un toque, como Tricount. Se puede correr más de una vez.
-- El link del equipo muestra el plantel; cada uno toca quién es y entra con una cuenta rápida (sin apodo ni PIN).
-- Después, si quiere, elige apodo y PIN para entrar desde otro celu.

-- El plantel libre para elegir, con quién es invitado
create or replace function fc_team_preview(p_code text) returns json
language plpgsql stable security definer set search_path = public as $$
declare t fc_teams; c text := upper(trim(coalesce(p_code,'')));
begin
  select * into t from fc_teams where code = c or dt_code = c;
  if t.id is null then raise exception 'CODIGO_INVALIDO'; end if;
  return json_build_object('id', t.id, 'name', t.name, 'emoji', t.emoji, 'staff', t.dt_code = c, 'kind', t.kind,
    'members', (select count(*) from fc_members where team_id = t.id and active),
    'taken', (select count(*) from fc_members where team_id = t.id and active and user_id is not null),
    'free', (select coalesce(json_agg(json_build_object('id', id, 'name', name, 'number', number, 'guest', guest, 'plays', plays, 'pos', positions[1])
        order by guest, not plays, name), '[]'::json)
      from fc_members where team_id = t.id and user_id is null and active));
end $$;

-- Entrar eligiendo quién sos (o con tu nombre si no estás en la lista). Devuelve la sesión.
create or replace function fc_quick_join(p_code text, p_member uuid default null, p_name text default null) returns json
language plpgsql security definer set search_path = public as $$
declare t fc_teams; c text := upper(trim(coalesce(p_code,''))); staff boolean; m fc_members; u users; base text; nk text; i int := 0;
begin
  select * into t from fc_teams where code = c or dt_code = c;
  if t.id is null then raise exception 'CODIGO_INVALIDO'; end if;
  staff := t.dt_code = c;
  -- Freno por si alguien abusa del link
  if (select count(*) from users u2 join fc_members m2 on m2.user_id = u2.id where m2.team_id = t.id and u2.created_at > now() - interval '1 hour') >= 40
    then raise exception 'DEMASIADOS'; end if;
  if p_member is not null then
    select * into m from fc_members where id = p_member and team_id = t.id and active for update;
    if m.id is null then raise exception 'NO_PERMITIDO'; end if;
    if m.user_id is not null then raise exception 'YA_RECLAMADO'; end if;
    base := m.name;
  else
    base := left(regexp_replace(trim(coalesce(p_name, '')), '\s+', ' ', 'g'), 30);
    if base = '' then raise exception 'DATOS_INVALIDOS'; end if;
  end if;
  -- Apodo interno único; si después crea su usuario, elige el que quiera
  loop
    nk := left(base, 24) || ' ' || lpad(floor(random() * 10000)::int::text, 4, '0');
    begin
      insert into users(nick, tz) values (nk, 'America/Argentina/Buenos_Aires') returning * into u;
      exit;
    exception when unique_violation then
      i := i + 1; if i > 8 then raise exception 'INTENTA_DE_NUEVO'; end if;
    end;
  end loop;
  if m.id is not null then
    update fc_members set user_id = u.id, role = case when staff then 'dt' else role end where id = m.id;
  else
    insert into fc_members(team_id, user_id, name, role) values (t.id, u.id, base, case when staff then 'dt' else 'jugador' end);
  end if;
  return json_build_object('token', u.token, 'team', t.id);
end $$;

-- Crear el usuario (opcional): apodo y PIN para entrar desde otro celu
create or replace function fc_account_secure(p_token uuid, p_nick text, p_pin text) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare v uuid := _uid(p_token); n text := regexp_replace(trim(coalesce(p_nick, '')), '\s+', ' ', 'g');
begin
  if n = '' or char_length(n) > 30 then raise exception 'APODO_INVALIDO'; end if;
  if p_pin !~ '^\d{4}$' then raise exception 'PIN_INVALIDO'; end if;
  begin
    update users set nick = n, pin_hash = crypt(p_pin, gen_salt('bf')), pin_fails = 0, pin_locked_until = null where id = v;
  exception when unique_violation then raise exception 'APODO_EN_USO';
  end;
end $$;

-- Si alguien eligió un nombre que no era el suyo: el DT o un ayudante lo libera para que lo elija quien corresponde
create or replace function fc_member_release(p_token uuid, p_member uuid) returns void
language plpgsql security definer set search_path = public as $$
declare m fc_members; me fc_members;
begin
  select * into m from fc_members where id = p_member;
  if m.id is null then raise exception 'NO_EXISTE'; end if;
  me := _fc_admin(_uid(p_token), m.team_id);
  if m.id = me.id then raise exception 'NO_PERMITIDO'; end if;
  if m.role = 'dt' and me.role <> 'dt' then raise exception 'SOLO_DT'; end if;
  update fc_members set user_id = null where id = p_member;
end $$;
