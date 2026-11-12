# Sincronización — corrección de la candidata 1.0.0 (20)

El titular comunicó una espera indefinida aparente al sincronizar tanto en iPhone como en Android. No se ha verificado la causa exacta en sus dispositivos ni en producción. El código permitía esperas de hasta 90 segundos en autenticación y hasta 120 segundos por Retry-After, junto con una primera copia secuencial sin indicador de tarjeta/repaso. Se respetan esos límites del servidor; no se aumentan sus cuotas ni se cambia de plan.

## Cambios

- Se muestra la fase de subida y el número de tarjeta/repaso, en lugar de un «Sincronizando» genérico durante toda la copia.
- Se informa cuando el servidor limita peticiones y se mantiene el Retry-After. Esa espera se puede interrumpir sin adelantar peticiones.
- «Detener esta subida» interrumpe la espera HTTP actual y evita continuar la operación. Se solicitan también abortos de transporte mediante AbortableRequest cuando el cliente los admite. La parada no revierte una escritura ya aceptada por el servidor. Las tarjetas y los puntos de control locales se conservan; la recuperación por lookup evita duplicar una tarjeta cuya respuesta se perdió.
- La parada corresponde a esa subida, no a una revocación del consentimiento de sincronización automática: si estaba activada, su coordinador puede reintentar después.
- El acceso a Google tiene un plazo máximo de 90 segundos para obtener el token; un token tardío no se intercambia por una sesión del servidor después de ese plazo.
- La pantalla explica la espera después de ocho segundos, mantiene navegación y recupera sus botones cuando termina o falla la operación.
- El mensaje de timeout indica que los datos locales se conservan y que el servidor podría estar arrancando, sin afirmar que esa sea la causa real.

No se modifica el esquema SQLCipher, las claves, el contenido privado, el aislamiento de cuentas ni el control de conflictos. No se anuncian todas las copias como instantáneas: el tiempo de una primera subida sigue dependiendo del volumen y de la red/servidor. No se implementa un endpoint masivo nuevo.

## Pruebas y límites

Suite Flutter completa: 166 superadas, una omitida. Análisis Flutter limpio. Pruebas específicas de Apple/build: 19 superadas. Se verifican parada con respuesta tardía, conservación local, reanudación sin duplicados de la tarjeta aceptada, espera Retry-After interrumpible sin peticiones prematuras y pantalla que libera botones ante un Google que no responde. Los tests usan transportes y credenciales sintéticas.

No se ha probado el flujo corregido con Google real ni en un iPhone/Android físico. La consulta de /health de Render falló desde el proxy del entorno con CONNECT 403: no demuestra una caída del servicio. El acceso nativo Google de la fuente iOS continúa deshabilitado; esta corrección no incorpora Google/Apple como proveedores nuevos en iOS.

La candidata anterior 1.0.0 (19) no contiene este cambio. Instalar el build 20 cuando termine su compilación y procesamiento. No desinstalar ni borrar datos; actualizar sobre la instalación existente. Android de pruebas conserva es.lexmemoria.app.preview y su firma existente; no es el AAB definitivo de Play Store.
