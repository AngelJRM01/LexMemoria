# Evidencia de validación

## Ejecutado en esta máquina

- **34 pruebas backend aprobadas**, `python -m pytest -q`, Python 3.12. Incluyen rotación/revocación de tokens, aislamiento de usuarios, rechazo de citas inexistentes, deduplicación de revisiones, conflicto de clave, bloqueo de tarjetas, exportación/borrado, ETag, promociones sin renovación/cobros, SM-2, puntuación, importación atómica, XML preservado con tabla, versiones antiguas conservadas, cuarentena, 429/reintentos, permisos editoriales y banco congelado de simulacro. Las subidas con IDs estables se prueban sin duplicación.
- **Smoke HTTP real aprobado**: arranque con `scripts/start_backend.sh`, GET `/health`, crear identidad temporal, crear mazo privado, borrar la identidad y sus datos. El smoke no deja tarjetas o cuentas de prueba.
- **Sintaxis Dart aprobada por tree-sitter-dart** en todos los archivos `.dart`, incluidos tests. Es solo parseo: no resuelve tipos/imports ni valida widgets o plugins.
- `compileall` de módulos Python aprobado.
- Wrapper Gradle descargado de la etiqueta oficial v9.3.1 y cotejado con SHA-256 oficial `b3a875ddc1f044746e1b1a55f645584505f4a10438c1afea9f15e92a7c42ec13`. Distribución fijada con SHA-256 en propiedades.

El runner muestra una advertencia de Starlette sobre futura migración del TestClient de httpx a httpx2; los 34 tests se completan. No se desactivaron aserciones ni verificación TLS/checksums.

## No ejecutado / bloqueado

- Descarga de Dart/Flutter: **bloqueada por proxy CONNECT 403 a storage.googleapis.com**. Clonar Flutter 3.47.9 desde GitHub sí funcionó.
- `flutter pub get`, `flutter analyze`, `flutter test`, renderizado y pruebas manuales de UI: **no ejecutados**. Se han escrito 24 tests Flutter (aprendizaje, almacenamiento y widget), pendientes de ejecución. No hay `pubspec.lock` resuelto.
- Builds APK/AAB/web/iOS, instalación en dispositivo, firma y publicación: **no ejecutados**. Android SDK no está instalado e iOS necesita macOS/Xcode.
- API BOE en vivo, importación de corpus real, licencia/revisión editorial: **no verificadas**. El catálogo inicial son 20 referencias identificadas; no se etiqueta texto educativo como verificado.
- PostgreSQL real, conexiones en varios móviles, Keychain/Keystore real, voz nativa y permisos de plataforma: **no verificados**.
- CI preparada, pero **no enviada ni ejecutada en GitHub**.
- Compras sandbox/reales, APNs/FCM, OAuth/MFA, backups cifrados/restauración operativa, auditoría RGPD, rendimiento y accesibilidad con dispositivos: **pendientes**.

## Reproducción

Backend:

```sh
cd /workspace/LexMemoria/backend
/workspace/lexmemoria-venv/bin/python -m pytest -q
```

Una vez aplicado el acceso de red y preparado Android/macOS, ejecutar `scripts/setup.sh`, `flutter build apk --debug` y `flutter build ios --simulator` en las plataformas correspondientes. Los resultados anteriores no sustituyen esas comprobaciones.

## Segunda iteración

Siete pruebas adicionales cubren selección histórica por fecha efectiva, reforma futura, fecha de cambio inclusiva, metadatos incompletos, conflictos en la misma fecha, texto fuera de su intervalo y contrato HTTP `asOf`. Se añaden tests Flutter de vacaciones, descansos, previsión semanal y consulta histórica, todavía sin ejecutar por el bloqueo del SDK.

## Tercera iteración

34 pruebas backend aprobadas: se añaden lotes reanudables y deduplicados, backoff persistente, recuperación de lease, cuarentena/reintento manual, backfill de días fallidos, deduplicación diaria, cambio horario de Madrid, paginación de eventos, recuperación de identidad de un solo uso, revocación de sesiones antiguas y metadatos de exportación no suplantables.

SQLCipher y almacenamiento seguro: versiones comprobadas en pub.dev. Código y tests de migración escritos; **no se han ejecutado plugins nativos**. La sincronización cliente tiene tests escritos de refresh, aislamiento de tokens por URL de API, restauración de historial y conservación de revisiones pendientes, también pendientes de Flutter.
