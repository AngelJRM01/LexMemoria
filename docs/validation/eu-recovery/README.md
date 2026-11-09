# Recuperación de incidencias europeas — 9 de noviembre de 2026

Los diez registros con error se recuperaron usando PDF alternativos anunciados en el catálogo oficial CDM. Se validó la cabecera/formato de cada respuesta, se archivó su hash y se registró el cambio de manifestación con los elementos anteriores y nuevos en la tabla de incidencias. No se borraron objetos originales.

`recovered-records.jsonl` recoge los diez resultados; `official-alternative-manifestations.jsonl` conserva las URLs y hashes de las consultas oficiales que anunciaban los formatos alternativos. Se pasó de 177.188 a 177.198 registros completos y de diez a cero errores. Esto no certifica extracción de artículos ni revisión jurídica de los PDF.

El recuento oficial de esta comprobación fue 184.737 frente a 184.732 registros locales. Se inició una nueva enumeración completa, reconsultando también las manifestaciones de los 7.534 registros sin archivo. Esa revisión y el control de integridad están en curso: este informe no afirma cobertura total ni integración en la aplicación. La preparación de estructuras continúa pausada por indicación del titular.

## Comprobaciones adicionales

Se verificaron 215.335 objetos y 280.956 referencias de archivo sin errores de integridad, en un punto de control anterior al final de la nueva enumeración. Una muestra independiente de 10.000 extracciones HTML también pasó las comprobaciones de hashes, procedencia y marcas de revisión pendiente. Los informes indican expresamente sus límites; no prueban revisión jurídica ni extracción de artículos.

La auditoría específica terminó sobre las 7.534 fichas que no tenían texto: 6.415 no anunciaban manifestación española y 1.119 tenían manifestación sin archivo asociado. Entre estas últimas, 1.117 anunciaban únicamente formato `print` y dos anunciaban `pdf`. Las dos referencias PDF (`01996X0746-20011105` y `01996X0746-20010226`) devolvieron 404 al solicitar PDF al identificador persistente del proveedor. Se conservan como incidencias de disponibilidad, sin declararlas recuperadas.

Esta es evidencia del catálogo CDM consultado, no una demostración de inexistencia mundial del texto ni de imposibilidad de obtenerlo por otra vía oficial. Los originales y el estado `metadata_only` se conservan. Los títulos en español no se convierten en supuestas traducciones del texto completo.

El script `scripts/audit_eu_metadata.py` usa consultas de 25 registros, guarda las respuestas oficiales en el archivo inmutable y conserva hashes y fecha por ficha en una base de auditoría separada. Reanuda las fichas no revisadas; para una auditoría nueva de disponibilidad debe utilizarse otra carpeta de salida. No publica en el móvil ni reactiva la preparación estructural pausada.
