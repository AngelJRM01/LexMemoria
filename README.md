# LexMemoria

Aplicación Flutter para estudiar Derecho español en Universidad y Oposiciones, con backend FastAPI. Implementación en desarrollo a partir de la especificación maestra V2 aportada por el usuario. **No es todavía el producto completo ni está lista para publicación.**

## Qué contiene

- Cliente móvil Android/iOS y proyecto web adaptable, interfaz en español, cinco destinos, modo oscuro y tipografía del sistema.
- Onboarding Universidad/Oposiciones/Ambos, acceso local sin registro, cambio de itinerario conservando datos.
- Inventario de 20 referencias BOE. Búsqueda tolerante a tildes, materias, marcadores y seguimiento local. Las referencias **no incluyen textos descargados ni material jurídico certificado**.
- Descarga de normas importadas desde una API configurable, lectura offline, notas privadas, copia de referencias, voz mediante plataforma, selector histórico, consulta por fecha efectiva que rechaza metadatos ambiguos y comparación textual de párrafos.
- Tarjetas personales QA, cloze, verdadero/falso, ordenación, caso y test; creación desde artículo; importación CSV con previsualización, límites y validación completa antes de guardar.
- Repaso con cuatro grados, programación SM-2 adaptada `sm2-1`, eventos persistentes, bloqueo por revisión normativa, sesión guardada, borradores y deshacer local.
- Plan de estudio con cola que respeta descansos y vacaciones, previsión semanal, fecha de examen y asignaturas personales. Simulacro cronometrado con banco congelado, respuestas guardadas, penalización y corrección al finalizar. El contenido no se presenta como examen oficial.
- Historial, progreso por mazo, exportación/restauración JSON, consentimientos separados y borrado local confirmado.
- Identidad remota opcional con tokens en almacenamiento seguro, subida de tarjetas/revisiones con identificadores estables y conflictos explícitos, exportación/borrado remoto. **No hay recuperación de identidad, OAuth/email ni fusión multidispositivo completa.**
- Backend con SQLite para desarrollo o PostgreSQL mediante `DATABASE_URL`, API OpenAPI, sesiones de 15 minutos, refresh rotatorio, revocación, control de propietario, ETag y claves de idempotencia.
- Conector BOE XML con timeout/reintentos, SHA-256, XML original, versiones inmutables, publicación transaccional, cuarentena y bloqueo conservador de tarjetas afectadas. CLI de importación y captura diaria por fecha civil de Madrid.
- API editorial con separación de autor y revisores, doble aprobación y acceso deshabilitado por defecto hasta configurar MFA. **No equivale a un backoffice de producción ni a una pasarela MFA implementada.**

Consulta [la matriz de requisitos](docs/matriz-requisitos.md), [el estado de validación](docs/VALIDACION.md) y [las limitaciones](docs/PENDIENTES.md). No hay contenido marcado como verificado sin revisión humana.

## Preparación

Requisitos: Python 3.12, Flutter **3.47.9**, Java 17 y Android SDK para Android; macOS/Xcode/CocoaPods para iOS. El SDK Flutter se ha clonado en `/workspace/tools/flutter`, pero la descarga de Dart está bloqueada por la política de red de este entorno.

```bash
export PATH="/workspace/tools/flutter/bin:$PATH"
./scripts/setup.sh
```

El script instala el backend con versiones fijadas, completa metadatos nativos mediante `flutter create` sin sobrescribir código existente, resuelve paquetes y ejecuta análisis/pruebas móviles. **Su parte Flutter está pendiente de ejecución.** Guarda `pubspec.lock` después de la primera resolución válida para fijar las dependencias del cliente.

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

Requiere acceso HTTPS a `www.boe.es`. Importar no certifica vigencia ni crea tarjetas verificadas. El comando `watch` conserva el sumario del día de Madrid y evita duplicar una fecha completada; **la clasificación de reformas, backfill, actualización masiva de consolidados y envío push no están completos**. Los fallos no sustituyen la última versión válida.

CSV de tarjetas: UTF-8 con encabezados `pregunta,respuesta`, máximo 2 MB y 2000 tarjetas. No se evalúa HTML ni se ejecutan fórmulas. Anki `.apkg` no está implementado.

## Ejecución Flutter

```bash
cd mobile
flutter pub get
flutter run
flutter build apk --debug
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

CI preparada para backend, análisis/tests Flutter, web, APK debug y simulador iOS. No se ha publicado ni ejecutado remotamente este workflow. No se generan compras reales, cargos, notificaciones ni sellos editoriales ficticios.
