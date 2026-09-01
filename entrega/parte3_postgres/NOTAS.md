# Parte 3 — Función de reserva de inventario

## ¿Qué estrategia de bloqueo elegiste y por qué?

**Bloqueo pesimista con `FOR UPDATE`, en dos niveles y en orden fijo.**

1. **La solicitud** (`reservation_requests`), al entrar. Es lo que serializa los
   reintentos de una misma solicitud.
2. **Todos los lotes candidatos** del material en ese almacén, antes de decidir nada.

El segundo bloqueo es el que más se discute, porque parece excesivo: se bloquean lotes
que quizá no se lleguen a consumir. Es deliberado. La elección entre `partial` y
`backordered` depende del **total disponible**, y una suma que otra transacción puede
estar modificando no sirve para decidir. Para que la respuesta sea fiable, la foto
tiene que estar congelada.

**Por qué no `SKIP LOCKED`.** Es el reflejo automático al ver «consumo concurrente de
filas», y aquí es un error. `SKIP LOCKED` es para colas de trabajo, donde da igual qué
elemento coge cada worker. Saltarse un lote bloqueado rompería el FIFO —consumiría uno
más nuevo dejando vivo uno más antiguo— y, peor, declararía inventario insuficiente
cuando el material existía y solo estaba ocupado un instante. Un `backordered` falso
detiene una orden de producción.

**Por qué no bloqueo optimista** (leer, calcular, escribir comprobando versión): la
operación tiene efectos secundarios —inserta movimientos— así que reintentarla es caro,
y bajo contención sobre el material más pedido degenera en reintentos en cadena.

**Por qué no `SERIALIZABLE`.** Funcionaría, pero traslada el problema al llamador:
tendría que capturar `serialization_failure` y reintentar. El enunciado dice que la
función es el contrato; que el cliente tenga que saber reintentar es filtrar la
implementación hacia fuera.

**Deadlocks.** Todas las llamadas bloquean en el mismo orden: primero la solicitud,
después los lotes por `(received_at, id)`. Dos transacciones sobre el mismo material
piden los mismos recursos en la misma secuencia, así que no hay ciclo de espera.

**El coste, dicho claramente:** dos reservas del mismo material en el mismo almacén se
serializan. Es el precio de no repartir el mismo lote dos veces, y es el correcto: el
cuello de botella es por material, no global.

## ¿Cómo garantizas la idempotencia y qué pasa si dos reintentos entran a la vez?

Dos piezas que solo funcionan juntas:

1. **La guarda por estado.** Si la solicitud está en `fulfilled` o `partial`, la función
   reconstruye el resultado anterior desde `reservation_requests` y `stock_movements` y
   sale sin escribir. `pending` y `backordered` **no** son terminales: reintentar sobre
   ellas es válido y es el caso de haber recibido mercancía nueva.
2. **El `FOR UPDATE` sobre la solicitud.** Sin él la guarda no vale nada: dos reintentos
   simultáneos leerían `pending` a la vez y ambos consumirían inventario.

**Con dos reintentos a la vez**, el primero toma el bloqueo de la fila y el segundo
queda esperando —no lee un valor viejo, espera—. Cuando el primero hace commit, el
segundo entra, lee el `status` ya actualizado y devuelve el resultado anterior sin
tocar nada. Si el primero hace *rollback*, el segundo ve `pending` y procede, que es
justo lo que debe pasar.

Está comprobado en `test_concurrency.sh`, caso B: dos sesiones llamando a la vez sobre
la misma solicitud dejan **un solo movimiento** y el lote descontado una sola vez.

Y en el caso A, dos solicitudes distintas de 300 sobre 475 disponibles reparten
`300 (fulfilled)` y `175 (partial)`. Suman 475, no 600.

## ¿Por qué esto vive en la base de datos y no en Ruby? ¿Qué se pierde?

**Por qué aquí.** La corrección depende de que leer, decidir y escribir ocurran sin que
nadie se cuele en medio. En Ruby, entre el `SELECT` que suma el disponible y el `UPDATE`
que descuenta hay un viaje de red, y esa ventana es exactamente donde se pierde
inventario. Además, la invariante deja de depender de que *todos* los clientes usen la
misma librería: un job de Sidekiq, un ETL nocturno o alguien en `psql` obtienen la misma
garantía, porque la garantía está en el único sitio por el que todos pasan. Y el bucle
FIFO en Ruby serían N consultas por reserva en lugar de una.

**Qué se pierde, sin adornos:**

- **Herramientas de prueba.** No hay RSpec, ni factories, ni un buen depurador. Las
  pruebas son SQL, y la de concurrencia necesita un script de shell con dos sesiones.
