# frozen_string_literal: true

class CutPlanner
  # Una barra fisica ya sacada del almacen, con las piezas que se le han ido
  # asignando. Es el unico objeto mutable del planificador.
  class Bar
    attr_reader :stock_id, :length, :usable_length, :pieces

    def initialize(stock_id:, length:, usable_length:, kerf:)
      @stock_id      = stock_id
      @length        = length
      @usable_length = usable_length
      @kerf          = kerf
      @pieces        = []
      @consumed      = 0.0
    end

    # Coste real de una pieza: su longitud mas el corte que la separa.
    # Ver NOTAS.md para por que la ultima pieza tambien paga kerf.
    def cost_of(piece_length)
      piece_length + @kerf
    end

    def fits?(piece_length)
      cost_of(piece_length) <= remnant + TOLERANCE
    end

    def place(piece_length)
      @consumed += cost_of(piece_length)
      @pieces << piece_length
      self
    end

    # Tramo aprovechable que queda libre al final de la barra.
    def remnant
      @usable_length - @consumed
    end

    # Longitud util realmente convertida en piezas.
    def produced
      @pieces.sum
    end

    # Todo lo que de esta barra no acaba siendo pieza: los dos despuntes, el
    # kerf de cada corte y el retal final.
    def waste
      @length - produced
    end

    def to_h
      { stock_id:, length:, pieces: pieces.dup, remnant: remnant.round(4), waste: waste.round(4) }
    end
  end
end
