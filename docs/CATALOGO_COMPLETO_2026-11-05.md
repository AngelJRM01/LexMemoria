# Catálogo y mazos de estudio 0.3.0

La aplicación incorpora el índice de las **12.451 normas del catálogo consolidado observado del BOE el 5 de noviembre de 2026**: 8.831 estatales y 3.620 autonómicas. No es un inventario universal de legislación española, europea, local ni histórica. La fuente puede incluir normas con vigencia agotada; la interfaz las distingue como históricas según ese metadato, sin emitir una certificación de vigencia.

## Uso

Biblioteca y Mazos preparados permiten buscar y filtrar el catálogo completo. Las listas se construyen por demanda y mantienen los controles visibles cuando hay espacio. Los nombres breves conservan el título oficial completo en el detalle.

Cada norma ofrece recuerdo literal, huecos, test de expresión literal y reconocimiento de artículos. La división de párrafos largos recorre el texto una sola vez y respeta caracteres Unicode completos. Los ejercicios se preparan automáticamente desde los textos citados; el usuario puede modificarlos después. Un nombre de mazo personalizado permite reunir varias normas y formatos en un tema. Instalar de nuevo la misma selección conserva tarjetas, modificaciones y progreso existentes.

Hay **684.375 fragmentos base de recuerdo literal**. Los demás formatos omiten fragmentos sin palabras adecuadas, sin suficientes alternativas o con respuestas ambiguas. No son preguntas oficiales, explicaciones jurídicas ni casos revisados por profesionales. Cada tarjeta conserva norma, bloque, versión y hash de la fuente.

Las veinte normas iniciales y sus 13.914 tarjetas de recuerdo siguen incluidas en el APK para comenzar sin red. El resto se descarga por norma desde la [rama pública de contenido](https://github.com/AngelJRM01/LexMemoria/tree/legal-corpus-20261105). No requiere cuenta ni servidor privado. El catálogo comprimido ocupa aproximadamente 1,9 MB; los paquetes suman 483.159.512 bytes, con un máximo individual de 8.132.143 bytes comprimidos.

En Android/iOS los paquetes se guardan en archivos de soporte de la aplicación, separados del progreso cifrado. Se comprueban tamaño, SHA-256, esquema e identidad antes de utilizarlos. Un máximo de cuatro normas permanece decodificado en memoria; las restantes se vuelven a abrir desde sus archivos. En web esta caché dura la sesión. La copia JSON del progreso no incluye los textos públicos y estos pueden descargarse otra vez.

## Verificación

Se cotejaron los 12.451 paquetes con el archivo oficial descargado, incluidos **695.207 versiones de bloques**, XML, texto derivado, fechas y hashes. Las primeras veinte normas conservan sus identificadores y versiones originales; sus textos y fechas se compararon con el archivo más reciente sin diferencias jurídicas de contenido detectadas por esa comparación técnica.

Los informes completos están en `verification.json` y `exercises-verification.json` de la rama de contenido. La comprobación técnica no sustituye una revisión jurídica humana. El archivo bruto de descarga conserva además las respuestas originales; los paquetes de distribución no pretenden ser dichas respuestas originales.

Validación local de esta entrega: 49 pruebas Flutter, 72 pruebas backend y análisis Flutter sin incidencias. El APK es release de prueba, con firma de pruebas; iOS y el workflow remoto no se consideran validados por estas pruebas locales.

## Operación

```bash
python scripts/build_corpus_distribution.py --help
# En el entorno donde existe el archivo y la distribución:
python scripts/verify_corpus_distribution.py
python scripts/audit_prepared_corpus.py /workspace/lexmemoria-distribution --jobs 4
# Alternativa en un solo proceso:
cd mobile
dart --packages=.dart_tool/package_config.json tool/audit_prepared_corpus.dart /workspace/lexmemoria-distribution
```

El backend puede importar los mismos paquetes, manteniendo las versiones de las citas y los datos privados:

```bash
cd backend
python -m app.cli import-distribution /workspace/lexmemoria-distribution --limit 20
```

La importación rechaza cambios de contenido en una versión inmutable y bloquea las tarjetas de versiones anteriores cuando cambia la norma. La instalación en el móvil no necesita ejecutar esa importación.

## Alcance pendiente

La descarga de documentos europeos continúa con checkpoints y no se anuncia como completa ni integrada en el catálogo móvil. Los boletines adicionales conservan una recopilación inicial de documentos, no sus archivos históricos completos. Las cuentas de producción siguen necesitando desplegar el backend HTTPS y configurar los proveedores; esta entrega no activa Google/Apple, push, compras ni publicación en tiendas. Véase [el estado pendiente](PENDIENTES.md).

Fuente: Agencia Estatal Boletín Oficial del Estado. Se conservan enlaces oficiales y atribución de reutilización en los paquetes.
