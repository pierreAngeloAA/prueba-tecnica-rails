# frozen_string_literal: true

class CreateLineItemDirectives < ActiveRecord::Migration[7.2]
  def change
    create_table :line_item_directives do |t|
      t.bigint   :line_item_id,   null: false
      t.string   :directive_type, null: false, limit: 10 # 'header' | 'unit'
      t.string   :unit_uid,                     limit: 64 # NULL cuando directive_type = 'header'
      t.string   :key,            null: false, limit: 64
      t.text     :value
      t.string   :source,         null: false, limit: 16 # 'user'|'resolution'|'preserved'|'default'
      t.integer  :version,        null: false
      t.datetime :created_at,     null: false
    end

    # El resolutor distingue cabecera de unidad por `unit_uid IS NULL`, que es
    # sargable y permite que un unico indice sirva a los dos ambitos. Esta
    # restriccion es lo que hace que esa lectura sea siempre equivalente a
    # `directive_type = 'header'`.
    add_check_constraint :line_item_directives,
                         "(directive_type = 'header' AND unit_uid IS NULL) OR " \
                         "(directive_type = 'unit' AND unit_uid IS NOT NULL)",
                         name: "chk_line_item_directives_scope"

    # Camino de acceso principal: acotar por renglon, quedarse con la cabecera y
    # las unidades pedidas, y cortar por version. Sirve tanto a `unit_uid IS NULL`
    # como a `unit_uid IN (...)` porque un b-tree indexa los NULL.
    add_index :line_item_directives,
              %i[line_item_id unit_uid key version],
              name: "idx_line_item_directives_by_unit"

    # Camino alternativo para cuando llega `keys:` con pocas claves y muchas
    # unidades: ahi el conjunto de claves es mas selectivo que el de unidades.
    add_index :line_item_directives,
              %i[line_item_id key version],
              name: "idx_line_item_directives_by_key"
  end
end
