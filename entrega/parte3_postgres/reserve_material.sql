-- ============================================================================
-- reserve_material — atiende una solicitud de reserva consumiendo lotes en FIFO
-- ============================================================================
-- El razonamiento completo (bloqueo, idempotencia, indices) esta en NOTAS.md.

-- Indice de trabajo de la funcion. Es parcial a proposito: los lotes agotados
-- no vuelven a consultarse nunca, y en una planta se acumulan sin limite, asi
-- que mantenerlos fuera del indice lo deja proporcional al stock vivo y no al
-- historico. El orden (received_at, id) es el mismo del FIFO, asi que el
-- ORDER BY se resuelve leyendo el indice, sin ordenacion.
CREATE INDEX IF NOT EXISTS idx_stock_lots_fifo
  ON stock_lots (material_id, warehouse_id, received_at, id)
  WHERE quantity > 0;

-- Reconstruir el resultado de una solicitud ya atendida recorre sus
-- movimientos; sin este indice seria un recorrido secuencial de una tabla que
-- solo crece.
CREATE INDEX IF NOT EXISTS idx_stock_movements_request
  ON stock_movements (request_id);


CREATE OR REPLACE FUNCTION reserve_material(
  p_request_id    BIGINT,
  p_warehouse_id  BIGINT,
  p_allow_partial BOOLEAN DEFAULT TRUE
) RETURNS reservation_result
LANGUAGE plpgsql
AS $$
DECLARE
  v_request    reservation_requests%ROWTYPE;
  v_lot        RECORD;
  v_available  NUMERIC(14,4);
  v_pending    NUMERIC(14,4);
  v_take       NUMERIC(14,4);
  v_reserved   NUMERIC(14,4) := 0;
  v_lots_used  INTEGER       := 0;
  v_status     VARCHAR(16);
