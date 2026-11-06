# LexMemoria — Especificación funcional y técnica actualizada

Inventario de capacidades, límites y trabajo pendiente — edición 0.5.0

Fecha de revisión: **6 de noviembre de 2026**. Aplicación **0.5.0+8**; código de referencia **`2d1035a`**, posterior a la integración Google de `1325a0e`. La corrección 422 está subida a `main`; su despliegue y aceptación en el móvil siguen pendientes de confirmación. Este documento sustituye al inventario 0.4.0 para describir el estado actual; los documentos y resultados antiguos conservan valor histórico.

Este inventario describe el código y la evidencia disponibles, contrastados con la especificación maestra V2. El documento V2 expresa objetivos, no funcionalidades que deban darse por terminadas. Tampoco se considera operativo un servicio por tener una pantalla, un adaptador o pruebas simuladas. No se asigna un porcentaje global de finalización: hay requisitos con pesos y estados distintos.

**Estados utilizados:**

- **Implementado localmente:** existe el flujo en el cliente; se indican sus límites y validación.
- **Implementado con servidor:** hay cliente/API o infraestructura de código, pero requiere desplegar/configurar el servidor para uso real.
- **Parcial:** existe una parte, pero faltan funciones, integración o aceptación.
- **Pendiente:** no está disponible de extremo a extremo.
- **Pendiente de aceptación externa:** existe implementación y evidencia local, pero falta comprobar proveedor, servidor desplegado o dispositivo físico.

Los objetivos de V2 y de la solicitud V3 se distinguen de las capacidades existentes. Un archivo descargado no equivale a contenido integrado; una compilación correcta no equivale a prueba en el teléfono; un servicio que responde a salud no acredita recuperación completa del progreso. Los recuentos europeos son instantáneas con fecha, no cifras finales.

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

## 10. Cuentas, Google y sincronización

**Implementado en cliente y servidor; aceptación real incompleta**

- Interfaz Perfil → Cuenta y copias. API configurable; comunicaciones privadas por HTTPS. La lectura y el estudio locales no requieren cuenta.
- Identidad invitada remota, sesiones propias de LexMemoria, refresh rotatorio, cierre/revocación y recuperación mediante código privado de un solo uso que sustituye al anterior.
- Google nativo en Android mediante SDK oficiales Google Sign-In y Firebase Auth. El cliente intercambia la identidad Google por un ID token Firebase y lo envía al backend; el servidor valida firma, emisor, proyecto, fechas y proveedor.
- Proyecto comunicado y configuración recibida: `lexmemoria-aa86a`. Paquete del APK configurado: `es.lexmemoria.app.preview`. Se han comprobado proyecto, paquete, cliente OAuth web y coincidencia de certificado con la configuración.
- El botón Google requiere Android configurado y API HTTPS. Los APK genéricos de GitHub sin configuración y flags pueden mostrar la misma versión 0.5.0 sin ofrecer ese botón. El APK específico entregado sí contiene la configuración pública necesaria.
- Una cuenta invitada activa se vincula conservando su ID; una colisión no provoca una fusión silenciosa ni acceso alternativo automático. Sin sesión se inicia mediante identidad federada. Los cambios de propietario requieren confirmación cuando corresponde.
- Cancelar selección no sube datos. Iniciar sesión tampoco sube ni sustituye automáticamente todo el contenido educativo. La copia/subida y la descarga siguen siendo operaciones explícitas.
- Las credenciales propias se guardan en un sobre seguro ligado a cuenta y servidor. Cambiar servidor o restaurar una copia no autoriza reutilizar credenciales sobrantes. Las peticiones privadas no siguen redirecciones; se rechazan cambios de cuenta/servidor durante una operación y se deduplica el refresh paralelo.
- Sesiones antiguas se comprueban mediante la API antes de atribuirles contenido. No se confía solo en el identificador guardado localmente.
- IDs estables y reintentos idempotentes de tarjetas y eventos. Se sube el historial de contenido antes de los repasos asociados a revisiones antiguas. Descarga de tarjetas, estados e historial; conservación de conflictos y cambios pendientes.
- Sincronización opcional de perfil/plan, notas, asignaturas y seguimientos: comparación de base anterior, local y servidor, control de revisión y elección explícita por sección ante conflicto.
- Peticiones de autenticación con espera de hasta 90 segundos para el arranque de la API gratuita; las demás mantienen el límite de 30 segundos. Esto no garantiza un tiempo de respuesta máximo de Render.

