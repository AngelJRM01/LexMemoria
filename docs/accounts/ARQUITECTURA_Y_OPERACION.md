# Cuentas, personalización y colaboración — 0.6.0

Borrador de desarrollo del 6 de noviembre de 2026. No acredita despliegue en Render, aceptación con Google ni cumplimiento jurídico. La rama remota `main` se comprobó inicialmente en `a9d674bda39a01fd259aceaba3653b5943590cb9`; este documento describe los cambios locales posteriores.

## Responsabilidades

Se conserva Flutter → FastAPI → SQLAlchemy/PostgreSQL, Firebase como proveedor de identidad y el almacén cifrado local existente. No se añade contraseña propia, feed, chat ni sexta pestaña. El usuario local puede seguir estudiando, leyendo, creando materiales y exportando sin cuenta. La colaboración se abre desde navegación secundaria.

- `accounts.py`: perfil canónico, alias, sesiones, credenciales vinculadas y derechos del servidor.
- `collaboration.py`: contactos, invitaciones, permisos centralizados, grupos, catálogo y moderación. Las consultas de contenido compartido usan listas explícitas de campos y no incluyen eventos ni estados de estudio.
- `avatars.py`: imágenes privadas, límites, decodificación real y recodificación sin metadatos. La foto de Google se importa una vez, con identidad fresca verificada; no se permite una URL arbitraria de seguimiento.
- `editorial_security.py`: autorización de personal y prueba de un gateway MFA. Una variable que diga «MFA configurado» por sí sola no autoriza operaciones.
- `recovery_receipts.py`: recuperación idempotente cuando se pierde la respuesta. El cliente guarda el intento y un secreto aleatorio antes de consumir el código; el servidor conserva temporalmente una respuesta cifrada para ese intento.
- `sync_clock.py`: versión por usuario para detectar cambios educativos, con incremento atómico en PostgreSQL y SQLite. Los procesos CLI que usan `connect()` también registran estos hooks. El historial anterior de tarjetas se conserva tanto en ediciones explícitas como en actualizaciones de fuentes.
- `notifications.py`: bandeja interna, categorías opcionales, silencio y frecuencia. No envía FCM/APNs.
- `postgres_backup.py`: archivo pg_dump cifrado con AES-256-GCM y restauración verificada sobre una base distinta y vacía.

## Modelo y migración

Se reutiliza `Record` con su versión optimista para perfiles, configuración académica, grupos, recursos, publicaciones, reportes, notificaciones y derechos. No se duplican los mazos, tarjetas o estados existentes con un segundo modelo social. Se añaden tablas específicas únicamente donde son necesarias las restricciones relacionales:

| Tabla | Garantía |
| --- | --- |
| `user_sessions` | Familia identificable por cuenta, fecha y actividad aproximada |
| `session_tokens` | Token vinculado a familia; borrado en cascada |
| `alias_claims` | Alias único y cuenta estable independiente del alias |
| `memberships` | Unicidad del miembro por recurso y claves foráneas |
| `invitations` | Digest del secreto, pertenencia, caducidad, usos y versión |
| `relationships` | Contacto/bloqueo único y referencias a cuentas |
| `recovery_receipts` | Respuesta cifrada de recuperación, vinculada a cuenta e intento |
| `account_sync_clocks` | Contador de cambios persistente, separado por cuenta |

El arranque crea tablas ausentes sin eliminar ni transformar columnas pobladas. PostgreSQL toma un advisory lock durante la creación del esquema para serializar arranques. No sustituye una herramienta de migraciones versionadas si en el futuro se necesita `ALTER TABLE`.

Antes de un despliegue real: guardar y verificar un backup cifrado, probar el esquema sobre una copia y conservar la versión anterior del servicio. Para volver al servidor anterior, conservar las tablas añadidas; **no ejecutar DROP sobre tablas con datos**. Las aplicaciones antiguas pueden seguir usando los contratos anteriores. Las secciones nuevas de workspace se conservan cuando un cliente antiguo no las envía. Los tokens antiguos se reconocen, pero su sesión no se presenta como un dispositivo identificable.

La migración nativa del almacén cifrado se comprobó en un emulador Android 15/API 35 con una fila heredada de más de 3 MB, Unicode, reapertura real y fallo transaccional inducido. Esto no acredita todavía el OPPO del titular.

