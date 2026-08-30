# frozen_string_literal: true

module DirectiveHelpers
  LINE_ITEM = 1

  # Azucar para construir historial. `at` desempata dentro de una misma version.
  def header(key:, value:, version:, source: "default", at: nil, line_item_id: LINE_ITEM)
    create_directive(line_item_id:, directive_type: "header", unit_uid: nil,
                     key:, value:, source:, version:, at:)
  end

  def unit(uid, key:, value:, version:, source: "default", at: nil, line_item_id: LINE_ITEM)
    create_directive(line_item_id:, directive_type: "unit", unit_uid: uid,
                     key:, value:, source:, version:, at:)
  end

  def create_directive(line_item_id:, directive_type:, unit_uid:, key:, value:, source:, version:, at:)
    LineItemDirective.create!(
      line_item_id:, directive_type:, unit_uid:, key:, value:, source:, version:,
      created_at: at || Time.zone.parse("2026-01-01 00:00:00") + version.minutes
    )
  end

  # Cuenta consultas reales, descartando el ruido de esquema y de transaccion
  # que mete el propio entorno de pruebas.
  def count_queries
    queries = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      next if payload[:name].in?(%w[SCHEMA TRANSACTION])
      next if payload[:sql].match?(/\A\s*(SAVEPOINT|RELEASE|ROLLBACK|BEGIN|COMMIT)/i)

      queries << payload[:sql]
    end
    yield
    queries
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end
end
