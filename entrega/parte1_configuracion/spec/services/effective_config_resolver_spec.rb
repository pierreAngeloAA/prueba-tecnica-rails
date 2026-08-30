# frozen_string_literal: true

require "rails_helper"

RSpec.describe EffectiveConfigResolver do
  include DirectiveHelpers

  let(:line_item_id) { DirectiveHelpers::LINE_ITEM }

  def resolve(unit_uids: %w[unit-a], version: 10, keys: nil)
    described_class.call(line_item_id:, unit_uids:, version:, keys:)
  end

  describe "regla 1 — corte por version" do
    it "ignora las directivas por encima de la version objetivo" do
      unit "unit-a", key: "width", value: "1000", version: 3
      unit "unit-a", key: "width", value: "9999", version: 11

      expect(resolve(version: 10)).to eq("unit-a" => { "width" => "1000" })
    end

    it "incluye la directiva escrita exactamente en la version objetivo" do
      unit "unit-a", key: "width", value: "1000", version: 3
      unit "unit-a", key: "width", value: "1200", version: 10

      expect(resolve(version: 10)).to eq("unit-a" => { "width" => "1200" })
    end
  end

  describe "regla 2 — gana la mas reciente" do
    it "gana la version mas alta" do
      unit "unit-a", key: "width", value: "1000", version: 2
      unit "unit-a", key: "width", value: "1200", version: 5

      expect(resolve).to eq("unit-a" => { "width" => "1200" })
    end

    it "con empate de version gana la escrita mas tarde" do
      t = Time.zone.parse("2026-02-01 09:00:00")
      unit "unit-a", key: "width", value: "primera", version: 4, at: t
      unit "unit-a", key: "width", value: "segunda", version: 4, at: t + 1.hour

      expect(resolve).to eq("unit-a" => { "width" => "segunda" })
    end

    it "con empate de version y de created_at gana la insertada despues" do
      t = Time.zone.parse("2026-02-01 09:00:00")
      unit "unit-a", key: "width", value: "primera", version: 4, at: t
      unit "unit-a", key: "width", value: "segunda", version: 4, at: t

      expect(resolve).to eq("unit-a" => { "width" => "segunda" })
    end
  end

  describe "regla 3 — prioridad de la eleccion del usuario" do
    it "user gana a una resolution posterior en una clave de intencion" do
      unit "unit-a", key: "glass_type", value: "laminated", version: 3, source: "user"
      unit "unit-a", key: "glass_type", value: "tempered",  version: 8, source: "resolution"

      expect(resolve).to eq("unit-a" => { "glass_type" => "laminated" })
    end

    it "entre varias directivas user gana la mas reciente" do
      unit "unit-a", key: "coating", value: "viejo",  version: 2, source: "user"
      unit "unit-a", key: "coating", value: "nuevo",  version: 6, source: "user"
      unit "unit-a", key: "coating", value: "motor",  version: 9, source: "resolution"

      expect(resolve).to eq("unit-a" => { "coating" => "nuevo" })
    end

    it "no aplica a claves fuera de USER_INTENT_KEYS" do
      unit "unit-a", key: "spacer", value: "elegido",  version: 3, source: "user"
      unit "unit-a", key: "spacer", value: "calculado", version: 8, source: "resolution"

      expect(resolve).to eq("unit-a" => { "spacer" => "calculado" })
    end

    it "solo cuenta la directiva user si esta dentro del corte de version" do
      unit "unit-a", key: "glass_type", value: "elegido",   version: 12, source: "user"
      unit "unit-a", key: "glass_type", value: "calculado", version: 8,  source: "resolution"

      expect(resolve(version: 10)).to eq("unit-a" => { "glass_type" => "calculado" })
    end
  end

  describe "regla 4 — herencia desde la cabecera" do
    it "la unidad hereda las claves que no tiene propias" do
      header key: "glass_type", value: "laminated", version: 1
      header key: "width",      value: "1000",      version: 1
      unit "unit-a", key: "width", value: "1200", version: 4

      expect(resolve).to eq("unit-a" => { "glass_type" => "laminated", "width" => "1200" })
    end

    it "una unidad sin ninguna directiva propia recibe la cabecera completa" do
      header key: "glass_type", value: "laminated", version: 1
      header key: "width",      value: "1000",      version: 1

      expect(resolve(unit_uids: %w[unit-a unit-b])).to eq(
        "unit-a" => { "glass_type" => "laminated", "width" => "1000" },
        "unit-b" => { "glass_type" => "laminated", "width" => "1000" }
      )
    end

    it "la cabecera se resuelve con las mismas reglas 1 a 3" do
      header key: "glass_type", value: "elegido",   version: 2, source: "user"
      header key: "glass_type", value: "calculado", version: 7, source: "resolution"

      expect(resolve).to eq("unit-a" => { "glass_type" => "elegido" })
    end

    it "una directiva propia con valor NULL anula la herencia" do
      header key: "coating", value: "low-e", version: 1
      unit "unit-a", key: "coating", value: nil, version: 5

      expect(resolve).to eq("unit-a" => { "coating" => nil })
    end
  end

  describe "regla 5 — excepcion dimensional" do
    it "resolution gana a un user anterior en una clave dimensional" do
      unit "unit-a", key: "width", value: "1000", version: 3, source: "user"
      unit "unit-a", key: "width", value: "1180", version: 8, source: "resolution"

      expect(resolve).to eq("unit-a" => { "width" => "1180" })
    end

    it "aplica a las cuatro claves dimensionales" do
      described_class::DIMENSIONAL_KEYS.each_with_index do |dim_key, i|
        unit "unit-a", key: dim_key, value: "user",    version: 3, source: "user"
        unit "unit-a", key: dim_key, value: "motor#{i}", version: 8, source: "resolution"
      end

      expect(resolve).to eq(
        "unit-a" => described_class::DIMENSIONAL_KEYS.each_with_index.to_h { |k, i| [k, "motor#{i}"] }
      )
    end
  end

  describe "aislamiento entre unidades y renglones" do
    it "no mezcla directivas de otras unidades" do
      unit "unit-a", key: "width", value: "1000", version: 4
      unit "unit-b", key: "width", value: "2000", version: 4

      expect(resolve(unit_uids: %w[unit-a unit-b])).to eq(
        "unit-a" => { "width" => "1000" },
        "unit-b" => { "width" => "2000" }
      )
    end

    it "no mezcla directivas de otro renglon" do
      unit "unit-a", key: "width", value: "1000", version: 4
      unit "unit-a", key: "width", value: "9999", version: 9, line_item_id: 99

      expect(resolve).to eq("unit-a" => { "width" => "1000" })
    end
  end

  describe "parametro keys:" do
    before do
      header key: "glass_type", value: "laminated", version: 1
      unit "unit-a", key: "width",  value: "1200", version: 4
      unit "unit-a", key: "height", value: "800",  version: 4
    end

    it "devuelve solo las claves pedidas, herencia incluida" do
      expect(resolve(keys: %w[width glass_type])).to eq(
        "unit-a" => { "width" => "1200", "glass_type" => "laminated" }
      )
    end

    it "empuja el filtro a la consulta en vez de recortar el resultado al final" do
      sql = count_queries { resolve(keys: %w[width]) }.first
      expect(sql).to include("key IN")
    end

    it "keys: [] no consulta nada y devuelve la unidad vacia" do
      expect(count_queries { expect(resolve(keys: [])).to eq("unit-a" => {}) }).to be_empty
    end

    it "keys: nil devuelve todas las claves" do
      expect(resolve(keys: nil).fetch("unit-a").keys).to match_array(%w[glass_type width height])
    end
  end

  describe "coste en consultas" do
    it "usa una sola consulta y no crece con el numero de unidades ni de claves" do
      uids = Array.new(50) { |i| "unit-#{i}" }
      uids.each_with_index do |uid, i|
        10.times { |k| unit uid, key: "k#{k}", value: "v#{i}-#{k}", version: 2 }
      end

      pocas   = count_queries { described_class.call(line_item_id:, unit_uids: uids.first(2), version: 10) }
      muchas  = count_queries { described_class.call(line_item_id:, unit_uids: uids, version: 10) }
      con_key = count_queries { described_class.call(line_item_id:, unit_uids: uids, version: 10, keys: %w[k1 k2]) }

      expect(pocas.size).to eq(1)
      expect(muchas.size).to eq(1)
      expect(con_key.size).to eq(1)
    end
  end

  describe "entradas de borde" do
    it "sin unidades devuelve un hash vacio sin consultar" do
      expect(count_queries { expect(resolve(unit_uids: [])).to eq({}) }).to be_empty
    end

    it "deduplica los unit_uid repetidos" do
      unit "unit-a", key: "width", value: "1200", version: 4
      expect(resolve(unit_uids: %w[unit-a unit-a])).to eq("unit-a" => { "width" => "1200" })
    end
  end
end