## Contratos e idempotencia

La referencia completa se genera en `openapi-0.6.0.json`. Los endpoints privados requieren el bearer de la API; Firebase verifica el proveedor en el intercambio existente. El UID interno no depende de nombre, correo o alias.

- Perfil: GET/PUT `/v1/account/profile`, `If-Match` obligatorio en escritura. Alias normalizado, reservado y retenido 30 días tras cambiarlo para reducir suplantaciones.
- Seguridad: `/v1/account/security`, revocación de sesión y `revoke-others`. Renovar mantiene la familia; cerrar sesión revoca esa familia. La última actividad corresponde a emisión/renovación, no a una identificación exacta del móvil.
- `/v1/sync/status`: devuelve UID y versiones de progreso, workspace y perfil, sin descargar todo el contenido.
- Tarjetas: ID estable del cliente, recuperación por lote `/v1/cards/lookup`, revisiones e historial. Repetir exactamente una edición tras perder la respuesta devuelve el resultado confirmado; un contenido divergente sigue produciendo 409.
- Workspace: GET/PUT `/v1/workspace` con `If-Match`. Perfil académico, notas, cursos/temas, normas seguidas, marcadores, favoritos, lectura y simulacros. El perfil de cuenta tiene una única autoridad en su endpoint, no otra copia editable dentro del workspace.
- Invitaciones: secreto aleatorio, solo digest persistido, fragmento URL para que el navegador no lo envíe al cargar la página. Aceptación verifica emisor, rol vigente, bloqueo, destinatario, caducidad y usos dentro de la transacción. Revocación inmediata para accesos remotos futuros.
- Copiar mazo: `Idempotency-Key`, bloqueo por usuario, IDs nuevos, atribución y contenido sin historial académico ajeno. La copia sobrevive al borrado del autor original; se anonimiza su identificación. Las actualizaciones posteriores requieren comparar y confirmar; las tarjetas editadas personalmente se separan de la fuente.
- Grupos: recursos propios, roles aplicados en backend, retirada de acceso al salir o expulsar y retirada del material que aportó quien sale. Eliminar el grupo no elimina mazos personales.
- Catálogo: publicación explícita pendiente de moderación; admitir un material no certifica su corrección jurídica. Filtros por texto, materia y norma. No se inventa una correspondencia con oposiciones.

## Sincronización segura

El usuario confirma la primera subida/descarga. Puede activar por separado la sincronización automática de progreso y la de notas/plan después de una sincronización inicial. El consentimiento queda vinculado a cuenta y servidor; una copia JSON o un cambio de cuenta no puede conceder esa autoridad.

El coordinador funciona **mientras la aplicación está abierta**. Agrupa cambios durante tres segundos, consulta cambios remotos aproximadamente cada minuto y aplica reintentos con espera creciente ante errores. No promete trabajo permanente en segundo plano. Conserva colas y estados locales en el almacén cifrado.

Un cambio remoto de tarjeta se aplica automáticamente solo si el contenido local sigue en la revisión conocida. Si ambos cambian, se conserva el contenido local, se bloquea su estudio hasta comparar y se ofrece conservar ambas versiones mediante una copia independiente. Los repasos pendientes no desaparecen: quedan conservados y asociados a su revisión histórica.

Notas, cursos y demás secciones se combinan a tres bandas: local, última base confirmada y servidor. Si solo cambia una parte se puede combinar; si la misma sección cambia en ambos dispositivos se requiere comparación explícita. La confirmación local es atómica y comprueba que la cuenta y los datos no hayan cambiado durante la petición. Campos desconocidos de un workspace nunca se convierten en credenciales o configuración raíz del móvil.

El éxito se muestra después de una respuesta y una identidad de servidor verificadas, no al iniciar la petición. Los eventos idempotentes, las ediciones repetidas y la búsqueda por clientId evitan duplicados al reintentar. Los errores de disco no se presentan como guardado correcto.

## Moderación fuerte

Las herramientas de personal exigen rol autorizado y un gateway que realmente autentique con MFA. No hay un gateway operativo configurado en esta entrega. El gateway debe eliminar cualquier `X-LexMemoria-Editorial` recibido del cliente y generar su propia prueba, manteniendo el secreto exclusivamente en servidor.

