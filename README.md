# Prueba técnica — Desarrollador Ruby on Rails

Energía Solar S.A. E.S.P. — Grupo Tecnoglass · Área de Investigación y Desarrollo

Tres ejercicios de código, un video explicativo y tres preguntas cortas. Cada parte es
independiente y se ejecuta por separado.

## Estructura

```
entrega/
  parte1_configuracion/   Rails 7.2 + PostgreSQL — resolución de configuración efectiva
  parte2_corte/           Ruby puro — planificador de corte de material
  parte3_postgres/        PL/pgSQL — función de reserva de inventario
  parte4_video/           enlace al video explicativo
  parte5_preguntas.md     respuestas a las tres preguntas
```

Cada parte de código lleva su propio `README.md` con las instrucciones y un `NOTAS.md`
con el razonamiento: qué decidí, qué descarté, qué supuse y qué dejé fuera. **Si solo se
va a leer un archivo por parte, que sea el `NOTAS.md`.**

## Entorno usado

Ruby 3.3.5 · Rails 7.2.3.1 · PostgreSQL 16 · RSpec

Las partes 1 y 3 esperan un PostgreSQL accesible por el socket local con el usuario del
sistema. Si tu instalación pide contraseña, ajusta `config/database.yml` en la parte 1 y
pasa las variables de conexión a `psql` en la parte 3.

---

## Parte 1 — Resolución de configuración efectiva

La configuración de un renglón de cotización no se guarda sobrescribiendo: se acumula
como un historial inmutable de directivas versionadas, cada una con su origen. El
servicio traduce ese historial al **valor efectivo** de cada clave para cada unidad, en
una versión dada, aplicando cinco reglas de precedencia.

**Decisión central:** las cinco reglas no necesitan cinco pasadas. Las reglas 1 y 3 son
filtros o pesos por fila y las reglas 2 y 5 son desempates, así que colapsan en un único
criterio de orden. Eso las resuelve un `DISTINCT ON` de PostgreSQL en **una sola consulta
por invocación** —el enunciado permite hasta tres—, constante respecto al número de
unidades y de claves. La herencia desde la cabecera queda en Ruby como una fusión de
hashes, porque `unit_uid IS NULL` es un grupo más de la misma consulta.

```bash
cd entrega/parte1_configuracion
bundle install
bin/rails db:create db:migrate
bundle exec rspec                          # 24 ejemplos
bundle exec rspec --format documentation   # leídos como especificación, regla a regla
```

📄 [README](entrega/parte1_configuracion/README.md) · [NOTAS](entrega/parte1_configuracion/NOTAS.md)

---

## Parte 2 — Planificador de corte de material

Reparte una lista de piezas sobre el inventario de barras disponible, respetando
despuntes y espesor de sierra, y devuelve el plan, lo que no se pudo producir y el
desperdicio. Es el *cutting stock problem*: NP-difícil, no se busca el óptimo.

**Decisión central:** First Fit Decreasing. Las piezas entran de mayor a menor porque las
largas son las difíciles de colocar; al revés, las barras se llenan de fragmentos y las
largas obligan a abrir barras solo para ellas. Con 5.000 piezas resuelve en 0,65 s y usa
790 barras frente a una cota inferior teórica de 780.

Toda la heurística se reduce a dos decisiones —en qué barra abierta va la pieza y qué
barra se abre cuando no cabe en ninguna—, aisladas en `Policies`. Por eso «priorizar
consumir primero los retales cortos» viene implementado y **medido**: cuesta un 21 % más
de barras, lo que lo convierte en una decisión de negocio explícita.

```bash
cd entrega/parte2_corte
bundle install
bundle exec rspec                          # 30 ejemplos
```

📄 [README](entrega/parte2_corte/README.md) · [NOTAS](entrega/parte2_corte/NOTAS.md)

---

## Parte 3 — Función de reserva de inventario

`reserve_material` atiende una solicitud consumiendo lotes en FIFO dentro de un almacén,
deja constancia de cada consumo y es segura frente a reintentos y a llamadas
concurrentes. PL/pgSQL puro: la función es el contrato y no queda lógica en la aplicación.

**Decisión central:** `FOR UPDATE` bloqueante, **no** `SKIP LOCKED`. Saltarse un lote
ocupado rompería el FIFO y, peor, declararía inventario insuficiente cuando el material
existía y solo estaba bloqueado un instante —un `backordered` falso detiene una orden de
producción—. Se bloquean todos los lotes candidatos antes de decidir, porque la elección
entre `partial` y `backordered` depende del total disponible y esa suma tiene que estar
congelada para ser fiable.

```bash
cd entrega/parte3_postgres
createdb parte3_reservas
psql -d parte3_reservas -f schema.sql -f reserve_material.sql -f seeds.sql
psql -d parte3_reservas -f test.sql        # 12 casos, aborta si alguno falla
./test_concurrency.sh parte3_reservas      # dos sesiones simultáneas
```

📄 [README](entrega/parte3_postgres/README.md) · [NOTAS](entrega/parte3_postgres/NOTAS.md)

---

## Parte 4 — Video explicativo

Enlace y detalles en [entrega/parte4_video/](entrega/parte4_video/).

## Parte 5 — Tres preguntas cortas

📄 [entrega/parte5_preguntas.md](entrega/parte5_preguntas.md)

---

## Ejecutar todas las pruebas

```bash
(cd entrega/parte1_configuracion && bundle exec rspec)
(cd entrega/parte2_corte         && bundle exec rspec)
(cd entrega/parte3_postgres      && psql -d parte3_reservas -f test.sql && ./test_concurrency.sh)
```

## Sobre los supuestos

Donde el enunciado dejaba margen, resolví con el criterio que me pareció mejor y lo dejé
anotado en el `NOTAS.md` de la parte correspondiente, con el cambio que haría falta si la
lectura esperada fuera la otra. Los que más pueden condicionar una evaluación:

- **Parte 1** — una directiva de origen `user` en una clave de intención gana también
  sobre `preserved` y `default` posteriores, no solo sobre `resolution`.
- **Parte 2** — la última pieza de una barra también paga el espesor de sierra, porque
  separarla del retal exige un corte real.
- **Parte 3** — `partial` es terminal: una solicitud parcial no se completa aunque llegue
  material. Y «almacén desconocido» se deduce de que no tenga ningún lote, porque el
  esquema no incluye una tabla de almacenes.
