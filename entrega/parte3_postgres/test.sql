-- ============================================================================
-- Pruebas de reserve_material
-- ============================================================================
--   psql -d parte3_reservas -f schema.sql -f reserve_material.sql -f seeds.sql -f test.sql
--
-- Cada caso corre dentro de BEGIN/ROLLBACK: parte siempre del mismo estado y,
-- de paso, demuestra que la funcion se ejecuta dentro de una transaccion de la
-- aplicacion. Las comprobaciones son ASSERT: si alguna falla, psql aborta con
-- ON_ERROR_STOP y el script devuelve codigo distinto de cero.
--
-- Inventario de partida (material 1, almacen 1), en orden FIFO:
--   lote 4: 75    lote 2: 250    lote 1: 100    lote 3: 50   = 475 total

\set ON_ERROR_STOP on
\timing off

\echo ''
\echo '=== 1. Cabe en un solo lote ==================================='
BEGIN;
DO $$
DECLARE r reservation_result;
BEGIN
  r := reserve_material(1, 1);
  ASSERT r.status            = 'fulfilled', 'status: ' || r.status;
  ASSERT r.quantity_reserved = 60,          'reservado: ' || r.quantity_reserved;
  ASSERT r.quantity_pending  = 0,           'pendiente: ' || r.quantity_pending;
  ASSERT r.lots_used         = 1,           'lotes: ' || r.lots_used;
  -- Consume del mas antiguo (lote 4), no del de id menor ni del mayor.
  ASSERT (SELECT quantity FROM stock_lots WHERE id = 4) = 15, 'el lote 4 deberia quedar en 15';
  ASSERT (SELECT quantity FROM stock_lots WHERE id = 2) = 250, 'el lote 2 no deberia tocarse';
  ASSERT (SELECT count(*) FROM stock_movements WHERE request_id = 1) = 1, 'un solo movimiento';
END $$;
ROLLBACK;
\echo 'OK'

\echo ''
\echo '=== 2. Necesita varios lotes, en orden FIFO ==================='
BEGIN;
DO $$
DECLARE r reservation_result; v_orden BIGINT[];
BEGIN
  r := reserve_material(2, 1);
  ASSERT r.status            = 'fulfilled', 'status: ' || r.status;
  ASSERT r.quantity_reserved = 200,         'reservado: ' || r.quantity_reserved;
  ASSERT r.lots_used         = 2,           'lotes: ' || r.lots_used;
  ASSERT (SELECT quantity FROM stock_lots WHERE id = 4) = 0,   'el lote 4 debe agotarse';
  ASSERT (SELECT quantity FROM stock_lots WHERE id = 2) = 125, 'del lote 2 deben salir 125';

  -- El consumo sigue el orden de entrada, no el de id.
  SELECT array_agg(stock_lot_id ORDER BY id) INTO v_orden
    FROM stock_movements WHERE request_id = 2;
  ASSERT v_orden = ARRAY[4::BIGINT, 2::BIGINT], 'orden FIFO incorrecto: ' || v_orden::text;
END $$;
ROLLBACK;
\echo 'OK'

\echo ''
\echo '=== 3. Agota el inventario justo ============================='
BEGIN;
DO $$
DECLARE r reservation_result;
BEGIN
  r := reserve_material(3, 1);
  ASSERT r.status            = 'fulfilled', 'status: ' || r.status;
  ASSERT r.quantity_reserved = 475,         'reservado: ' || r.quantity_reserved;
  ASSERT r.quantity_pending  = 0,           'pendiente: ' || r.quantity_pending;
  ASSERT r.lots_used         = 4,           'lotes: ' || r.lots_used;
  ASSERT (SELECT count(*) FROM stock_lots
           WHERE material_id = 1 AND warehouse_id = 1 AND quantity > 0) = 0,
         'no deberia quedar stock vivo';
  ASSERT (SELECT min(quantity) FROM stock_lots) >= 0, 'ninguna cantidad puede ser negativa';
END $$;
ROLLBACK;
\echo 'OK'

\echo ''
\echo '=== 4. Excede el inventario CON allow_partial ================='
BEGIN;
DO $$
DECLARE r reservation_result;
BEGIN
  r := reserve_material(4, 1, TRUE);
  ASSERT r.status            = 'partial', 'status: ' || r.status;
  ASSERT r.quantity_reserved = 475,       'reservado: ' || r.quantity_reserved;
  ASSERT r.quantity_pending  = 125,       'pendiente: ' || r.quantity_pending;
  ASSERT r.lots_used         = 4,         'lotes: ' || r.lots_used;
  ASSERT (SELECT status FROM reservation_requests WHERE id = 4) = 'partial', 'status persistido';
