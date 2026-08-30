# frozen_string_literal: true

# Fila del historial de directivas de un renglon de cotizacion.
#
# El historial es inmutable: las directivas se acumulan y nunca se modifican ni
# se borran. Por eso el modelo no tiene `updated_at` y no expone escrituras
# distintas de la insercion.
class LineItemDirective < ApplicationRecord
  HEADER = "header"
  UNIT   = "unit"

  SOURCES = %w[user resolution preserved default].freeze

  validates :line_item_id, :key, :version, presence: true
  validates :directive_type, inclusion: { in: [HEADER, UNIT] }
  validates :source, inclusion: { in: SOURCES }
  validates :unit_uid, presence: true, if: -> { directive_type == UNIT }
  validates :unit_uid, absence: true,  if: -> { directive_type == HEADER }
end
