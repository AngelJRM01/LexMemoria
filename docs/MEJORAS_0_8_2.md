# LexMemoria 0.8.2 — respuesta de la aplicación y base de datos

## Cambios en el móvil

- Las pestañas se montan al visitarlas. Las ocultas conservan filtros/posición y no se reconstruyen al guardar cada cambio; tampoco se refresca el panel de fondo mientras hay otra ruta encima.
- Los temas claro/oscuro se construyen una vez, en lugar de volver a crear ambos en cada notificación del almacén.
- Un repaso y la posición siguiente de la sesión se confirman en una sola escritura atómica. Se eliminan la segunda escritura y su invalidación general de cachés. Una pulsación repetida mientras se guarda no genera dos respuestas.
- Los datos grandes se codifican fuera del isolate de interfaz en Android. Solo se congelan/deserializan las secciones que cambiaron, conservando la detección de cambios concurrentes, la escritura confirmada y la protección ante disco lleno.
- SQLCipher actualiza únicamente los fragmentos cuyo contenido cambió y retira los sobrantes dentro de la misma transacción. No requiere cambiar el esquema v2, las claves ni reinstalar. No se usa una caché de hashes que pueda dejar datos antiguos con otro escritor.
- Las colas de repaso utilizan un índice por mazo ligado a la colección actual. Abrir cada mazo deja de recorrer todas las tarjetas; editar/cambiar un mazo o revisar una tarjeta conserva los resultados correctos.
- La biblioteca europea reutiliza sus resultados al paginar, no copia todo el catálogo para la vista sin filtros y usa un conjunto para las referencias guardadas. La espera tras escribir baja de 300 a 100 ms; el primer acceso y una descarga siguen dependiendo de procesamiento/red.

## Cambios en el servidor

Se añaden índices no únicos por propietario/tipo/ID y propietario/tipo/identificador local. La extracción del identificador JSON usa una expresión constante compatible con SQLite y PostgreSQL: un índice que no coincide con la consulta no acelera esa consulta. Se conserva el aislamiento por propietario y la detección de identificadores ambiguos.

La reconstrucción del buscador deja de hacer un SELECT por norma. Procesa lotes de cien, inserta/repara por upsert y no reescribe filas idénticas. Los índices también se crean de forma idempotente cuando las tablas ya existen; no solo en bases nuevas. Son cambios aditivos, sin borrar tarjetas, eventos o fuentes.

## Mediciones reproducibles

| Escenario | Antes | Después |
| --- | ---: | ---: |
| PostgreSQL 18, reconstrucción inicial de 12.457 normas | 12.890 ms / 24.915 consultas | 1.418 ms / 126 consultas |
| PostgreSQL 18, búsqueda por identificador entre 50.000 tarjetas | 38,96 ms mediana | 0,34 ms mediana |
| SQLite, misma búsqueda de tarjeta | 33,74 ms mediana | 0,05 ms mediana |
| Host Flutter, selección para 200 mazos con 20.000 tarjetas | 65,40 ms mediana caliente | 9,56 ms mediana caliente |
| Escrituras por respuesta y continuación | 2 | 1 |

Los resultados de las colas antes/después producen el mismo SHA-256. El plan PostgreSQL confirma el uso del índice nuevo; los endpoints reales de creación, búsqueda, búsqueda por lote y repaso se comprueban con dos cuentas aisladas en PostgreSQL local.

Los tiempos son del entorno de pruebas, con datos sintéticos y catálogo real. No son latencias del OPPO ni mediciones de Render. La codificación en un worker persigue reducir el bloqueo visual; el tiempo total de una escritura no es su presupuesto de fotograma. No se afirma que todas las interacciones ya estén por debajo de 100 ms.

## Aceptación y despliegue

Objetivo de aceptación: respuesta visual local por debajo de 100 ms, sin trabajo masivo en el hilo de interfaz, y desplazamiento fluido. Falta medir p50/p95 y fotogramas en el OPPO físico. Descargas y arranque en frío de Render Free no pueden prometerse instantáneos mediante índices locales; las funciones locales no deben depender de esperar al servidor.

Los cambios de servidor se aplicarán cuando Render despliegue y arranque esta versión. La primera creación de índices puede alargar ese arranque; no se han ejecutado cambios sobre la base de producción desde este entorno. Actualizar el APK y desplegar el backend son dos acciones distintas.

La nueva entrega conserva paquete y certificado de pruebas de Google para actualizar sin borrar datos. La firma de pruebas no sustituye Play App Signing ni prueba el acceso Google real. Informes en `docs/validation/0.8.2/`; scripts de medición en `scripts/benchmark_database.py` y `scripts/benchmark_postgresql.py`.

## Validación

217 pruebas backend, 147 Flutter, analizador sin incidencias y pruebas de API sobre PostgreSQL 18 local. Las regresiones móviles verifican carga diferida, conservación del filtro de Biblioteca, una sola revisión ante pulsaciones rápidas, commit atómico de la continuación y protección frente a mutación externa durante una escritura.

Las dos pruebas nativas de SQLCipher pasaron en Android 15 emulado: fila heredada superior a tres MiB, Unicode, cero actualizaciones al repetir un snapshot idéntico, una actualización al cambiar su cola, reducción de tamaño, rollback y reapertura con clave. Las pruebas nativas no verifican Google real ni latencias de un teléfono físico.
