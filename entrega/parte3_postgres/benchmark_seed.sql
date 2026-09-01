-- Volumen sintetico para medir el plan de la consulta principal.
--   psql -d parte3_reservas -f benchmark_seed.sql
-- 300.000 lotes, de los que solo ~5% siguen vivos: es la forma que toma un
-- almacen real, donde los lotes agotados se acumulan y nunca se borran.
INSERT INTO stock_lots (material_id, warehouse_id, quantity, received_at)
SELECT 1 + (i % 4),
       1 + (i % 3),
       CASE WHEN i % 20 = 0 THEN 100.0 ELSE 0.0 END,
       timestamptz '2024-01-01' + (i || ' minutes')::interval
FROM generate_series(1, 300000) i;
ANALYZE stock_lots;
