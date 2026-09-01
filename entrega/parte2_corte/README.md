# Parte 2 — Planificador de corte de material

Ruby puro: sin Rails, sin base de datos y sin más dependencia que el framework de
pruebas. La heurística elegida, lo que descarté y las mediciones están en
[NOTAS.md](NOTAS.md).

## Requisitos

Ruby 3.2+ (usa `Data.define`).

## Pruebas

```bash
bundle install
bundle exec rspec
bundle exec rspec --format documentation   # leída como especificación
```

## Uso

```ruby
require "cut_planner"

plan = CutPlanner.new(
  pieces: [{ length: 1_450.0, quantity: 12 }, { length: 820.5, quantity: 30 }],
  stock:  [{ id: "BAR-A", length: 6_000.0, available: 8 },
           { id: "BAR-B", length: 4_000.0, available: 3 }],
  config: { kerf: 4.0, head_trim: 100.0, tail_trim: 50.0 }
).call

plan.bars               # barras usadas, cada una con sus piezas y su retal
plan.unplaced           # [#<data Unplaced length=..., quantity=...>]
plan.waste_ratio        # desperdicio / material consumido
plan.bars_used_by_stock # {"BAR-A" => 8}
plan.to_h               # el plan completo, serializable
```

Con la política alternativa (priorizar retales cortos):

```ruby
CutPlanner.new(..., policy: CutPlanner::Policies::ShortestRemnantFirst.new).call
```

## Estructura

```
lib/cut_planner.rb            orquestación: orden de las piezas, stock, unplaced
lib/cut_planner/policies.rb   las dos decisiones de la heurística, sustituibles
lib/cut_planner/bar.rb        barra en curso: qué cabe y qué retal queda
lib/cut_planner/plan.rb       resultado inmutable y sus métricas
lib/cut_planner/stock_type.rb tipo de barra y su longitud aprovechable
lib/cut_planner/config.rb     kerf y despuntes
```
