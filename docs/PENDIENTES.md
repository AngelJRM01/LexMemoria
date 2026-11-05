# Estado real y trabajo pendiente

La aplicación es ejecutable en web y dispone de APK Android de desarrollo, con veinte normas BOE incluidas, estudio privado y capacidades de sincronización. **No está terminada al 100 % ni lista para publicación comercial.** La existencia de pantallas, adaptadores y tests no sustituye las aceptaciones de la especificación.

[Avance implementado de 5 de noviembre](AVANCE_V2_2026-11-05.md) · [Pruebas ejecutadas](VALIDACION.md) · [Despliegue propuesto](DESPLIEGUE.md)

## Integraciones y operación pendientes

- Proyecto Firebase real, configuración de aplicaciones/Google/Apple, interfaz federada nativa, vinculación y revocación probadas con el proveedor.
- FCM/APNs, permisos del sistema, tokens de dispositivo, entrega push, quiet hours y enlaces profundos. La bandeja interna no acredita entrega push.
- Google Play Billing/StoreKit: productos y precios aprobados, comprobación servidor con tiendas reales, webhooks autenticados, restauración, reembolsos, gracia y revocación. El endpoint de compras sigue rechazando compras sin verificar.
- Render/hosting y PostgreSQL administrado contratados/configurados por el titular. El blueprint es revisable y no ha sido desplegado. Faltan dominio/TLS público, rate limiting compartido para múltiples réplicas, migraciones completas, backups PostgreSQL, observabilidad, alertas, presupuestos y RPO/RTO aprobados.
- Firma de release, App Store Connect/Google Play Console, pruebas sandbox, AAB/symbols/dSYM y publicación. El APK entregado es debug. iOS no está compilado en esta máquina Linux.

## Implementación de producto pendiente

- Esquema relacional V2 completo, migraciones, full-text a escala y rendimiento con 10.000 normas. El índice de catálogo actual no es un motor jurídico completo.
- Conectores autonómicos/EUR-Lex/municipales y fuentes universitarias, revisión individual de licencias y declaraciones auditables de cobertura.
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