**Corrección del error 422, código `2d1035a`**

- La API anterior rechazaba una tarjeta citada cuando su versión normativa no existía en la base del servidor, aunque el móvil tuviera el paquete oficial descargado. Se ha reproducido ese supuesto en servidor local vacío; no se ha capturado la petición privada exacta del teléfono.
- POST/PUT de tarjetas privadas ahora conservan citas completas de versiones no importadas con estado `pending_source`. No borran las citas, no crean normas a partir de datos del usuario y no las convierten en contenido verificado.
- Si la versión está disponible se sigue comprobando correspondencia de norma, artículo y hash. Citas incompletas, ejercicios inválidos y referencias incompatibles con versiones existentes siguen rechazándose.
- Las referencias pendientes no pueden superar la aprobación editorial sin fuente disponible. La corrección no importa por sí sola el catálogo BOE al servidor.
- Regresión comprobada: crear, reintentar, editar, conservar historial, subir repaso anterior, exportar y aislar otra cuenta. El cambio es del servidor; no requiere nuevo APK, reinstalación ni borrado de datos.
- Subida a GitHub confirmada. Falta confirmar despliegue Live del commit en Render y repetir el guardado desde el móvil.

**Pendiente**

- Aceptación real de Google y sincronización en OPPO, recuperación en segundo dispositivo, reconexión, caducidad de sesión y conservación tras reinicio del servidor.
- Prueba integral de grandes mazos, rate limiting, cortes, respuestas perdidas y edición concurrente entre dispositivos. No se promete sincronización automática completa de todos los datos.
- Recuperación idempotente si se pierde totalmente la respuesta tras consumir un código. Si el servidor responde pero falla el guardado local, existe tratamiento del código sustituto; no resuelve el caso de pérdida total de red.
- Revocación y borrado coordinados con Firebase, aceptación de todas las cachés nativas y del cierre del proveedor. La sesión propia del backend y la de Firebase tienen ciclos distintos.
- Apple, Google en iOS/web, email/contraseña y correo transaccional operativos. Apple se ha aplazado por elección del titular.

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

**Archivo original y procesamiento incremental implementados**

- Archivo reanudable de la Oficina de Publicaciones de la UE: CELEX sectores **0 y 3 con expresión española** y manifestaciones textuales seleccionadas. No cubre todos los sectores, idiomas o jurisprudencia europea.
- Conserva originales, CELEX, metadatos, atribución, hashes, checkpoints y estado por obra. Cada obra puede tener varios archivos; los metadatos solos no cuentan como texto descargado.
- Supervisor y trabajador separados, exclusión de duplicados, reintentos progresivos, pausas compartidas y respeto de limitaciones de la fuente. Conciliación del inventario e integridad; los checkpoints permiten continuar tras una interrupción del entorno.
- Extractor independiente de HTML/XHTML a párrafos en paralelo con la descarga. Lee el archivo original sin modificarlo; verifica hash del original y del derivado, guarda gzip atómicos, índice propio, checkpoint y lock.
- Ignora scripts y estilos y no ejecuta los documentos. El resultado se marca automático, pendiente de revisión: los párrafos no se presentan como artículos jurídicos validados.
- Formatos no HTML quedan diferidos; documentos inválidos o que exceden límites quedan registrados como fallidos. Un archivo diferido o fallido no se considera procesado.
- Supervisor, trabajador y extractor observados como procesos presentes al preparar este inventario. Su disponibilidad continuada depende de que el entorno siga activo; no se garantiza ejecución tras suspenderlo.

