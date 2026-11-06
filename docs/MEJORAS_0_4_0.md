# Navegación y ejercicios · 0.4.0+6

Las materias se obtienen del catálogo real. Criminología y otras categorías sin normas no se ofrecen en biblioteca, mazos preparados, bienvenida ni preferencias. Una preferencia anterior sin contenido no se borra del archivo del usuario.

Biblioteca y mazos preparados permiten combinar materia, ámbito y comunidad autónoma. Las 3.620 normas autonómicas se asignan a las 17 comunidades presentes en el catálogo; los nombres alternativos de Baleares y Comunidad Valenciana se unifican. Seleccionar una comunidad limita la consulta a su legislación autonómica, no a todas las leyes estatales aplicables en ese territorio.

La biblioteca, los mazos preparados, las tarjetas y el índice de artículos tienen paginación real: anterior, siguiente, salto numérico y 20/50/100 elementos por página. El índice empieza con 50; las otras listas, con 20. Cambiar búsqueda, filtros o tamaño vuelve al inicio. Los filtros permanecen accesibles y los controles de página quedan fuera de la lista desplazable. En pantallas de poca altura, la cabecera puede desplazarse para dejar espacio a los resultados.

## Ejercicios breves

Los nuevos huecos y test usan pasajes de hasta 320 caracteres Unicode. Completar huecos pide dos o tres términos o expresiones diferentes, con campos numerados y corrección por respuesta. La comparación ignora mayúsculas y espacios repetidos, conservando tildes y ñ. Los test preguntan por una expresión dentro de un contexto breve y presentan cuatro alternativas extraídas de la fuente. El reconocimiento de artículos también usa extractos breves. Las tarjetas de recuerdo mantienen el formato anterior.

Para renovar un mazo existente, hay que volver a preparar la misma norma y formato desde **Mazos preparados**. Las tarjetas generadas antiguas sin editar pasan a **Ejercicios anteriores**, donde se conserva su consulta e historial. Las tarjetas editadas, personales o vinculadas a sincronización no se retiran automáticamente. Se conservan los registros de repaso, favoritos y estados anteriores; los ejercicios nuevos comienzan con identificadores propios. Repetir la preparación no duplica tarjetas. Una sesión guardada solo se reinicia si incluía tarjetas retiradas.

La auditoría completa de 12.451 normas comprueba 8.386.362 ejercicios: 684.375 de recuerdo, 2.747.278 de huecos, 2.827.050 test y 2.127.659 de reconocimiento. Verifica citas, pertenencia de respuestas al texto fuente, límites de longitud e identificadores. No equivale a revisión jurídica humana ni certifica preguntas oficiales de examen. [Informe técnico](validation/boe-exercises-0.4.0.json).

## Guardado y compatibilidad

El almacén SQLCipher pasa a esquema 2 conservando archivo y clave. Guarda el estado en bloques pequeños dentro de una transacción, para evitar el límite de fila del cursor de Android con mazos grandes. La lectura del esquema antiguo también usa fragmentos; una escritura fallida revierte la transacción y conserva el estado anterior. No se borran los datos ni se cambia a almacenamiento sin cifrar.

## Validación

- 63 pruebas Flutter correctas, incluidas paginación, salto numérico, filtros reales, generación y respuesta de huecos, renovación sin perder ediciones ni historial y fragmentación Unicode de estados grandes.
- Análisis Flutter sin incidencias. Compilación web JavaScript release correcta.
- APK Android release compilado, firma verificada, sin `application-debuggable` y con catálogo empaquetado cotejado por SHA-256. [Datos del APK](validation/android-0.4.0.json).
- Auditoría técnica completa de todos los formatos sobre las 12.451 normas del catálogo.
- Se añaden pruebas nativas de migración de un estado cifrado de más de 3 MB, reapertura y reversión ante fallo. Están configuradas para Android 15 en GitHub Actions; no se han ejecutado en este entorno ni en un OPPO físico.

Las descargas europeas siguen en su proceso supervisado independiente, con checkpoints. Todavía no están completas y no se presentan como contenido europeo integrado en la app.
