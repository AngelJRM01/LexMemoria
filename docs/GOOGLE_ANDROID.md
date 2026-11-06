# Acceso Google Android: integración y configuración pendiente

Estado de trabajo: integración cliente implementada, **APK Android release configurado, compilado y verificado; pendiente de probar Google en dispositivo**. Apple queda fuera de este incremento. iOS/web mantienen el lector y el estudio, pero este botón de acceso solo se habilita en Android configurado.

## Datos conocidos

- Firebase: `lexmemoria-aa86a`; el titular confirma proveedor Google habilitado.
- APK de pruebas: `es.lexmemoria.app.preview`.
- SHA-1 del certificado local de pruebas: `96:76:43:56:9E:DD:B5:73:C9:15:3C:E9:7B:4B:78:96:71:C2:90:08`.
- SHA-256: `52:5F:9D:CA:16:4C:4E:16:1F:C6:AC:D8:EF:10:AC:54:53:CD:10:B0:90:A0:01:EB:AC:BF:0C:48:6E:92:12:92`.
- El titular ha registrado Android y confirma haber añadido la huella. Archivo `google-services.json` actualizado recibido y validado: proyecto, paquete, cliente web y huella coinciden. URL pública confirmada por el titular: `https://lexmemoria-api.onrender.com`. El archivo local queda ignorado por Git.

El apodo de Firebase es opcional. Añadir la huella después del registro no obliga a registrar otra app: hay que volver a descargar la configuración desde Configuración del proyecto → General → Tus apps → app Android. No se necesita una clave de cuenta de servicio ni un archivo con private_key.

## Implementación

Firebase Core/Auth y Google Sign-In oficiales. La selección Google obtiene un token de Google, lo intercambia mediante Firebase Auth y envía **el ID token Firebase** al backend; no confunde los dos tokens. El servidor existente valida firma RSA, proyecto/emisor, caducidad y proveedor.

- Una cuenta invitada existente se vincula por `/v1/auth/link`, conservando ID, tarjetas, revisiones, notas y programación. Un 409 no dispara login alternativo ni fusión silenciosa.
- Sin cuenta activa, `/v1/auth/oidc` entrega la sesión propia de LexMemoria, guardada en su almacén seguro y vinculada a cuenta/servidor. Cambios de propietario requieren confirmación; cambios durante la selección/respuesta cancelan la vinculación local.
- Cancelar selección no contacta al backend ni modifica datos. No se sube contenido de estudio ni se descarga progreso automáticamente al pulsar Google.
- Se solicita el cierre de las sesiones temporales Firebase/Google al terminar el intercambio (best effort). El SDK gestiona su propia caché temporal durante el acceso; no se promete ausencia de caché tras un cierre abrupto en mitad del flujo. Los tokens no se añaden al snapshot ni a las exportaciones.
- Mensajes de fallo no muestran tokens ni excepciones completas del proveedor. Endpoints de autenticación admiten hasta 90 s para el despertar del servidor gratuito; operaciones restantes conservan su límite anterior.
- El botón requiere proveedor Android configurado y API HTTPS válida. Los builds sin configuración siguen ofreciendo lectura/estudio y recuperación por código con API configurada.

## Build configurado

`google-services.json` queda fuera de Git mediante gitignore. El helper valida proyecto, paquete, identificador SDK, cliente OAuth web y SHA-1 antes de habilitar el botón. Rechaza JSON administrativo. Comprueba después la firma real del APK contra la configuración, sin imprimir claves.

```bash
/workspace/lexmemoria-venv/bin/python scripts/build_android.py \
  --preview-release --no-pub \
  --google-config /ruta/google-services.json \
  --api-url https://URL_PUBLICA_CONFIRMADA
```

La URL base va sin `/health`, credenciales, consulta o fragmento. La configuración se copia a `mobile/android/app/google-services.json`, ignorado por Git. Google Services Gradle solo se aplica si existe ese archivo. El helper pasa `LEXMEMORIA_GOOGLE_ENABLED=true` y proyecto/URL como configuración pública de compilación.

