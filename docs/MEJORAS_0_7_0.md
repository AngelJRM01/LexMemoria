# LexMemoria 0.7.0 — artículos, ejercicios y rendimiento

Trabajo sobre las 12.451 normas BOE consolidadas archivadas. No se han borrado XML originales, versiones, citas ni hashes oficiales. La revisión del corpus es automática y estructural; no se presenta como revisión jurídica o pedagógica manual de cada ejercicio.

## Lectura y clasificación

El índice abre exclusivamente artículos. Los títulos, libros y capítulos funcionan como separadores de contexto, sin flecha ni tratamiento de artículo. Preámbulo, disposiciones y anexos tienen un acceso independiente en «Partes de la norma». Las firmas y notas iniciales no se ofrecen como artículos. Las normas sin artículos no reciben ejercicios ficticios por usar un fallback genérico.

Las notas editoriales `nota_pie`, incluidas anotaciones «Se modifica…», se extraen del cuerpo usado para leer, escuchar y practicar. Su XML y su texto original se conservan; la comparación histórica y el enlace oficial siguen disponibles. No se elimina una disposición transitoria, derogatoria o final por considerarla innecesaria: se separa de la lista de artículos.

La auditoría verifica todos los hashes de paquetes y clasifica 337.812 artículos, 103.331 encabezados, 88.362 disposiciones, 12.107 preámbulos, 12.480 firmas, 4.661 notas iniciales y otros bloques. El detalle por norma está en `validation/boe-structure-0.7.0.json`.

## Calidad de ejercicios

- **Recuerdo literal:** fragmentos completos de hasta 320 caracteres. La pregunta proporciona el comienzo exacto de la regla y el artículo como pista; la respuesta conserva el fragmento literal. No se pide recitar un artículo enorme mediante una pregunta genérica.
- **Huecos:** dos o tres objetivos reconocidos —conceptos jurídicos, instituciones, plazos o importes— con límites de longitud y cobertura. Se elimina la selección de palabras por su longitud. Si no hay objetivos suficientes, no se fabrica la tarjeta.
- **Test literal:** cuatro opciones distintas y una solución cotejada con la fuente. Las alternativas pertenecen a la misma categoría semántica y no aparecen ya en el fragmento mostrado. Sin tres alternativas válidas, se omite el test.
- **Reconocimiento de artículos:** cuatro referencias distintas y solo una contiene el fragmento entre las opciones. Se comprueban títulos repetidos y ambigüedad de citas.
- No se corta una frase larga a mitad para inventar una regla. Los fragmentos que no permiten un ejercicio seguro se omiten. La cantidad es una consecuencia de las reglas de calidad.

Los 20 mazos incluidos se regeneran con **35.903** tarjetas breves de recuerdo. La validación de todos los formatos en el corpus produjo:

| Formato | Ejercicios comprobados |
| --- | ---: |
| Recuerdo literal | 2.000.386 |
| Huecos | 27.152 |
| Test literal | 178.696 |
| Reconocimiento de artículos | 1.798.560 |

Estos números representan ejercicios derivables y comprobados automáticamente, no tarjetas descargadas de antemano ni revisión humana individual. El informe completo está en `validation/0.7.0/corpus-exercises.json`; cubre las 12.451 normas y está ligado al hash del catálogo.

La versión del generador cambia a v3 para no reemplazar silenciosamente contenido editado con los mismos IDs. Al renovar un mazo se archivan ejercicios automáticos antiguos reconocibles y no sincronizados; se conservan las ediciones personales, los estados y el historial. No se eliminan copias remotas ya sincronizadas por una limpieza local. Las tarjetas antiguas de una instalación existente se renuevan al preparar de nuevo el formato correspondiente; instalar el APK no reescribe de golpe todos los mazos personales.

## Rendimiento

Se elimina la descompresión de hasta cuatro normas guardadas antes de mostrar Inicio. Los paquetes se abren bajo demanda. El catálogo combinado y las tarjetas se reutilizan entre lecturas, con invalidación al cambiar los datos o paquetes. La búsqueda evita normalizar miles de textos cuando la consulta está vacía y reutiliza el índice normalizado al escribir. El índice de una norma conserva también sus filas y contexto entre reconstrucciones de pantalla.

Comparación con el commit `73f6fe8`, ejecutando el mismo escenario en copias aisladas del código:

| Escenario | Antes | Después |
| --- | ---: | ---: |
| 100 accesos al catálogo de 12.451 normas | 6.858 ms | 29 ms |
| 20 accesos a 20.000 tarjetas | 1.401 ms | 147 ms |
| Reapertura con cuatro normas guardadas y 20.000 tarjetas | 1.718 ms | 891 ms |
| Normas descomprimidas antes de Inicio | 4 | 0 |

Son mediciones del ejecutor de pruebas Flutter, bajo carga concurrente de validadores. No son una prueba de fluidez en un OPPO físico ni una garantía sobre una red móvil. El arranque sin normas guardadas no mostró una mejora significativa en ese escenario. Se conservan las mediciones completas en `validation/0.7.0/performance.json`.

El plan gratuito de Render puede añadir espera al iniciar una instancia dormida. Este trabajo no cambia de plan, no crea servicios de pago ni presenta ese tiempo del proveedor como resuelto mediante la caché local.

## Verificación y entrega

- 176 pruebas del servidor y 114 de Flutter pasan.
- Análisis Flutter sin incidencias.
- Corpus completo: hashes, clasificación, citas, respuestas, huecos, opciones y tamaños comprobados mediante procesos independientes.
- APK Android release con Google y firma de pruebas compatible; no es una firma de producción de Google Play.
- La configuración Firebase y las claves de firma no se incorporan a Git. El APK de CI sin esa configuración queda identificado como `preview-sin-google`; el APK configurado se entrega por separado.

Las funciones de cuentas y colaboración 0.6.0 se incluyen en esta entrega. Los datos legales del responsable y soporte siguen pendientes por decisión del titular. La aceptación real de Google, iOS, push y el gateway MFA del personal no se sustituye por pruebas con proveedores simulados. La confirmación de Render Live requiere acceso real al servicio; subir código a GitHub no demuestra por sí solo que el despliegue haya terminado.
