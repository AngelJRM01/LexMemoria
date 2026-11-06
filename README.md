# LexMemoria

Aplicación Flutter para estudiar Derecho español en Universidad y Oposiciones, con backend FastAPI. Implementación en desarrollo a partir de la especificación maestra V2 aportada por el usuario. **No es todavía el producto completo ni está lista para publicación.**

## Qué contiene

- Cliente móvil Android/iOS y proyecto web adaptable, interfaz en español, cinco destinos, modo oscuro y tipografía del sistema.
- Onboarding Universidad/Oposiciones/Ambos, acceso local sin registro, cambio de itinerario conservando datos.
- Catálogo de 12.451 normas del BOE consolidado observado, veinte incluidas y el resto descargable por norma sin servidor privado. Búsqueda tolerante a tildes, materias, marcadores y seguimiento local. Los textos son consolidaciones informativas; **no incluyen material educativo certificado**.
- Descarga de normas importadas desde una API configurable, lectura offline, notas privadas, copia de referencias, voz mediante plataforma, selector histórico, consulta por fecha efectiva que rechaza metadatos ambiguos y comparación textual de párrafos.
- Tarjetas personales QA, cloze, verdadero/falso, ordenación, caso y test; creación desde artículo; importación CSV con previsualización, límites y validación completa antes de guardar.
- Almacén SQLCipher en Android/iOS con clave separada en Keychain/Keystore; migración verificada desde preferencias. La versión web conserva preferencias locales sin este cifrado. La integración nativa está pendiente de ejecución.
- Repaso con cuatro grados, programación SM-2 adaptada `sm2-1`, eventos persistentes, bloqueo por revisión normativa, sesión guardada, borradores y deshacer local.
- Plan de estudio con cola que respeta descansos y vacaciones, previsión semanal, fecha de examen y asignaturas personales. Simulacro cronometrado con banco congelado, respuestas guardadas, penalización y corrección al finalizar. El contenido no se presenta como examen oficial.
- Historial, progreso por mazo, exportación/restauración JSON, consentimientos separados y borrado local confirmado.
- Identidad remota opcional con tokens en almacenamiento seguro, subida de tarjetas/revisiones con identificadores estables y conflictos explícitos, exportación/borrado remoto. Recuperación con código de un solo uso y descarga de tarjetas, estados e historial; los conflictos se conservan. OAuth/email y resolución avanzada de conflictos siguen pendientes.
- Backend con SQLite para desarrollo o PostgreSQL mediante `DATABASE_URL`, API OpenAPI, sesiones de 15 minutos, refresh rotatorio, revocación, control de propietario, ETag y claves de idempotencia.
- Conector BOE XML con timeout/reintentos, SHA-256, XML original, versiones inmutables, publicación transaccional, cuarentena y bloqueo conservador de tarjetas afectadas. Cola persistente de importación con lotes, backoff, leases y reanudación; vigilancia diaria y backfill por fecha civil de Madrid, con eventos de publicación deduplicados.
- API editorial con separación de autor y revisores, doble aprobación y acceso deshabilitado por defecto hasta configurar MFA. **No equivale a un backoffice de producción ni a una pasarela MFA implementada.**

Consulta [la matriz de requisitos](docs/matriz-requisitos.md), [el estado de validación](docs/VALIDACION.md) y [las limitaciones](docs/PENDIENTES.md). No hay contenido marcado como verificado sin revisión humana.

## Preparación

Requisitos validados: Python 3.12, Flutter **3.47.9** y un JDK completo (validado con Java 21, bytecode Java 17). Android necesita SDK 34/35/36, NDK 28.2.13676358 y CMake 3.22.1; iOS necesita macOS/Xcode/CocoaPods.

```bash
export PATH="/workspace/tools/flutter/bin:$PATH"
./scripts/setup.sh
```

El script instala las versiones fijadas del backend y cliente, ejecuta análisis y pruebas. `mobile/pubspec.lock` está resuelto. No regenera ni sobrescribe el proyecto nativo.

