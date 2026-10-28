# Entrenamientos y torneo oficial

Estas partes ya están cargadas en la base (proyecto racha-app). Quedan anotadas acá para saber qué hay.

## Entrenamientos
- `fc_trainings`: entrenamientos en cancha (con día, hora y lugar) o en casa (con fecha límite y foto de prueba).
- `fc_training_logs`: la respuesta de cada jugador (va, no puede, presente, ausente, hecho, a rehacer), con la foto comprimida.
- Las fotos duran 24 h: `casaca-limpiar-fotos` corre cada 15 minutos y las borra; queda anotado que el entrenamiento se hizo.
- Funciones: `fc_trainings_list`, `fc_training_save`, `fc_training_log`, `fc_proof` y `fc_training_delete` (esta última está en `actualizar.sql`).

## Torneo oficial (Todo Torneos, por ejemplo Alto Nono)
- `fc_leagues`: el torneo conectado a cada equipo, con la tabla y la planilla oficial (solo nombre y números de cancha; los DNI y teléfonos no se guardan).
- `fc_league_matches`: todos los partidos del torneo, fecha a fecha.
- Los partidos del equipo se pasan solos a `fc_matches` (resultado, día, hora y cancha) y se enganchan con los que ya estaban cargados.
- Actualización automática con pg_cron (horario de Argentina):
  - sábados a las 20:00 y a las 22:00, para los resultados;
  - domingos, miércoles y viernes a las 12:00, para correcciones y horarios.
  - `casaca-torneo-procesar` corre cada 2 minutos y procesa lo que respondió el servidor del torneo.
- El DT puede forzar una actualización desde la app, como mucho una vez cada 10 minutos.

## Rutinas
- La biblioteca de rutinas de fútbol viene en la app (`ROUTINES` en `index.html`): explosividad, piques, pasadas, correr, fartlek, tren superior, fuerza, prevención (FIFA 11+), recuperación, técnica, activación pre-partido y HIIT.
- Cada ejercicio trae series, un consejo y un link a videos de YouTube de ese ejercicio.
- `fc_routines`: las rutinas propias del equipo (copias ajustadas o creadas desde cero). Funciones `fc_routines_list` y `fc_routine_save` (se archivan, no se borran).
- `fc_trainings.plan`: la rutina completa que se mandó con cada entrenamiento.

## Planilla de cada partido (rivales y resúmenes)
- `fc_league_matches.sheet`: la planilla oficial de cada partido terminado (quiénes jugaron, goles, tarjetas y figura de los dos equipos). Solo nombre, número y lo que pasó en la cancha.
- La pide sola `fc_league_process` después de cada actualización del fixture (ver `rivales.sql`).
- Con eso la app arma el informe de cada rival y el resumen de cada fecha.

## Invitaciones por WhatsApp
- `api/i.js` (Vercel): el link `/i/CODIGO` muestra en WhatsApp el escudo y el nombre del equipo, y después abre la app con el código.