Configurar en el servicio protegido `EDITORIAL_MFA_GATEWAY=configured` y `EDITORIAL_GATEWAY_SHARED_KEY` aleatorio de al menos 32 caracteres. La prueba es `timestamp.nonce.hmac_sha256_hex`, válida durante 60 segundos. El mensaje firmado une con saltos de línea: UID, timestamp, nonce, método, ruta, SHA-256 de los bytes exactos del cuerpo y SHA-256 del bearer. Cada nonce se consume una sola vez y queda auditado. No incluir query string en la ruta firmada. El gateway debe verificar MFA antes de firmar. La suite usa un firmante de pruebas explícito; no demuestra un proveedor MFA real.

Los reportes propios y apelaciones no requieren privilegios administrativos. Las decisiones y restricciones dejan auditoría. Una restricción de colaboración no elimina el acceso a los datos privados ni a la exportación del usuario.

## Backups de PostgreSQL

Usar pg_dump/pg_restore compatibles con PostgreSQL 18. Guardar una clave aleatoria de 32 bytes en un archivo con permiso 0600, separado de la copia. Nunca pegar URL de base, contraseñas o claves en chat, Git ni argumentos del proceso. Cargar `DATABASE_URL` mediante el gestor seguro del servicio; para restaurar, usar `LEXMEMORIA_RESTORE_DATABASE_URL` de una base nueva y vacía.

```sh
python -m app.postgres_backup backup /ruta/segura/lexmemoria.dump.enc --key-file /ruta/segura/backup.key
python -m app.postgres_backup restore /ruta/segura/lexmemoria.dump.enc --key-file /ruta/segura/backup.key
```

El cifrado autentica archivo y cabecera. La restauración rechaza un archivo alterado antes de escribir en PostgreSQL y rechaza bases pobladas. La herramienta no borra ni sobrescribe una base existente. Las pruebas reales y sus límites están en `postgres-*.json`.

Quedan por decidir con el responsable retención, ubicación externa, programación, custodia/rotación de claves, recuperación de copias antiguas y tratamiento de solicitudes de supresión en backups. Una herramienta de backup local no equivale a una política de copias operativa en Render. La instancia gratuita del titular indica caducidad el **6 de diciembre de 2026**.

## Dependencias externas y publicación

- Render: el titular no sabe si la revisión actual está Live. No se ha verificado el despliegue 0.6.0 ni la API del titular desde este entorno; `onrender.com` no está permitido por su política de red. Las pruebas PostgreSQL son locales.
- Google/Firebase: el APK de pruebas reutiliza `es.lexmemoria.app.preview`, su configuración ignorada por Git y la firma de pruebas existente. Compilar y comprobar el SHA-1 no sustituye iniciar sesión, revocar y recuperar en dos dispositivos reales.
- Eliminación web: ruta `/account/delete`, autenticación Google fresca y verificación del usuario. Hace falta `FIREBASE_WEB_API_KEY` y autorizar el dominio en Firebase. No se ha probado el SDK contra el proyecto real. La eliminación de Firebase puede reintentarse si se pierde la conexión después de eliminar los datos de API.
- Privacidad: faltan `PUBLIC_CONTROLLER_NAME`, `PUBLIC_SUPPORT_EMAIL` y `PUBLIC_PRIVACY_POLICY_URL`, por decisión expresa del titular. La página no inventa estos datos ni declara cumplimiento integral.
- Apple/iOS: integración de identidad extensible; configuración, compilación nativa, firma y pruebas reales pendientes. No se publica en App Store.
- FCM/APNs: no se activan envíos antes de configurar y probar proveedores y dispositivos. La bandeja interna sí existe. La generación de recordatorios ocurre al consultar la bandeja; no hay tarea programada de push.
- Google Play: verificación de cuenta, firma de producción, ficha, política y formulario de datos siguen siendo pasos del titular. El APK preview no es un AAB de producción.
- Pagos: derechos definidos por servidor, sin cobros ni límites comerciales finales.

No se ha publicado esta iteración en GitHub, Render ni tiendas. Los artefactos locales se entregan para revisión y aceptación.
