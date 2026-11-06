# LexMemoria: especificaciones implementadas y pendientes

Fecha de revisión: **6 de noviembre de 2026**. Versión examinada: **0.4.0+6**, código `2604a1a` en `main`.

Este inventario describe el código y la evidencia disponibles, contrastados con la especificación maestra V2. El documento V2 expresa objetivos, no funcionalidades que deban darse por terminadas. Tampoco se considera operativo un servicio por tener una pantalla, un adaptador o pruebas simuladas. No se asigna un porcentaje global de finalización: hay requisitos con pesos y estados distintos.

**Estados utilizados:**

- **Implementado localmente:** existe el flujo en el cliente; se indican sus límites y validación.
- **Implementado con servidor:** hay cliente/API o infraestructura de código, pero requiere desplegar/configurar el servidor para uso real.
- **Parcial:** existe una parte, pero faltan funciones, integración o aceptación.
- **Pendiente:** no está disponible de extremo a extremo.

## 1. Plataformas, navegación y presentación

**Implementado localmente**

- Cliente Flutter con proyectos Android, iOS y web. Compilaciones Android release y web release generadas para esta versión. El proyecto iOS existe, pero no se ha compilado ni validado aquí.
- Interfaz en español y modo claro/oscuro; tipografía del sistema.
- Cinco destinos principales: Inicio, Estudiar, Biblioteca, Actualidad y Perfil.
- Navegación inferior en móvil y lateral en anchos de al menos 900 píxeles lógicos.
- Bienvenida sin registro obligatorio. Objetivos: Leer y repasar, Preparar un examen y Seguir mis asignaturas. Se pueden cambiar en Ajustes conservando datos; no bloquean herramientas según el itinerario.
- Inicio con repasos previstos, objetivo diario, progreso del día y aviso de descanso.
- Contenido secundario en pantallas y secciones desplegables; márgenes inferiores y uso de áreas seguras en los flujos modificados.
- Fechas legibles como día/mes/año y, cuando procede, hora/minutos. Los datos internos conservan precisión para ordenación y sincronización.
- Categorías obtenidas del contenido real: no se ofrecen materias vacías como Criminología. Una preferencia antigua sin contenido no se elimina del archivo del usuario.
- Mensajes de carga, errores, confirmaciones y diagnóstico de arranque sin mostrar claves o datos privados. La lectura fallida del estado no provoca un borrado automático.

**Parcial o pendiente**

- Revisión visual y de accesibilidad completa de todas las pantallas y estados, teclado y foco, TalkBack/VoiceOver, todos los tamaños de texto y rotación, lectores reales y dispositivos diversos.
- Más idiomas, ajustes avanzados de accesibilidad y toda la matriz de microinteracciones de V2.
- No se acredita que toda la aplicación sea ya minimalista o que no exista ningún desbordamiento: se han simplificado y probado flujos concretos.

## 2. Biblioteca, catálogo y cobertura BOE

**Implementado localmente**

- Catálogo de **12.451 normas** del catálogo consolidado BOE observado el 5 de noviembre de 2026: **8.831 estatales y 3.620 autonómicas**.
- Datos de identificación, título, fuente, versión y metadatos territoriales/temporales cuando están disponibles. BOE/ELI y procedencia se conservan en las representaciones que los incluyen.
- Veinte textos iniciales incluidos en el APK, con 11.777 bloques y sus redacciones; el resto se descarga por norma desde paquetes públicos de la rama `legal-corpus-20261105`, sin cuenta ni servidor privado.
- Búsqueda por título o referencia sin exigir coincidencia de tildes/mayúsculas; marcadores y normas guardadas.
- Filtros combinables por materia, ámbito estatal/autonómico y comunidad autónoma. Se cubren las 17 comunidades presentes en el catálogo y se unifican nombres alternativos de Baleares y Comunidad Valenciana.
- Elegir comunidad selecciona legislación autonómica de esa comunidad; no calcula toda la legislación estatal aplicable a ese territorio.
- Biblioteca, mazos preparados, tarjetas e índice de artículos con paginación real: anterior/siguiente, salto numérico y 20/50/100 resultados. El índice inicia con 50; las otras listas, con 20. Búsqueda, filtros y tamaño de página reinician la página y el desplazamiento.
- Filtros accesibles sobre la lista y controles de página fuera de ella; en pantallas muy bajas la cabecera puede desplazarse para dejar espacio a resultados.
- Filas construidas según se necesitan. Caché de paquetes en archivos nativos separada del progreso; hasta cuatro normas decodificadas en memoria. Validación de tamaño, SHA-256, esquema e identidad al abrir paquetes.
- Lectura sin conexión de textos incluidos o ya descargados en la aplicación nativa. En web la caché de paquetes actual es de sesión: no se garantiza recarga completa sin conexión.
- Indicación de fuente oficial, fechas, consolidación informativa y estado histórico cuando lo aporta la fuente.

