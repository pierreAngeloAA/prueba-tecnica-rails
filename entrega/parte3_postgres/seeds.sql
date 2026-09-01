-- Datos de prueba. Los ids son fijos para que test.sql pueda afirmar sobre
-- ellos y para que dos ejecuciones den exactamente el mismo resultado.

TRUNCATE stock_movements, reservation_requests, stock_lots, materials RESTART IDENTITY CASCADE;

-- Almacenes: 1 (principal) y 2 (secundario). No hay tabla de almacenes en el
-- esquema; existen porque tienen lotes. El 99 no existe.
INSERT INTO materials (id, code, unit) VALUES
  (1, 'ALU-6063-T5', 'kg'),   -- material con varios lotes
  (2, 'VID-LAM-6MM', 'm2'),   -- material con un unico lote grande
  (3, 'SIL-NEUTRO',  'un'),   -- material SIN lotes en ningun almacen
  (4, 'ALU-CERO',    'kg');   -- material cuyo unico lote esta a cero

SELECT setval('materials_id_seq', 10);

INSERT INTO stock_lots (id, material_id, warehouse_id, quantity, received_at) VALUES
  -- ALU-6063-T5 en el almacen 1: cuatro lotes, deliberadamente insertados
  -- desordenados para que el FIFO se note (el mas antiguo es el id 4).
  (1, 1, 1, 100.0000, '2026-03-10 08:00+00'),
  (2, 1, 1, 250.0000, '2026-02-01 08:00+00'),
  (3, 1, 1,  50.0000, '2026-04-20 08:00+00'),
  (4, 1, 1,  75.0000, '2026-01-15 08:00+00'),
  -- Mismo material en otro almacen: no debe tocarse al reservar en el 1.
  (5, 1, 2, 999.0000, '2026-01-01 08:00+00'),
  -- Dos lotes con el mismo received_at: el desempate por id los ordena.
  (6, 2, 1,  20.0000, '2026-05-05 12:00+00'),
  (7, 2, 1,  30.0000, '2026-05-05 12:00+00'),
  -- Lote agotado: existe, pero no debe generar movimiento ninguno.
  (8, 4, 1,   0.0000, '2026-01-01 08:00+00');

SELECT setval('stock_lots_id_seq', 100);

INSERT INTO reservation_requests (id, production_order_id, material_id, quantity_required) VALUES
  (1,  9001, 1,  60.0000),   -- cabe entero en el lote mas antiguo (75)
  (2,  9002, 1, 200.0000),   -- necesita varios lotes
  (3,  9003, 1, 475.0000),   -- agota el inventario del almacen 1 justo
  (4,  9004, 1, 600.0000),   -- excede el inventario  (con allow_partial)
  (5,  9005, 1, 600.0000),   -- excede el inventario  (sin allow_partial)
  (6,  9006, 3,  10.0000),   -- material sin lotes
  (7,  9007, 4,   5.0000),   -- material cuyo unico lote esta a cero
  (8,  9008, 1,  60.0000),   -- para la segunda llamada sobre solicitud atendida
  (9,  9009, 2,  45.0000),   -- cruza dos lotes con el mismo received_at
  (10, 9010, 1,  10.0000),   -- para probar el almacen inexistente
  -- Para test_concurrency.sh: dos solicitudes que juntas (600) exceden el
  -- inventario del almacen 1 (475), y una tercera para los reintentos a la vez.
  (11, 9011, 1, 300.0000),
  (12, 9012, 1, 300.0000),
  (13, 9013, 1,  60.0000);

SELECT setval('reservation_requests_id_seq', 100);