**Últimas instantáneas leídas, no recuento final**

Archivo original, instante **2026-11-06T12:27:03.895982+00:00** (UTC):

| Estado | Cantidad |
| --- | ---: |
| Registros identificados | 184.732 |
| Registros completos | 46.120 |
| Solo metadatos | 7.534 |
| Pendientes | 131.073 |
| En curso | 3 |
| Fallidos | 2 |
| Archivos guardados | 72.093 |

Derivados, instante **2026-11-06T12:27:01.791588+00:00** (UTC): **35.270 extraídos**, **36.808 diferidos** y **12 fallidos**. Estos son estados de archivos del extractor y no equivalen al recuento de obras completas. El inventario mantiene diferencias de conciliación y no acredita archivo íntegro.

**Pendiente**

- Completar y reconciliar la descarga y resolver o documentar ausencias/errores. No existe una fecha de finalización acreditada.
- Conversión de PDF, Formex, Word y otros formatos; estructura jurídica por artículos/anexos, versiones, relaciones y búsqueda.
- Supervisión específica del extractor ante terminación inesperada; su checkpoint ya permite reanudar.
- Distribución europea al móvil e integración real en catálogo, filtros, lector y generador de ejercicios. **Europa aún no está disponible como corpus completo de estudio en la app.**
- Cobertura íntegra de boletines autonómicos/municipales adicionales, jurisprudencia TJUE, otros sectores CELEX, otros idiomas y fuentes internacionales.

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

## 15. Infraestructura, monetización y publicación

**Implementado o configurado**

- Backend FastAPI preparado para Render; el titular ha creado API `lexmemoria-api` y PostgreSQL `lexmemoria-db`, ambos Free y en Frankfurt según el panel comunicado.
- URL comunicada: `https://lexmemoria-api.onrender.com`. El titular confirmó un despliegue operativo y respuesta de salud. No se ha verificado directamente esa URL desde este entorno por su política de red.
- PostgreSQL 18, base `lexmemoria_db`, usuario `lexmemoria_db_user`, capacidad de 1 GB, según panel aportado. Contraseña y URL privada se configuran en Render y no forman parte del documento.
- El panel indica caducidad de la base gratuita el **6 de diciembre de 2026** y eliminación sin actualización de plan. Hay que resolver continuidad, copia y restauración antes de esa fecha.
- En staging/production se exige DATABASE_URL PostgreSQL: se rechaza configuración ausente, malformada o SQLite para evitar guardar progreso en disco efímero. `/health` informa versión, dialecto y proyecto Firebase; su respuesta no acredita todos los flujos.
- Proyecto Firebase real y configuración Google Android recibida. Configuración SDK pública compilada en el APK específico, sin subir el JSON original, claves privadas, service-account ni keystore al repositorio.
- APK de pruebas 0.5.0+8, paquete `es.lexmemoria.app.preview`, release sin modo debug, compilado, firmado y verificado. Se ha publicado un enlace directo en GitHub y descargado por completo para comprobar su hash.
- CI definida para backend, Flutter, web, integración Android 15 y simulador iOS. La definición no acredita que todas las ejecuciones remotas o plataformas estén aprobadas.
- Pantalla informativa de planes Free/Estudiante Plus/Opositor Pro. Importes de 3,99 y 7,99 €/mes son hipótesis; no hay suscripciones comerciales contratables verificadas.
- Promoción interna de 30 días sin cobro ni renovación automática. La validación de compras no configuradas se rechaza.

**Pendiente de producción**