**Veinte normas iniciales**

Constitución Española; Código Civil; Código Penal; Ley de Enjuiciamiento Civil; Ley de Enjuiciamiento Criminal; Ley Orgánica del Poder Judicial; Ley 39/2015 de Procedimiento Administrativo Común; Ley 40/2015 de Régimen Jurídico del Sector Público; Estatuto de los Trabajadores; Ley General Tributaria; Código de Comercio; Ley de Sociedades de Capital; Ley de la Jurisdicción Contencioso-administrativa; Ley Reguladora de la Jurisdicción Social; Ley de Contratos del Sector Público; Estatuto Básico del Empleado Público; Ley Orgánica de Protección de Datos y garantía de derechos digitales; Ley Orgánica de Igualdad; Ley Reguladora de las Bases del Régimen Local; Ley Orgánica del Tribunal Constitucional.

**Parcial o pendiente**

- Este inventario es un corte del catálogo BOE consolidado; no representa toda la legislación española, histórica, municipal o europea.
- Cobertura íntegra de boletines autonómicos y locales adicionales, jurisprudencia y fuentes universitarias autorizadas.
- Motor jurídico full-text de todo el corpus y filtros completos por rango, etiquetas, oposición, asignatura y relaciones normativas.
- Índice jerárquico completo de libros/títulos/capítulos, presentación fiel de todas las tablas, anexos y elementos complejos y auditoría editorial de dicha estructura.
- Actualización continua en producción de los paquetes públicos: existe la maquinaria de importación/vigilancia, pero no un servicio comercial desplegado y garantizado.

## 3. Lector y herramientas jurídicas

**Implementado localmente**

- Índice de unidades/artículos y vista de texto con búsqueda dentro de la norma descargada.
- Apertura de coincidencias en su fragmento, resaltado y lectura por fragmentos, con opción de texto completo.
- Conservación del último punto de lectura por norma/artículo. Se recupera solo si coinciden versión y hash; no se aplica una posición antigua a otro texto.
- Historial de redacciones disponibles y selección por fecha de estudio cuando los metadatos de efecto permiten resolverla sin contradicciones.
- Comparación textual por párrafos entre versiones.
- Notas privadas por artículo, copia de referencia, apertura de fuente oficial y creación de tarjeta desde el lector con cita y hash de la redacción.
- Lectura en voz mediante el servicio TTS de la plataforma y opción de detenerla; disponibilidad/calidad dependen del dispositivo.

**Parcial o pendiente**

- Interpretación jurídica de vigencias parciales, regímenes transitorios, derogaciones tácitas y conflictos normativos.
- Comparador semántico jurídico, renumeraciones, referencias cruzadas completas y mapa modifica/desarrolla/deroga/cita.
- Sincronización remota específica del punto de lectura; actualmente se conserva localmente y en la copia JSON.
- La consulta temporal rechaza situaciones ambiguas; no certifica el derecho aplicable a un caso.

## 4. Mazos preparados y ejercicios automáticos

**Implementado localmente**

