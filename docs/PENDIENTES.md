# Estado real y trabajo pendiente

La aplicación es ejecutable en web y dispone de APK Android release de prueba, con un catálogo de 12.451 normas y veinte textos BOE incluidos, estudio privado y capacidades de sincronización. **No está terminada al 100 % ni lista para publicación comercial.** La existencia de pantallas, adaptadores y tests no sustituye las aceptaciones de la especificación.

[Avance implementado de 5 de noviembre](AVANCE_V2_2026-11-05.md) · [Pruebas ejecutadas](VALIDACION.md) · [Despliegue propuesto](DESPLIEGUE.md)

## Integraciones y operación pendientes

- Proyecto Firebase `lexmemoria-aa86a` comunicado por el titular, proveedor Google y app Android de pruebas configurados; interfaz Google Android implementada y APK verificado, pendiente de aceptación real en dispositivo. Faltan Apple, Google en iOS/web, firma estable y revocación federada probada con el proveedor. [Estado Google Android](GOOGLE_ANDROID.md).
- FCM/APNs, permisos del sistema, tokens de dispositivo, entrega push, quiet hours y enlaces profundos. La bandeja interna no acredita entrega push.
- Google Play Billing/StoreKit: productos y precios aprobados, comprobación servidor con tiendas reales, webhooks autenticados, restauración, reembolsos, gracia y revocación. El endpoint de compras sigue rechazando compras sin verificar.
- El titular ha creado API y PostgreSQL de pruebas en Render Free y comunicado /health correcto. Pendiente migrar a un plan con conservación/backups adecuados antes de la caducidad de la base gratuita, verificar PostgreSQL y sincronización reales y completar producción. El blueprint sigue siendo una propuesta; el alta fue manual. Faltan dominio propio si se decide usarlo, rate limiting compartido para múltiples réplicas, migraciones completas, backups PostgreSQL, observabilidad, alertas, presupuestos y RPO/RTO aprobados.
- Firma de release, App Store Connect/Google Play Console, pruebas sandbox, AAB/symbols/dSYM y publicación. El APK entregado es release firmado para pruebas; falta una firma estable de distribución. iOS no está compilado en esta máquina Linux.

## Implementación de producto pendiente

- Esquema relacional V2 completo, migraciones, full-text a escala y rendimiento de búsquedas jurídicas complejas. El catálogo móvil de 12.451 normas usa listas por demanda y caché de archivos, pero no es un motor jurídico completo.
- Completar e integrar las descargas europeas y los boletines autonómicos/municipales adicionales y fuentes universitarias. El catálogo BOE ya incluye 3.620 normas autonómicas; los boletines no están archivados íntegramente. Mantener revisión de licencias y declaraciones auditables de cobertura.
- Índices jerárquicos completos; interpretación jurídica de vigencias parciales/transitorias y reformas, referencias cruzadas, correlación con consolidación atrasada y clasificación especializada de eventos. No inferir derogaciones tácitas.
- MFA real y RBAC editorial por tenant, backoffice de cotejo y asignación, auditoría firmada, checklist jurídico, rollback y circuito de resolución de reportes. La recepción de un reporte no implica revisión profesional. No activar `EDITORIAL_MFA_GATEWAY` como sustituto de MFA.
- Corpus educativo validado por profesionales, explicaciones, glosario, resúmenes y casos revisados; no hay material con sello de verificación por el hecho de incluir legislación.
- Convocatorias y temarios oficiales versionados y verificados, mapeo tema-artículo y guías docentes autorizadas. Las plantillas personales no son programas oficiales.
- Resolución avanzada de conflictos de tarjetas entre dispositivos, compensación remota de undo y sincronización granular por entidad. Las revisiones y los conflictos se conservan; no todos los conflictos tienen resolución automática.
- Importación Anki, adjuntos con escaneo/controles, uso compartido y moderación. CSV sigue siendo privado no verificado.
- Planificador por prioridad de temas, tiempo disponible y capacidad horaria; edición avanzada de evaluaciones/temas y mapeo multidisciplinar. La previsión actual no simula futuras respuestas ni garantiza cobertura.
- Copias SQLite cifradas de desarrollo están probadas; faltan backups del proveedor, retención y simulacros operativos de recuperación parcial por entidad en PostgreSQL.

## Validación y decisiones del titular

Faltan SQLCipher/Keychain/Keystore en dispositivos reales, comportamiento multidispositivo con red inestable, TalkBack/VoiceOver, teclado, escalado y rotación en toda la aplicación, pruebas de carga/consumo y auditoría de dependencias/seguridad completa. Un build correcto o una prueba visual de Chromium no acredita estos puntos.

El titular debe concretar presupuesto/región/proveedor, proyecto Firebase, productos/precios, responsable editorial jurídico, convocatorias piloto, identidad del responsable del tratamiento, contacto, menores, RGPD, políticas de conservación y licencias comerciales. Usar ajustes seguros para las credenciales; nunca enviarlas al chat ni guardarlas en Git.

## Seguimiento V3

La [matriz V3](v3/MATRIZ_REQUISITOS.md) y el [plan con aceptación por fase](v3/PLAN_Y_EVIDENCIAS.md) detallan el siguiente incremento 0.4.1. La extracción europea HTML ya puede ejecutarse por lotes en paralelo a la descarga; todavía faltan otros formatos, estructura jurídica y distribución al móvil. Persisten la aceptación nativa/dispositivos, recuperación idempotente si se pierde toda la respuesta de red de un código de recuperación, CVE/seguridad completa y los bloqueos de producción. Ninguna fase completa se da por cerrada.