- Confirmar despliegue actualizado, persistencia PostgreSQL tras reinicio, copias/restauración reales, alertas, retención y operación continua. Los planes Free no se presentan como operación comercial validada.
- Resolver caducidad de PostgreSQL, elegir presupuesto/plan, almacenamiento y separación real de staging/producción. Verificar condiciones y precios vigentes en el proveedor.
- Clave Android estable bajo control del titular y estrategia de actualizaciones. La firma efímera de GitHub puede diferir del APK específico; no desinstalar para resolver una incompatibilidad sin proteger el progreso.
- Paquete y firma definitivos de tienda, AAB, símbolos, Play Console/App Store Connect, fichas, capturas, política de privacidad, pruebas beta y publicación. El paquete preview no es la aplicación comercial definitiva.
- Google Play Billing/StoreKit y pruebas sandbox de compra, restauración, reembolso, caducidad y revocación; validación oficial en servidor y webhooks. No hay cobros reales habilitados.
- Push FCM/APNs reales, dominios del titular, canales de soporte, monitorización y gestión de incidentes.
- iOS en macOS/dispositivo y distribución App Store. Tener proyecto iOS no acredita una aplicación iOS lista.
- Identidad legal, condiciones, fiscalidad, contratos, revisión de licencias, protección de datos y responsable editorial.

## 16. Evidencia disponible y aceptación pendiente

**Resultados registrados**

- **146 pruebas backend aprobadas** en la última ejecución tras la corrección 422: unidad/API local y SQLite, incluidos casos negativos y regresión de copias privadas citadas. No es una prueba de PostgreSQL/Render real.
- **89 pruebas Flutter aprobadas** en la entrega Google 0.5.0, análisis sin incidencias y compilaciones Android release y web JavaScript release correctas. No se han repetido esas suites para redactar este documento, porque no se modifica código de aplicación.
- Google dispone de pruebas con proveedor/HTTP simulados; la verificación de servidor usa fixtures RSA firmadas. No se confunden con acceso a una cuenta Google real en el móvil.
- APK configurado: 87.102.881 bytes; SHA-256 `3a451bd920b816410cd3518cb246ec936ace6641e2aa194833ec37feffc559a9`. Release sin depuración; certificado, recursos Firebase, URL compilada y catálogo comprobados; descarga pública completa cotejada.
- Cotejo histórico de 12.451 paquetes BOE y 695.207 versiones de bloques contra originales retenidos: texto, XML, fechas y hashes. Auditoría técnica de 8.386.362 ejercicios posibles; no revisión jurídica humana ni precarga de todos en el teléfono.
- Persistencia/mutaciones y sesiones: pruebas de fallo de escritura, restauración inválida, checkpoint recuperable, concurrencia local, autoridad tras restore, cambio de cuenta/servidor, redirecciones y refresh.
- Procesamiento europeo: pruebas de trazabilidad, integridad, reanudación, no ejecución de scripts y formatos diferidos; muestra histórica de 100 archivos cotejada independientemente. No validación editorial del archivo completo.

**No acreditado todavía**

- Despliegue Live de la corrección 422 y desaparición del fallo en el móvil del titular. La captura exacta de su petición no está disponible.
- Google real, cambio de dispositivo y conservación de todos los datos tras cerrar/reabrir sesión, actualizar y reiniciar servidor.
- Pruebas nativas locales de SQLCipher/Keystore/Keychain, migración desde versión antigua, rollback tras cierre abrupto y aceptación en OPPO Reno 10 Pro Android 15.
- Integración PostgreSQL real, carga, cortes de red prolongados, almacenamiento escaso, batería, memoria, accesibilidad integral y todas las ejecuciones CI remotas.
- iOS, Apple, compras, push, recuperación operativa, seguridad completa y revisión jurídica/editorial.

La matriz V3 conserva 100 requisitos/reglas como herramienta de trazabilidad. Sus estados y resultados históricos no se actualizan por inferencia al publicar este inventario. Ninguna fase completa de V3 queda aceptada por este documento; no se asigna un porcentaje global de finalización.

