# LexMemoria 0.7.1 — contraste oficial y segunda revisión

Esta entrega distingue tres tareas: contrastar el inventario y el texto con el BOE, revisar casos jurídicos concretos y comprobar automáticamente los ejercicios. Ninguna de ellas se presenta como lectura jurídica manual de todas las leyes ni como garantía de ausencia total de errores.

## Contraste en internet

Se ha consultado el inventario oficial completo y los textos completos de las 20 leyes incluidas en el APK. Tras recuperar el entorno se ha repetido la consulta con respuestas nuevas, no solo con la caché anterior. Las 20 respuestas de texto coinciden exactamente con sus hashes archivados.

El inventario observado el 7 de noviembre contiene **12.457 normas**: seis identificadores nuevos respecto a la copia de 12.451. Se detectaron 31 registros con actualización: doce tienen cambios en cuerpos de bloques y diecinueve no presentan cambios de ese contenido. Los cambios meramente informativos no se confunden con una modificación jurídica.

Se conserva el archivo anterior. La nueva copia fechada está en `/workspace/lexmemoria-corpus-20261107`, con respuestas, versiones y hashes; solo se descargaron los 37 registros nuevos o actualizados. Los bloques idénticos conservan su identidad educativa para evitar invalidar el estudio por un cambio de metadatos. El nuevo catálogo se publica en una rama fechada diferente para conservar los enlaces y hashes de la versión anterior.

## Casos leídos en fuentes oficiales

1. **Código Civil, artículo 92.8 y STC 185/2012.** El fallo anuló el inciso «favorable» en la redacción de 2005. El texto actual consultado dice «con informe del Ministerio Fiscal». No se debe reintroducir el requisito anulado al copiar una redacción anterior; tampoco se deduce que todo el artículo sea nulo. [Sentencia](https://www.boe.es/diario_boe/txt.php?id=BOE-A-2012-14060) y [Código Civil](https://www.boe.es/buscar/act.php?id=BOE-A-1889-4763).
2. **LEC, artículos 34 y 35 y STC 34/2019.** El fallo se refiere a determinados párrafos e incisos de la redacción de 2009. El BOE incluye redacciones anteriores dentro de bloques editoriales. El extractor anterior podía conservar parte de esa cita histórica después de retirar únicamente el párrafo de nota: ahora se separa el bloque editorial completo, manteniendo las citas normativas auténticas. [Sentencia](https://www.boe.es/diario_boe/txt.php?id=BOE-A-2019-5727) y [LEC](https://www.boe.es/buscar/act.php?id=BOE-A-2000-323).
3. **Código Penal, artículo 92 y STC 169/2021.** Se han leído el fallo y el fundamento 9, incluida su parte b). El fallo exige interpretar el artículo 92.3, párrafo tercero, y el 92.4 conforme a ese fundamento. Una tarjeta no debe presentar la regla aisladamente ni confundir el fallo con los votos particulares que también aparecen publicados. [Sentencia](https://www.boe.es/diario_boe/txt.php?id=BOE-A-2021-18372) y [Código Penal](https://www.boe.es/buscar/act.php?id=BOE-A-1995-25444).

Estos ejemplos documentan la revisión de problemas concretos; no extienden una conclusión jurídica a todos los artículos del corpus.

## Tratamiento de notas y advertencias

El cuerpo actual se separa de los contenedores editoriales que contienen notas y redacciones anteriores. Se conserva su texto en un apartado desplegable del lector. Las citas normativas que forman parte auténtica del artículo permanecen en el cuerpo. El editor de tarjetas personales usa también esa extracción, evitando copiar inadvertidamente textos históricos.

Se señalan preventivamente **4.179 artículos** con notas judiciales o de aplicación que requieren comprobar su alcance. No se declaran inválidos: algunas notas afectan a redacciones anteriores o contienen una interpretación conforme. Se mantienen disponibles para lectura y se excluyen de la generación automática mientras no se resuelva ese contexto.

Las tarjetas automáticas no editadas vinculadas a esos artículos muestran una revisión pendiente. También se detectan fuentes publicadas más recientes que una copia local; una copia local realmente más reciente no se degrada por usar un catálogo anterior. No se borra el texto personal ni su historial. Estas medidas no certifican las tarjetas editadas por personas: conservan su carácter personal y su trazabilidad.

## Optimización adicional

- El guardado atómico conserva las colecciones que no cambiaron, después de verificar la escritura y los conflictos. Cambiar un ajuste ya no obliga a reconstruir todas las tarjetas y sus índices de búsqueda.
- La huella de sincronización reutiliza las secciones codificadas que no cambiaron, manteniendo exactamente el formato y digest anterior. Una modificación real del progreso o un guardado heredado invalida las cachés correspondientes.
- La siguiente sesión se selecciona mediante una cola acotada, manteniendo el orden por vencimiento, fallos y preferencias, sin ordenar toda la colección.
- Las tarjetas nuevas sin fecha de repaso no provocan miles de excepciones de análisis de fecha.

Las mediciones comparan el mismo código de prueba y los mismos datos con 0.7.0, en una copia aislada. Son pruebas de host Flutter, no mediciones del OPPO físico ni garantía del mínimo teórico de carga. Los datos y resultados completos se guardan en `validation/0.7.1/performance.json`.

## Límites y publicación

El tiempo de arranque de un servidor Render gratuito dormido depende del proveedor y no se presenta como resuelto por las cachés de la aplicación. El acceso de comprobación a Render sigue sujeto a la configuración de red del entorno y al acceso al servicio del titular.

La revisión jurídica integral, la aceptación en un teléfono físico y los proveedores pendientes no se sustituyen por los validadores automáticos. Los datos legales del responsable continúan pendientes por decisión del titular. Las descargas europeas se mantienen como proceso separado y reanudable; no se contabilizan como corpus BOE ni como contenido integrado automáticamente en la aplicación.

## Validación de esta entrega

Han pasado 177 pruebas del backend y 123 pruebas Flutter, sin incidencias del analizador. La verificación completa contrasta 695.727 versiones de bloques con los originales y valida los cuatro formatos generados en las 12.457 normas. Es una comprobación técnica, no una certificación jurídica.

Con 20.000 tarjetas, veinte consultas de la huella pasan de 3.091,16 ms a 163,31 ms; diez selecciones de sesión, de 1.949,91 ms a 46,10 ms. Ambos códigos producen el mismo digest.

El APK es una compilación release de pruebas 0.7.1+11 con el certificado de pruebas registrado en Firebase. Ese certificado no sustituye la firma de producción de Google Play.
