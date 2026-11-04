# Trabajo pendiente para cumplir íntegramente la especificación V2

Esta entrega contiene código funcional del servidor y código cliente pendiente de compilación. No satisface todavía todos los requisitos del documento. Los bloqueos externos no eliminan el trabajo de implementación que queda.

## Bloqueos actuales del entorno

1. `storage.googleapis.com`: el proxy deniega la descarga del Dart SDK (HTTP CONNECT 403). La adición está guardada en el borrador, pendiente de aplicarse en ajustes. Sin Dart no se han podido resolver paquetes, analizar tipos, ejecutar Flutter ni compilar APK.
2. `www.boe.es` y `boe.es`: destinos añadidos al mismo borrador para las importaciones reales. Falta comprobar acceso una vez aplicados. Los tests del conector usan fixtures sintéticos, no acreditan compatibilidad con el BOE en vivo.
3. Android SDK no instalado; iOS requiere macOS/Xcode y firma. No hay artefacto APK/IPA entregado.

## Implementación restante

- Corpus real de 20 normas importado/cotejado, índices jerárquicos completos y ELI, versiones parciales, resolver vigencias parciales y disposiciones transitorias sin inferencias. La consulta histórica ya selecciona por fechas efectivas explícitas y rechaza fechas ausentes/conflictivas; no sustituye una interpretación jurídica.
- Esquema relacional completo V2, migraciones, full-text indexado con tildes, paginación cliente, partición e inventario de cobertura por fuente, jurisdicción y materia.
- Conectores autonómicos, EUR-Lex, fuentes universitarias y licencias. No hay catálogo municipal ni cobertura total.
- Ingesta masiva reanudable, cola persistente, checkpoints/backfill, circuito de fallos, clasificación del sumario, correlación de normas modificadoras con consolidados, alertas por consolidación atrasada y entrada en vigor futura.
- Frontend editorial completo, autenticación MFA real, RBAC por tenant, auditoría firmada, checklist jurídico, rollback editorial y revisión por profesionales. La API editorial permanece deshabilitada; `EDITORIAL_MFA_GATEWAY` es una salvaguarda de desarrollo, **no implementa ni verifica MFA** y no debe habilitarse en un servidor público.
- Edición de tarjetas con revisiones inmutables y reconciliación en varios dispositivos; sincronización bidireccional completa, recuperación de identidad, OAuth/email, conflictos en notas/planes y descargas cifradas SQLite. Actualmente preferencias JSON locales y tokens seguros separados; el texto y las notas no incorporan cifrado adicional.
- Ejercicios estructurados de ordenación y verdadero/falso (ahora son autoevaluados), glosario, resúmenes revisados, material débil, favoritos de tarjetas, undo remoto compensatorio, informes enviados al equipo. Los reportes actuales son locales.
- Importación Anki y adjuntos, escaneo de archivos, controles de uso compartido, moderación y licencias por documento. CSV se importa solo como contenido privado no verificado.
- Programación de recordatorios/push APNs/FCM, preferencias de canales/quiet hours, deduplicación de entregas y enlaces profundos. No se solicitan permisos push inexistentes.
- Convocatorias oficiales y temarios verificables, mapa tema-artículo, asignaturas con evaluaciones/ponderaciones, semestres archivables, bibliografía licenciada, exámenes oficiales contrastados. Las oposiciones actuales son plantillas genéricas etiquetadas.
- Planificación avanzada por prioridad de temas y capacidad horaria. Ya se guardan vacaciones y descansos, la cola diaria los respeta y se muestra una previsión de siete días con pendientes acumulados. La previsión todavía no simula futuras respuestas ni revisiones nuevas.
- Compras Google Play/StoreKit, productos y precios con impuestos, entitlements autoritativos completos, restauración, webhooks firmados/deduplicados, reembolsos, gracia y revocación. El endpoint de validación rechaza compras hasta configurar integraciones; no hay botón de compra engañoso.
- Registro del responsable, contacto y textos legales finales, inventario RGPD, política de menores, conservación/borrado de backups y revisión de licencias. Los avisos actuales describen el comportamiento de desarrollo.
- Infraestructura dev/staging/prod, TLS público, cifrado de discos/backups, gestor de secretos, despliegue, colas/cron administrados, backup/restore operativo, observabilidad sin PII, alertas, SBOM/escaneo, límites de coste y recuperación RPO/RTO.
- QA de accesibilidad real con TalkBack/VoiceOver, textos 200%, rotaciones, teclado y dispositivos; rendimiento con 10.000 normas, prueba multidispositivo y todas las aceptaciones LEG/EDU/UX/PAY/SEC/OPS del documento. Una comprobación de sintaxis no valida estos puntos.
- Firmas, AAB, symbols/dSYM y publicación con cuentas de desarrollador. No se han creado cuentas, contratado servicios ni enviado comunicaciones.

## Configuración y decisiones del titular

Hacen falta cuentas de tiendas, proveedor de hosting/PostgreSQL/colas/almacenamiento, identidad/OAuth, Firebase/APNs, presupuestos, productos/precios finales, revisión jurídica y licencias. No se deben enviar secretos en el chat; deben configurarse en el gestor seguro correspondiente. El documento deja estas decisiones expresamente abiertas.
