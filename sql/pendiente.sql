-- La Casaca: lo único que falta en la base (Supabase pide confirmarlo porque la función borra entrenamientos).

-- Borrar un entrenamiento (DT y ayudantes)
create or replace function fc_training_delete(p_token uuid, p_training uuid) returns void
language plpgsql security definer set search_path = public as $$
declare t uuid;
begin
  select team_id into t from fc_trainings where id = p_training;
  perform _fc_admin(_uid(p_token), t);
  delete from fc_trainings where id = p_training;
end $$;

-- Trae ya mismo goleadores, figuras, valla, fair play y suspendidos del torneo de Camarón.
update fc_leagues set last_request = null where torneo_id = 175;
select fc_league_fetch();
