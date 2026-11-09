# Recuperación de incidencias europeas — 9 de noviembre de 2026

Los diez registros con error se recuperaron usando PDF alternativos anunciados en el catálogo oficial CDM. Se validó la cabecera/formato de cada respuesta, se archivó su hash y se registró el cambio de manifestación con los elementos anteriores y nuevos en la tabla de incidencias. No se borraron objetos originales.

`recovered-records.jsonl` recoge los diez resultados; `official-alternative-manifestations.jsonl` conserva las URLs y hashes de las consultas oficiales que anunciaban los formatos alternativos. Se pasó de 177.188 a 177.198 registros completos y de diez a cero errores. Esto no certifica extracción de artículos ni revisión jurídica de los PDF.

El recuento oficial de esta comprobación fue 184.737 frente a 184.732 registros locales. Se inició una nueva enumeración completa, reconsultando también las manifestaciones de los 7.534 registros sin archivo. Esa revisión y el control de integridad están en curso: este informe no afirma cobertura total ni integración en la aplicación. La preparación de estructuras continúa pausada por indicación del titular.

## Comprobaciones adicionales

Se verificaron 215.335 objetos y 280.956 referencias de archivo sin errores de integridad, en un punto de control anterior al final de la nueva enumeración. Una muestra independiente de 10.000 extracciones HTML también pasó las comprobaciones de hashes, procedencia y marcas de revisión pendiente. Los informes indican expresamente sus límites; no prueban revisión jurídica ni extracción de artículos.

La auditoría específica terminó sobre las 7.534 fichas que no tenían texto: 6.415 no anunciaban manifestación española y 1.119 tenían manifestación sin archivo asociado. Entre estas últimas, 1.117 anunciaban únicamente formato `print` y dos anunciaban `pdf`. Las dos referencias PDF (`01996X0746-20011105` y `01996X0746-20010226`) devolvieron 404 al solicitar PDF al identificador persistente del proveedor. Se conservan como incidencias de disponibilidad, sin declararlas recuperadas.

Esta es evidencia del catálogo CDM consultado, no una demostración de inexistencia mundial del texto ni de imposibilidad de obtenerlo por otra vía oficial. Los originales y el estado `metadata_only` se conservan. Los títulos en español no se convierten en supuestas traducciones del texto completo.

El script `scripts/audit_eu_metadata.py` usa consultas de 25 registros, guarda las respuestas oficiales en el archivo inmutable y conserva hashes y fecha por ficha en una base de auditoría separada. Reanuda las fichas no revisadas; para una auditoría nueva de disponibilidad debe utilizarse otra carpeta de salida. No publica en el móvil ni reactiva la preparación estructural pausada.

La consulta directa de EUR-Lex para esas dos referencias tampoco entregó PDF: devolvió estado 202 y cuerpo vacío. No se ha intentado eludir restricciones del proveedor ni se han incorporado esas respuestas como textos. Los resultados de ambas vías están en `pdf-reference-probes.jsonl` y `eurlex-pdf-probes.jsonl`.

Las 7.534 evidencias por ficha se contrastaron con 302 respuestas oficiales archivadas, verificando hashes y coincidencia exacta de los registros. No hubo identificadores de obra duplicados en esa auditoría.

Los 55 fallos del extractor HTML son `source_size_limit`: los originales están archivados, con tamaños de 131 a 464 MiB, y su extracción sigue pendiente. No se confunden con los diez fallos de descarga ya recuperados ni con pérdida de archivos.

## Cierre del cotejo y del archivo disponible

El 9 de noviembre terminó la enumeración completa y el recuento oficial y local coincidieron en **184.737 registros**. Los cinco nuevos registros se descargaron: `02025R0666-20250407`, `32026D05944`, `32026R2409`, `32026H05593` y `02016R2070-20260901`.

Resultado: **177.203 registros completos**, **280.961 archivos referenciados**, **7.534 registros solo con metadatos**, cero pendientes y cero errores de descarga. La comprobación final pasó sin errores y el supervisor quedó en `watching_source`, con revisión periódica de la fuente. Los tres informes `final-*.json` conservan el estado y alcance exactos.

`all_available_records_archived: true` significa cobertura del inventario y los archivos anunciados para el alcance CDM seleccionado; `all_texts_archived: false` sigue siendo correcto por las fichas sin texto. No implica obtención de todos los textos por cualquier vía de internet. El archivo de originales está comprobado; la extracción de formatos diferidos y la integración en la aplicación siguen siendo etapas distintas. Los 55 HTML que superan el límite del extractor permanecen pendientes de procesamiento y la preparación estructural continúa pausada.
