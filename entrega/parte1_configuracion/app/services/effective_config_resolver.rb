# frozen_string_literal: true

# Responde: dado un renglon, un conjunto de `unit_uid` y una version objetivo V,
# cual es el valor efectivo de cada clave para cada unidad.
#
#   EffectiveConfigResolver.call(
#     line_item_id: 42,
#     unit_uids:    %w[unit-a unit-b],
#     version:      7,
#     keys:         nil # nil = todas las claves; array = solo esas
#   )
#   # => { "unit-a" => { "width" => "1200", "glass_type" => "laminated" }, ... }
#
# Enfoque: las cinco reglas de resolucion no necesitan cinco pasadas. Las reglas
# 1 y 3 son filtros/pesos por fila y las reglas 2 y 5 son desempates, asi que
# juntas colapsan en un unico criterio de orden que Postgres resuelve con
# DISTINCT ON. La regla 4 (herencia) es lo unico que queda en Ruby, y es una
# fusion de dos hashes. Resultado: una sola consulta, sea cual sea el numero de
# unidades y de claves.
class EffectiveConfigResolver
  # Claves donde una eleccion explicita del usuario manda sobre lo que el motor
  # calcule despues (regla 3).
  USER_INTENT_KEYS = %w[glass_type color_id finish_id coating low_e].freeze

  # Claves dimensionales: nunca aplican la regla 3, solo la 1 y la 2 (regla 5).
  DIMENSIONAL_KEYS = %w[width height dlo_width dlo_height].freeze

  # Conjunto efectivo sobre el que la regla 3 tiene efecto. Hoy los dos conjuntos
  # son disjuntos y la resta no quita nada, pero deja la regla 5 escrita en el
  # codigo: si manana alguien mete `width` en USER_INTENT_KEYS, la excepcion
  # dimensional sigue ganando.
  INTENT_KEYS = (USER_INTENT_KEYS - DIMENSIONAL_KEYS).freeze

  TABLE = "line_item_directives"

  def self.call(...) = new(...).call

  def initialize(line_item_id:, unit_uids:, version:, keys: nil)
    @line_item_id = Integer(line_item_id)
    @version      = Integer(version)
    @unit_uids    = Array(unit_uids).map(&:to_s).uniq
    @keys         = keys.nil? ? nil : Array(keys).map(&:to_s).uniq
  end

  def call
    return {} if @unit_uids.empty?
    # `keys: []` pide explicitamente cero claves: no hay nada que consultar.
    return @unit_uids.index_with { {} } if @keys == []

    merge_header_into_units(fetch_winning_directives)
  end

  private

  attr_reader :line_item_id, :unit_uids, :version, :keys

  # Devuelve ya resueltas las directivas ganadoras: una fila por
  # (unit_uid, key), incluida la cabecera (unit_uid NULL).
  def fetch_winning_directives
    ActiveRecord::Base.connection.select_all(resolution_sql, "EffectiveConfigResolver")
  end

  def resolution_sql
    ActiveRecord::Base.sanitize_sql_array([<<~SQL.squish, binds])
      SELECT DISTINCT ON (unit_uid, key) unit_uid, key, value
      FROM #{TABLE}
      WHERE line_item_id = :line_item_id
        AND version <= :version
        AND (unit_uid IS NULL OR unit_uid IN (:unit_uids))
        #{key_filter_sql}
      ORDER BY
        unit_uid,
        key,
        CASE WHEN source = 'user' AND key IN (:intent_keys) THEN 1 ELSE 0 END DESC,
        version DESC,
        created_at DESC,
        id DESC
    SQL
  end

  # `keys:` viaja al WHERE, no a un `select` posterior en Ruby: recorta las filas
  # leidas y deja usable el indice (line_item_id, key, version).
  def key_filter_sql
    keys.nil? ? "" : "AND key IN (:keys)"
  end

  def binds
    b = {
      line_item_id: line_item_id,
      version: version,
      unit_uids: unit_uids,
      intent_keys: INTENT_KEYS
    }
    b[:keys] = keys unless keys.nil?
    b
  end

  # Regla 4: la unidad hereda de la cabecera toda clave para la que no tiene
  # directiva propia. Una directiva propia con `value` NULL cuenta como valor:
  # el historial no se borra, poner NULL es la forma de anular una clave.
  def merge_header_into_units(rows)
    header    = {}
    per_unit  = Hash.new { |h, uid| h[uid] = {} }

    rows.each do |row|
      scope = row["unit_uid"].nil? ? header : per_unit[row["unit_uid"]]
      scope[row["key"]] = row["value"]
    end

    unit_uids.index_with { |uid| header.merge(per_unit.fetch(uid, {})) }
  end
end
