# Matriz de requisitos — cuentas, personalización y colaboración

Fecha: 6 de noviembre de 2026. Alcance: `SOLICITUD.md`, sobre el código local 0.6.0. No equivale a despliegue ni aceptación en producción.

Estados: **IP** = implementado y probado en el entorno indicado; **IA** = implementado, pendiente de aceptación con servicios/dispositivos reales; **P** = parcial; **PD** = pendiente; **BT** = bloqueado por datos, decisión o acceso del titular. Una prueba con proveedores simulados no se contabiliza como aceptación de Google, Apple o Render.

La evidencia ejecutable está en `backend/tests`, `mobile/test`, `mobile/integration_test/startup_test.dart` y los informes de esta carpeta. Los contratos completos están en `openapi-0.6.0.json`; operación, migraciones y límites en `ARQUITECTURA_Y_OPERACION.md`.

## 1–3. Producto, diseño y modalidades

| ID | Requisito | Estado | Evidencia / límite |
| --- | --- | --- | --- |
| D01 | Cinco destinos Inicio, Estudiar, Biblioteca, Actualidad y Perfil | IP | `shell.dart`; colaboración mediante rutas secundarias |
| D02 | Estudio prioritario, sin feed, chat, seguidores ni rankings obligatorios | IP | `collaboration.dart`, prueba de invitado y navegación existente |
| D03 | Interfaz progresiva y opciones de cuenta agrupadas | IA | Perfil y grupos mediante Details; revisión visual en móvil físico pendiente |
| D04 | Estudiar, legislación, descargas y ejercicios sin cuenta | IP | Código y suites existentes de estudio, lector, corpus y ejercicios; sin intercambio de identidad al usar perfil local |
| D05 | Notas, asignaturas, simulacros y copia local sin correo | IP | `planning.dart`, `store.dart`, `backup.dart`; suites locales |
| D06 | Explicar pérdida de datos al desinstalar y copia JSON legible | IP | Cuenta y copias conserva avisos; no exige registro para exportar |
| D07 | Cuenta gratuita con recuperación y colaboración opcional | IA | API y Flutter implementados; aceptación Google/Render multidispositivo pendiente |
| D08 | Free / Estudiante Plus / Opositor Pro | IP | Entitlements del servidor; caducidad no borra datos ni retira estudio básico |
| D09 | Sin cobros ni límites comerciales no autorizados | IP | No se incorpora SDK de pagos ni bloqueo educativo por variable Premium local |
| D10 | Android, iOS y web | P | Android release compilado y pruebas nativas en emulador; Flutter compartido; iOS nativo y Google web requieren configuración/pruebas |
| D11 | Reutilizar identidad, editor, permisos, revisiones y almacenamiento | IP | Se reutilizan Firebase, `Record`, CardEditor, SM2, componentes de búsqueda y almacén existente |

## 4. Identidad y sesiones

| ID | Requisito | Estado | Evidencia / límite |
| --- | --- | --- | --- |
| I01 | Inicio Google y vinculación con invitado | IA | SDK existente endurecido, verificación de identidad API; pruebas criptográficas locales y de cliente; falta proveedor real |
| I02 | Inicios repetidos, caducidad, renovación y mala conexión | IP | `remote_test.dart`, `test_identity_backup.py`, sesiones API; tokens en vault, actualización por pareja |
| I03 | Cambio de cuenta sin mezcla silenciosa | IP | Confirmación y ámbito cuenta/servidor; se reinician mapas y consentimientos automáticos |
| I04 | Cierre de sesión actual preserva datos educativos | IP | Familia de sesión revocada; mensaje de conservación local; pruebas de familias |
| I05 | Sesiones activas, última actividad aproximada y fecha de cuenta | IP | `/account/security`, AccountSecurityPage; no se promete modelo exacto de dispositivo |
| I06 | Revocar una sesión y cerrar otras conservando la actual | IP | `test_accounts.py`; sesiones heredadas sin familia se identifican como tales |
| I07 | Credenciales vinculadas y desvinculación segura | IA | Backend impide retirar último acceso sin recuperación; identidad fresca; prueba real de proveedor pendiente |
| I08 | Recuperación mediante código y respuesta perdida | IP | Recibo cifrado idempotente, intento persistido antes de enviar; tests de servidor y cliente |
| I09 | Recuperar con Google en otro teléfono real | BT | Titular no ha confirmado Live ni probado dos dispositivos; no se afirma aceptación |
| I10 | Interfaz extensible para otros proveedores | IP | FirebaseVerifier/ExternalIdentity y contratos de proveedor existentes; sin contraseña propia |
| I11 | Sign in with Apple operativo | BT | Decisión/configuración del titular y equipo Apple; no se activa ahora |