## 17. Trabajo pendiente y responsabilidades

**Orden de aceptación recomendado**

1. Desplegar `2d1035a` y confirmar guardado desde el móvil sin 422. Si persiste, identificar operación y mensaje del servidor, sin borrar datos.
2. Probar cuenta Google, copia, reapertura y recuperación desde un segundo dispositivo con datos de prueba controlados. Comparar tarjetas, historial, respuestas y estados, no solo el mensaje de éxito.
3. Probar interrupciones y grandes mazos; reforzar reintentos, límites y conflictos donde las pruebas revelen fallos.
4. Acreditar persistencia PostgreSQL, copia y restauración; resolver la caducidad de la base antes del 6 de diciembre de 2026.
5. Completar archivo y procesamiento europeo e integrar contenido trazable en el móvil por fases, sin presentarlo como íntegro antes de tiempo.
6. Revisar calidad pedagógica/jurídica, lector, navegación, accesibilidad y rendimiento en dispositivos reales.
7. Completar firma estable, requisitos legales y beta de tienda antes de abrir uso comercial.

**Puede avanzar el desarrollo sin nuevas cuentas del titular**

Procesamiento e integración europea, herramientas de ingestión, pruebas, gestión de errores/conflictos, mejoras de lectura/ejercicios/planificación, estructura de programas, diseño de permisos y documentación. La continuidad de descargas depende del entorno y las fuentes; el texto no promete ejecución indefinida.

**Necesita intervención o validación del titular**

- Confirmación de despliegue si Render no actualiza automáticamente y prueba física de instalación/sincronización en su teléfono. No se dispone de acceso directo a su consola ni al dispositivo.
- Decisión de presupuesto, continuidad del plan de base y políticas de copias/retención. Render y Firebase ya se han elegido para esta primera etapa; no hay que crear de nuevo las cuentas.
- Custodia de firma y cuentas de tienda, consentimientos/configuración de producción y aprobación comercial.
- Identidad/contacto legal, textos revisados, derechos de reutilización y responsables de contenido/moderación.
- Apple/iOS y monetización cuando se decida abordarlos. No se solicitan secretos en el chat ni en Git.

## 18. Integridad de datos y sesiones añadida desde el inventario anterior

- Mutaciones críticas serializadas sobre el último estado confirmado: repasar, deshacer, editar/añadir tarjeta y cambios de perfil. Una escritura fallida no publica el nuevo estado en memoria.
- Restauración valida estructura, IDs duplicados, tipos, respuestas, estados, sesiones, vacaciones y ponderaciones antes de sustituir datos. Conserva campos desconocidos compatibles.
- Reset y restauración confirman persistencia antes de mostrar éxito. Existe checkpoint anterior recuperable desde Ajustes, sin anidamiento recursivo de checkpoints.
- Las copias no restauran tokens ni autoridad de sincronización. El checkpoint puede contener datos privados anteriores y la exportación JSON es legible.
- Respuestas de huecos se envían como mapa numerado, aceptado y validado por API; se conserva el resultado objetivo separado de la autoevaluación y se evita duplicar eventos al reintentar.
- Estas garantías tienen pruebas locales de fallos y concurrencia, con las limitaciones nativas y multidispositivo indicadas; no equivalen a certificación de seguridad.

## 19. Capacidades todavía ausentes de extremo a extremo

| Área | Lo que no está terminado |
| --- | --- |
| Europa | Archivo íntegro reconciliado, conversión de todos los formatos y corpus integrado en la app |
| Cobertura jurídica | Toda la legislación española/local, jurisprudencia y vigencia jurídica interpretada |
| Pedagogía | Banco conceptual y de casos revisado, dificultad calibrada y preguntas oficiales con derechos |
| Programas | Convocatorias y planes universitarios oficiales versionados con correspondencia verificada |
| Comunidad | Invitaciones, ACL, enlaces revocables, edición compartida y moderación operativa |
| Cuentas | Aceptación Google multidispositivo; Apple/email operativos y revocación coordinada |
| Operación | PostgreSQL/recuperación/carga aceptados, alertas y continuidad del plan |
| Plataformas | iOS verificado; accesibilidad y rendimiento físicos completos |
| Tiendas y cobros | Firma definitiva, publicación, Billing/StoreKit y compras verificadas |
| Legal/editorial | Responsable, textos legales, revisión humana, soporte y procesos de incidentes |

