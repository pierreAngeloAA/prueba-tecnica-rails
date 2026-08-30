# Parte 2 — Planificador de corte de material

## Modelo físico

Una barra de longitud `L` no se aprovecha entera: los despuntes se llevan
`head_trim + tail_trim`, así que el tramo utilizable es `L - head_trim - tail_trim`.
Dentro de ese tramo, **cada pieza consume `longitud + kerf`**.

**Decisión sobre el último corte** (el enunciado la deja abierta): cobro kerf también
a la última pieza. Para separarla del retal hay que dar un corte real, y ese corte se
lleva su material. Solo te ahorrarías ese kerf si la pieza terminara exactamente en el
borde del despunte final, un encaje perfecto que en planta no ocurre. Es la lectura
conservadora: el plan nunca promete una pieza que luego no sale. El coste de
equivocarse en este sentido es un retal 4 mm más largo; en el otro, una pieza que no
se puede fabricar.

Las longitudes son coma flotante y las sumas acumulan error, así que las comparaciones
llevan una tolerancia de `1e-9` mm. Sin ella una pieza que encaja justo se declararía
fuera por 1e-13 mm.

## Qué heurística elegí

**First Fit Decreasing.** Se ordenan las piezas de mayor a menor; cada una entra en la
primera barra abierta donde quepa; si no cabe en ninguna se abre una barra nueva —la
más larga disponible—; si no queda stock que la admita, se declara no producible.

Lo que hace el trabajo es el orden descendente. **Las piezas largas son las difíciles
de colocar.** Metiendo primero las cortas, las barras se llenan de fragmentos y luego
las largas no caben en ningún hueco y obligan a abrir barras solo para ellas. Al revés,
las cortas rellenan los huecos que dejan las largas, y las cortas caben casi en
cualquier parte.

Coste `O(n log n + n·b)` con `n` piezas y `b` barras abiertas. Sin recursión, sin
retroceso: el tiempo está acotado por la entrada, no por la dificultad del caso.

**Medido con 5.000 piezas** (50 longitudes de 300 a 1.525 mm, 100 de cada una,
barras de 6.000 y 4.000 mm):

| | barras | desperdicio | tiempo |
|---|---|---|---|
| First Fit Decreasing | **790** | 3,74 % | 0,65 s |
| cota inferior teórica | 780 | — | — |

Un 1,3 % por encima del mínimo teórico. La garantía conocida de FFD es que nunca pasa
de ~22 % sobre el óptimo; aquí queda muy por debajo porque las piezas son pequeñas
frente a la barra.

## Qué descarté

- **Fuerza bruta / *branch and bound*.** Da el óptimo y no termina: el problema es
  NP-difícil y la entrada llega a 5.000 piezas. El enunciado lo prohíbe.
- **First Fit sin ordenar.** Mismo coste asintótico y peor resultado. Ordenar es la
  parte barata (`O(n log n)`) y es de donde sale casi toda la calidad.
- **Best Fit Decreasing.** La alternativa real. Coloca la pieza en la barra donde deje
  *menos* retal en vez de en la primera que sirva. En la literatura empata con FFD, y
  cuesta recorrer todas las barras abiertas en lugar de parar en la primera. Está
  implementada como `Policies::ShortestRemnantFirst`, y medida más abajo.
- **Generación de columnas (Gilmore-Gomory).** Es *la* solución clásica del cutting
  stock y da resultados muy superiores. Necesita un solver de programación lineal:
  librería de optimización, prohibida por el enunciado.

## Cómo mediría si un plan de corte es bueno

`waste_ratio` sirve para comparar dos planes de la misma demanda, pero **no dice si un
plan es bueno**: un plan que no produce nada tiene desperdicio cero. Miraría cuatro
cosas, en este orden:

1. **Piezas no producidas.** Un plan que deja piezas fuera con material disponible está
   mal, por bueno que sea su desperdicio. Es la única métrica que puede invalidar el plan.
2. **Barras usadas frente a la cota inferior** `⌈Σ longitudes / longitud útil⌉`. Es
   barata de calcular y acota lo lejos que estás del óptimo sin conocerlo. Es la
   medida que uso arriba.
3. **Distribución de los retales, no su suma.** Diez retales de 500 mm valen más que uno
   de 5.000: los cortos se reutilizan en piezas pequeñas. `waste_ratio` no distingue
   esos dos casos y por eso no basta.
4. **Coste, no longitud.** Si las barras tuvieran precios distintos, minimizar
   milímetros dejaría de ser el objetivo correcto. Hoy no hay precios en la entrada.

## Si mañana hay que priorizar consumir primero los retales cortos

Ya se puede: es `Policies::ShortestRemnantFirst`, y se pasa por parámetro.

Toda la heurística cabe en dos decisiones —en qué barra abierta va la pieza y qué tipo
de barra se abre cuando no cabe en ninguna—, y las dos viven en la política. El resto
del planificador (orden de las piezas, control de stock, cuentas de desperdicio) no se
entera de cuál está activa.

Lo interesante es que **el cambio no es gratis, y se puede cuantificar**:

| | barras | desperdicio |
|---|---|---|
| First Fit Decreasing | 790 | 3,74 % |
| ShortestRemnantFirst | 960 | 4,15 % |

Un **21 % más de barras**. Cerrar retales pequeños antes de morder barras enteras deja
el almacén más limpio, pero consume más material en esta tanda. Eso convierte la
petición en una decisión de negocio explícita —¿vale la pena gastar un 21 % más de
barras hoy para no acumular retales?— en lugar de un cambio silencioso de algoritmo.

## Qué dejo fuera

- **No aprovecho los retales entre ejecuciones.** Cada llamada parte del almacén que se
  le pasa; los sobrantes no vuelven al inventario. Sería el siguiente paso real.
- **No agrupo piezas idénticas.** Con 5.000 piezas y 0,65 s no hace falta; si la entrada
  creciera un orden de magnitud, colocar de golpe las `k` piezas iguales que caben en
  una barra reduciría mucho el trabajo.
- **Una sola dimensión.** El vidrio se corta en dos, y ese es otro problema.