## 5. Perfil y privacidad de identidad

| ID | Requisito | Estado | Evidencia / límite |
| --- | --- | --- | --- |
| P01 | UID estable, nombre, alias opcional y fecha de creación | IP | Perfil API/Flutter; cuenta independiente del alias |
| P02 | Alias normalizado, longitud, caracteres, unicidad y reservados | IP | `test_accounts.py`, restricciones SQL y 409 en carrera |
| P03 | Cambiar alias con protección frente a suplantación | IP | Retención de alias retirado 30 días; recuperación permitida al titular original |
| P04 | Iniciales y avatares predeterminados | IP | Perfil local y conectado; no exige fotografía |
| P05 | Foto propia opcional, privada y sin EXIF | IP | Pillow, formato real, límite de bytes/píxeles, recodificación; pruebas de imágenes falsas y metadatos |
| P06 | Foto de Google con consentimiento y sin URL de seguimiento | IA | Endpoint de importación solo desde identidad propia fresca y host permitido; prueba real Google pendiente |
| P07 | Tema claro, oscuro o sistema | IP | Mi perfil es el editor de apariencia; sincronización canónica separada del plan académico |
| P08 | Idioma preferido | P | Español persistido; no hay catálogo de traducciones a otros idiomas |
| P09 | Objetivo educativo y perfil académico opcionales | IP | Planificador existente: universidad/oposición/ambos/otros, asignaturas y objetivos; se conserva privacidad |
| P10 | No pedir datos sin utilidad | IA | Campos académicos opcionales y navegación progresiva; evaluación de uso por personas pendiente |
| P11 | Descubrimiento por alias y enlaces reversible y apagado por defecto | IP | Dos opciones independientes, verificadas por backend; pruebas de usuarios no descubribles |
| P12 | Validación de contenido visual inapropiado | P | Validación técnica de imagen implementada; no existe clasificación automática ni revisión humana de fotografías |

## 6. Sincronización y recuperación

| ID | Requisito | Estado | Evidencia / límite |
| --- | --- | --- | --- |
| S01 | Mazos, tarjetas, versiones y referencias jurídicas | IP | Export/pull, lookup por clientId y revisiones; pruebas con contenido privado de referencia todavía no importada |
| S02 | Eventos, SM2, errores, progreso y favoritos individuales | IP | Estado privado por cuenta, eventos idempotentes y reconstrucción; compartición nunca entrega progreso ajeno |
| S03 | Perfil y preferencias de cuenta | IP | Perfil canónico con If-Match y base local; no se duplica autoridad dentro del workspace |
| S04 | Objetivos, cursos, temas, notas y normas seguidas | IP | Workspace versionado; mezcla a tres bandas y comparación de secciones |
| S05 | Marcadores, punto de lectura y simulacros | IP | Workspace ampliado; cliente antiguo conserva secciones omitidas; prueba Flutter incluye lectura/favoritos/historial |
| S06 | No duplicar paquetes públicos en copia privada | IP | Workspace excluye corpus público; referencias a legislación separadas |
| S07 | Estados claros y último resultado confirmado | IP | progressStatus, colas y fecha; no éxito antes de identidad/respuesta comprobadas |
| S08 | Primera sincronización explícita | IP | Cuenta y copias; interruptores posteriores separados y confirmación |
| S09 | Automatización voluntaria de progreso y workspace | IP | AutoSyncHost, consentimiento ligado a cuenta/servidor, consultas ligeras y colas persistentes; pruebas locales |
| S10 | Automatización permanente con app cerrada | PD | No se promete; solo primer plano. No se instala un servicio nativo de background |
| S11 | Reintentos, reconexión y duplicados | IP | Espera creciente, Retry-After, claves idempotentes y lookup; tests de respuesta perdida |
| S12 | Conflicto de tarjeta resoluble conservando ambas | IP | SyncConflictsPage y copia local con IDs/historial propios; conserva eventos pendientes |
| S13 | Conflicto de notas/plan y ediciones simultáneas | IP | Merge a tres bandas; no PUT si misma sección diverge; elección explícita y copia histórica |
| S14 | Edición remota sin edición local no produce falso conflicto | IP | Nueva prueba `a remote-only card edit...` |
| S15 | Guardado local atómico y cambio de cuenta durante petición | IP | commitRemotePull/commitWorkspace con comparación previa; prueba de disco lleno conserva todos los campos |
| S16 | Backup no otorga sesión ni consentimientos automáticos | IP | Se eliminan tokens, mapas de nube, bases y autoridad de colas al restaurar |
| S17 | Reinicio de servidor conserva progreso en PostgreSQL | IP | `postgres-local.json`, instancia local PostgreSQL 18; no Render |
| S18 | Caso obligatorio completo en dos dispositivos reales con Google | BT | Falta aceptación del titular/servicio real; las pruebas automatizadas no lo sustituyen |

