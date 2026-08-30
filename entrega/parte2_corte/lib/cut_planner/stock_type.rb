# frozen_string_literal: true

class CutPlanner
  # Un tipo de barra del almacen: su longitud nominal, cuantas quedan y cuanto
  # de esa longitud es realmente aprovechable una vez quitados los despuntes.
  StockType = Data.define(:id, :length, :available, :usable_length) do
    def self.from(attrs, config)
      id     = attrs[:id]
      length = Float(attrs[:length])
      raise InvalidInput, "la barra #{id.inspect} debe tener longitud positiva" unless length.positive?

      available = Integer(attrs[:available])
      raise InvalidInput, "la barra #{id.inspect} no puede tener stock negativo" if available.negative?

      new(id:, length:, available:,
          usable_length: [length - config.head_trim - config.tail_trim, 0.0].max)
    end

    # Una pieza cabe en una barra virgen de este tipo si entra ella y su corte.
    def admits?(piece_length, kerf)
      piece_length + kerf <= usable_length + TOLERANCE
    end
  end
end
