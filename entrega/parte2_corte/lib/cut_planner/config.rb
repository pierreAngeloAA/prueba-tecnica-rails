# frozen_string_literal: true

class CutPlanner
  # Parametros fisicos del corte, en milimetros.
  #
  #   head_trim / tail_trim  descarte fijo en cada extremo de la barra
  #   kerf                   material que se lleva la sierra en cada corte
  Config = Data.define(:kerf, :head_trim, :tail_trim) do
    def self.from(attrs)
      attrs ||= {}
      new(
        kerf:      non_negative(attrs[:kerf],      "kerf"),
        head_trim: non_negative(attrs[:head_trim], "head_trim"),
        tail_trim: non_negative(attrs[:tail_trim], "tail_trim")
      )
    end

    def self.non_negative(value, name)
      number = Float(value || 0)
      raise InvalidInput, "#{name} no puede ser negativo" if number.negative?

      number
    end
    private_class_method :non_negative
  end
end