END $$;
ROLLBACK;
\echo 'OK'

\echo ''
\echo '=== 5. Excede el inventario SIN allow_partial: no toca nada ==='
BEGIN;
DO $$
DECLARE r reservation_result;
BEGIN
  r := reserve_material(5, 1, FALSE);
  ASSERT r.status            = 'backordered', 'status: ' || r.status;
  ASSERT r.quantity_reserved = 0,             'no debe reservar nada';
  ASSERT r.lots_used         = 0,             'no debe tocar lotes';
  ASSERT (SELECT count(*) FROM stock_movements WHERE request_id = 5) = 0,
         'no debe registrar movimientos';
  -- El inventario queda intacto, hasta el ultimo gramo.
  ASSERT (SELECT sum(quantity) FROM stock_lots WHERE material_id = 1 AND warehouse_id = 1) = 475,
         'el inventario no debe cambiar';
END $$;
ROLLBACK;
\echo 'OK'

\echo ''
\echo '=== 6. Material sin lotes ===================================='
BEGIN;
DO $$
DECLARE r reservation_result;
BEGIN
  r := reserve_material(6, 1);
  ASSERT r.status            = 'backordered', 'status: ' || r.status;
  ASSERT r.quantity_reserved = 0,             'reservado: ' || r.quantity_reserved;
  ASSERT r.quantity_pending  = 10,            'pendiente: ' || r.quantity_pending;
  ASSERT (SELECT count(*) FROM stock_movements WHERE request_id = 6) = 0, 'sin movimientos';
END $$;
ROLLBACK;
\echo 'OK'

\echo ''
\echo '=== 7. Lote con cantidad cero ================================'
BEGIN;
DO $$
DECLARE r reservation_result;
BEGIN
  r := reserve_material(7, 1);
  ASSERT r.status    = 'backordered', 'status: ' || r.status;
  ASSERT r.lots_used = 0,             'un lote a cero no cuenta como usado';
  -- Invariante 3: jamas un movimiento de cantidad cero.
  ASSERT (SELECT count(*) FROM stock_movements WHERE quantity_moved = 0) = 0,
         'no puede existir un movimiento de cantidad cero';
END $$;
ROLLBACK;
\echo 'OK'

\echo ''
\echo '=== 8. Segunda llamada sobre una solicitud ya atendida ========'
BEGIN;
DO $$
DECLARE r1 reservation_result; r2 reservation_result; v_movs INTEGER;
BEGIN
  r1 := reserve_material(8, 1);
  ASSERT r1.status = 'fulfilled', 'la primera llamada deberia cumplir';
  SELECT count(*) INTO v_movs FROM stock_movements WHERE request_id = 8;

  -- El reintento no debe consumir nada mas y debe devolver el resultado anterior.
  r2 := reserve_material(8, 1);
  ASSERT r2.status            = r1.status,            'status distinto en el reintento';
  ASSERT r2.quantity_reserved = r1.quantity_reserved, 'cantidad distinta en el reintento';
  ASSERT r2.quantity_pending  = r1.quantity_pending,  'pendiente distinto en el reintento';
  ASSERT r2.lots_used         = r1.lots_used,         'lotes distintos en el reintento';
  ASSERT (SELECT count(*) FROM stock_movements WHERE request_id = 8) = v_movs,
         'el reintento no puede anadir movimientos';
  ASSERT (SELECT quantity FROM stock_lots WHERE id = 4) = 15,
         'el reintento no puede volver a descontar';
END $$;
ROLLBACK;
\echo 'OK'

\echo ''
\echo '=== 9. Empate de received_at: desempata por id ================'
BEGIN;
DO $$
DECLARE r reservation_result; v_orden BIGINT[];
BEGIN
  r := reserve_material(9, 1);
  ASSERT r.status    = 'fulfilled', 'status: ' || r.status;
  ASSERT r.lots_used = 2,           'lotes: ' || r.lots_used;
  SELECT array_agg(stock_lot_id ORDER BY id) INTO v_orden
    FROM stock_movements WHERE request_id = 9;
  ASSERT v_orden = ARRAY[6::BIGINT, 7::BIGINT], 'con empate gana el id menor: ' || v_orden::text;
  ASSERT (SELECT quantity FROM stock_lots WHERE id = 6) = 0, 'el lote 6 se agota';
  ASSERT (SELECT quantity FROM stock_lots WHERE id = 7) = 5, 'del lote 7 salen 25';
