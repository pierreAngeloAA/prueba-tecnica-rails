# frozen_string_literal: true

class CutPlanner
  # Toda la heuristica cabe en dos decisiones, y las dos viven aqui:
  #
  #   1. entre las barras ya abiertas donde la pieza cabe, ¿cual elijo?
  #   2. si no cabe en ninguna, ¿que tipo de barra saco del almacen?
  #
  # El resto del planificador (orden de las piezas, control de stock, cuentas de
  # desperdicio) no cambia al cambiar de politica. Por eso «prioriza consumir
  # primero los retales cortos» es una clase nueva, no un rediseño.
  module Policies
    # First Fit: la primera barra abierta donde quepa. Al abrir, la barra
    # disponible mas larga, que es la que deja mas sitio para las piezas
    # siguientes (que por el orden descendente son siempre menores o iguales).
    class FirstFit
      def choose_bar(bars, piece_length)
        bars.find { |bar| bar.fits?(piece_length) }
      end

      # `types` llega ordenado de mas larga a mas corta, asi que `find` es
      # determinista tambien cuando dos tipos miden lo mismo.
      def choose_stock(types, piece_length, kerf)
        types.find { |type| type.admits?(piece_length, kerf) }
      end
    end

    # Respuesta a «prioriza consumir primero los retales cortos»: entre las
    # barras donde la pieza cabe, la que menos sitio libre tiene, para cerrar
    # retales pequeños antes de morder barras enteras. Al abrir, la mas corta
    # que sirva, por el mismo motivo.
    #
    # `min_by` y `max_by` devuelven el primer elemento empatado, asi que sobre
    # una lista estable el resultado sigue siendo determinista.
    class ShortestRemnantFirst
      def choose_bar(bars, piece_length)
        bars.select { |bar| bar.fits?(piece_length) }.min_by(&:remnant)
      end

      def choose_stock(types, piece_length, kerf)
        types.select { |type| type.admits?(piece_length, kerf) }.min_by(&:usable_length)
      end
    end
  end
end