La aplicación incluye el índice de **12.451 normas oficiales del BOE** y veinte textos locales con 11.777 bloques. El resto dispone de paquetes públicos con versiones, hashes, fechas y atribución. En Biblioteca abre una norma y pulsa Descargar texto para guardarla para lectura; no necesita servidor. Es texto consolidado informativo, sin certificación jurídica ni material educativo verificado. La actualización remota es opcional y debe configurarse en Perfil.

[Avance V2 y límites](docs/AVANCE_V2_2026-11-05.md) · [Evidencia de validación](docs/VALIDACION.md) · [Despliegue propuesto en Render](docs/DESPLIEGUE.md)

El checkout ya está aislado; usa `/workspace/LexMemoria` y no crees otro worktree.

## Backend

```bash
python3 -m venv /workspace/lexmemoria-venv
/workspace/lexmemoria-venv/bin/pip install -r backend/requirements.lock
./scripts/start_backend.sh
```

Se escucha solo en loopback. Para un móvil real despliega detrás de HTTPS; configura esa URL en Perfil. La consulta de metadatos permite loopback de desarrollo, pero la subida de datos privados exige HTTPS. No desactives TLS.

Comprobación interna: `curl --fail http://127.0.0.1:8000/health`. Documentación OpenAPI en la ruta `/docs` del servidor. No hay despliegue público ni enlaces de preview en este entorno.

PostgreSQL: configura `DATABASE_URL=postgresql+psycopg://…` mediante variables seguras, sin incluir credenciales en el repositorio. El modelo actual usa agregados JSON y tablas separadas para cuentas, tokens, idempotencia y auditoría; la normalización y migraciones del esquema completo de V2 siguen pendientes.

## Importación jurídica

```bash
cd backend
/workspace/lexmemoria-venv/bin/python -m app.cli import BOE-A-1978-31229
/workspace/lexmemoria-venv/bin/python -m app.cli watch 20261104
```

Requiere acceso HTTPS a `www.boe.es`. Importar no certifica vigencia ni crea tarjetas verificadas. El comando `watch` conserva y estructura el sumario, genera eventos pendientes de análisis y evita duplicar una fecha completada. `backfill` recupera rangos de hasta 31 días; `enqueue`/`worker` procesan lotes reanudables. La clasificación jurídica de reformas y el envío push siguen pendientes. Los fallos no sustituyen la última versión válida.

Procesar el inventario inicial sin inventar cobertura:

```bash
cd backend
/workspace/lexmemoria-venv/bin/python -m app.cli enqueue ../docs/normas-iniciales.txt
/workspace/lexmemoria-venv/bin/python -m app.cli worker --limit 20
/workspace/lexmemoria-venv/bin/python -m app.cli backfill 2026-11-01 2026-11-04
```

La cola conserva errores, XML de cuarentena y checkpoints por trabajo. `batch ID` informa los contadores; `retry ID` requiere corregir antes la causa del fallo. No ejecuta publicaciones editoriales automáticamente.

CSV de tarjetas: UTF-8 con encabezados `pregunta,respuesta`, máximo 2 MB y 2000 tarjetas. No se evalúa HTML ni se ejecutan fórmulas. Anki `.apkg` no está implementado.

## Ejecución Flutter

```bash
cd mobile
flutter pub get --enforce-lockfile
flutter run
flutter build apk --debug
# En este entorno, con proxy y JDK completo:
JAVA_HOME=/workspace/tools/jdk/jdk-21.0.13+9 python3 ../scripts/build_android.py --preview-release
```

Para iOS: `flutter build ios --simulator` en macOS; firma y publicación requieren cuenta y perfiles propios. Los targets nativos proceden de las plantillas oficiales de Flutter 3.47.9. El wrapper Gradle 9.3.1 está verificado contra SHA-256 oficial y la distribución incluye checksum fijado. El identificador provisional es `es.lexmemoria.app`.

## Pruebas

