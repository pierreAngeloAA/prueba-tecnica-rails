# frozen_string_literal: true

class CutPlanner
  # Una longitud que no se pudo producir, con cuantas veces se pidio.
  Unplaced = Data.define(:length, :quantity)

  # Resultado del planificador. Inmutable: describe un plan ya cerrado.
  class Plan
    attr_reader :bars, :unplaced

    def initialize(bars:, unplaced:)
      @bars     = bars.freeze
      @unplaced = unplaced.freeze
      freeze
    end

    # Material que sale del almacen: la barra entera, porque se consume entera
    # aunque sobre retal.
    def consumed_length
      bars.sum(&:length)
    end

    # Longitud que acaba siendo pieza util.
    def produced_length
      bars.sum(&:produced)
    end

    # Desperdicio sobre material consumido: despuntes + kerf + retales.
    # Sin barras usadas no hay material consumido y el ratio es 0.
    def waste_ratio
      return 0.0 if consumed_length.zero?

      ((consumed_length - produced_length) / consumed_length).round(6)
    end

    def bars_used_by_stock
      bars.each_with_object(Hash.new(0)) { |bar, tally| tally[bar.stock_id] += 1 }
    end

    def to_h
      {
        bars: bars.map(&:to_h),
        unplaced: unplaced.map(&:to_h),
        waste_ratio:,
        bars_used_by_stock:
      }
    end
  end
end
