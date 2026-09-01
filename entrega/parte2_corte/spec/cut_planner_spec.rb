# frozen_string_literal: true

RSpec.describe CutPlanner do
  # Despuntes de 100 + 50 sobre una barra de 6.000 dejan 5.850 utiles.
  DEFAULT_CONFIG = { kerf: 4.0, head_trim: 100.0, tail_trim: 50.0 }.freeze

  def plan_for(pieces:, stock:, config: DEFAULT_CONFIG, **rest)
    described_class.new(pieces:, stock:, config:, **rest).call
  end

  def bar(id, length, available) = { id:, length:, available: }
  def piece(length, quantity) = { length:, quantity: }

  describe "el ejemplo del enunciado" do
    subject(:plan) do
      plan_for(pieces: [piece(1_450.0, 12), piece(820.5, 30)],
               stock:  [bar("BAR-A", 6_000.0, 8), bar("BAR-B", 4_000.0, 3)])
    end

    it "produce todas las piezas" do
      expect(plan.unplaced).to be_empty
    end

    it "mete 4 piezas de 1450 por barra: 4 x 1454 = 5816 <= 5850" do
      barras_1450 = plan.bars.select { |b| b.pieces.include?(1_450.0) }
      expect(barras_1450.map { |b| b.pieces.size }).to all(eq(4))
    end

    it "informa del desperdicio sobre el material consumido" do
      expect(plan.waste_ratio).to be_within(0.001).of(0.125)
    end
  end

  describe "inventario insuficiente" do
    it "coloca lo que puede y devuelve el resto en unplaced" do
      plan = plan_for(pieces: [piece(1_450.0, 10)], stock: [bar("BAR-A", 6_000.0, 1)])

      expect(plan.bars.size).to eq(1)
      expect(plan.bars.first.pieces.size).to eq(4)
      expect(plan.unplaced.map(&:to_h)).to eq([{ length: 1_450.0, quantity: 6 }])
    end

    it "no falla ni lanza excepcion cuando no alcanza el material" do
      expect { plan_for(pieces: [piece(1_000.0, 99)], stock: [bar("BAR-A", 6_000.0, 1)]) }
        .not_to raise_error
    end

    it "nunca usa mas barras de un tipo que las disponibles" do
      plan = plan_for(pieces: [piece(1_450.0, 100)],
                      stock:  [bar("BAR-A", 6_000.0, 2), bar("BAR-B", 4_000.0, 3)])

      expect(plan.bars_used_by_stock).to eq("BAR-A" => 2, "BAR-B" => 3)
    end

    it "agota un tipo de barra y sigue con el siguiente" do
      plan = plan_for(pieces: [piece(1_450.0, 12)],
                      stock:  [bar("BAR-A", 6_000.0, 2), bar("BAR-B", 4_000.0, 5)])

      expect(plan.bars_used_by_stock).to eq("BAR-A" => 2, "BAR-B" => 2)
      expect(plan.unplaced).to be_empty
    end
  end

  describe "una pieza mas larga que cualquier barra util" do
    it "la declara no producible sin abrir ninguna barra" do
      # 5.900 cabe en los 6.000 nominales pero no en los 5.850 utiles.
      plan = plan_for(pieces: [piece(5_900.0, 1)], stock: [bar("BAR-A", 6_000.0, 8)])

      expect(plan.bars).to be_empty
      expect(plan.unplaced.map(&:to_h)).to eq([{ length: 5_900.0, quantity: 1 }])
      expect(plan.waste_ratio).to eq(0.0)
    end

    it "una pieza que no cabe no impide colocar las que si caben" do
      plan = plan_for(pieces: [piece(9_000.0, 1), piece(1_000.0, 2)],
                      stock:  [bar("BAR-A", 6_000.0, 8)])

      expect(plan.bars.size).to eq(1)
      expect(plan.bars.first.pieces).to eq([1_000.0, 1_000.0])
      expect(plan.unplaced.map(&:to_h)).to eq([{ length: 9_000.0, quantity: 1 }])
    end

    it "tiene en cuenta el kerf al decidir si cabe en una barra virgen" do
      # Util = 1.000. Una pieza de 1.000 necesita 1.000 + 4 de kerf: no cabe.
      sin_kerf = plan_for(pieces: [piece(1_000.0, 1)], stock: [bar("B", 1_150.0, 1)],
                          config: { kerf: 0.0, head_trim: 100.0, tail_trim: 50.0 })
      con_kerf = plan_for(pieces: [piece(1_000.0, 1)], stock: [bar("B", 1_150.0, 1)],
                          config: DEFAULT_CONFIG)

      expect(sin_kerf.unplaced).to be_empty
      expect(con_kerf.unplaced.map(&:to_h)).to eq([{ length: 1_000.0, quantity: 1 }])
    end
  end

  describe "el kerf cambia el resultado" do
    # Util = 3.000. Tres piezas de 1.000 entran justas solo si la sierra no
    # se lleva nada; con kerf de 4 mm hacen falta 3.012 y solo caben dos.
    let(:pieces) { [piece(1_000.0, 3)] }
    let(:stock)  { [bar("BAR-C", 3_150.0, 1)] }

    it "sin kerf caben las tres piezas en una barra" do
      plan = plan_for(pieces:, stock:, config: { kerf: 0.0, head_trim: 100.0, tail_trim: 50.0 })

      expect(plan.bars.size).to eq(1)
      expect(plan.bars.first.pieces.size).to eq(3)
      expect(plan.unplaced).to be_empty
    end

    it "con kerf solo caben dos y la tercera se queda fuera" do
      plan = plan_for(pieces:, stock:, config: DEFAULT_CONFIG)

      expect(plan.bars.first.pieces.size).to eq(2)
      expect(plan.unplaced.map(&:to_h)).to eq([{ length: 1_000.0, quantity: 1 }])
    end

    it "el kerf empeora el aprovechamiento con la misma entrada" do
      sin_kerf = plan_for(pieces: [piece(1_000.0, 6)], stock: [bar("X", 3_150.0, 4)],
                          config: { kerf: 0.0, head_trim: 100.0, tail_trim: 50.0 })
      con_kerf = plan_for(pieces: [piece(1_000.0, 6)], stock: [bar("X", 3_150.0, 4)],
                          config: DEFAULT_CONFIG)

      expect(sin_kerf.bars.size).to eq(2)
      expect(con_kerf.bars.size).to eq(3)
      expect(con_kerf.waste_ratio).to be > sin_kerf.waste_ratio
    end
  end

  describe "despuntes" do
    it "descuenta cabeza y cola del tramo aprovechable" do
      plan = plan_for(pieces: [piece(5_850.0, 1)], stock: [bar("BAR-A", 6_000.0, 1)],
                      config: { kerf: 0.0, head_trim: 100.0, tail_trim: 50.0 })

      expect(plan.bars.first.remnant).to be_within(1e-6).of(0.0)
      expect(plan.unplaced).to be_empty
    end

    it "sin despuntes se aprovecha la barra entera" do
      plan = plan_for(pieces: [piece(6_000.0, 1)], stock: [bar("BAR-A", 6_000.0, 1)],
                      config: { kerf: 0.0, head_trim: 0.0, tail_trim: 0.0 })

      expect(plan.unplaced).to be_empty
      expect(plan.waste_ratio).to eq(0.0)
    end

    it "unos despuntes mayores que la barra la dejan inservible" do
      plan = plan_for(pieces: [piece(10.0, 1)], stock: [bar("CORTA", 100.0, 1)],
                      config: { kerf: 0.0, head_trim: 80.0, tail_trim: 80.0 })

      expect(plan.bars).to be_empty
      expect(plan.unplaced.map(&:to_h)).to eq([{ length: 10.0, quantity: 1 }])
    end
  end

  describe "determinismo" do
    let(:entrada) do
      { pieces: [piece(1_450.0, 12), piece(820.5, 30), piece(300.0, 17), piece(1_450.0, 5)],
        stock:  [bar("BAR-A", 6_000.0, 8), bar("BAR-B", 4_000.0, 3), bar("BAR-C", 6_000.0, 2)] }
    end

    it "dos ejecuciones con la misma entrada producen el mismo plan" do
      primera = plan_for(**entrada)
      segunda = plan_for(**entrada)

      expect(segunda.to_h).to eq(primera.to_h)
    end

    it "el orden de las piezas en la entrada no cambia el plan" do
      normal    = plan_for(**entrada)
      invertida = plan_for(**entrada.merge(pieces: entrada[:pieces].reverse))

      expect(invertida.bars.map { |b| b.pieces.sort }).to eq(normal.bars.map { |b| b.pieces.sort })
    end
  end

  describe "heuristica" do
    it "coloca primero las piezas largas y deja que las cortas rellenen el hueco" do
      plan = plan_for(pieces: [piece(1_000.0, 3), piece(3_000.0, 1)],
                      stock:  [bar("BAR-A", 6_000.0, 8)],
                      config: { kerf: 0.0, head_trim: 100.0, tail_trim: 50.0 })

      # Util = 5.850. La de 3.000 entra primera aunque venga la ultima en la
      # entrada, y dos de 1.000 rellenan detras; la tercera ya no cabe.
      expect(plan.bars.first.pieces).to eq([3_000.0, 1_000.0, 1_000.0])
      expect(plan.bars.size).to eq(2)
    end

    it "abre la barra mas larga disponible" do
      plan = plan_for(pieces: [piece(1_000.0, 1)],
                      stock:  [bar("CORTA", 2_000.0, 5), bar("LARGA", 6_000.0, 5)])

      expect(plan.bars.first.stock_id).to eq("LARGA")
    end
  end

  describe "politica alternativa: priorizar retales cortos" do
    let(:politica) { CutPlanner::Policies::ShortestRemnantFirst.new }

    it "abre la barra mas corta que sirva en vez de la mas larga" do
      plan = plan_for(pieces: [piece(1_000.0, 1)],
                      stock:  [bar("CORTA", 2_000.0, 5), bar("LARGA", 6_000.0, 5)],
                      policy: politica)

      expect(plan.bars.first.stock_id).to eq("CORTA")
    end

    # Dentro del planificador las dos politicas coinciden casi siempre: como las
    # piezas entran de mayor a menor, la primera barra abierta suele ser tambien
    # la de menor retal. La diferencia se ve aislando la decision.
    it "elige el retal mas ajustado donde First Fit elige el primero que encuentra" do
      holgada = CutPlanner::Bar.new(stock_id: "LARGA", length: 6_000.0,
                                    usable_length: 5_850.0, kerf: 0.0)
      justa   = CutPlanner::Bar.new(stock_id: "CORTA", length: 2_000.0,
                                    usable_length: 1_900.0, kerf: 0.0)
      abiertas = [holgada, justa]

      expect(politica.choose_bar(abiertas, 1_000.0)).to be(justa)
      expect(CutPlanner::Policies::FirstFit.new.choose_bar(abiertas, 1_000.0)).to be(holgada)
    end

    it "produce el mismo total de piezas que la politica por defecto" do
      entrada = { pieces: [piece(1_450.0, 12), piece(820.5, 30)],
                  stock:  [bar("BAR-A", 6_000.0, 8), bar("BAR-B", 4_000.0, 3)] }

      por_defecto = plan_for(**entrada)
      alternativa = plan_for(**entrada, policy: politica)

      expect(alternativa.bars.sum { |b| b.pieces.size })
        .to eq(por_defecto.bars.sum { |b| b.pieces.size })
    end
  end

  describe "escala" do
    it "resuelve 5.000 piezas en tiempo razonable y sin recursion" do
      pieces = 50.times.map { |i| piece(300.0 + (i * 25), 100) } # 5.000 piezas
      stock  = [bar("BAR-A", 6_000.0, 2_000), bar("BAR-B", 4_000.0, 500)]

      inicio = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      plan   = plan_for(pieces:, stock:)
      tardo  = Process.clock_gettime(Process::CLOCK_MONOTONIC) - inicio

      expect(plan.bars.sum { |b| b.pieces.size } + plan.unplaced.sum(&:quantity)).to eq(5_000)
      expect(tardo).to be < 10.0
    end
  end

  describe "entradas invalidas" do
    it "rechaza una pieza de longitud cero" do
      expect { plan_for(pieces: [piece(0.0, 1)], stock: [bar("A", 6_000.0, 1)]) }
        .to raise_error(CutPlanner::InvalidInput, /longitud positiva/)
    end

    it "rechaza cantidades no positivas" do
      expect { plan_for(pieces: [piece(100.0, 0)], stock: [bar("A", 6_000.0, 1)]) }
        .to raise_error(CutPlanner::InvalidInput, /cantidad positiva/)
    end

    it "rechaza un kerf negativo" do
      expect { plan_for(pieces: [piece(100.0, 1)], stock: [bar("A", 6_000.0, 1)], config: { kerf: -1.0 }) }
        .to raise_error(CutPlanner::InvalidInput, /kerf/)
    end

    it "rechaza stock vacio" do
      expect { plan_for(pieces: [piece(100.0, 1)], stock: []) }
        .to raise_error(CutPlanner::InvalidInput, /stock/)
    end

    it "un tipo de barra con cero disponibles no se usa" do
      plan = plan_for(pieces: [piece(1_000.0, 1)],
                      stock:  [bar("AGOTADA", 6_000.0, 0), bar("BAR-B", 4_000.0, 1)])

      expect(plan.bars.first.stock_id).to eq("BAR-B")
    end
  end

  describe "el servicio no imprime nada" do
    it "no escribe en stdout ni en stderr" do
      expect do
        plan_for(pieces: [piece(1_450.0, 12), piece(820.5, 30)],
                 stock:  [bar("BAR-A", 6_000.0, 8)])
      end.to output("").to_stdout.and(output("").to_stderr)
    end
  end
end
