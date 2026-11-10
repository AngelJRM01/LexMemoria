# LexMemoria 0.8.1 — revisión de ejercicios y especificación de publicación

## Correcciones

Se revisaron muestras reales contra fuentes oficiales y se ajustó el generador para rechazar títulos, introducciones y listas incompletas. Las frases largas completas y las definiciones admisibles tienen tarjetas de recuerdo de hasta 1.200 caracteres; los otros formatos mantienen 320. Las definiciones numeradas no se cortan en un punto y coma. Se mantiene la numeración de los fragmentos anteriores para conservar los identificadores de las tarjetas que siguen siendo válidas.

Los tests separan categorías de datos, sujetos, derechos y unidades temporales. Los conceptos genéricos sin distractores suficientemente precisos no se convierten en tests. La generación conserva la fuente y no inventa alternativas para alcanzar un número de tarjetas.

Al arrancar se archivan las preguntas locales reconocibles e incompletas de recuerdo automático, manteniendo estados y repasos. Las tarjetas editadas y copias sincronizadas quedan preservadas. Al volver a preparar una norma se retiran las plantillas antiguas identificadas y se pueden actualizar opciones de tarjetas locales sin cambios personales, conservando identidad y progreso. No se realiza una sustitución universal de todo material privado ni una certificación de sus respuestas.

Los veinte bancos incluidos se regeneran con 26.922 tarjetas de recuerdo. Los textos originales, sus versiones y los 12.457 paquetes BOE no cambian: la comprobación de hashes queda en el informe de integridad. Las correcciones afectan al material derivado, no reescriben las leyes.

La comprobación de definiciones reutiliza el análisis del último artículo, sin acumular libros en memoria. Una comparación sobre BOE-A-2023-11022 conserva idénticas las salidas de los cuatro formatos; la generación QA pasó de 332,2 a 203,3 ms en el host bajo carga concurrente. No es una medición del OPPO.

## Revisión y alcance

El contraste online del 9 de noviembre comprueba el inventario BOE, las veinte leyes principales y los veintidós registros con metadatos más recientes. No se detectaron cambios del cuerpo, notas o historial en estos últimos. Tres fuentes europeas coinciden con el archivo. La lectura manual continuó el 10 de noviembre hasta diecinueve artículos completos y muestras de los cuatro formatos. Es una revisión de casos, no la lectura de todos los artículos de la biblioteca.

Los informes de `validation/content-review-2026-11-09` separan diario manual, contraste de fuentes, integridad de paquetes y auditorías automáticas. El ledger mantiene las normas completas pendientes de lectura manual. La aceptación física, Google real, Render Live y publicación en tiendas siguen abiertas.

## Documento para decidir la V1

La [especificación de 10 de noviembre](ESPECIFICACION_Y_PUBLICACION_2026-11-10.md), en Word y PDF, inventaría funciones actuales y límites, propone alcance Android gratuito y detalla doce cierres con responsables y criterios de aceptación. Incluye la caducidad de PostgreSQL comunicada, firma de Play, privacidad, soporte, pruebas de dispositivos y moderación. Apple, push y pagos pueden aplazarse sin anunciarse como disponibles.

El anexo técnico enumera las rutas y componentes presentes en el código. Su existencia no se contabiliza como aceptación en producción. Los informes históricos se conservan sin alterar sus fechas ni sustituir sus resultados por inferencias.

## Verificación final

Pasaron 215 pruebas backend, 140 Flutter con integración europea real, análisis sin incidencias y builds Android release/web. La auditoría BOE cubre las 12.457 normas y valida 1.427.352 QA, 31.087 huecos, 79.344 tests y 1.223.774 referencias. La europea recorre los 149.352 actos y valida las ediciones técnicamente admitidas: 2.171.522 QA, 116.045 huecos, 87.363 tests y 1.659.666 referencias. Los contadores no son revisión jurídica ni precarga universal de tarjetas.

El APK de pruebas 0.8.1+14 conserva el certificado registrado para Google, no tiene modo debug y su descarga pública completa coincide con SHA-256 f3058cf6db2219e57d9018949e59379d5dd4d3b51afd0974de87b93d952e0f77. No acredita Google en teléfono físico, Render Live ni publicación en tiendas.
