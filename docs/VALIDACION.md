# Evidencia de validación · 5 de noviembre de 2026

Resultados de esta iteración, sin publicación de entorno, servicios o aplicación. No equivalen a aceptación integral de la especificación.

| Comprobación | Resultado |
| --- | --- |
| Backend, Python 3.12.14, `python -m pytest -q` | **53 pruebas aprobadas** |
| Flutter 3.47.9 / Dart 3.13.7, `flutter analyze` | **Sin incidencias** |
| `flutter test` | **37 pruebas aprobadas** |
| `scripts/setup.sh` con lockfile estricto | Ejecutado correctamente |
| `pip check` | Sin dependencias incompatibles |
| `flutter build web --release --no-web-resources-cdn` | Build generado |
| APK Android debug | Build generado con JDK Temurin 21.0.13, Gradle 9.3.1 verificado, SDK 34/35/36 y NDK 28.2.13676358 |
| Smoke HTTP real | Salud, búsqueda sin tildes, lectura de Constitución, tarjeta estructurada, espacio privado y supresión/revocación aprobados |
| Chromium real | Invitado → Biblioteca → paquete local → artículo 1 de Constitución; sin errores JavaScript |
| Recarga web sin conexión | No acreditada: el navegador de prueba no quedó controlado por un service worker |
| Corpus empaquetado | **20 normas, 11.777 bloques**; hashes del manifiesto y referencias comprobados |
| BOE real, sumario 2026-11-04 | 234 documentos capturados, eventos pendientes de análisis |
| BOE real, actualizaciones consolidadas 2026-11-04 | 23 actualizaciones capturadas, checkpoint completo |
| Backups SQLite | Copia consistente, restauración, integridad y rechazo de manipulación/sobrescritura probados |
| Firebase servidor | Firmas RSA de prueba, emisor/audiencia/fechas/proveedor, vinculación y aislamiento probados; sin proyecto real |

Las pruebas nuevas cubren revisiones inmutables, progreso conservado, `If-Match`, respuestas estructuradas, hashes de redacción histórica, búsqueda y cursor, informes idempotentes, avisos internos, espacios de estudio privados y comparación de conflictos. Flutter comprueba integridad de paquetes y recarga sin guardar el corpus completo en preferencias. Las ponderaciones universitarias conservan el peso de evaluaciones pendientes.

## Artefactos locales

- APK: `mobile/build/app/outputs/flutter-apk/app-debug.apk`.
- Web: `mobile/build/web/`.
- Captura de la lectura en Chromium: `/tmp/lex-reader.png` (evidencia temporal de esta sesión).
- API OpenAPI: `docs/openapi.json` regenerado desde el código.

No se ha instalado el APK en un dispositivo/emulador. La firma es de desarrollo; no usarla para publicar en tiendas. No se ha probado SQLCipher/Keychain/Keystore nativo ni iOS/macOS. No hay compra, push, login federado real, PostgreSQL ni despliegue remoto acreditados por estos resultados.

## Advertencias observadas

- Starlette avisa de la futura migración del TestClient de httpx a httpx2; las pruebas se completan.
- El build JavaScript web pasa; el dry-run Wasm detecta dependencias incompatibles de secure storage/TTS. No se ha generado Wasm.
- Plugins Android actuales avisan de una futura migración a Kotlin integrado. El APK actual compila. No se han ocultado verificaciones TLS, checksums ni aserciones.
- Las pruebas de texto grande y el recorrido de Chromium son parciales; no sustituyen una auditoría de accesibilidad en todas las pantallas.

## Reproducción

```bash
cd /workspace/LexMemoria
export PATH="/workspace/tools/flutter/bin:$PATH"
./scripts/setup.sh
cd backend
/workspace/lexmemoria-venv/bin/python -m pytest -q
cd ../mobile
flutter build web --release --no-web-resources-cdn
cd ..
JAVA_HOME=/workspace/tools/jdk/jdk-21.0.13+9 python3 scripts/build_android.py
```

Para regenerar paquetes tras nuevas importaciones verificadas: `/workspace/lexmemoria-venv/bin/python scripts/build_legal_assets.py`. Esto preserva hashes/atribución y no certifica vigencia ni crea contenido educativo público.

## Corrección de arranque Android · 0.1.1+2

El error genérico comunicado por el usuario en OPPO Reno 10 Pro con Android 15 ocultaba el paso de inicialización fallido. Se ha confirmado directamente con SQLCipher 4.10.0 en Android 15 que `execSQL("PRAGMA secure_delete = ON")` lanza `SQLiteException: Queries can be performed using SQLiteDatabase query or rawQuery methods only.` La misma instrucción con `rawQuery` devuelve `secure_delete=1`. La inicialización de la app usa ahora esa vía y continúa rechazando almacenamiento sin cifrar.

Las 37 pruebas Flutter y el análisis pasan. Se añaden pruebas de reintento, conservación de datos inválidos, diagnóstico sin información privada y regresión del contrato nativo de consultas. El APK `mobile/build/app/outputs/flutter-apk/app-release.apk` se ha compilado en modo release, con firma de pruebas válida y sin `application-debuggable`. Su identificador es `es.lexmemoria.app.preview` y su nombre visible **LexMemoria Prueba**, para no sustituir la instalación anterior.

El emulador local, sin KVM, presentó reinicios de servicios del propio sistema (NetworkStack/Bluetooth) y no permitió completar la instalación y el recorrido completo. La prueba directa de SQLCipher sí se ejecutó. No se acredita aquí el arranque completo en OPPO ni en ese emulador. `integration_test/startup_test.dart` comprueba SQLCipher/Keystore reales, escritura y reapertura; GitHub ejecutará esa prueba en Android 15 antes de generar el artefacto `lexmemoria-android-preview-release`. Su ejecución remota queda pendiente de la nueva CI.
