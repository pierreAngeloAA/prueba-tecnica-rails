-- Datos sinteticos para reproducir el plan documentado en NOTAS.md.
--   psql -d parte1_configuracion_development -f db/benchmark_seed.sql
-- 200 renglones x 25 unidades x 15 claves x 5 versiones + cabeceras = 378.000 filas.
TRUNCATE line_item_directives;

INSERT INTO line_item_directives (line_item_id, directive_type, unit_uid, key, value, source, version, created_at)
SELECT li, 'unit', 'unit-' || u, 'key_' || k, 'v' || li || u || k || ver,
       (ARRAY['user','resolution','preserved','default'])[1 + (k + ver) % 4], ver,
       timestamp '2026-01-01' + (ver || ' minutes')::interval
FROM generate_series(1, 200) li,
     generate_series(1, 25)  u,
     generate_series(1, 15)  k,
     generate_series(1, 5)   ver;

INSERT INTO line_item_directives (line_item_id, directive_type, unit_uid, key, value, source, version, created_at)
SELECT li, 'header', NULL, 'key_' || k, 'h' || li || k, 'default', 1, timestamp '2026-01-01'
FROM generate_series(1, 200) li,
     generate_series(1, 15)  k;

ANALYZE line_item_directives;
