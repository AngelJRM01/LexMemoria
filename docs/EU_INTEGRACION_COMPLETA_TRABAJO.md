# Integración europea completa — estado del 9 de noviembre de 2026

Se ha implementado la incorporación de todo el inventario europeo archivado, con sus ediciones, correcciones, fichas sin texto y referencias originales. Datos y APK publicados; manifiesto, índice y muestras de lectura descargados desde GitHub con hashes comprobados. La descarga completa del APK también coincide con el SHA-256 del binario compilado. Los informes de descarga pública y resumen de versión contienen los commits y verificaciones.

## Datos y verificación

- Inventario: 184.737 registros de los sectores CELEX 0 y 3 con expresión española, agrupados en 149.352 actos/documentos. Se conservan 280.961 referencias de archivos originales; no se borraron ni modificaron sus bytes.
- Lectura: 177.200 ediciones con texto recuperado, distribuidas en 177.543 documentos de lectura y 128.675.562 párrafos. Las demás ediciones mantienen su ficha y fuente. Tres PDF originales no permiten recuperar un documento fiable; quince XML son índices de paquetes, cuyo texto procede de otros recursos del registro.
- Las 28.905 consolidaciones tienen relación oficial de acto base contrastada con CDM. Se corrigieron las agrupaciones de tratados, acuerdos, actos complementarios, documentos institucionales y un anuncio del Diario Oficial; no se fabrica un identificador del sector 3.
- Las correcciones se muestran como documentos relacionados, sin sustituir silenciosamente el acto. No se seleccionan ediciones futuras por defecto ni se certifica vigencia.
- Se verifican todos los objetos comprimidos, tamaños, cobertura de registros, orden/rangos de párrafos y pertenencia a unidades y ediciones. También se comprueba cada relación de acto base contra la evidencia oficial.

## Aplicación 0.8.0+13

Biblioteca europea completa con búsqueda por título y CELEX, filtros por familia/año/texto/referencias guardadas y paginación 20/50/100. El índice se carga fuera del arranque y se reutiliza entre aperturas por hash. Los textos se abren por páginas, incluidos los anexos gigantes. Hay selector de edición, recursos originales, descarga para lectura offline con contador de avance, referencias guardadas y continuación de lectura.

La preparación de mazos ofrece QA, huecos, test literal e identificación de artículos cuando pasan los controles. Excluye contenido no articulado, numeraciones ambiguas, anexos, anuncios, OCR/PDF y documentos cuyo propósito principal es reformar otro acto. Los huecos seleccionan dos o tres expresiones jurídicas/plazos/importes completos en fragmentos breves. Los cambios de edición conservan versiones anteriores y los datos personales.

La clasificación y generación son automáticas. `legalReview: not_performed` continúa siendo correcto; los candidatos a artículos no son un banco editorial certificado.

## Validación y límites externos

214 pruebas del backend y 136 de Flutter pasadas, incluida la carga del catálogo real, los 99 artículos originales del RGPD, sus cuatro formatos de mazo, los tratados y la exclusión de anuncios. Analizador limpio y compilaciones web/Android release completadas. Se comprobó inicio, lectura offline y recuperación del perfil en Android 15 emulado; el informe identifica el candidato nativo probado y su alcance. No se afirma rendimiento de un teléfono físico a partir de un emulador sin KVM.

Siguen pendientes la aceptación en el OPPO del titular y el acceso Google/sincronización real. Render no tiene credenciales de despliegue disponibles en este entorno y su dominio está bloqueado por la política de red; no se acredita Live desde aquí. Responsable/correo de privacidad permanecen pendientes por decisión del titular. No se contrataron planes ni se publicó en tiendas.

## Reproducción

- Originales: `/workspace/lexmemoria-eu-corpus`.
- HTML corregido/estructura: `/workspace/lexmemoria-eu-leaf-processed`, `/workspace/lexmemoria-eu-reviewed-structures`.
- PDF, OCR, Word y Formex: `/workspace/lexmemoria-eu-other-processed`, `/workspace/lexmemoria-eu-other-structures`.
- Títulos y relaciones: `/workspace/lexmemoria-eu-titles`, `/workspace/lexmemoria-eu-parents`.
- Exportación: `/workspace/lexmemoria-eu-full-distribution`, revisión `eu-full-reviewed-4`. El fingerprint impide reanudar un índice con fuentes diferentes; se conservan índices anteriores como derivados históricos.
- `scripts/fetch_eu_consolidation_parents.py`, `build_eu_full_library.py`, `verify_eu_full_library.py` y `publish_eu_full_library.py` implementan consulta oficial, exportación, validación independiente y publicación con manifiesto al final.
- Rama de datos publicada: `european-corpus-20261109`; APK configurado: `android-google-preview-0.8.0`. Los informes de publicación y descarga documentan la comprobación final, no el mero nombre de rama.