La firma de runners temporales GitHub puede diferir. **No se considera Google habilitado en esos APK sin configurar certificado estable y archivo/flags correspondientes.** No publicar keystores ni contraseñas en Git o artefactos. Registrar producción (`es.lexmemoria.app`) y firma de tienda es un paso distinto.

## Pruebas y aceptación

Ejecutado durante preparación: **89 pruebas Flutter y 144 backend**, incluyendo cancelación, sesión segura sin subir notas, vinculación conservando invitado, conflicto entre cuentas, cambio de servidor/cuenta durante acceso, botón condicionado y rechazo de configuración incorrecta o administrativa. Son pruebas locales con proveedor/HTTP simulados y firmas RSA de fixture existentes; **no prueban una cuenta Google real**.

Pendiente: APK Android configurado y prueba física en OPPO, cancelar/reintentar, primer acceso, vincular invitado, cerrar/reabrir sesión, segundo dispositivo y conservación de datos. Firebase Google debe permitir la firma real, usuario/consentimiento del proyecto y API Render debe tener FIREBASE_PROJECT_ID correcto. La respuesta `/health` solo acredita salud puntual de API/consulta; no valida OAuth ni la sincronización de todo el corpus citado. Los paquetes/versiones jurídicos usados por las tarjetas deben estar disponibles en el servidor antes de aceptar su subida.

La prueba debe empezar con datos de prueba y copia local exportada. Si Android rechaza una actualización por firma, no desinstalar ni borrar la app que contiene progreso para forzarla.

## Evidencia de compilación 0.5.0+8

APK release generado, sin application-debuggable, con paquete es.lexmemoria.app.preview y la firma SHA-1 registrada. Se comprobaron dentro del APK proyecto, app Firebase y cliente web frente al archivo recibido, URL Render en el binario ARM64 y catálogo BOE intacto. El archivo google-services.json no se incluye como archivo bruto ni se versiona en Git; sus recursos públicos necesarios sí forman parte del APK, como requiere el SDK. [Verificación del APK](validation/android-google-0.5.0.json).

Se corrigió el helper de compilación: Flutter 3.47 no regenera plugins nativos de release con --no-pub, dejando integration_test tras los tests. El build release permite ahora la regeneración oficial con las dependencias resueltas del lockfile; no se modifica a mano GeneratedPluginRegistrant.java. La nueva compilación excluye el plugin de tests correctamente.

El APK configurado se entrega como LexMemoria-0.5.0-google-prueba.apk. El flujo real de Google y la actualización física conservando progreso permanecen pendientes de aceptación por el titular.

## Diagnóstico y límites del servidor

Se corrige la etiqueta antigua 0.1.0 de /health: devuelve la versión de la API, el dialecto real de base de datos y el ID público de proyecto Firebase configurado, sin URL/credenciales de conexión. Tras desplegar este commit, el servicio de Render debe indicar database=postgresql y firebaseProject=lexmemoria-aa86a. Esa información acredita configuración y conectividad puntual; no prueba una cuenta Google real.

Las sesiones propias del backend conservan su caducidad y revocación por cierre/borrado. Deshabilitar un usuario en Firebase no invalida automáticamente todas las sesiones propias de LexMemoria: la revocación federada y el borrado coordinado con el proveedor siguen pendientes para producción.

[Resultados, tipos de pruebas y límites](validation/google-0.5.0.json). Las compilaciones Android configurada y web release son correctas; iOS no se ha compilado localmente.

## Descarga accesible desde el móvil

[APK configurado con Google](https://raw.githubusercontent.com/AngelJRM01/LexMemoria/751f44440c2f0e993c6f723bf73c3bb0ddeb21db/LexMemoria-0.5.0-google-prueba.apk). Alojado en la rama de distribución `android-google-preview-0.5.0`, con commit inmutable en el enlace. Descarga completa verificada por HTTP (87.102.881 bytes) y SHA-256 idéntico al informe del APK. No es el artefacto genérico de Actions. Código fuente y configuración pública del SDK documentados en el README de esa rama; no hay keystore ni claves privadas de servidor en el paquete.