No se interpreta que todo lo que exista parcialmente esté listo para publicación. Este inventario describe el estado desarrollado y un criterio de aceptación, no una certificación ni una promesa de cobertura universal.

## 20. Arquitectura y contratos principales

- Cliente Flutter/Dart: navegación, biblioteca y lector; preparación/edición/estudio; planificación, universidad y perfil; persistencia, copias, identidad y sincronización en módulos separados.
- Estado privado nativo en SQLCipher, clave fuera del snapshot; preferencias web con garantías distintas. Los paquetes legales públicos se mantienen separados del progreso.
- Servidor Python/FastAPI, SQLAlchemy, SQLite para pruebas/desarrollo y PostgreSQL exigido en staging/producción. Identidad, tokens, idempotencia y auditoría tienen tablas específicas; parte del dominio está en agregados JSON versionados.
- Contratos HTTP: `/health`; autenticación invitada/federada/vinculación/sesión/refresh; biblioteca/versiones/artículos; mazos/tarjetas/historial; repasos/estados; workspace privado; novedades/seguimientos/avisos; reportes; simulacros y administración editorial.
- Autorización por propietario en datos privados, control de revisión `If-Match`, IDs e idempotencia para reintentos y límites de cuerpo/peticiones. No existe todavía limitador distribuido para múltiples réplicas.
- Ingesta BOE, cola y monitor separados de las peticiones privadas. Archivo europeo original y salida derivada independientes. La existencia de scripts no garantiza ejecución periódica en Render.
- Build Android configurado mediante helper que valida Firebase y firma; no habilita Google por mera presencia de un número de versión. La reproducción requiere configuración pública correcta y material de firma custodiado fuera del repositorio.

## Evidencia y referencias

- [Especificación maestra V2, texto conservado](especificacion-v2.txt). Sus instrucciones y metas no se confunden con funciones ya desarrolladas.
- [Matriz histórica de requisitos](matriz-requisitos.md): referencia de trazabilidad inicial, no aceptación actualizada punto por punto; algunos códigos se repiten entre secciones de V2.
- [Google Android y corrección de sincronización](GOOGLE_ANDROID.md), [validación Google](validation/google-0.5.0.json), [APK 0.5.0](validation/android-google-0.5.0.json) y [descarga pública verificada](validation/google-apk-download-0.5.0.json). Los informes 0.5.0 anteriores a `2d1035a` conservan la limitación histórica de citas que este commit corrige.
- [Plan y evidencias V3](v3/PLAN_Y_EVIDENCIAS.md), [solicitud V3](v3/SOLICITUD_V3.md) y [matriz V3](v3/MATRIZ_REQUISITOS.md), con fecha y alcance propios.
- [Cambios 0.4.0](MEJORAS_0_4_0.md), [auditoría de ejercicios](validation/boe-exercises-0.4.0.json) y [verificación APK](validation/android-0.4.0.json).
- [Lectura 0.3.1](LECTURA_0_3_1.md), [catálogo BOE 0.3.0](CATALOGO_COMPLETO_2026-11-05.md) y [archivo europeo](DESCARGA_EUROPEA.md). Los recuentos y tests antiguos describen sus respectivas versiones; este inventario utiliza los valores posteriores indicados.
- Código principal: mobile/lib/{shell,library,reading,study,prepared,exercises,planning,university,profile,workspace,store,remote,persistence}.dart y backend/app/.
