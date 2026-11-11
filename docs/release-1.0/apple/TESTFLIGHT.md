# Subida de la candidata a TestFlight

Workflow `.github/workflows/apple-testflight-upload.yml`. Usa exclusivamente la IPA del artefacto `LexMemoria-1.0.0-SIGNED-IPA-3`, ejecución 43105880193, ya firmada y verificada. Comprueba SHA256SUMS, ZIP, paquete `es.lexmemoria.app`, versión 1.0.0 y build 18 antes de subir. No recompila ni modifica el binario.

Secretos del repositorio confirmados por el titular: APP_STORE_CONNECT_KEY_ID, APP_STORE_CONNECT_ISSUER_ID y APP_STORE_CONNECT_PRIVATE_KEY_BASE64. Se validan formatos, se materializa temporalmente el .p8 con permiso 0600 fuera del checkout y se elimina siempre al terminar. No se imprime la clave ni se publica como artefacto. El acceso de la clave al equipo/app y la validez criptográfica se comprueban realmente al autenticar con Apple, no por las pruebas sintéticas.

La ejecución descarga el artefacto con permisos contents/read y actions/read y utiliza `xcrun altool --upload-app` con la clave de equipo. Se activa con el cambio de este workflow en release/1.0.0-rc1 o manualmente seleccionando esa rama. No ejecutarlo repetidamente si la versión 18 ya ha sido aceptada: Apple puede rechazar un build duplicado. El artefacto de origen caduca a los 14 días.

No envía a revisión, no distribuye a testers externos ni publica la app. Tras el comando de subida, Apple aún debe procesar el build; revisar TestFlight y los correos del titular para errores posteriores. La declaración de exportación/cifrado, información beta, aceptación de contratos, política de privacidad, acceso de revisión y pruebas físicas siguen siendo requisitos independientes. No marcar pruebas físicas como superadas por la subida.

Comprobación local: 6 pruebas específicas de permisos de archivo, formatos inválidos, aislamiento de secretos, artefacto exacto, limpieza y sintaxis Bash superadas. No acreditan recepción por Apple. El estado real debe consultarse en GitHub y después en App Store Connect.
