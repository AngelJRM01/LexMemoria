# LexMemoria 0.8.0 — biblioteca europea completa

## Funciones implementadas

La entrada «Biblioteca europea completa» consulta el catálogo público separado del BOE. Agrupa el acto original, sus consolidaciones y correcciones mediante CELEX y la relación oficial CDM `act_consolidated_based_on_resource_legal`, contrastada para las 28.905 consolidaciones; conserva todas las ediciones y sus referencias originales. Las correcciones se identifican como documentos relacionados, sin sustituir silenciosamente el acto. Las consolidaciones con fecha futura no se seleccionan por defecto. La fecha de edición no acredita vigencia ni aplicabilidad jurídica.

La búsqueda consulta títulos oficiales y CELEX; incluye filtros de tipo, año, texto disponible y referencias guardadas. Resultados con paginación 20/50/100 y filtros fijos cuando cabe la pantalla. El índice completo se descarga al entrar en esta biblioteca, fuera del arranque general y en un isolate. Se reutiliza entre aperturas durante la sesión y se invalida por hash, evitando repetir la descompresión. El texto solo se descarga al solicitar una norma y sus páginas; los anexos de millones de párrafos no se descomprimen enteros para abrirlos.

Cada norma permite elegir la edición, consultar los archivos originales, guardar una referencia, descargar los textos para leer sin conexión y continuar la lectura. El lector separa artículos, preámbulo, considerandos, anexos y otros apartados; pagina los fragmentos y guarda la posición por edición y hash. Las descargas verifican SHA-256 y tamaños. Al cambiar de edición se archiva cualquier paquete anterior y se mantienen las tarjetas, notas y repasos personales.

Los textos sin encabezados de artículos reconocibles se conservan en apartados separados. Las fichas sin texto recuperable mantienen sus enlaces oficiales. Las imágenes son recursos de la fuente, no artículos. PDF digital une líneas de un mismo párrafo; OCR español, Word y Formex conservan procedencia y advertencias. Los tres PDF corruptos están identificados en el informe de excepciones y mantienen su ficha y referencia, sin reemplazar una edición por otra.

Las familias de catálogo distinguen tratados, acuerdos internacionales, documentos institucionales y anuncios. La familia internacional incluye también actos de órganos previstos por acuerdos; el título oficial conserva la forma concreta del documento. Los anuncios administrativos no generan ejercicios.

## Estudio literal y límites

La acción de preparar mazos ofrece pregunta/respuesta, huecos, test literal e identificación de artículos cuando el texto reúne los controles técnicos. Reutiliza el generador existente, fragmenta el artículo y conserva edición y hash. Solo considera artículos HTML de extracción corregida, sin advertencias estructurales ni numeraciones repetidas. Excluye anexos, correcciones, OCR, PDF y actos cuyo propósito principal es modificar o derogar otro acto. La interfaz permite elegir el formato disponible y añadir el mazo sin duplicar tarjetas existentes.

La selección de términos reconoce conceptos e instituciones europeas, plazos como «un mes», porcentajes y cantidades completas como «20 000 000 EUR». Los huecos exigen dos o tres expresiones relevantes por fragmento, no una palabra arbitraria de un artículo largo. En el RGPD original, la prueba real produjo 169 tarjetas de huecos y 498 tests literales, además de 796 de pregunta/respuesta y 696 de identificar artículos; son resultados automáticos, no certificaciones editoriales.

Estos controles no equivalen a una revisión jurídica manual. Las extracciones y los ejercicios literales muestran su carácter automático; no se anuncian como banco editorial certificado ni examen oficial. El archivo original permanece intacto. No se atribuye vigencia a todos los registros ni se deduplican actos europeos contra transposiciones nacionales por simple semejanza.

## Distribución y verificaciones

El inventario observado contiene 184.737 registros de los sectores CELEX 0 y 3 con expresión española, agrupados en 149.352 actos con todas sus ediciones. No equivale a todos los sectores de EUR-Lex ni a una certificación de vigencia.

El exportador espera a que todos los procesadores alcancen el archivo y sus estructuras coincidan con los hashes de entrada. Después exporta objetos comprimidos y páginas acotadas; un verificador independiente recorre todas las ediciones, recursos y párrafos. La publicación sube los objetos en lotes y activa el manifiesto raíz al final, evitando anunciar referencias todavía inexistentes.

El verificador independiente ha comprobado 184.737 registros, 280.961 referencias de fuente, 525.359 objetos y 128.675.562 párrafos, agrupados en 149.352 actos. Los 1.013.421 candidatos a artículos son una clasificación técnica, no un banco certificado. Los contadores, hashes y enlaces definitivos figuran en los informes de validación y en el README de esta versión. El código de compilación comprueba la firma Android registrada para Google.

Pasaron 214 pruebas del backend y 136 de Flutter, incluida la integración con el catálogo real completo; analizador limpio, web y APK release compilados. Se comprobó en un emulador Android 15 el acceso local, la navegación, lectura offline de la Constitución y recuperación del perfil al reiniciar. El informe identifica el APK usado en esa prueba nativa, anterior a las últimas mejoras puras de Dart, y las pruebas separadas de la versión final. No se usa un emulador sin aceleración para prometer tiempos en un teléfono real.

Siguen pendientes la aceptación en el móvil físico del titular, confirmar Render Live desde su cuenta, identidad pública/correo de privacidad y los trámites de tiendas. Esta versión no activa Apple, compras reales ni servicios de pago.
