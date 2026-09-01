# frozen_string_literal: true

require_relative "cut_planner/config"
require_relative "cut_planner/stock_type"
require_relative "cut_planner/bar"
require_relative "cut_planner/plan"
require_relative "cut_planner/policies"

# Planificador de corte de material en una dimension.
#
#   plan = CutPlanner.new(
#     pieces: [{ length: 1_450.0, quantity: 12 }, { length: 820.5, quantity: 30 }],
#     stock:  [{ id: "BAR-A", length: 6_000.0, available: 8 },
#              { id: "BAR-B", length: 4_000.0, available: 3 }],
#     config: { kerf: 4.0, head_trim: 100.0, tail_trim: 50.0 }
#   ).call
#
#   plan.bars        # barras usadas, con sus piezas y el retal sobrante
#   plan.unplaced    # lo que no se pudo producir
#   plan.waste_ratio # desperdicio / material consumido
#
# Heuristica: First Fit Decreasing. Se ordenan las piezas de mayor a menor y
# cada una entra en la primera barra abierta donde quepa; si no cabe en ninguna
# se abre una barra nueva; si no queda stock que la admita, se declara no
# producible. El problema es NP-dificil y no se busca el optimo: FFD da una
# solucion a lo sumo ~22% peor que el optimo en numero de barras, en tiempo
# O(n log n + n·b). El razonamiento completo esta en NOTAS.md.
class CutPlanner
  # Margen para comparar longitudes en coma flotante. Las medidas llegan en
  # milimetros con decimales y acumular sumas introduce error; sin tolerancia,
  # una pieza que encaja justo se declararia fuera por 1e-13 mm.
  TOLERANCE = 1e-9

  class InvalidInput < ArgumentError; end

  def initialize(pieces:, stock:, config: {}, policy: Policies::FirstFit.new)
    @config = Config.from(config)
    @policy = policy
    @stock  = build_stock(stock)
    @demand = build_demand(pieces)

    @bars      = []
    @remaining = @stock.to_h { |type| [type.id, type.available] }
    @unplaced  = Hash.new(0)
  end

  def call
    sorted_demand.each { |piece_length| place(piece_length) }

    Plan.new(bars: @bars, unplaced: collected_unplaced)
  end

  private

  attr_reader :config, :policy, :stock, :demand

  # Piezas de mayor a menor. Las grandes son las dificiles de colocar: si se
  # dejan para el final, las barras ya estan salpicadas de piezas pequeñas y hay
  # que abrir barras nuevas solo para ellas. El indice de entrada rompe los
  # empates para que dos ejecuciones con la misma entrada den el mismo plan.
  def sorted_demand
    demand.sort_by.with_index { |piece_length, i| [-piece_length, i] }
  end

  def place(piece_length)
    bar = policy.choose_bar(@bars, piece_length) || open_bar(piece_length)

    if bar.nil?
      @unplaced[piece_length] += 1
    else
      bar.place(piece_length)
    end
  end

  # Saca una barra nueva del almacen, si queda alguna que admita la pieza.
  # Devuelve nil cuando no hay stock donde quepa: ese es el unico camino por el
  # que una pieza acaba en `unplaced`.
  def open_bar(piece_length)
    type = policy.choose_stock(types_in_stock, piece_length, config.kerf)
    return nil if type.nil?

    @remaining[type.id] -= 1
    Bar.new(stock_id: type.id, length: type.length,
            usable_length: type.usable_length, kerf: config.kerf)
        .tap { |bar| @bars << bar }
  end

  def types_in_stock
    stock.select { |type| @remaining[type.id].positive? }
  end

  def collected_unplaced
    @unplaced.sort_by { |length, _| -length }
             .map { |length, quantity| Unplaced.new(length:, quantity:) }
  end

  # Tipos de barra ordenados de mas larga a mas corta, con el orden de entrada
  # como desempate. Las politicas recorren esta lista, asi que fijar el orden
  # aqui es lo que hace determinista la eleccion de barra.
  def build_stock(entries)
    raise InvalidInput, "stock no puede estar vacio" if entries.nil? || entries.empty?

    entries
      .map { |attrs| StockType.from(attrs, config) }
      .sort_by.with_index { |type, i| [-type.length, i] }
  end

  # Expande {length:, quantity:} a una lista plana de longitudes. Con el tope de
  # 5.000 piezas del enunciado el coste en memoria es irrelevante y evita tener
  # que arrastrar cantidades por todo el algoritmo.
  def build_demand(entries)
    raise InvalidInput, "pieces no puede estar vacio" if entries.nil? || entries.empty?

    entries.flat_map do |attrs|
      length = Float(attrs[:length])
      raise InvalidInput, "las piezas deben tener longitud positiva" unless length.positive?

      quantity = Integer(attrs[:quantity] || 1)
      raise InvalidInput, "las piezas deben tener cantidad positiva" unless quantity.positive?

      Array.new(quantity, length)
    end
  end
end
