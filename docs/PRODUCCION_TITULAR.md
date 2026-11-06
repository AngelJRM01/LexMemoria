# Puesta en marcha: datos y pasos del titular

Proyecto Firebase comunicado: **lexmemoria-aa86a**. Es un identificador público, no una credencial ni una prueba de acceso a la consola. El titular confirma que Render tiene acceso a AngelJRM01/LexMemoria. No se ha creado ni contratado ningún servicio desde este entorno.

## Paso actual: seleccionar PostgreSQL

En Render abrir **New → PostgreSQL** y preparar:

| Campo | Valor |
| --- | --- |
| Name | lexmemoria-db |
| Database | lexmemoria |
| User | lexmemoria |
| Region | Frankfurt, si está disponible; API y base en la misma región |
| Plan | Revisar el menor plan de pago y su precio vigente antes de crear |

El presupuesto sigue sin estar elegido y los precios actuales no se han podido consultar desde este entorno. El titular debe confirmar nombre del plan e importe mostrado; crear el recurso puede generar cargos. Las condiciones de copias, retención, almacenamiento, impuestos y suspensión se revisan en el plan elegido. No asumir que un plan gratuito ofrece conservación o recuperación adecuadas para producción.

Después de crear la base elegida, su **Internal Database URL** se introduce directamente en la variable segura DATABASE_URL del servicio Render correspondiente. No pegarla en el chat, capturas públicas ni GitHub. No se necesita para comunicar la selección del plan.

## Servicio API, después de revisar coste y base

Conectar el repositorio en un Web Service con rama main y root directory backend; región igual a PostgreSQL. Los comandos están preparados en render.yaml:

- Build: `pip install -r requirements.lock`.
- Start: `uvicorn app.main:app --host 0.0.0.0 --port $PORT --workers 1 --no-access-log`.
- Health check: `/health`.
- LEXMEMORIA_ENV: `production` en el blueprint; para aceptación previa puede usarse `staging`, con la misma exigencia de PostgreSQL.
- DATABASE_URL: conexión privada, introducida en Render como secreto.
- FIREBASE_PROJECT_ID: `lexmemoria-aa86a`.
- CORS_ORIGINS: orígenes web exactos cuando exista cliente web; vacío para la prueba inicial exclusivamente móvil/HTTP sin navegador cruzado.
- Despliegue automático desactivado durante la preparación.

El blueprint también contiene un cron BOE separado, con coste propio: revisar cada recurso antes de aplicar el blueprint. La creación inicial de cuenta en Render no despliega esos servicios automáticamente. No hace falta contratar todos los recursos a la vez para validar la API.

Se añade protección para que staging/production rechace una DATABASE_URL ausente, malformada o SQLite en vez de guardar progreso en el disco efímero del servidor. Las pruebas de configuración no conectan a PostgreSQL real y no acreditan su aceptación. Tras el despliegue se probarán salud, persistencia después de reinicio, cuentas aisladas, copias/restauración y sincronización con datos de prueba antes de usuarios reales.

## Firebase y plataformas, siguiente bloque

Crear el proyecto no activa Google/Apple. Hay que habilitar Authentication, configurar proveedores y aplicaciones, orígenes autorizados y los certificados correctos. La app Android de producción usa provisionalmente es.lexmemoria.app y la de pruebas es.lexmemoria.app.preview: no registrar una como si fuese la otra. Confirmar identificadores definitivos y firma estable antes de configurar certificados de producción.

El acceso nativo federado todavía requiere implementación e integración del cliente y pruebas con este proyecto. No es necesario crear Firestore para el modelo actual, que guarda progreso en PostgreSQL. No entregar al chat contraseñas, claves privadas, service-account JSON ni archivos de firma. Los datos públicos que sí pueden comunicarse son ID de proyecto, URL pública de API, región, plan y precio.

## Validación de esta preparación

132 pruebas backend aprobadas, incluidas 12 comprobaciones de configuración productiva. Las pruebas de URLs/driver usan mocks y no representan una conexión PostgreSQL real. Blueprint parseado y revisado: ID público correcto, región común y DATABASE_URL sin valor en Git. No se han desplegado ni contratado servicios.
