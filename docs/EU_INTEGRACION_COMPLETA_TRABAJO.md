# Integración europea completa — trabajo activo

El titular ha autorizado incorporar **todo el corpus**, incluyendo fichas sin texto con su fuente, todas las ediciones y avisos; no quedarse en tres muestras. También están autorizados GitHub, APK y despliegues posibles dentro de las cuentas/planes existentes. No contratar servicios de pago. No afirmar revisión jurídica manual de 184.737 registros ni convertir contenido dudoso automáticamente en preguntas.

## Estado comprobado

- Archivo original: `/workspace/lexmemoria-eu-corpus`, 184.737 registros; 177.203 completos y 7.534 fichas sin archivo español anunciado. 280.961 archivos, integridad comprobada. Originales inmutables.
- Primera extracción: `/workspace/lexmemoria-eu-processed`, 135.806 HTML extraídos. Primera estructura `/workspace/lexmemoria-eu-structure-stream`, cinco fallos por tamaño recuperados con páginas. Incluye un caso con relleno NUL, eliminado de la copia de estudio con registro explícito; original conservado.
- Extracción corregida: `/workspace/lexmemoria-eu-leaf-processed`, proceso `app.eu_leaf_processing --watch`; tablas de maquetación ya no engullen párrafos. Ahora limpia NUL en el flujo y declara su recuento. Log `/workspace/lexmemoria-eu-leaf-processing.log`.
- Revisión de HTML: `/workspace/lexmemoria-eu-reviewed-structures`, proceso `app.eu_review_processing`. Reconoce ordinales/bis y separa PROYECTO posterior a firma como documento incorporado, no como artículos del acto principal. Todo sigue con legalReview not_performed/clientReady false.
- Otros formatos: `/workspace/lexmemoria-eu-other-processed`, `app.eu_other_processing --watch`; PDF con pdftotext, Formex/XML y ZIP. Distingue 103.400 imágenes como source_asset; 41.684 PDF, 30 XML, 37 ZIP, 4 Word. OCR español y los cuatro Word recuperados, junto con Formex grande. Tres PDF corruptos quedan sin texto recuperable; quince XML son índices de paquete. También se recuperó un CORR dentro de ZIP como corrección con texto, no como artículos. Log `/workspace/lexmemoria-eu-other-processing.log`.
- Revisión de otros formatos: `/workspace/lexmemoria-eu-other-structures`, `app.eu_review_processing --processed ...other-processed --output ...other-structures`.
- Títulos oficiales COMPLETOS: `/workspace/lexmemoria-eu-titles/titles.sqlite3`, tabla titles(work,celex,title JSON variantes,query_hash,observed_at), 184.737 filas. `scripts/fetch_eu_titles.py` usa POST oficial SPARQL en lotes 500, rate/backoff heredado, guarda respuestas y hashes en el archivo.
- Agrupación original/consolidaciones/correcciones implementada en el exportador. No confunde correcciones con ediciones completas ni transposiciones nacionales.

## Pendiente para completar el objetivo

1. Completar la segunda pasada y tratar OCR/Word/XML grandes, conservando originales y avisos sin fabricar texto.
2. Exportador reproducible de todo el catálogo y versiones, agrupadas por CELEX de acto base; correcciones relacionadas, ediciones futuras no elegidas como actuales. Títulos oficiales disponibles. No duplicar BOE por similitud: solo equivalencias identificadas.
3. Paquetes de lectura por páginas verificadas, sin cargar anexos gigantes ni todo el corpus al arrancar. Normas sin texto tendrán ficha y fuente, no artículos inventados. Fuentes de imágenes/documentos originales conservadas.
4. Biblioteca europea completa en Flutter con búsqueda, filtros, paginación fija y descarga/caché a demanda; lector de ediciones y páginas. Cliente 0.8.0 implementado con catálogo completo remoto, lector paginado, continuación, descarga por edición y mazos literales condicionados. La distribución pública completa aún espera al exportador y a su verificación independiente. Mantener progreso personal y excluir ejercicios inciertos.
5. Publicación de datos verificables en rama de contenido GitHub (se prevé `european-corpus-20261109`), código main y APK cuando las pruebas y los datos estén listos. Falta diseñar/exportar/publicar este conjunto; no afirmar que ya existe.

La cuenta Render no tiene credenciales de despliegue aquí y su host está bloqueado por el proxy; no se ha acreditado Live. El plan gratuito no debe ampliarse sin autorización. Los datos legales de responsable y soporte siguen pendientes por decisión del titular.

## Comprobaciones del 9 de noviembre

- Segunda pasada HTML y estructura: ambas alcanzan 280.961 fuentes, con 135.806 documentos de lectura y cero estructuras obsoletas.
- Segunda pasada PDF continúa en `app.eu_other_processing --pdf-only --watch`; el consumidor contrasta `source_output_hash` para reemplazar las estructuras que cambian, incluso si cambia el rowid de SQLite.
- Exportador `scripts/build_eu_full_library.py --wait` no activa el catálogo hasta finalizar ambas pasadas y sus consumidores.
- Publicador `scripts/publish_eu_full_library.py` exige informe de integridad independiente y hash del manifiesto; sube objetos en lotes y el manifiesto público al final.
- Backend: 209 pruebas pasadas. Cliente: 131 pruebas iniciales y tres pruebas de pantalla, incluida pantalla de 390 px con texto 1,4; suite final en ejecución. Analizador limpio antes de compilar.
- APK anterior público: 0.7.2; nuevo 0.8.0+13 todavía no publicado. No anunciar la nueva biblioteca como disponible antes de comprobar el manifiesto público.
