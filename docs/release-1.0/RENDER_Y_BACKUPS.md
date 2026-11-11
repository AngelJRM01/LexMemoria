# Render y PostgreSQL — comprobación y recuperación sin sobrescritura

## Evidencia disponible

El código exige PostgreSQL en staging/production, no permite fallback SQLite efímero y devuelve dialecto y proyecto público en /health. La publicación pública está desactivada por defecto mediante PUBLIC_DECK_PUBLICATION_ENABLED=false y render.yaml lo hace explícito. El blueprint es una propuesta, no prueba de lo aplicado en tu consola.

En esta revisión, la consulta HTTPS pública a /health no pudo atravesar el proxy del entorno. No hay credenciales Render ni DATABASE_URL productiva disponibles. No se ha conectado ni modificado la base real. No se da por desplegada la 1.0 ni por comprobado su estado Live.

Se ha probado con PostgreSQL 18 local aislado: dos propietarios, idempotencia de repaso, conflictos de workspace, reinicio, copia cifrada, comparación de todas las tablas tras restaurar, API restaurada, rechazo del origen/destino ocupado y rechazo de copia manipulada antes de escribir. Evidencia: evidence/postgresql-integrity.json. Las claves y archivos sintéticos de backup del ensayo fueron temporales y no son claves del titular.

## Comprobar personalmente en Render

1. API lexmemoria-api y base lexmemoria-db: región, estado, plan y fecha de vencimiento actuales. El panel anterior mostraba 6/12/2026 para PostgreSQL Free; hay que verificarlo de nuevo.
2. Commit Live: debe corresponder a la entrega 1.0 aceptada; root backend, instalación requirements.lock, comando Uvicorn del blueprint y health /health.
3. Variables seguras: LEXMEMORIA_ENV=production, DATABASE_URL interna de PostgreSQL, FIREBASE_PROJECT_ID=lexmemoria-aa86a, PUBLIC_DECK_PUBLICATION_ENABLED=false. No pegar valores secretos en chat ni GitHub.
4. /health: status ok, versión 1.0.0, database postgresql, proyecto correcto y publicDeckPublicationEnabled false. Esta comprobación no prueba sincronización ni backups.
5. Reglas de acceso externo a PostgreSQL: revisar si todavía existe 0.0.0.0/0 y restringir según los clientes de administración/backup realmente necesarios; no cortar la ruta usada antes de asegurar una alternativa.
6. Con datos sintéticos: sincronizar, reiniciar la API y recuperar desde un segundo cliente. No reiniciar ni migrar como prueba sin copia previa del progreso único.
7. Backups del proveedor, retención y restauración disponibles en el plan elegido. API y PostgreSQL tienen planes independientes. No se ha cambiado ni contratado un plan.
8. Dominios Firebase web y configuración de /account/delete; contacto y política /account/privacy.

## Preparación de una copia propia cifrada

Requisitos: cliente pg_dump/pg_restore de la versión mayor compatible (el panel indicaba PostgreSQL 18), Python y dependencias del backend, espacio y ubicación protegida. La URL de origen se configura en DATABASE_URL mediante el mecanismo seguro del equipo/servidor. No escribirla en argumentos, logs o repositorio.

La clave del backup se genera y custodia en el equipo del titular fuera del repositorio, en una ubicación con permisos restringidos. El programa requiere 32 bytes aleatorios. No se necesita compartir esa clave con el chat. Guardar una copia custodiada separada del backup; perderla impide restaurar.

Desde backend:

`python -m app.postgres_backup backup /ruta/protegida/lexmemoria-fecha.lexbackup --key-file /ruta/custodia/backup.key`

El archivo no se sobrescribe si ya existe. El backup es cifrado y autenticado AES-256-GCM. pg_dump lee una instantánea consistente; no debe usarse el disco efímero del servicio como única ubicación de conservación.

## Restauración de ensayo

Crear una base NUEVA y VACÍA, distinta del origen. Configurar su URL como LEXMEMORIA_RESTORE_DATABASE_URL; DATABASE_URL mantiene el origen para la protección. No reemplazar primero la URL de la API activa. Desde backend:

`python -m app.postgres_backup restore /ruta/protegida/lexmemoria-fecha.lexbackup --key-file /ruta/custodia/backup.key`

El programa autentica el archivo, valida su formato, rechaza destino ocupado y restaura con transacción única y exit-on-error. Nunca utiliza --clean ni elimina la base de origen. Aun así, la elección de un destino realmente separado debe comprobarla el operador.

Comparar conteos, datos sintéticos conocidos, integridad de relaciones, tarjetas/repasos/notas y acceso aislado desde una API de ensayo conectada SOLO a la base restaurada. Registrar fecha, versión, tamaño/hash, resultado y duración sin credenciales. No activar la base restaurada automáticamente ni reutilizar sus sesiones en un entorno público de ensayo.

## Decisiones operativas pendientes

Aprobar frecuencia, retención, ubicación separada, permisos, responsable de alertas y tiempo/pérdida de datos tolerables. Propuesta inicial para estudiar: copia diaria y ensayo periódico; estos valores son una propuesta y no un servicio ya activo. Antes de cobrar o aceptar usuarios reales, implantar y verificar lo acordado.