- Preparación automática por norma: el usuario no tiene que redactar cada tarjeta desde cero.
- Cuatro formatos: recuerdo literal, completar huecos, test de recuerdo literal e identificar artículo.
- Nombre de mazo personalizado para reunir varias normas y formatos en un tema propio.
- Identificadores estables para evitar duplicados al preparar de nuevo la misma selección.
- Veinte bancos iniciales con 13.914 tarjetas de recuerdo incluidos para empezar sin red; el resto se deriva de los textos al solicitarlo.
- En los nuevos huecos, test e identificación, pasajes de hasta **320 caracteres Unicode**. Las tarjetas de recuerdo mantienen su formato anterior.
- Huecos con **dos o tres respuestas distintas**, numeradas, sin solaparse ni ocultar casi todo el pasaje; campos para contestar y retroalimentación individual. La corrección ignora mayúsculas y espacios repetidos, conservando tildes y ñ.
- Test literal de expresión o término en contexto breve, con cuatro opciones extraídas del texto fuente y posición correcta distribuida de forma determinista.
- Identificación de artículo mediante extracto y alternativas de la misma norma; se excluyen alternativas ambiguas detectadas por el generador.
- Cita de norma, unidad, versión y hash en las tarjetas derivadas. No se generan reglas jurídicas inventadas para completar vacíos.
- Renovación v2 de huecos/test/identificación: al volver a preparar norma y formato, los originales automáticos v1 sin editar pasan a Ejercicios anteriores. Se preservan sus estados e historial; las tarjetas editadas, personales o vinculadas a sincronización no se retiran automáticamente. Las nuevas tienen identificadores y programación propios.

**Capacidad auditada del catálogo completo, no tarjetas precargadas en el móvil**

| Formato | Ejercicios técnicamente comprobados |
| --- | ---: |
| Recuerdo literal | 684.375 |
| Completar huecos | 2.747.278 |
| Test literal | 2.827.050 |
| Identificar artículo | 2.127.659 |
| **Total** | **8.386.362** |

La auditoría recorrió las 12.451 normas. Estos números reflejan ejercicios automáticos posibles al preparar los textos, no preguntas oficiales ni material con revisión jurídica humana. Se omiten los fragmentos sin contenido o alternativas adecuados.

**Parcial o pendiente**

- Banco pedagógico revisado por profesionales: preguntas conceptuales, excepciones, explicaciones, casos, glosarios, resúmenes y dificultad calibrada.
- Preguntas oficiales de oposiciones, derechos de reutilización y correspondencia verificada con convocatorias.
- Evaluación jurídica de respuestas abiertas. El test actual trabaja recuerdo literal; no es un motor que compruebe razonamiento jurídico.
- Renovación automática general de todos los mazos existentes: el usuario solicita la preparación de nuevo; no se modifica todo su contenido al arrancar.

## 5. Tarjetas personales y edición

**Implementado localmente**

- Editor de tarjetas con mazo, pregunta, respuesta, explicación y tipos QA, cloze, verdadero/falso, ordenación, caso y test.
- Opciones y solución en tipos de elección; respuesta activa y retroalimentación en elección/verdadero-falso/ordenación y huecos.
- Los casos y preguntas abiertas son material personal con autoevaluación; no corrección jurídica automática.
- Edición con revisiones anteriores archivadas, control de revisión esperada y progreso conservado; borradores para continuar la edición.
- Búsqueda por mazo, pregunta, respuesta, explicación y referencia; favoritas y filtro por fallos anteriores.
- Importación privada CSV UTF-8 con columnas pregunta/respuesta, hasta 2 MB y 2.000 tarjetas, validación del lote y confirmación antes de guardar. No se ejecutan fórmulas ni HTML.
- Historial de contenido y acceso a ejercicios automáticos archivados.
- Registro local de reportes de error y envío idempotente a la API cuando hay cuenta/servidor configurados.

**Pendiente**

- Importación Anki `.apkg`, adjuntos multimedia con controles y escaneo, colaboración, catálogo de mazos de terceros y moderación.
- Backoffice profesional de resolución y seguimiento de reportes. Recibir un reporte no significa corregirlo editorialmente.

## 6. Repaso espaciado

**Implementado localmente**

- Programación SM-2 adaptada, identificada como `sm2-1`; no es FSRS.
- Cuatro valoraciones: Otra vez, Difícil, Bien y Fácil.
- Estados por tarjeta con intervalo, facilidad, repeticiones, fallos y próxima revisión.
- Registro de cada repaso con tarjeta/revisión de contenido, instante, latencia, respuesta y estado anterior; la respuesta objetiva se conserva separada de la valoración subjetiva.
- Cola por mazo, vencimiento y prioridad de repasos frente a tarjetas nuevas, limitada por el objetivo diario. Excluye tarjetas bloqueadas y respeta descansos/vacaciones.
- Sesión guardada para continuar y protección contra repasar una revisión de tarjeta que ha cambiado.
- Deshacer la última revisión local no sincronizada; una revisión ya sincronizada no se elimina con este botón.

**Pendiente**