## 7–8. Contactos y mazos compartidos

| ID | Requisito | Estado | Evidencia / límite |
| --- | --- | --- | --- |
| C01 | Buscar por alias exacto, sin directorio ni correos | IP | Contactos API, filtros exactos y privacidad por defecto |
| C02 | Solicitud, aceptación, rechazo y cancelación | IP | Invitaciones por destinatario/link y pruebas de flujo |
| C03 | Eliminar contacto y bloquear | IP | Relaciones privadas; bloqueo revoca acceso directo e impide enlaces antiguos |
| C04 | Límite persistente de solicitudes y Retry-After | IP | Rate windows por cuenta/acción más control global; probado tras recrear la app |
| C05 | Lista con nombre/alias, avatar básico y acceso a compartir | IP | Compañeros en Perfil, selector paginado de mazos propios |
| C06 | Fotografías en listas de contactos | P | Se usan iniciales/iconos; la fotografía privada no se expone a otros usuarios |
| M01 | Mazo privado por defecto | IP | ACL de propietario y API privada; no basta esconder botones |
| M02 | Invitación con lector/editor/propietario independiente | IP | Permisos centralizados y pruebas de edición no autorizada |
| M03 | Publicación explícita en catálogo | IP | Confirmación y cola de revisión; retirada por propietario |
| M04 | Lectura y estudio con progreso personal | IP | Previsualización compartida y copia personal editable; sin historial de terceros |
| M05 | Copia con atribución, IDs propios y fuentes | IP | Copia idempotente y prueba de eliminación de cuenta original |
| M06 | Copia no cambia automáticamente | IP | Actualizaciones comparadas/confirmadas; respeta tarjetas modificadas personalmente |
| M07 | Actualizaciones conservan versiones y progreso | IP | Historial, If-Match y conflictos; hooks cubren cambios desde procesadores |
| M08 | Enlaces difíciles de adivinar y secreto no persistido en claro | IP | Digest, fragmento URL, sin contenido privado en landing |
| M09 | Revocación, caducidad opcional y usos limitados | IP | Pruebas SQLite y PostgreSQL; una invitación de un uso concurrente acepta solo a una cuenta |
| M10 | Compartir mediante aplicaciones del dispositivo | IA | SharePlus por acción explícita; aceptación WhatsApp/correo en teléfono pendiente |
| M11 | Página web al no tener app y aceptación pegando enlace | IP | Landing informativa sin vista privada; formulario en app |
| M12 | Apertura automática de app con enlace verificado | PD | No hay Android App Links/universal links operativos; se ofrece copiar/pegar |
| M13 | Acceso remoto retirado tras revocar | IP | ACL vuelve a comprobar membresía/bloqueo; no promete borrar copias legítimas ya descargadas |

## 9–10. Grupos y catálogo

| ID | Requisito | Estado | Evidencia / límite |
| --- | --- | --- | --- |
| G01 | Crear/editar grupo privado con nombre, descripción, icono, tema y tipo | IP | Group form/API, tipos general/universidad/oposición |
| G02 | Invitar, unirse, salir y expulsar | IP | Roles backend y pruebas PostgreSQL reales locales |
| G03 | Administrador, colaborador y miembro | IP | Cambio de roles, emisor vigente y límites de administración |
| G04 | Compartir y retirar mazos propios | IP | Recursos del grupo; retiro no elimina la copia personal del propietario |
| G05 | Organizar recursos por tema | IP | Tema opcional al compartir y visualización en lista |
| G06 | Compartir archivos/materiales arbitrarios | P | Se comparte material en forma de mazos; no se añade almacenamiento general de PDF/archivos |
| G07 | Eliminar grupo conserva mazos personales | IP | Prueba de grupo y revocación, cascadas controladas |
| G08 | Notas, estadísticas y calificaciones privadas | IP | Endpoints compartidos usan whitelist; no se implementa ranking ni publicación de notas |
| G09 | Compartir objetivos resumidos por consentimiento específico | PD | Propuesto para más adelante; no se activa ni se infiere consentimiento |
| K01 | Catálogo secundario sin nueva pestaña | IP | Acceso desde Estudiar/colaboración |
| K02 | Búsqueda, materia, norma y paginación con filtro persistente | IP | SearchPageBody y cursor, también para mazos propios y selector de recursos |
| K03 | Filtro por oposición verificada | BT | No hay correspondencias verificadas de mazos comunitarios; no se inventan |
| K04 | Autor, tarjetas, fecha, preview, copia y denuncia | IP | Endpoints y páginas de catálogo/SharedDeckPage |
| K05 | Diferenciar usuario, automatizado, oficial y revisión editorial | IP | Procedencia y mensaje de contenido de usuario no certificado; moderación no altera aprobación jurídica |
| K06 | Revisión humana real de contenido público | BT | Herramientas creadas; faltan equipo, criterios operativos y gateway MFA real |

