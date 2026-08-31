# Parte 4 — Video explicativo

**Parte elegida:** Parte 3 — función de reserva de inventario en PL/pgSQL.

**Enlace:** _(pendiente de subir)_

**Duración:** máximo 3 minutos · formato MP4

## De qué trata

De una sola decisión, que es lo que pide el enunciado: **por qué el bloqueo es
`FOR UPDATE` y no `FOR UPDATE SKIP LOCKED`**, que es el reflejo automático al ver
consumo concurrente de filas.

Saltarse un lote bloqueado rompería el FIFO y, sobre todo, declararía inventario
insuficiente cuando el material sí estaba y solo estaba ocupado un instante. Ese
`backordered` falso detiene una orden de producción: la base de datos queda
perfectamente consistente y la planta, parada.

El razonamiento completo está en [../parte3_postgres/NOTAS.md](../parte3_postgres/NOTAS.md).