- Planificación adaptativa más avanzada, prioridad ponderada de temas, calibración por tiempo real disponible y modelos de retención validados.
- Compensación remota de deshacer y resolución avanzada de todos los conflictos entre dispositivos.

## 7. Planificador y organización universitaria

**Implementado localmente**

- Objetivo de 5 a 200 tarjetas/día, disponibilidad declarada de 0,5 a 8 horas, días de descanso, vacaciones y fecha opcional de examen.
- Previsión de siete días calculada con tarjetas/estados actuales y arrastre de pendientes. No anticipa respuestas futuras ni garantiza que se complete un temario.
- Asignaturas personales con institución y semestre/curso, temas/subtemas y apuntes privados.
- Archivo y recuperación de asignaturas sin destruir sus datos.
- Evaluaciones con ponderación, puntuación máxima y calificación opcional; validación de pesos y notas. Las pendientes no redistribuyen su peso y no se predicen notas futuras.
- Puntos acumulados sobre diez y porcentaje de evaluación registrado/completado.

**Parcial o pendiente**

- Las horas se guardan como disponibilidad: no existe todavía un optimizador que convierta ese dato en un calendario completo por temas.
- Edición avanzada de todos los temas/evaluaciones, vinculación multidisciplinar artículo-tema y planificación completa de V2.
- Guías docentes oficiales autorizadas, planes por titulación, bibliografía y programas verificados de cada universidad.
- Catálogo de convocatorias de oposición con bases, cuerpo, turno, territorio, temario versionado y mapeo oficial tema-artículo. Los temas propios no son una oposición oficial ya preparada.

## 8. Simulacros y progreso

**Implementado localmente**

- Simulacro personal con tarjetas tipo test instaladas y no bloqueadas.
- Cantidad, duración y penalización configurables; banco de preguntas/revisiones congelado al iniciar, respuestas persistentes y continuación del intento.
- Temporizador y cierre al agotar el tiempo; corrección al finalizar con aciertos, errores, blancas, puntuación y penalización.
- Historial de simulacros, total de revisiones, proporción de autoevaluaciones Bien/Fácil, progreso por mazo e historial reciente.
- El servidor también tiene contratos para crear/entregar intentos y ocultar soluciones antes de entregar.

**Límites y pendientes**

- La versión local conserva soluciones para corregir sin conexión: no es una plataforma de examen supervisado.
- El porcentaje de Bien/Fácil mide recuerdo declarado, no probabilidad de aprobar.
- Faltan bancos oficiales verificados, reglas específicas por convocatoria, análisis avanzado por competencia y cuadros de evolución completos.

## 9. Datos locales, copias y privacidad

**Implementado en código**

- Estado privado Android/iOS en SQLCipher con clave separada en Keychain/Keystore; tokens fuera de las exportaciones y del estado educativo compartido.
- Migración desde preferencias que comprueba la escritura antes de retirar el original.
- Esquema 2: snapshots fragmentados en bloques pequeños y escritura transaccional; lectura fragmentada de la fila antigua para evitar el límite de cursor Android. Una escritura fallida revierte la transacción.
- Paquetes públicos de lectura separados del progreso; no se copian todos los textos legales dentro de preferencias ni de cada copia de progreso.
- Exportación/restauración JSON y compartición mediante la plataforma. Incluye datos personales locales y punto de lectura; no las claves/tokens ni los textos públicos descargables.
- Borrado local con confirmación, y exportación/borrado remoto cuando la API está configurada.
- Preferencias separadas de analítica y comunicaciones; no hay proveedor de analítica, publicidad ni comunicaciones conectado.
- Pantalla de privacidad/fuentes que informa del comportamiento actual y de sus límites.

**Parcial o pendiente**

- Las pruebas nativas de migración/reapertura/rollback están escritas, pero no se han ejecutado aquí en Android/iOS ni acreditado en el OPPO. La fragmentación Unicode sí tiene prueba unitaria.
- Web conserva preferencias locales sin el cifrado SQLCipher y depende del almacenamiento del navegador.
- La copia JSON compartida es legible: no se ofrece como archivo cifrado automáticamente.
- Política legal final del responsable, contacto, bases jurídicas, menores, conservación, contratos y cumplimiento RGPD revisado; auditoría de seguridad y dependencias completa.

## 10. Cuentas y sincronización