END $$;
ROLLBACK;
\echo 'OK'

\echo ''
\echo '=== 10. No cruza almacenes ==================================='
BEGIN;
DO $$
DECLARE r reservation_result;
BEGIN
  r := reserve_material(4, 1, TRUE); -- pide 600, en el almacen 1 solo hay 475
  ASSERT r.quantity_reserved = 475, 'no debe echar mano del almacen 2';
  ASSERT (SELECT quantity FROM stock_lots WHERE id = 5) = 999,
         'el lote del almacen 2 debe quedar intacto';
END $$;
ROLLBACK;
\echo 'OK'

\echo ''
\echo '=== 11. Errores identificables, sin escrituras a medias ======='
BEGIN;
DO $$
DECLARE r reservation_result; v_code TEXT;
BEGIN
  -- Solicitud inexistente
  BEGIN r := reserve_material(9999, 1); v_code := 'ninguno';
  EXCEPTION WHEN OTHERS THEN v_code := SQLSTATE; END;
  ASSERT v_code = 'ES001', 'solicitud inexistente deberia dar ES001, dio ' || v_code;

  -- Almacen desconocido
  BEGIN r := reserve_material(10, 99); v_code := 'ninguno';
  EXCEPTION WHEN OTHERS THEN v_code := SQLSTATE; END;
  ASSERT v_code = 'ES004', 'almacen desconocido deberia dar ES004, dio ' || v_code;

  -- Almacen nulo
  BEGIN r := reserve_material(10, NULL); v_code := 'ninguno';
  EXCEPTION WHEN OTHERS THEN v_code := SQLSTATE; END;
  ASSERT v_code = 'ES003', 'almacen nulo deberia dar ES003, dio ' || v_code;

  -- Ningun error debe haber dejado rastro.
  ASSERT (SELECT count(*) FROM stock_movements) = 0, 'un error no puede escribir movimientos';
  ASSERT (SELECT sum(quantity) FROM stock_lots WHERE material_id = 1 AND warehouse_id = 1) = 475,
         'un error no puede tocar el inventario';
END $$;
ROLLBACK;
\echo 'OK'

\echo ''
\echo '=== 12. Los tres invariantes tras varias reservas ============='
BEGIN;
DO $$
DECLARE r reservation_result;
BEGIN
  r := reserve_material(1, 1);   -- 60
  r := reserve_material(9, 1);   -- 45 de otro material
  r := reserve_material(2, 1);   -- 200
  r := reserve_material(4, 1);   -- lo que quede, parcial

  -- 1. quantity_reserved = SUM(stock_movements.quantity_moved)
  ASSERT NOT EXISTS (
    SELECT 1 FROM reservation_requests q
     WHERE q.quantity_reserved <> COALESCE(
       (SELECT sum(m.quantity_moved) FROM stock_movements m WHERE m.request_id = q.id), 0)
  ), 'invariante 1: quantity_reserved no cuadra con los movimientos';

  -- 2. cantidad actual + total movido desde el lote = cantidad inicial
  ASSERT NOT EXISTS (
    SELECT 1 FROM stock_lots l
      JOIN (VALUES (1,100.0),(2,250.0),(3,50.0),(4,75.0),(5,999.0),(6,20.0),(7,30.0),(8,0.0))
        AS inicial(id, qty) ON inicial.id = l.id
     WHERE l.quantity + COALESCE(
       (SELECT sum(m.quantity_moved) FROM stock_movements m WHERE m.stock_lot_id = l.id), 0)
       <> inicial.qty
  ), 'invariante 2: el material movido no cuadra con la cantidad inicial';

  -- 3. nunca un movimiento de cantidad cero
  ASSERT (SELECT count(*) FROM stock_movements WHERE quantity_moved <= 0) = 0,
         'invariante 3: hay movimientos de cantidad no positiva';

  -- Y la restriccion del esquema sigue en pie.
  ASSERT (SELECT min(quantity) FROM stock_lots) >= 0, 'hay un lote en negativo';
END $$;
ROLLBACK;
\echo 'OK'

\echo ''
\echo '=============================================================='
\echo ' Todas las pruebas pasaron.'
\echo '=============================================================='