- **Observabilidad.** La función no aparece en el APM de la aplicación. Un error sale
  como un `SQLSTATE`, no como una excepción con traza.
- **Despliegue y versionado.** Una función no se versiona sola: hay que gestionarla con
  migraciones y cuidar que `CREATE OR REPLACE` no cambie la firma bajo los pies de una
  aplicación en marcha.
- **Revisores.** En la mayoría de equipos hay bastante menos gente cómoda leyendo
  PL/pgSQL que Ruby, y eso alarga cada cambio.
- **Lógica repartida.** Parte de las reglas de negocio quedan en la aplicación y parte
  en la base. Quien venga detrás tiene que saber dónde mirar.

Es un intercambio consciente: se paga en comodidad de desarrollo para comprar una
garantía que en la capa de aplicación no se puede dar.

## ¿Qué índice añadirías y cuál sería el plan de la consulta principal?

```sql
CREATE INDEX idx_stock_lots_fifo
  ON stock_lots (material_id, warehouse_id, received_at, id)
  WHERE quantity > 0;
```

Las columnas están en el orden del acceso: los dos filtros de igualdad primero y después
las dos del `ORDER BY`, en la misma secuencia que el FIFO, de modo que el índice puede
entregar las filas ya ordenadas.

**Es parcial a propósito.** Los lotes agotados nunca vuelven a consultarse, y en una
planta se acumulan sin límite. Dejarlos fuera mantiene el índice proporcional al stock
**vivo** y no al histórico.

Medido sobre 300.008 lotes de los que solo 15.007 siguen vivos (5 %), en el escenario
realista de un material con 2.000 lotes históricos y 29 vivos:

```
LockRows (actual rows=29)
  ->  Sort  (Sort Key: received_at, id)
        ->  Bitmap Heap Scan on stock_lots
              ->  Bitmap Index Scan on idx_stock_lots_fifo
                    Index Cond: (material_id = 5 AND warehouse_id = 1)
                    Buffers: shared hit=5
Execution Time: 0.189 ms
```

**Sobre el `Sort` que aparece ahí, para no venderlo mejor de lo que es:** el índice
*puede* dar el orden, y forzando `enable_bitmapscan = off` el plan pasa a `Index Scan` y
el `Sort` desaparece. Con estos volúmenes el planificador prefiere el bitmap y ordenar
29 filas en memoria, que le sale más barato. Es una decisión suya y es razonable; no
merece la pena forzarla.

El segundo índice, `stock_movements (request_id)`, es para el camino de la idempotencia:
reconstruir el resultado de una solicitud ya atendida recorre sus movimientos, y sin
índice sería un recorrido secuencial de una tabla que solo crece.

## Supuestos

1. **`partial` es terminal.** El enunciado dice que una solicitud ya atendida
   (`fulfilled` o `partial`) no debe consumir nada más. Así que una parcial no se
   completa aunque llegue material: haría falta una solicitud nueva. Si la intención
   fuera lo contrario, basta con sacar `'partial'` de la guarda.
2. **`backordered` y `pending` no son terminales.** Reintentar sobre ellas es válido, que
   es el caso de haber recibido mercancía.
3. **«Almacén desconocido».** No hay tabla `warehouses` en el esquema, así que la única
   señal disponible de que un almacén existe es que alguna vez haya guardado un lote. Es
   una aproximación con un límite conocido: un almacén recién creado y todavía vacío daría
   error en lugar de `backordered`. Con una tabla `warehouses` esto sería una clave
   foránea y el problema desaparecería. Nótese que es distinto de «este material no tiene
   lotes aquí», que **no** es un error sino inventario insuficiente.
4. **Sin bloque `EXCEPTION` en toda la función.** Cualquier error se propaga y aborta la
   transacción del llamador, que es lo que garantiza que no queden escrituras a medias.
   Un `EXCEPTION` abriría un savepoint implícito y podría dejar un lote descontado cuyo
   movimiento no llegó a insertarse.

## Qué dejo fuera

- **No hay liberación de reservas.** Falta la operación inversa, que en producción hace
  falta el día que se cancela una orden.
- **No se «despiertan» las solicitudes en `backordered`** cuando entra mercancía. Hoy
  alguien tiene que volver a llamar; lo natural sería un proceso que reintente las
  pendientes al registrar una entrada.
- **La contención es por material y almacén, no por lote.** Con más tiempo mediría si
  merece la pena una segunda fase que bloquee solo los lotes que de verdad se van a
  consumir, a cambio de una decisión `partial`/`backordered` más delicada.
