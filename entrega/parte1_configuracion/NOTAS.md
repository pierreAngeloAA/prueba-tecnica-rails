# Parte 1 — Resolución de configuración efectiva

## Enfoque

Las cinco reglas parecen cinco pasadas, pero no lo son. Las reglas 1 y 3 son **filtros o
pesos por fila**; las reglas 2 y 5 son **desempates**. Juntas colapsan en un único criterio
de orden sobre `(unit_uid, key)`:

```
CASE WHEN source = 'user' AND key IN (:intent_keys) THEN 1 ELSE 0 END DESC,  -- reglas 3 y 5
version DESC, created_at DESC, id DESC                                        -- regla 2
```

con `version <= V` en el `WHERE` (regla 1). Eso es exactamente un `DISTINCT ON (unit_uid, key)`
de PostgreSQL: la base de datos devuelve ya **una sola fila ganadora por ámbito y clave**.

La regla 5 no necesita una rama aparte: basta con que las claves dimensionales no estén en el
conjunto que activa el peso. Se implementa como `INTENT_KEYS = USER_INTENT_KEYS - DIMENSIONAL_KEYS`.
Hoy los dos conjuntos son disjuntos y la resta no quita nada, pero deja la regla escrita en el
código en vez de en un comentario: si mañana alguien mete `width` en `USER_INTENT_KEYS`, la
excepción dimensional sigue ganando.

Lo único que queda en Ruby es la regla 4 (herencia), que es una fusión de dos hashes:
`header.merge(unidad)`. La cabecera se resuelve en la misma pasada porque `unit_uid IS NULL`
es un grupo más del `DISTINCT ON`.

**Coste: una consulta por invocación** (el enunciado permite hasta tres), constante respecto al
número de unidades y de claves. Hay un test que lo verifica comparando 2 unidades contra 50.
`keys:` viaja al `WHERE`, no a un `select` posterior: recorta filas leídas y habilita el índice
por clave. `unit_uids: []` y `keys: []` no llegan a consultar.

## Índices y plan medido

Dos índices, uno por camino de acceso, porque la selectividad se invierte según los argumentos:

| Índice | Cuándo gana |
|---|---|
| `(line_item_id, unit_uid, key, version)` | `keys: nil` — manda el conjunto de unidades |
| `(line_item_id, key, version)` | `keys:` con pocas claves y muchas unidades |

Medido sobre 378.000 filas (`db/benchmark_seed.sql` lo reproduce):

- `keys: nil`, 5 unidades → `BitmapOr` sobre `by_unit`, una rama para la cabecera
  (`unit_uid IS NULL`) y otra para las unidades. 315 filas leídas, 56 buffers.
- `keys: [2 claves]`, 25 unidades → el planificador **cambia solo** a `by_key`. 202 filas leídas.

Un b-tree indexa los `NULL`, así que `unit_uid IS NULL` es sargable y el mismo índice sirve a
cabecera y unidades. Para poder apoyarme en eso añadí un `CHECK` que garantiza
`directive_type = 'header' ⟺ unit_uid IS NULL`: sin él, leer el ámbito por `unit_uid` sería una
suposición y no un invariante.

## Supuestos

Resueltos con el criterio que me pareció mejor, por si el evaluador esperaba otro:

1. **Regla 3 frente a orígenes que no son `resolution`.** El enunciado dice que `user` gana
   «aunque exista una `resolution` posterior». Interpreto que `resolution` es el caso ilustrativo
   y que la intención explícita del usuario también prevalece sobre `preserved` y `default`
   posteriores. Si la lectura correcta fuera la literal, el cambio es una condición más en el `CASE`.
2. **`value` NULL cuenta como valor.** Una directiva propia con `value` NULL anula la herencia de
   la cabecera en vez de caer a ella. El historial nunca se borra, así que escribir NULL es la
   única forma de anular una clave; tratarlo como «ausente» haría imposible expresarlo.
3. **Desempate final por `id`.** Con `version` y `created_at` iguales gana el `id` mayor, que en
   una `BIGSERIAL` es la fila escrita después. Es el único desempate total disponible.
4. **Toda unidad pedida aparece en la salida**, aunque no tenga ninguna directiva propia: recibe
   la cabecera resuelta. Si tampoco hay cabecera, un hash vacío.
5. **`keys: []` significa cero claves**, no «todas». `nil` es «todas».

## Qué dejo fuera

- **Sin caché.** Cada invocación va a la base de datos. Con historial inmutable y `version` como
  parte de la clave, el resultado es cacheable de forma trivial, pero eso pertenece a quien llama.
- **No valido que los `unit_uid` existan** en el renglón: una unidad desconocida devuelve la
  cabecera heredada en vez de error. Cambiarlo requiere decidir el contrato, y el enunciado no lo fija.
- **Todos los valores son `String`**, tal cual el esquema. No hay coerción a entero ni a booleano.

## Qué haría distinto con más tiempo

1. **Índice de cobertura**: añadir `INCLUDE (value, source)` para que la consulta sea
   *index-only scan* y no toque el heap. No lo hice porque duplica el peso del índice sobre una
   tabla que solo crece, y con los volúmenes medidos aún no compensa.
2. **Resolver varios renglones o varias versiones en una llamada.** Hoy la firma es de un renglón;
   un comparador de versiones haría N llamadas. La consulta admite el batch sin cambiar de forma.
3. **Snapshot materializado por versión** si el historial crece hasta que el `Sort` deje de caber
   en memoria. Es la primera cosa que se rompería: el `DISTINCT ON` ordena todas las filas
   candidatas del renglón, y ese conjunto crece con el número de versiones guardadas.