**Implementado con servidor; no operativo en producción en la instalación entregada**

- API configurable y comunicaciones privadas que requieren HTTPS; excepciones locales solo para desarrollo donde corresponde.
- Identidad invitada remota, sesiones, refresh rotatorio, cierre/revocación y recuperación con código privado de un solo uso que sustituye el anterior.
- Interfaz Cuenta y copias para subir/descargar tarjetas y progreso y recuperar una cuenta por código, disponible cuando se configura servidor.
- Tokens guardados en almacenamiento seguro y separados por servidor/ruta.
- IDs estables, reintentos idempotentes, subida de revisiones de contenido antes de sus eventos offline, descarga de tarjetas/estados/historial y conservación de conflictos y revisiones locales pendientes.
- Sincronización opcional de perfil/plan, notas, asignaturas y seguimientos: comparación local/servidor/base anterior; elección explícita por sección en conflictos, control de versión y copia local anterior conservada.
- Adaptador servidor de identidad Firebase Google/Apple con validación de firma RSA, emisor, audiencia, fechas/proveedor y vinculación a invitado. Sus pruebas usan identidades de test, no proveedores reales configurados.

**Pendiente para uso real**

- Desplegar backend HTTPS y base de datos operativa; la copia manual JSON es la opción disponible sin ese servidor.
- Proyecto Firebase real, configuración Google/Apple, interfaz de acceso federado nativa y pruebas reales de vinculación, revocación y recuperación. Acceso email/contraseña y correo transaccional no están implementados como servicio operativo.
- Sincronización automática completa y granular, recuperación ante redes inestables y todos los conflictos entre múltiples dispositivos; no se afirma que todo esté resuelto por disponer de una API.

## 11. Actualidad, vigilancia y avisos

**Implementado con servidor**

- Pantalla Actualidad con eventos, fuente y fechas, filtros Todos/Pendientes/Consolidados y normas seguidas.
- Sincronización de novedades por cursor y carga adicional; esta pantalla conserva Cargar más, no el paginador numérico de biblioteca/mazos/artículos/tarjetas.
- Seguimiento local de normas y suscripciones remotas opcionales.
- Bandeja interna opt-in por cuenta, eventos deduplicados, marcado de lectura y agrupación temporal soportada por servidor.
- Conector de sumarios BOE y actualizaciones del catálogo consolidado, checkpoints por fecha y recuperación de intervalos. Fechas civiles de vigilancia en Europe/Madrid.
- Evidencia real previa: sumario del 4 de noviembre de 2026 con 234 documentos y catálogo del mismo día con 23 actualizaciones capturadas, pendientes de análisis jurídico.
- Bloqueo conservador de tarjetas afectadas por nueva versión; el cliente conserva paquetes anteriores en cuarentena e invalida el texto desactualizado al recibir nuevos metadatos.

**Parcial o pendiente**

- Servicio diario de producción desplegado, alertas operativas y compromisos de actualización.
- Clasificación jurídica profesional de reformas, vigencias y afectaciones granulares; correlación completa de consolidaciones retrasadas.
- Notificaciones push FCM/APNs, permisos de sistema, tokens de dispositivo, franjas de silencio y navegación por notificación probados en dispositivo.
- Seguimiento granular completo por título/artículo/convocatoria. Actualidad vacía no demuestra que una norma no haya cambiado.

## 12. Descargas europeas y otras fuentes

**Implementado y en ejecución**

- Archivo reanudable de la Oficina de Publicaciones de la UE, alcance CELEX sectores **0 y 3 con expresión española**.
- Conservación de originales, identificador CELEX, metadatos, atribución, hashes, checkpoints y estados por obra; una obra puede tener varios archivos.
- Selección de manifestaciones textuales disponibles, verificación de formatos y recuperación de adjuntos parciales; no se cuentan metadatos como texto completo.
- Supervisor con exclusión de duplicados, recuperación del trabajador, reintentos progresivos, pausas compartidas y ajuste conservador ante límites de la fuente.
- Reenumeración y conciliación del inventario, comprobación de integridad y vigilancia posterior a completar el archivo. Depende de que el entorno permanezca encendido; los checkpoints permiten reanudar.
- Instantánea observada a las **10:37 del 6 de noviembre, hora peninsular**: 184.732 registros identificados, 37.903 completos, 7.534 con solo metadatos, 139.291 pendientes, cuatro en curso y 58.632 archivos guardados. Es una instantánea cambiante, no un total final ni una previsión de plazo.