BEGIN
  -- Sin bloque EXCEPTION en toda la funcion: cualquier error se propaga y
  -- aborta la transaccion del llamador. Es lo que garantiza que no queden
  -- escrituras a medias. Un bloque EXCEPTION abriria un savepoint implicito y
  -- podria dejar consumido un lote cuyo movimiento no llego a insertarse.

  IF p_warehouse_id IS NULL THEN
    RAISE EXCEPTION 'se requiere un almacen para reservar'
      USING ERRCODE = 'ES003', HINT = 'p_warehouse_id no puede ser NULL';
  END IF;

  --------------------------------------------------------------------------
  -- 1. Bloqueo de la solicitud.
  --------------------------------------------------------------------------
  -- Este FOR UPDATE es lo que hace idempotente a la funcion bajo concurrencia.
  -- Dos reintentos de la MISMA solicitud se serializan aqui: el segundo espera
  -- al primero y, cuando entra, ya lee el status actualizado. Sin este bloqueo
  -- los dos leerian 'pending' a la vez y consumirian inventario dos veces.
  SELECT * INTO v_request
    FROM reservation_requests
   WHERE id = p_request_id
     FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'la solicitud de reserva % no existe', p_request_id
      USING ERRCODE = 'ES001';
  END IF;

  --------------------------------------------------------------------------
  -- 2. Idempotencia: una solicitud ya atendida devuelve su resultado anterior.
  --------------------------------------------------------------------------
  -- 'fulfilled' y 'partial' son terminales por enunciado. 'pending' y
  -- 'backordered' no lo son: una llamada posterior debe reintentar, que es el
  -- caso de haber recibido mercancia nueva.
  IF v_request.status IN ('fulfilled', 'partial') THEN
    SELECT COUNT(DISTINCT stock_lot_id) INTO v_lots_used
      FROM stock_movements
     WHERE request_id = p_request_id;

    RETURN ROW(
      v_request.id,
      v_request.status,
      v_request.quantity_reserved,
      v_request.quantity_required - v_request.quantity_reserved,
      v_lots_used
    )::reservation_result;
  END IF;

  --------------------------------------------------------------------------
  -- 3. Validaciones. Todas antes de la primera escritura.
  --------------------------------------------------------------------------
  IF v_request.quantity_required <= 0 THEN
    RAISE EXCEPTION 'la solicitud % pide una cantidad no positiva (%)',
      p_request_id, v_request.quantity_required
      USING ERRCODE = 'ES003';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM materials WHERE id = v_request.material_id) THEN
    RAISE EXCEPTION 'el material % de la solicitud % no existe',
      v_request.material_id, p_request_id
      USING ERRCODE = 'ES002';
  END IF;

  -- No hay tabla de almacenes en el esquema, asi que la unica senal disponible
  -- de que un almacen existe es que alguna vez haya guardado un lote. Ver el
  -- supuesto en NOTAS.md: distingue «almacen desconocido» (error) de «este
  -- material no tiene lotes aqui» (inventario insuficiente, no error).
  IF NOT EXISTS (SELECT 1 FROM stock_lots WHERE warehouse_id = p_warehouse_id) THEN
    RAISE EXCEPTION 'el almacen % no existe', p_warehouse_id
      USING ERRCODE = 'ES004';
  END IF;

  v_pending := v_request.quantity_required - v_request.quantity_reserved;

  --------------------------------------------------------------------------
  -- 4. Bloqueo del inventario y foto estable de lo disponible.
  --------------------------------------------------------------------------
  -- FOR UPDATE bloqueante, no SKIP LOCKED: saltarse un lote bloqueado romperia
  -- el FIFO y, peor, declararia inventario insuficiente cuando solo estaba
  -- ocupado. Se bloquean todos los lotes candidatos antes de decidir porque la
  -- eleccion entre 'partial' y 'backordered' depende del total disponible, y
  -- esa suma tiene que estar congelada para ser fiable.
  --
  -- Todas las llamadas bloquean en el mismo orden (received_at, id) dentro de
  -- un mismo material y almacen, asi que no hay ciclos de espera.
  SELECT COALESCE(SUM(quantity), 0) INTO v_available
    FROM (
      SELECT quantity
        FROM stock_lots
       WHERE material_id  = v_request.material_id
         AND warehouse_id = p_warehouse_id
         AND quantity     > 0
       ORDER BY received_at, id
         FOR UPDATE
    ) lotes_bloqueados;

  --------------------------------------------------------------------------
  -- 5. Sin material suficiente y sin permiso de parcial: no se toca nada.
  --------------------------------------------------------------------------
  IF v_available < v_pending AND NOT p_allow_partial THEN
    UPDATE reservation_requests
       SET status = 'backordered', updated_at = now()
     WHERE id = p_request_id;

    RETURN ROW(p_request_id, 'backordered'::VARCHAR,
               v_request.quantity_reserved,
               v_request.quantity_required - v_request.quantity_reserved,
               0)::reservation_result;
  END IF;

  --------------------------------------------------------------------------
  -- 6. Consumo FIFO.
  --------------------------------------------------------------------------
  -- Sin FOR UPDATE: estos lotes ya quedaron bloqueados por esta misma
  -- transaccion en el paso 4, y el bloqueo dura hasta el commit.
  FOR v_lot IN
    SELECT id, quantity
      FROM stock_lots
     WHERE material_id  = v_request.material_id
       AND warehouse_id = p_warehouse_id
       AND quantity     > 0
     ORDER BY received_at, id
  LOOP
    EXIT WHEN v_pending <= 0;

    v_take := LEAST(v_lot.quantity, v_pending);
    CONTINUE WHEN v_take <= 0; -- invariante 3: nunca un movimiento de cantidad cero

    -- El descuento se escribe como resta sobre el valor almacenado, no sobre el
    -- que leyo el cursor, para que el CHECK (quantity >= 0) del esquema sea la
    -- ultima linea de defensa contra una cantidad negativa.
    UPDATE stock_lots
       SET quantity = quantity - v_take
     WHERE id = v_lot.id;

    INSERT INTO stock_movements (request_id, stock_lot_id, quantity_moved)
    VALUES (p_request_id, v_lot.id, v_take);

    v_reserved  := v_reserved + v_take;
    v_pending   := v_pending - v_take;
    v_lots_used := v_lots_used + 1;
  END LOOP;

  --------------------------------------------------------------------------
  -- 7. Cierre de la solicitud.
  --------------------------------------------------------------------------
  v_reserved := v_request.quantity_reserved + v_reserved;

  IF v_reserved >= v_request.quantity_required THEN
    v_status := 'fulfilled';
  ELSIF v_reserved > 0 THEN
    v_status := 'partial';
  ELSE
    -- Nada disponible. Con p_allow_partial la solicitud sigue viva a la espera
    -- de mercancia: 'backordered', no 'partial', porque no hay nada reservado.
    v_status := 'backordered';
  END IF;

  UPDATE reservation_requests
     SET quantity_reserved = v_reserved,
         status            = v_status,
         updated_at        = now()
   WHERE id = p_request_id;

  RETURN ROW(p_request_id, v_status, v_reserved,
             v_request.quantity_required - v_reserved,
             v_lots_used)::reservation_result;
END;
$$;
