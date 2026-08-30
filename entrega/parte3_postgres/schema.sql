-- Esquema del enunciado, sin modificar. Se incluye para que la funcion, los
-- seeds y las pruebas se puedan ejecutar de principio a fin sobre una base
-- limpia. Ninguna restriccion se relaja: la funcion vive con ellas.

DROP TABLE IF EXISTS stock_movements, reservation_requests, stock_lots, materials CASCADE;
DROP TYPE  IF EXISTS reservation_result CASCADE;

CREATE TABLE materials (
  id   BIGSERIAL PRIMARY KEY,
  code VARCHAR(32) NOT NULL UNIQUE,
  unit VARCHAR(8)  NOT NULL
);

CREATE TABLE stock_lots (
  id           BIGSERIAL PRIMARY KEY,
  material_id  BIGINT        NOT NULL REFERENCES materials(id),
  warehouse_id BIGINT        NOT NULL,
  quantity     NUMERIC(14,4) NOT NULL CHECK (quantity >= 0),
  received_at  TIMESTAMPTZ   NOT NULL
);

CREATE TABLE reservation_requests (
  id                  BIGSERIAL PRIMARY KEY,
  production_order_id BIGINT        NOT NULL,
  material_id         BIGINT        NOT NULL REFERENCES materials(id),
  quantity_required   NUMERIC(14,4) NOT NULL CHECK (quantity_required > 0),
  quantity_reserved   NUMERIC(14,4) NOT NULL DEFAULT 0,
  status              VARCHAR(16)   NOT NULL DEFAULT 'pending',
    -- 'pending' | 'fulfilled' | 'partial' | 'backordered' | 'failed'
  created_at          TIMESTAMPTZ   NOT NULL DEFAULT now(),
  updated_at          TIMESTAMPTZ   NOT NULL DEFAULT now()
);

CREATE TABLE stock_movements (
  id            BIGSERIAL PRIMARY KEY,
  request_id    BIGINT        NOT NULL REFERENCES reservation_requests(id),
  stock_lot_id  BIGINT        NOT NULL REFERENCES stock_lots(id),
  quantity_moved NUMERIC(14,4) NOT NULL CHECK (quantity_moved > 0),
  moved_at      TIMESTAMPTZ   NOT NULL DEFAULT now()
);

CREATE TYPE reservation_result AS (
  request_id        BIGINT,
  status            VARCHAR,
  quantity_reserved NUMERIC,
  quantity_pending  NUMERIC,
  lots_used         INTEGER
);
