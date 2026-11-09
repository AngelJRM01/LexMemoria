# LexMemoria 0.7.2 — comienzo de integración europea

La biblioteca incorpora una muestra real de tres textos europeos para lectura offline: RGPD (99 artículos), Directiva 2019/1152 (26) y Decisión 2021/914 (4). Son las ediciones originales publicadas, no una promesa de vigencia actual. Se conservan todos los párrafos de la extracción, identificadores, hashes y referencias a la fuente. Los paquetes solo se abren cuando se solicita una norma; no se descomprime el corpus europeo durante el arranque.

El filtro «Europeo» distingue estas normas del ámbito estatal y autonómico. El índice separa artículos, preámbulo, considerandos y anexos. El lector muestra la fuente europea y la fecha de publicación, sin presentar esta fecha como inicio de efectos jurídicos ni etiquetar el documento como BOE. Un aviso explica que puede haber modificaciones posteriores.

Estas muestras están disponibles para lectura, sin generación automática de preguntas, huecos, tests ni referencias. Tanto el generador móvil como el backend respetan el bloqueo explícito de unidades pendientes de revisión. Las tarjetas preparadas del BOE siguen disponibles. No se declara realizada la revisión jurídica de todos los artículos europeos.

## Extracción y preparación del resto

Se recuperaron 56 HTML que excedían el límite del extractor anterior. Se decodifican incrementalmente, verificando el hash del original y del derivado antes de publicar su índice. No se duplica en memoria todo el texto como reserva. Los tests comprueban fragmentos de un byte, caracteres multibyte, texto fuera de etiquetas de párrafo y rechazo de un hash incorrecto.

La recuperación usa archivos temporales y mantiene los originales. Se conserva el límite de un GiB por fuente y de cuatro MiB por párrafo, en lugar de aceptar tamaños ilimitados. El índice de extracción quedó sin errores. Otros formatos, incluidos PDF y Formex, siguen diferidos: archivar esos archivos no equivale a extraer sus artículos.

La clasificación estructural vuelve a ejecutarse como proceso local incremental, con bloqueo de escritor, comprobación de hashes y conservación exacta de párrafos. Al alcanzar el final revisita filas omitidas que después hayan podido extraerse, aunque su rowid no haya cambiado. Las advertencias y los candidatos no se publican automáticamente como material de estudio. Algunos documentos históricos o de modificación necesitan reglas más precisas; archivos derivados muy grandes pueden seguir requiriendo otro tratamiento.

## Validación y alcance

Pasaron 190 pruebas del backend, 125 de Flutter y el analizador sin incidencias. Se verificaron la apertura offline de las tres muestras, las cantidades de artículos, la separación de considerandos y el bloqueo en los cuatro formatos de ejercicios. El APK de pruebas 0.7.2+12 se compiló en release y se comprobó contra el certificado de pruebas registrado para Google. Sigue pendiente la aceptación en un teléfono físico y la comprobación de Render Live.

Los informes en `validation/0.7.2` son resultados fechados o instantáneas de progreso. El corpus europeo completo todavía no está integrado en la aplicación ni tiene una revisión jurídica integral. La clasificación continúa en el entorno mientras este permanezca activo.