## 11–12. Planificación y avisos

| ID | Requisito | Estado | Evidencia / límite |
| --- | --- | --- | --- |
| E01 | Objetivo diario, descanso, vacaciones y examen | IP | Planificador existente y datos sincronizables |
| E02 | Horas disponibles, asignaturas y temas | IP | Perfil académico y cursos; capacidad estimada por tiempo configurado |
| E03 | Prioridades de mazos y tipos de ejercicio preferidos | IP | Planificador ampliado, mantiene vencidas antes de preferencias |
| E04 | Calendario útil y previsión de carga | IP | Previsión semanal y minutos estimados; no predice aptitud para aprobar |
| E05 | Recomendación adaptativa validada pedagógicamente | P | Orden basado en SM2, vencimientos, preferencias y tiempo; sin validación de eficacia educativa |
| N01 | Categorías estudio/jurídica/colaboración independientes | IP | Perfil y bandeja opcionales, colaboración apagada por defecto |
| N02 | Silencio y límite diario | IP | Silencio Europe/Madrid y cupo configurado; también avisos jurídicos con perfil canónico |
| N03 | Invitaciones y cambios de permisos | IP | Avisos genéricos sin datos académicos privados |
| N04 | Actualización jurídica y posible desactualización | IP | Flujo legal existente, sin afirmar consecuencias jurídicas personales |
| N05 | Repasos/examen próximo al consultar bandeja | IP | Recordatorios internos vinculados al plan, descanso y vacaciones |
| N06 | Recordatorio exacto de objetivo completado / planificación pendiente | P | El recordatorio se suprime al cumplir el objetivo diario; planificación pendiente sigue siendo aviso genérico y no hay notificador programado |
| N07 | Push FCM/APNs real y permiso del sistema | BT | No se activa sin configuración y pruebas reales; UI lo indica expresamente |
| N08 | Avisos cuando la app está cerrada | PD | No hay programador externo activado; bandeja no equivale a push |

## 13–15. Privacidad, moderación y derechos

| ID | Requisito | Estado | Evidencia / límite |
| --- | --- | --- | --- |
| V01 | Autorización por recurso, membresía y aislamiento | IP | Pruebas de acceso cruzado y revocación SQLite/PostgreSQL |
| V02 | Exportación de datos y JSON legible advertido | IP | Exportación API/local y exclusión de secretos; copia local contiene datos legibles |
| V03 | Exportación local cifrada opcional | PD | Se ha implementado cifrado del backup PostgreSQL; el JSON de usuario sigue siendo legible |
| V04 | Eliminación de cuenta y anonimización asociada | IA | API y flujo móvil/web; copia ajena se conserva sin identificación del autor; falta Google real |
| V05 | Reintentar borrado de identidad después de fallo de red | IP | Marcador durable ligado a identidad/cuenta/servidor; prueba de preflight y repetición |
| V06 | Vía web de eliminación lista para dominio real | BT | HTML preparado; falta configurar API key pública web y dominio autorizado en Firebase, y aceptación SDK |
| V07 | Política de privacidad con responsable y correo reales | BT | Titular pidió dejarlo pendiente; endpoint no inventa datos |
| V08 | Retención, custodia de backups y revisión legal | BT | Procedimiento técnico documentado; política y revisión profesional requieren responsable |
| V09 | Registros sin tokens, secretos o fotografías | IP | Pruebas/no exposición, solo digests; HMAC de personal no se muestra al usuario |
| V10 | Bloqueo, denuncia y apelación | IP | Endpoints, páginas secundarias y auditoría |
| A01 | Reportes clasificados, severidad, triage y decisiones | IP | ModerationPage/API; pruebas con gateway de prueba explícito |
| A02 | Revisar/ocultar publicaciones y restricciones justificadas | IP | Razón y auditoría; estudio/exportación privada siguen accesibles |
| A03 | Revisión administrativa fuerte en producción | BT | Prueba de gateway MFA obligatorio implementada; proveedor/gateway real no configurado |
| A04 | Incidencias técnicas desde reportes y diagnóstico | P | Reportes y diagnóstico existentes; no hay integración externa con mesa de soporte |
| A05 | Separar moderación y validación jurídica | IP | Estados y permisos distintos; admisión no certifica Derecho |
| F01 | Derechos y vencimiento controlados por servidor | IP | API, asignación administrativa auditada y planes configurables |
| F02 | No borrar datos ni bloquear recuperación al caducar Premium | IP | Capacidades educativas/core y exportación no dependen de vigencia comercial |
| F03 | Cobros y límites comerciales definitivos | BT | No autorizados ni definidos; intencionadamente inactivos |