**Pendiente**

- Completar y reconciliar la descarga; la cifra del inventario puede cambiar durante la ejecución.
- Extracción/normalización de los documentos europeos, estructura por artículos, versiones, índices y paquetes compatibles con el lector.
- Integración de ese contenido en catálogo, filtros, lectura y ejercicios. Actualmente no hay un procesamiento incremental europeo de extremo a extremo funcionando.
- Jurisprudencia TJUE, todos los sectores/idiomas CELEX y fuentes internacionales: fuera del alcance actual de esta descarga.
- Archivo completo y conectores de distribución de los boletines autonómicos/municipales adicionales. Hay recopilaciones iniciales; no cobertura íntegra.

## 13. Backend, importación y seguridad de API

**Implementado y probado en desarrollo**

- FastAPI con contratos OpenAPI, SQLAlchemy y SQLite de desarrollo; selección de PostgreSQL mediante DATABASE_URL.
- APIs de biblioteca, versiones, unidades, comparación, cobertura, novedades, cuentas, mazos, tarjetas, revisiones, espacio privado, reportes, avisos, simulacros y administración inicial.
- Índice derivado para búsqueda de catálogo sin tildes, filtros y cursor estable; no es full-text jurídico universal.
- Adaptador BOE con validación XML, detección de errores aunque HTTP sea 200, conservación de originales y SHA-256, versiones inmutables, publicación transaccional y cuarentena ante fallo.
- Cola persistente de importación con lotes, reintentos/backoff, leases y reanudación. Importación de paquetes de distribución con comprobación de versiones inmutables.
- Control de propietario, expiración de sesiones, rotación de refresh, idempotencia, control ETag/If-Match y protección contra conflictos de edición.
- Límites de cuerpo incluso sin Content-Length, CORS explícito y conservación de datos ante errores recuperables.
- Copias de desarrollo SQLite cifradas con AES-256-GCM, captura consistente, comprobación de integridad y rechazo de manipulación/sobrescritura durante restauración.

**Parcial o pendiente**

- Modelo relacional completo V2 y migraciones operativas: buena parte del dominio actual son agregados JSON con tablas separadas de identidad, tokens, idempotencia y auditoría.
- Validación real sobre PostgreSQL, índices/carga a escala, rate limiting distribuido, múltiples réplicas y operación de colas/almacenamiento administrados.
- Backups PostgreSQL del proveedor, retención, restauración parcial periódica, observabilidad, alarmas y recuperación RPO/RTO.

## 14. Revisión editorial y calidad jurídica

**Base parcial implementada**

- Estados de contenido importado, del usuario y pendiente, citas/versiones y bloqueo por cambios.
- API editorial con roles básicos, separación del autor y requisito de dos revisores distintos sobre la revisión concreta; comprueba referencias actuales.
- Rutas editoriales deshabilitadas por defecto hasta configurar una pasarela MFA. Esa comprobación de configuración no implementa MFA por sí misma.
- Registros de decisiones e incidencias; recepción de reportes.

**Pendiente**

- Backoffice completo, MFA real, RBAC detallado/por tenant, asignación de trabajo, checklist jurídico, auditoría firmada y rollback editorial completo.
- Revisión humana del corpus educativo y circuito de resolución de reportes con responsables y plazos.
- Responsable editorial jurídico, clasificación de severidad y aceptación de cada categoría/banco comercial.
- No hay material educativo jurídicamente certificado por el hecho de pasar pruebas técnicas o proceder de un texto oficial.

## 15. Monetización, infraestructura y publicación

**Base parcial implementada**

- Pantalla informativa Free/Estudiante Plus/Opositor Pro. Los importes 3,99 €/mes y 7,99 €/mes son hipótesis, no productos contratables.
- Promoción interna de servidor de 30 días sin renovación ni cobro automático; endpoint de compras rechaza la validación no configurada.
- Propuesta de despliegue Render y configuración de ejemplo; no servicio contratado/desplegado.
- CI definida para backend, análisis/tests Flutter, web release, integración nativa Android 15, APK release de prueba e iOS en simulador. Configurar el workflow no acredita que todos los jobs remotos estén aprobados.
- APK optimizado de pruebas con paquete es.lexmemoria.app.preview, versión 0.4.0+6 y sin application-debuggable; proyecto Android principal separado.