```bash
cd backend
/workspace/lexmemoria-venv/bin/python -m pytest -q
# En un entorno con Flutter instalado:
cd ../mobile
flutter analyze
flutter test
```

CI preparada para backend, análisis/tests Flutter, web, arranque cifrado en Android 15, APK release de prueba y simulador iOS. El resultado remoto debe comprobarse en Actions; la validación local no lo acredita. No se generan compras reales, cargos, notificaciones ni sellos editoriales ficticios.

## APK de prueba sin modo debug

La CI entrega `lexmemoria-android-preview-release`, con `app-release.apk` dentro. Es una compilación optimizada **release** firmada para pruebas, no una publicación en tiendas. Aparece como **LexMemoria Prueba**, con identificador separado: conserva la app anterior y no importa ni borra sus datos. No desinstales la original si contiene progreso o no consigue abrir su almacén.

La firma de las compilaciones temporales de GitHub puede cambiar entre ejecuciones. Una distribución estable requiere configurar la clave de firma del titular; no se publica ningún keystore en Git ni como artefacto. Para diagnosticar un fallo de inicio, usa el botón Copiar diagnóstico de la versión nueva; el código no incluye notas, claves ni credenciales.

## Descarga masiva del catálogo BOE

`./scripts/download_corpus.sh --day 2026-11-05` enumera el catálogo completo observado y archiva las respuestas oficiales fuera del APK y de Git, con checkpoints, reintentos e integridad SHA-256. El inventario de este corte contiene 12.451 documentos, estatales y autonómicos; no equivale a toda la legislación española ni europea. Consultar [procedimiento, estados y límites](docs/DESCARGA_MASIVA.md). No se anuncia una descarga completa mientras queden pendientes o errores.
# Experiencia de estudio 0.2.0

Pantallas simplificadas, lector por fragmentos, filtros fijos y 20 mazos preparados con 13.914 tarjetas. Consulta [los cambios y su validación](docs/MEJORAS_ESTUDIO_2026-11-05.md), incluyendo el estado real de las cuentas y el alcance de las descargas masivas.

## Catálogo completo de estudio 0.3.0

12.451 normas con 684.375 fragmentos base, cuatro formatos automáticos y mazos temáticos personalizados. Descarga por norma, verificación de integridad y lectura sin conexión en Android/iOS. [Alcance, funcionamiento y validación](docs/CATALOGO_COMPLETO_2026-11-05.md). [Contenido público](https://github.com/AngelJRM01/LexMemoria/tree/legal-corpus-20261105).

## Lectura 0.3.1

Búsqueda dentro del texto de cada norma, apertura del fragmento encontrado y recuperación del punto de lectura con comprobación de versión y hash. Índices y artículos completos con filas por demanda. [Cambios y validación](docs/LECTURA_0_3_1.md).

## Archivo europeo supervisado

`./scripts/start_eu_download.sh` mantiene las descargas europeas con checkpoints, recuperación de fallos temporales y vigilancia posterior del catálogo. [Alcance, operación y evidencia](docs/DESCARGA_EUROPEA.md). La descarga sigue incompleta y depende de que el entorno permanezca encendido.

## Navegación y ejercicios 0.4.0

Materias con contenido, filtro por las 17 comunidades del catálogo, paginación con salto de página y ejercicios breves con varios huecos interactivos. La renovación conserva las ediciones e historial anteriores. [Cambios y validación](docs/MEJORAS_0_4_0.md).

## Auditoría y desarrollo V3 · 0.4.1

[Matriz de 100 requisitos y reglas](docs/v3/MATRIZ_REQUISITOS.md) y [orden de implementación, evidencia y aceptación por fase](docs/v3/PLAN_Y_EVIDENCIAS.md). Primer incremento: restauración recuperable y escrituras de estudio confirmadas antes de publicar el estado, sesiones vinculadas a cuenta/servidor, compatibilidad de respuestas de varios huecos y extracción incremental de HTML europeo en un archivo derivado separado. Las fases siguen abiertas; las integraciones externas y la aceptación nativa no se consideran aprobadas por pruebas locales.
