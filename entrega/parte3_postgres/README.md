# Parte 3 — Función de reserva de inventario

`reserve_material` atiende una solicitud de reserva consumiendo lotes en FIFO, deja
constancia de cada consumo y es segura frente a reintentos y frente a llamadas
concurrentes. PL/pgSQL puro: la función es el contrato y no hay lógica en la aplicación.

Las decisiones —bloqueo, idempotencia, índices, y qué se pierde por vivir en la base de
datos— están en [NOTAS.md](NOTAS.md).

## Requisitos

PostgreSQL 13 o superior.

## Ejecutar todo de principio a fin

```bash
createdb parte3_reservas

psql -d parte3_reservas -f schema.sql            # esquema del enunciado, sin modificar
psql -d parte3_reservas -f reserve_material.sql  # indices + funcion
psql -d parte3_reservas -f seeds.sql             # datos de prueba
psql -d parte3_reservas -f test.sql              # 12 casos, aborta si alguno falla

./test_concurrency.sh parte3_reservas            # dos sesiones simultaneas
```

`test.sql` usa `ASSERT` y `ON_ERROR_STOP`: si una comprobación falla, psql aborta y el
proceso termina con código distinto de cero.

## Archivos

| | |
|---|---|
| `schema.sql` | el DDL del enunciado, tal cual. Ninguna restricción se relaja |
| `reserve_material.sql` | los dos índices y la función |
| `seeds.sql` | datos con ids fijos: lotes desordenados, empates de fecha, lote a cero, material sin lotes |
| `test.sql` | 12 casos, cada uno en `BEGIN`/`ROLLBACK` |
| `test_concurrency.sh` | lo que no cabe en un script SQL: dos sesiones a la vez |
| `benchmark_seed.sql` | 300.000 lotes para reproducir el plan documentado en NOTAS.md |

## Firma

```sql
reserve_material(
  p_request_id    BIGINT,
  p_warehouse_id  BIGINT,
  p_allow_partial BOOLEAN DEFAULT TRUE
) RETURNS reservation_result
```

```sql
SELECT * FROM reserve_material(1, 1);
--  request_id | status    | quantity_reserved | quantity_pending | lots_used
--           1 | fulfilled |           60.0000 |           0.0000 |         1
```

## Errores

Cada condición inesperada tiene su propio `SQLSTATE`, para que el llamador pueda
distinguirlas sin leer el mensaje:

| SQLSTATE | Condición |
|---|---|
| `ES001` | la solicitud de reserva no existe |
| `ES002` | el material de la solicitud no existe |
| `ES003` | almacén nulo, o cantidad solicitada no positiva |
| `ES004` | el almacén no existe |

Ninguno deja escrituras a medias: la función no captura excepciones, así que el error
propaga y aborta la transacción del llamador.
