# Parte 5 — Tres preguntas cortas

## 1. La media bajó de 800 ms a 400 ms, los errores no subieron, y una semana después los usuarios dicen que va más lento

Las tres explicaciones son ciertas a la vez porque cada una falla en un eje distinto:
la estadística, el alcance de la medición y el tiempo.

**a) La media esconde la cola.** Bajó el p50 y subió el p95. Optimizar el caso común
—un acierto de caché, una cotización pequeña— puede empeorar el caso raro, y los
usuarios que se quejan son casi siempre los mismos: los que tienen más datos, que viven
en la cola. La media de todos mejoró; la experiencia de los que hablan, no.
→ **Medir:** percentiles en vez de media, y segmentados por tamaño de cuenta. Si el p95
subió mientras el p50 bajaba, es esto.

**b) El endpoint no es la experiencia.** La latencia que sufre el usuario es la de la
interacción completa. Si la optimización movió trabajo en vez de eliminarlo —el cliente
ahora hace tres llamadas donde antes hacía una, o el trabajo se fue a un job cuyo
resultado hay que esperar igual— el endpoint mejora y la pantalla empeora.
→ **Medir:** tiempo desde el navegador hasta que la vista es utilizable (RUM), y número
de peticiones por interacción, antes y después.

**c) La mejora era real y se degradó.** El día del despliegue fue rápido de verdad. En
una semana creció el volumen, se llenó una tabla, la caché se quedó pequeña o las
estadísticas del planificador envejecieron. Se compara con un recuerdo de hace una
semana, no con la medición de hace una semana.
→ **Medir:** la serie temporal día a día desde el despliegue junto al volumen de datos.
Si la latencia sube con la carga, es esto y no un problema del cambio.

## 2. «Quiero un botón que recalcule todos los precios de una cotización». Dos días

Ordenadas por cuánto cambian la solución. Las dos primeras son bloqueantes: sin ellas no
sé qué estoy construyendo.

1. **¿Sobrescribe los precios o propone un cambio que alguien aprueba?** Es la pregunta
   que decide el producto. Si propone, hay que construir una comparación antes/después y
   un paso de aceptación. Si sobrescribe, hace falta historial y forma de deshacer.
2. **¿Qué pasa con las líneas que alguien tocó a mano?** ¿El recálculo las pisa o las
   respeta? Si hay que respetarlas, necesito saber qué precios son manuales, y es muy
   posible que hoy no se esté guardando quién puso cada valor: eso es trabajo previo, no
   parte del botón.
3. **¿Sobre qué cotizaciones se puede pulsar?** Solo borradores, o también enviadas y
   aceptadas. Recalcular una cotización ya aceptada es una decisión contractual, no
   técnica, y si entra en el alcance necesito reglas de quién puede y con qué registro.
4. **¿Con qué tarifa: la de hoy o la de la fecha de la cotización?** Cambia de dónde se
   lee el precio y si hace falta guardar la fecha efectiva del cálculo.
5. **¿Cuántas líneas tiene una cotización grande?** Con veinte es un clic síncrono; con
   miles es un trabajo en segundo plano con aviso al terminar.

**Y una respuesta que también doy en la reunión:** si las respuestas son «sobrescribe,
con auditoría y aprobación, sobre cotizaciones ya enviadas», eso no cabe en dos días.
Entregaría primero la versión que solo propone sobre borradores, que es útil sola y no
puede romper nada, y acordaría el resto como un segundo paso.

## 3. Un proceso nocturno tarda 6 horas y tiene que terminar en 2

Sin tocar hardware, algoritmo ni reescribirlo, quedan estos caminos:

1. **Perfilar dónde se van las 6 horas.** Casi siempre el grueso está en una sola fase, y
   sin saber cuál, todo lo demás es adivinar.
2. **Procesar menos.** Hacerlo incremental: solo lo que cambió desde anoche. No cambia el
   algoritmo, cambia la entrada.
3. **Base de datos.** Índices que faltan, estadísticas viejas, escrituras fila a fila
   donde cabría `COPY` o inserción por lotes, un commit por registro.
4. **Paralelizar por partición.** Si procesa entidades independientes, repartirlas en
   varios procesos sobre los núcleos que ya hay.
5. **Solapar E/S y CPU.** Si alterna leer, calcular y escribir en serie, hacerlo por
   lotes con lectura adelantada. Es orquestación, no algoritmo.
6. **Sacar del camino crítico** lo que no tiene que estar listo a esa hora: informes,
   notificaciones, agregados derivados.
7. **Cachear lo repetido**: tarifas, tipos de cambio, catálogos que se releen por registro.
8. **Ajustar el runtime**: memoria de trabajo, pool de conexiones, presión de recolección
   de basura. Barato de probar y a veces sorprende.
9. **Revisar la contención**: si compite con el backup o con otro proceso, mover la ventana.
10. **Arrancar por fases** en cuanto cada bloque de datos esté disponible, en vez de
    esperar a tenerlos todos.
11. **Cuestionar el requisito**: ¿tiene que terminar todo en 2 horas, o tiene que estar
    disponible cierto resultado a esa hora? A veces basta con reordenar qué sale primero.

**Empezaría por perfilar (1).** Es lo único que convierte las otras diez opciones en una
decisión en vez de una apuesta, y cuesta una ejecución. Con la medición delante, mi
apuesta es que lo más rentable serán (3) y (2): en un proceso nocturno de este tamaño lo
habitual es que la mayor parte del tiempo se vaya en la base de datos y en reprocesar
cosas que no habían cambiado.
