# Google y Apple en iOS — candidata 1.0.0 (21)

Preparación de código del 12 de noviembre de 2026. No compilada ni aceptada físicamente todavía. El titular confirma haber habilitado Sign in with Apple en el identificador es.lexmemoria.app y guardado Apple como proveedor de Firebase. Eso no acredita autenticación ni revocación reales.

## Integración preparada

Google se habilita en iOS únicamente si están presentes ambas opciones de compilación LEXMEMORIA_GOOGLE_ENABLED y LEXMEMORIA_IOS_IDENTITY_ENABLED. Firebase recibe opciones del plist de cliente aportado por el titular y GoogleSignIn recibe su CLIENT_ID iOS. El retorno OAuth usa REVERSED_CLIENT_ID en Info.plist. El archivo plist no contiene la clave privada de un servicio; se transmite a CI mediante el secreto IOS_FIREBASE_CONFIG_BASE64 y solo se genera un JSON temporal de opciones. La configuración acaba necesariamente en el cliente instalado. No introducir claves privadas de Apple ni una cuenta de servicio Firebase en este campo.

Apple usa AppleAuthProvider y la implementación nativa ASAuthorizationAppleIDProvider de FlutterFire 7.0.1, que gestiona nonce y el intercambio Firebase. Solicita el ámbito email y permite las opciones nativas de Apple. Se añade el entitlement com.apple.developer.applesignin=Default solo a Runner. El botón se ofrece junto al de Google y permanece disponible con una sesión propia abierta.

Los tokens Firebase se intercambian por la sesión del backend existente, que ya verifica los proveedores google.com y apple.com. Cuando hay sesión se llama a /v1/auth/link conservando identidad, tarjetas y progreso; ante conflicto no se cambia de cuenta ni se fusiona en silencio. Los indicadores remotos de Apple y Google son separados y no se restauran como autoridad desde una copia.

La eliminación mediante Apple solicita identificación reciente, comprueba el sujeto Firebase esperado, elimina los datos del backend, revoca mediante revokeTokenWithAuthorizationCode y elimina la identidad Firebase. El fallo de una fase final conserva el marcador de eliminación pendiente para reintentar. No se ha validado esta revocación con Firebase/Apple reales; habilitar el proveedor por sí solo no prueba que su configuración esté completa. Completar cualquier configuración adicional requerida por Firebase para revocación antes de distribución pública, conservando sus claves privadas en los paneles correspondientes.

## Acciones del titular antes de compilar

1. Apple Developer → Profiles → LexMemoria App Store → Edit → Generate. Descargar el perfil regenerado con Sign in with Apple y el certificado de distribución existente.
2. Actualizar IOS_PROVISIONING_PROFILE_BASE64 en GitHub con ese perfil. No sustituir P12 ni certificado. El preflight ahora rechaza explícitamente un perfil sin el entitlement Apple.
3. Crear IOS_FIREBASE_CONFIG_BASE64 con el contenido Base64 del GoogleService-Info.plist correcto para es.lexmemoria.app/lexmemoria-aa86a. El plist ya aportado al chat pasa la validación de paquete, proyecto y datos de retorno; no ha sido subido como secreto por el agente.
4. Confirmar ambos pasos sin enviar valores privados al chat. Preparar entonces la ejecución del workflow de firma para la candidata 21.

El workflow de firma queda temporalmente manual para evitar lanzarlo con un perfil antiguo o sin el nuevo secreto. Cuando el titular confirme la configuración se podrá lanzar restableciendo su activación controlada, sin publicar ni enviar a revisión.

## Validación y límites

Suite Flutter: 170 pruebas superadas, una omitida. Análisis limpio. 27 pruebas específicas Python de firma/configuración/workflows superadas. 40 pruebas Flutter específicas de cuentas, copia y proveedores superadas antes de la suite completa.

El plist real aportado por el titular se validó localmente sobre archivos temporales sin mostrar sus valores. Pruebas de vinculación/cancelación usan credenciales y transportes simulados. No confundir esas pruebas con acceso real. Falta compilar con Xcode, validar entitlements del binario/perfil y probar Google y Apple en un iPhone físico, incluyendo cancelación, vinculación, restauración y eliminación/revocación. No se presenta la candidata como publicable sin esa aceptación. La privacidad/ficha y el acceso para revisión deben reflejar el binario final.
