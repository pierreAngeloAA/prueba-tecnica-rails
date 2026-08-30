# Parte 1 — Resolución de configuración efectiva

Servicio que traduce el historial inmutable de directivas de un renglón al valor
efectivo de cada clave para cada unidad, en una versión objetivo.

El razonamiento de diseño, los supuestos y los índices medidos están en [NOTAS.md](NOTAS.md).

## Requisitos

Ruby 3.1+ · Rails 7.2 · PostgreSQL 13+

## Puesta en marcha

```bash
bundle install
bin/rails db:create db:migrate
```

La conexión usa el socket local de PostgreSQL con el usuario del sistema. Si tu
instalación pide contraseña, ajusta `config/database.yml`.

## Pruebas

```bash
bundle exec rspec                          # la suite completa
bundle exec rspec --format documentation   # leída como especificación, regla a regla
```

## Uso

```ruby
EffectiveConfigResolver.call(
  line_item_id: 42,
  unit_uids:    %w[unit-a unit-b],
  version:      7,
  keys:         nil # nil = todas las claves; array = solo esas
)
# => { "unit-a" => { "width" => "1200", "glass_type" => "laminated" }, ... }
```

## Reproducir el plan de consulta

`db/benchmark_seed.sql` carga 378.000 filas sintéticas para comprobar que los dos
índices se usan y que el planificador elige uno u otro según los argumentos:

```bash
psql -d parte1_configuracion_development -f db/benchmark_seed.sql
```

El `EXPLAIN` esperado y su lectura están en [NOTAS.md](NOTAS.md#índices-y-plan-medido).