**Pendiente**

- Hosting, dominio, TLS público de servicio, almacenamiento y base de datos administrados, separación dev/staging/prod, presupuestos, métricas/alertas y operación continuada.
- Google Play Billing/StoreKit, productos/precios reales, validación oficial servidor, webhooks, restauración, reembolsos, cancelación, gracia y revocación.
- Clave estable del titular y firma de distribución, AAB/símbolos/dSYM según plataforma, configuración de tiendas, fichas, capturas, privacidad y pruebas sandbox/beta.
- Compilación/validación iOS en macOS y publicación en Google Play/App Store.
- La firma temporal de GitHub puede cambiar entre ejecuciones. Un APK release de pruebas no equivale a una distribución comercial estable.
- Identidad legal del titular, condiciones, fiscalidad/IVA, contratos de proveedores, revisión de licencias comerciales, precios y oposiciones piloto.

## 16. Evidencia disponible y comprobaciones pendientes

**Resultados registrados para el estado examinado**

- 63 pruebas Flutter aprobadas en la iteración 0.4.0, análisis sin incidencias, Android release y web JavaScript release compilados.
- Última validación backend documentada: 94 pruebas aprobadas, incluida supervisión/recuperación europea. No se ha repetido la suite para redactar este inventario.
- Cotejo de 12.451 paquetes BOE y 695.207 versiones de bloques contra el archivo oficial retenido: XML, texto derivado, fechas y hashes.
- Auditoría técnica de todos los formatos: 8.386.362 ejercicios sobre 12.451 normas, con pertenencia de respuestas al texto, citas, identificadores y límites de formato comprobados. No revisión jurídica humana.
- Pruebas de navegación, filtros por 17 comunidades, páginas/salto, lectura y reanudación, restauración, conflictos, formatos de ejercicios, migración de mazos y fragmentación Unicode del estado.
- Pruebas nativas escritas de migración de estado cifrado de más de 3 MB, reapertura y rollback de escritura, sin ejecución local acreditada.

**Falta acreditar**

- Instalación/actualización y conservación de datos en el OPPO Reno 10 Pro con Android 15, especialmente por el fallo de lectura local comunicado anteriormente.
- Integración nativa SQLCipher/Keystore/Keychain real, aceptación de las últimas migraciones y resultados de los jobs remotos correspondientes.
- Multidispositivo real, proveedores de acceso, redes inestables, interrupciones/almacenamiento limitado, carga/memoria/batería y accesibilidad completa.
- iOS, publicación, compras/push reales, seguridad operativa y aceptación jurídica/editorial.

## 17. Qué se puede continuar sin intervención del titular

**Desarrollo autónomo:** descargas, procesamiento e integración europea, refinamiento de ejercicios, navegación/estructura de contenido, ampliación de pruebas, importadores, mejor gestión de conflictos y documentación/configuración revisable.

**Requiere decisiones o acceso del titular:** proveedor/región/presupuesto, proyecto de identidad, cuentas de tienda y firma estable, productos/precios, identidad y textos legales, licencias/editor jurídico y pruebas en su teléfono. No se deben enviar contraseñas o claves por el chat.

## Evidencia y referencias

- [Especificación maestra V2, texto conservado](especificacion-v2.txt). Sus instrucciones y metas no se confunden con funciones ya desarrolladas.
- [Matriz histórica de requisitos](matriz-requisitos.md): referencia de trazabilidad inicial, no aceptación actualizada punto por punto; algunos códigos se repiten entre secciones de V2.
- [Cambios 0.4.0](MEJORAS_0_4_0.md), [auditoría de ejercicios](validation/boe-exercises-0.4.0.json) y [verificación APK](validation/android-0.4.0.json).
- [Lectura 0.3.1](LECTURA_0_3_1.md), [catálogo BOE 0.3.0](CATALOGO_COMPLETO_2026-11-05.md) y [archivo europeo](DESCARGA_EUROPEA.md). Los recuentos y tests antiguos describen sus respectivas versiones; este inventario utiliza los valores posteriores indicados.
- Código principal: mobile/lib/{shell,library,reading,study,prepared,exercises,planning,university,profile,workspace,store,remote,persistence}.dart y backend/app/.