## 17–20. Arquitectura, aceptación y entrega

| ID | Requisito | Estado | Evidencia / límite |
| --- | --- | --- | --- |
| T01 | Entidades equivalentes reutilizando dominio | IP | Mapeo y tablas en documento de arquitectura; no segundo sistema de identidad |
| T02 | FKs, unicidad y concurrencia en invitaciones | IP | Restricciones y bloqueo transaccional; resultado concurrente PostgreSQL 200/404 |
| T03 | Revisión optimista de contenidos y perfil | IP | If-Match, historial e idempotencia de respuesta perdida |
| T04 | Paginación y control de carga | IP | Listas principales, miembros y recursos de grupo paginados; copia máx. 2000 tarjetas por operación |
| T05 | Esquema aditivo sin destrucción de datos | IP | Creación bajo lock; rollback conservando tablas; futuras ALTER requieren migración versionada |
| T06 | PostgreSQL real, backup y restauración | IP | Informes locales PostgreSQL 18, backup cifrado, archivo alterado y destino poblado rechazados |
| T07 | Despliegue Render que resuelve 422 y aceptación Live | BT | Titular no está seguro; la API local acepta cita privada no importada pero no prueba Render |
| T08 | Migración/persistencia Android nativa | IP | Dos pruebas de SQLCipher/Keystore reales en emulador Android 15; no OPPO físico |
| T09 | Baterías automatizadas | IP | 174 servidor; 107 Flutter; análisis limpio; pruebas PostgreSQL y nativas registradas |
| T10 | APK release de pruebas con Google | IP | 0.6.0+9, paquete preview, sin debuggable y firma compatible verificada; `apk-0.6.0.json` |
| T11 | Compilación y aceptación web/iOS completas | P | Flutter web comprobable; Google web/iOS y dispositivos Apple no aceptados |
| T12 | Matriz, contratos, arquitectura, riesgos y operación | IP | Esta carpeta, OpenAPI y documentación de operación |
| T13 | Auditoría profesional de seguridad, accesibilidad y Derecho | BT | No se afirma certificación; requiere revisión independiente y responsables |
| T14 | Publicación en GitHub/Render/Play | PD | Esta iteración permanece local; no se ha publicado entorno ni servicio |

## Escenarios obligatorios y límites de la evidencia

- **Identidad:** invitado, vinculación/conflicto, refresh, revocación, cierre y aislamiento están cubiertos por suites. Google real en dos dispositivos no está aceptado.
- **Sincronización:** subida, pull, datos offline, reintentos duplicados, conflictos, fallo de disco, respuesta perdida, restauración y separación de cuentas tienen pruebas. Persistencia tras recrear aplicación y restauración de base se han ejecutado en PostgreSQL local.
- **Contactos:** solicitudes, aceptación/rechazo/cancelación, bloqueo, no descubrible y abuso cubiertos por API; Flutter tiene pruebas de opcionalidad, no un recorrido E2E de dos personas reales.
- **Mazos:** permisos lector/editor, copia, revocación, origen eliminado, privacidad e historial cubiertos. La actualización legal se prueba con fuentes/ficheros de prueba; no equivale a revisión jurídica humana de reformas reales.
- **Grupos:** crear/invitar/unirse/salir/expulsar/roles/borrar/retirar y acceso cruzado cubiertos en servidor SQLite y PostgreSQL local.
- **Privacidad:** exportación, eliminación API, imagen maliciosa, permisos y retirada de acceso cubiertos. Borrado Firebase, retención de backups y política pública tienen dependencias externas explícitas.

No es correcto declarar «100 % terminado en producción». Los bloqueos externos y las funciones parciales permanecen visibles, sin confundir una pantalla o un mock con aceptación real.
