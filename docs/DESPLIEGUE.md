# Despliegue propuesto

El titular ha comunicado el proyecto Firebase público `lexmemoria-aa86a` y acceso de Render al repositorio. [Pasos concretos y selección de recursos](PRODUCCION_TITULAR.md). Los servicios aún no se han creado desde este entorno.

Render es la opción inicial recomendada para FastAPI y PostgreSQL administrado. Firebase Auth puede gestionar Google y Apple; FCM/APNs debe conectarse a las cuentas del titular para push. No se ha contratado ni desplegado ningún servicio.

`render.yaml` es una propuesta revisable con API y cron. Los planes indicados tienen coste: comprobar precios, región y condiciones antes de crearlos. Añadir PostgreSQL administrado y configurar la misma `DATABASE_URL` en ambos procesos; no usar SQLite efímero en Render. El backend acepta URLs `postgres://`, `postgresql://` y `postgresql+psycopg://`. El proceso horario consulta el día anterior en Madrid y deduplica ambos inventarios; no requiere cambiar el cron durante el horario de verano. Huecos históricos requieren `backfill` para sumarios y `consolidations AAAA-MM-DD` para el catálogo. Domingos sin sumario pueden requerir revisión del resultado BOE; no se interpreta automáticamente un 404 como cobertura completa.

La API usa un trabajador mientras el rate limiter es local al proceso. Para varias réplicas se necesita un limitador compartido en el proxy y coordinar los trabajos. Configurar TLS con el dominio de Render o uno propio. El puerto lo inyecta la plataforma. La API no tiene logs de acceso con rutas o parámetros privados.

Variables (introducir secretos en ajustes, nunca en Git):

- `LEXMEMORIA_ENV`: `staging` o `production` exige una conexión PostgreSQL válida y deshabilita el fallback SQLite local.
- `DATABASE_URL`: conexión PostgreSQL con TLS según las condiciones del proveedor.
- `FIREBASE_PROJECT_ID`: identificador público del proyecto; el backend verifica firma RSA, emisor, audiencia, fechas y proveedor Google/Apple mediante certificados oficiales HTTPS. Se necesitan salidas hacia `www.googleapis.com`.
- `CORS_ORIGINS`: orígenes web exactos separados por comas. Vacío no habilita acceso cruzado. No usar `*` para datos privados.

Identidad: `POST /v1/auth/oidc` recibe un ID token Firebase; `POST /v1/auth/link` vincula ese proveedor a la cuenta invitada autenticada sin perder datos. No se fusionan automáticamente dos cuentas existentes. Crear/configurar el proyecto Firebase y sus aplicaciones, consentimientos OAuth, dominio autorizado, Apple Services ID y credenciales de proveedor es trabajo del titular. La interfaz nativa Firebase y la revocación federada de sesiones siguen pendientes de integración y pruebas con ese proyecto; los endpoints locales probados no acreditan un login real en las tiendas.

Publicaciones editoriales continúan deshabilitadas: no activar `EDITORIAL_MFA_GATEWAY` como si fuese MFA real. No hay publicación automática de contenido educativo ni compras sin validación de tienda.

## Copias de desarrollo SQLite

`python -m app.backup backup origen.db copia.lexbackup --key-file /ruta/segura/clave` crea una copia consistente con AES-256-GCM. La clave son 32 bytes aleatorios, fuera del checkout y de la propia copia. Nunca pasar la clave por argumentos ni publicarla. Guardarla separadamente en un gestor seguro; perderla impide restaurar.

`python -m app.backup restore copia.lexbackup restaurada.db --key-file /ruta/segura/clave` autentica y comprueba integridad y claves foráneas; rechaza sobrescribir un archivo existente. La restauración produce una base local sin cifrar, como SQLite de desarrollo: proteger sus permisos y no confundirlo con cifrado del disco.

Las pruebas incluyen copia/recuperación y rechazo de manipulación. PostgreSQL en producción requiere backups cifrados del proveedor, restauración de ensayo, política de retención, región y objetivos RPO/RTO acordados. El comando SQLite no cubre PostgreSQL ni sustituye ese procedimiento.


## Preview Android 0.1.1

`JAVA_HOME=/ruta/a/jdk python3 scripts/build_android.py --preview-release` genera una release optimizada para pruebas privadas. La opción activa explícitamente la firma de pruebas y el sufijo `.preview`; no sirve como firma de tienda. La versión se instala en paralelo, bajo el nombre LexMemoria Prueba, por lo que no puede leer el almacén de la app original. En Android se excluyen de copias y transferencia automática tanto la base cifrada como las preferencias: la clave de Keystore no viaja con esos archivos. Exportación y recuperación remota siguen siendo los mecanismos de portabilidad soportados.
