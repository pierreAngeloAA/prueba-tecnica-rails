#!/usr/bin/env bash
# ============================================================================
# Pruebas de concurrencia de reserve_material
# ============================================================================
# Lo unico que no se puede comprobar desde un solo test.sql: hacen falta dos
# sesiones simultaneas. Se lanzan dos psql en paralelo contra la misma base.
#
#   ./test_concurrency.sh [nombre_de_la_base]
set -euo pipefail

DB="${1:-parte3_reservas}"
aqui="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fallos=0

recargar() { psql -d "$DB" -q -f "$aqui/seeds.sql" >/dev/null; }

comprobar() { # comprobar <descripcion> <sql que devuelve boolean>
  if [[ "$(psql -d "$DB" -tAc "$2")" == "t" ]]; then
    echo "  OK   $1"
  else
    echo "  FALLO $1"
    fallos=$((fallos + 1))
  fi
}

echo
echo "=== A. Dos solicitudes distintas compiten por el mismo inventario ==="
echo "    Hay 475. Piden 300 y 300. Juntas no caben: el reparto debe sumar 475,"
echo "    nunca 600, y ningun lote puede quedar en negativo."
recargar

# La sesion A retiene los bloqueos un segundo para forzar el solapamiento.
psql -d "$DB" -q -c "BEGIN; SELECT reserve_material(11, 1, TRUE); SELECT pg_sleep(1); COMMIT;" >/dev/null &
sleep 0.2
psql -d "$DB" -q -c "BEGIN; SELECT reserve_material(12, 1, TRUE); COMMIT;" >/dev/null &
wait

psql -d "$DB" -tAc "
  SELECT '    reparto: ' || string_agg(id || ' -> ' || quantity_reserved || ' (' || status || ')', ', ' ORDER BY id)
  FROM reservation_requests WHERE id IN (11, 12);"

comprobar "el inventario repartido no excede el disponible" \
  "SELECT COALESCE(sum(quantity_reserved), 0) = 475 FROM reservation_requests WHERE id IN (11,12)"
comprobar "ningun lote queda en negativo" \
  "SELECT min(quantity) >= 0 FROM stock_lots"
comprobar "el inventario restante cuadra con lo movido" \
  "SELECT COALESCE(sum(quantity_moved),0) = 475 - COALESCE((SELECT sum(quantity) FROM stock_lots WHERE material_id=1 AND warehouse_id=1),0) + 0 FROM stock_movements WHERE request_id IN (11,12)"
comprobar "invariante 1: lo reservado cuadra con los movimientos" \
  "SELECT NOT EXISTS (SELECT 1 FROM reservation_requests q WHERE q.id IN (11,12) AND q.quantity_reserved <> COALESCE((SELECT sum(m.quantity_moved) FROM stock_movements m WHERE m.request_id = q.id), 0))"

echo
echo "=== B. Dos reintentos de la MISMA solicitud, a la vez ==============="
echo "    Es el caso del proceso que se reintenta. Solo uno puede consumir."
recargar

psql -d "$DB" -q -c "BEGIN; SELECT reserve_material(13, 1, TRUE); SELECT pg_sleep(1); COMMIT;" >/dev/null &
sleep 0.2
psql -d "$DB" -q -c "BEGIN; SELECT reserve_material(13, 1, TRUE); COMMIT;" >/dev/null &
wait

comprobar "se reserva la cantidad pedida una sola vez" \
  "SELECT quantity_reserved = 60 FROM reservation_requests WHERE id = 13"
comprobar "solo se registra un movimiento" \
  "SELECT count(*) = 1 FROM stock_movements WHERE request_id = 13"
comprobar "el lote se descuenta una sola vez" \
  "SELECT quantity = 15 FROM stock_lots WHERE id = 4"

echo
if [[ $fallos -eq 0 ]]; then
  echo "=============================================="
  echo " Concurrencia: todas las comprobaciones pasan."
  echo "=============================================="
else
  echo "Concurrencia: $fallos comprobacion(es) fallaron." >&2
  exit 1
fi
