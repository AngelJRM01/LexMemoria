# LexMemoria: especificación actual y preparación de la primera publicación

Fecha del documento: **10 de noviembre de 2026**. Repositorio: `AngelJRM01/LexMemoria`.

Versión inventariada: **0.8.1+14**, entregada como APK release de pruebas con Google, publicado en GitHub y verificado mediante descarga completa. Código funcional: `1ab19073ca153a47ed0b79ef771f9f7350429441`. No hay publicación en tiendas acreditada. No se confunde un cambio local, una subida a GitHub, un APK de pruebas, un despliegue Render y una publicación en tienda: son entregas diferentes.

## 1. Dictamen para decidir el lanzamiento

LexMemoria ya permite consultar legislación, leer artículos, preparar tarjetas, estudiar sin cuenta y conservar progreso local. Dispone de cuentas Google Android, sincronización, planificación y colaboración implementadas. El corpus europeo seleccionado está descargado, procesado e integrado en la biblioteca. **Todavía no hay evidencia suficiente para declarar aceptada la aplicación de producción ni publicada en Google Play o App Store.**

La primera versión aconsejada es **Android, gratuita, en español**, centrada en biblioteca, lectura, tarjetas y repaso. Google y copias remotas se pueden incluir si superan la aceptación real. La colaboración pública necesita moderación operativa: si no está preparada, debe quedar deshabilitada para ese lanzamiento mediante un control real del servidor y del cliente. No basta con decidirlo en este documento.

Apple, compras, push, jurisprudencia completa y temarios oficiales exhaustivos pueden incorporarse después. No hace falta terminar todas las aspiraciones futuras para publicar una primera versión acotada y veraz. Sí hace falta que lo anunciado funcione y que las obligaciones sobre datos, soporte y distribución estén resueltas.

**Bloqueos principales:** identidad y política de privacidad definitivas; firma/paquete de tienda; Google y recuperación probados en dispositivos reales; continuidad y recuperación de PostgreSQL; aceptación de rendimiento y accesibilidad; control de publicación de contenido compartido; requisitos y pruebas exigidos por Play Console. No se propone un porcentaje de finalización que oculte esos bloqueos.

## 2. Cómo leer los estados

| Estado | Significado |
| --- | --- |
| Implementado | Existe código y recorrido funcional. La evidencia automatizada se indica cuando está disponible. |
| Pendiente de aceptación real | El desarrollo existe, pero falta comprobarlo con el proveedor, dispositivo, usuarios o despliegue reales. |
| Parcial | Hay una parte útil y otra todavía ausente. |
| Pendiente | No está disponible como función terminada. |
| Decisión del titular | Requiere datos, cuenta, custodia, presupuesto o una decisión que no se debe inventar. |

Una prueba automatizada no acredita revisión jurídica humana. Un proyecto iOS no acredita una compilación Apple. Una respuesta `/health` no demuestra que las cuentas, copias y restauración funcionen. Los documentos antiguos conservan su valor histórico, pero sus contadores y pendientes no sustituyen este inventario.

## 3. Producto, usuarios y navegación

### 3.1 Finalidad

Aplicación de estudio jurídico para estudiantes, opositores y otras personas interesadas. El objetivo académico es opcional; no crea dos aplicaciones ni restringe el acceso a legislación. Universidad aporta asignaturas, evaluaciones y apuntes; oposición aporta organización personal hacia un examen. No existe un catálogo completo y verificado de todas las carreras, universidades o convocatorias.

### 3.2 Estructura de uso

Cinco destinos principales: **Inicio, Estudiar, Biblioteca, Actualidad y Perfil**. Planificador, progreso, asignaturas, cuenta, seguridad y colaboración se abren como recorridos secundarios. No se exige cuenta para estudiar localmente. No hay un feed social obligatorio, chat, seguidores o clasificación pública de notas.

Se han añadido navegación progresiva, detalles desplegables, márgenes inferiores y componentes de lista bajo demanda. Las fechas se presentan para lectura humana, sin milisegundos innecesarios. El perfil permite tema claro, oscuro o del sistema. El idioma funcional es español; guardar una preferencia no equivale a disponer de traducciones completas.

### 3.3 Alcance y límite visual

Biblioteca, listas de tarjetas, mazos preparados e índices disponen de búsqueda y paginación. Los filtros permanecen accesibles cuando la altura disponible permite una cabecera fija; en pantallas bajas se permite desplazarla para dejar sitio a resultados. Existen pruebas de pantallas y navegación, pero falta una aceptación visual exhaustiva en teléfonos físicos, texto grande, teclado, rotación y lectores de pantalla.

## 4. Plataformas y distribución actual

| Plataforma | Disponible | Qué falta para publicación |
| --- | --- | --- |
| Android | APK release de pruebas; Google configurado para paquete preview; pruebas nativas previas en emulador Android 15. | Paquete/firma de tienda, AAB final, aceptación física, ficha y pruebas Play. |
| Web | Cliente Flutter compilable y pruebas de interfaz; datos locales en almacenamiento del navegador. | Hosting aceptado, Google web, política de caché offline y accesibilidad de navegador. |
| iOS | Proyecto Flutter/iOS y código compartido. | Compilar con macOS/Xcode, firma, capacidades, identidad, dispositivo y TestFlight/App Store. |

APK de esta entrega: https://raw.githubusercontent.com/AngelJRM01/LexMemoria/android-google-preview-0.8.1/LexMemoria-0.8.1-google-prueba.apk. El informe de compilación conserva tamaño, hash y firma.

Paquete base del proyecto: `es.lexmemoria.app`. APK de pruebas configurado: `es.lexmemoria.app.preview`. La instalación de uno no es automáticamente una actualización del otro. Antes de cambiar de paquete hay que proteger y probar la transferencia del progreso. Nunca se debe resolver una incompatibilidad de firma pidiendo desinstalar sin conservar los datos.

El APK 0.8.1 verificado declara Android mínimo API 24 (Android 7), objetivo API 36 y arquitecturas arm64-v8a, armeabi-v7a y x86_64. Su tamaño es 89.977.157 bytes; no se ha generado todavía el AAB final de tienda. Declarar target API 36 no acredita por sí solo el cumplimiento de todos los requisitos vigentes de Play.

El proyecto iOS declara versión mínima 15.0; sigue pendiente de compilar y aceptar en Apple.

El certificado de pruebas registrado en Google no sustituye la custodia de la firma de distribución. Los APK genéricos de CI pueden carecer de configuración Google; no se debe asumir que dos APK con el mismo número de versión tienen idénticas capacidades.

## 5. Biblioteca española: contenido y cobertura

### 5.1 Inventario

Catálogo consolidado archivado del BOE: **12.457 normas**, corte del 7 de noviembre de 2026. Incluye legislación estatal y autonómica presente en ese catálogo. El inventario completo consultado de nuevo el 9 de noviembre coincide en identificadores: no se detectaron altas o ausencias respecto a ese corte. Esto no significa vigilancia garantizada en tiempo real ni cobertura de toda norma española histórica o local.

Hay veinte textos BOE incluidos para comenzar sin red: Constitución, Código Civil, Código Penal, LEC, LECrim, LOPJ, Ley 39/2015, Ley 40/2015, Estatuto de los Trabajadores, Ley General Tributaria, Código de Comercio, Ley de Sociedades de Capital, LJCA, LRJS, Ley de Contratos del Sector Público, EBEP, LOPDGDD, Ley de Igualdad, Ley de Bases del Régimen Local y LOTC.

Los restantes textos se solicitan por norma desde paquetes públicos con tamaño y SHA-256. Los paquetes se mantienen fuera de los datos privados de progreso. Descargar un catálogo no descarga todos los textos al teléfono.

### 5.2 Búsqueda y clasificación

- Buscar por título o referencia, sin exigir coincidencia de tildes o mayúsculas.
- Filtrar por materia disponible, ámbito estatal/autonómico y comunidad autónoma.
- Normalizar variantes territoriales, incluidas Baleares y Comunidad Valenciana.
- Marcar normas y mantener referencias seguidas o guardadas.
- Paginación anterior/siguiente, salto numérico y 20/50/100 resultados según pantalla; el cambio de filtro reinicia página y desplazamiento.
- Presentar metadatos de publicación, fuente, versión e información temporal disponible.

Elegir una comunidad muestra legislación autonómica clasificada para ella; no calcula toda la legislación estatal o europea aplicable al territorio. Las materias son clasificación de catálogo, no un programa académico certificado. No se debe anunciar una categoría como banco completo de criminología por el mero hecho de incluir normas penales.

### 5.3 Qué no está cubierto íntegramente

Boletines autonómicos y municipales completos, jurisprudencia de todos los tribunales, bibliografía autorizada, guías universitarias y materiales oficiales de todas las oposiciones. Tampoco hay un buscador jurídico full-text universal de todos los documentos remotos y relaciones normativas. La búsqueda de catálogo y la búsqueda dentro de un texto descargado son funciones diferentes.

## 6. Biblioteca europea completa del alcance seleccionado

### 6.1 Qué se ha descargado e incorporado

**184.737 registros** del inventario CELEX seleccionado —sectores 0 y 3 con expresión española— agrupados en **149.352 actos/documentos**, con todas sus ediciones retenidas. No se anuncia como todo EUR-Lex, todos los idiomas o toda la jurisprudencia europea.

La distribución contiene referencias a **280.961 fuentes**, **525.359 objetos** verificados y **128.675.562 párrafos**. La estructura identifica **1.013.421 candidatos a artículos**: candidato es una clasificación técnica, no una revisión jurídica.

Se han resuelto **28.905 relaciones** entre consolidaciones y acto base contra la relación oficial CDM. No se agrupa sustituyendo sin más un dígito del CELEX. Se conservan originales, consolidaciones, correcciones, metadatos y atribución.

Hay **177.200 ediciones con lectura recuperada** y **177.543 documentos de lectura**. Las otras fichas no se rellenan con texto inventado: **7.534** son solo metadatos y **3 PDF** están corruptos en la fuente archivada. Mantienen su referencia. Quince índices XML de paquete tienen lectura disponible mediante otros archivos; no equivalen a quince obras perdidas.

### 6.2 Funciones visibles

- Entrada separada «Biblioteca europea completa».
- Búsqueda por título oficial y CELEX; filtros de tipo, año, texto disponible y referencias guardadas.
- Paginación 20/50/100, descarga del índice fuera del arranque general y reutilización de la versión ya verificada.
- Ficha con selección de edición y acceso al original; una corrección no sustituye silenciosamente el acto.
- Descarga paginada bajo demanda, progreso de descarga y lectura offline de contenido guardado en nativo.
- Lector que separa artículos, considerandos, preámbulo, anexos y otros apartados; conserva posición por edición/hash.
- Familias de reglamentos, directivas, decisiones, tratados, acuerdos internacionales, documentos institucionales, legislación complementaria y anuncios. El título oficial conserva la denominación concreta.

Una edición con fecha futura no se selecciona por defecto cuando existe una anterior admisible. La fecha de edición no certifica aplicabilidad jurídica. Una directiva y su transposición BOE no se eliminan como duplicado por tratar una materia similar.

### 6.3 Extracción y uso para estudio

HTML, PDF digital, OCR, Word y Formex conservan procedencia y advertencias. No todos los formatos son admisibles para generar ejercicios. La generación europea exige artículos HTML del extractor corregido, sin advertencias estructurales, encabezados ocultos de otros artículos ni numeración ambigua entre partes. Excluye anexos, correcciones, PDF/OCR y actos principalmente modificativos cuando no se pueden presentar como reglas autónomas.

Los textos excluidos del generador siguen accesibles para lectura o en la fuente cuando procede. Archivo completo dentro del alcance no equivale a todas las normas convertidas en tarjetas ni a revisión jurídica íntegra.

## 7. Lector jurídico

El índice de estudio abre artículos. Libros, títulos y capítulos sirven como contexto; preámbulos, disposiciones, anexos y firmas quedan separados. No se borra una disposición transitoria por no ser un artículo.

El lector muestra fragmentos y texto, búsqueda dentro de la norma, coincidencias, notas privadas, referencia, enlace oficial y creación de tarjeta citada. Incluye lectura en voz por el servicio TTS del dispositivo, historial de redacciones y comparación textual por párrafos cuando están disponibles.

Se separan las notas editoriales y las citas históricas contenidas en bloques editoriales del texto usado para leer y generar ejercicios. Los originales XML, hashes, anotaciones e historial permanecen conservados. Una cita normativa que forma parte auténtica del artículo no se elimina como si fuera una nota.

La posición de lectura se aplica solo a la edición/hash correspondientes. El workspace de cuenta puede sincronizar marcadores y lectura; falta aceptar el recorrido completo en dispositivos reales. No se calcula automáticamente una solución jurídica para vigencias parciales, derogaciones tácitas, regímenes transitorios, conflictos normativos o interpretaciones judiciales.

## 8. Mazos preparados y calidad de ejercicios

### 8.1 Preparación

El usuario elige norma, formato y, opcionalmente, nombre de mazo. Hay veinte bancos iniciales incluidos, con 26.922 tarjetas de recuerdo, y generación bajo demanda desde otros textos admitidos. Puede agrupar varias normas en un mazo propio. Los identificadores estables evitan duplicados al repetir una selección.

Cada tarjeta derivada mantiene norma, unidad, versión y hash. La cantidad potencial de ejercicios no es una descarga masiva de todas las tarjetas en el móvil. Tampoco equivale a preguntas oficiales o editorialmente certificadas.

### 8.2 Cuatro formatos automáticos

| Formato | Comportamiento actual | Restricción de calidad |
| --- | --- | --- |
| Recuerdo literal | Pregunta por una regla con pista inicial; respuesta exacta de la fuente. | Se rechazan títulos e introducciones incompletas. Pasajes breves y frases/definiciones completas de hasta 1.200 caracteres. |
| Completar huecos | Dos o tres expresiones jurídicas, instituciones, plazos o importes; respuesta y corrección por hueco. | No palabras al azar, sin solapamiento ni ocultación excesiva; fragmentos de hasta 320 caracteres. |
| Test literal | Fragmento con expresión omitida, cuatro alternativas y solución literal. | Alternativas de categorías más específicas y unidades temporales compatibles; sin tres alternativas válidas se omite el test. |
| Identificar artículo | Fragmento y cuatro referencias de la misma norma. | Se rechazan títulos repetidos y alternativas que también contienen el fragmento. |

La respuesta objetiva y la valoración subjetiva del repaso se conservan separadas. Los huecos normalizan mayúsculas y espacios, conservando distinciones como tildes y ñ.

### 8.3 Correcciones de la revisión actual

- Un título como «Principios relativos al tratamiento» no debe convertirse por sí solo en regla.
- Una introducción terminada en dos puntos o una enumeración truncada no se ofrece como frase completa.
- La frase larga de la Constitución 24.2 no se omite solo por superar 320 caracteres: se conserva entera para recuerdo.
- Las definiciones del RGPD no se cortan en un punto y coma: se conserva la definición completa admisible o se descarta el fragmento.
- Los tests distinguen datos, sujetos, derechos, instituciones y unidades temporales. Los conceptos genéricos sin alternativas fiables no producen un test.
- Las plantillas locales reconocibles e incompletas se archivan sin borrar estados ni repasos; las ediciones personales y copias remotas se preservan. La actualización completa de otros mazos requiere volver a preparar el formato.
- Si una tarjeta local mantiene identidad, fuente, revisión y respuesta, se pueden renovar redacción/opciones sin reiniciar el historial. No se sobrescribe contenido personal editado.

### 8.4 Lo que todavía no existe como banco terminado

Preguntas conceptuales de todo el Derecho, explicaciones jurídicas profesionales para cada respuesta, casos corregidos jurídicamente, glosarios y resúmenes completos, dificultad calibrada, temarios verificados y preguntas oficiales con derechos de reutilización. Las tarjetas generadas siguen siendo **ejercicios literales automáticos**, aunque superen todos los controles técnicos.

## 9. Tarjetas personales, importación e historial

Editor con mazo, pregunta, respuesta, explicación, opciones y solución. Admite QA, huecos, verdadero/falso, ordenación, casos y test. Los casos y respuestas abiertas son autoevaluados; no hay corrección jurídica automática del razonamiento.

Se mantienen borradores, revisiones previas, referencias y progreso. Hay búsqueda por contenido y referencia, favoritas, fallos e historial. El usuario puede consultar ejercicios automáticos archivados.

Importación privada CSV UTF-8: hasta 2 MB y 2.000 tarjetas, validación y confirmación del lote. No se ejecutan fórmulas ni HTML. No está terminada la importación Anki `.apkg`, un repositorio general de archivos compartidos ni el escaneo de adjuntos multimedia.

## 10. Repaso espaciado y sesiones

Algoritmo **SM-2 adaptado, versión sm2-1**; no es FSRS. Valoraciones Otra vez, Difícil, Bien y Fácil. Conserva intervalo, facilidad, repeticiones, fallos y próxima revisión por tarjeta.

La cola prioriza vencidas, límites diarios, mazos y preferencias; excluye tarjetas bloqueadas y respeta descansos y vacaciones. Conserva sesión para continuar. Cada evento registra la revisión de contenido, instante, latencia, respuesta y estado anterior.

Deshacer alcanza la última revisión local no sincronizada; no elimina silenciosamente un evento ya remoto. No existe compensación remota general de deshacer ni un modelo validado de probabilidad de aprobar. La eficacia pedagógica del algoritmo y los ejercicios no se da por certificada.

## 11. Planificación, universidad y simulacros

### 11.1 Planificador

Objetivo diario de 5 a 200 tarjetas, disponibilidad de 0,5 a 8 horas, descansos, vacaciones y examen opcional. Prioridades de mazos y tipos preferidos. Previsión semanal y estimación de minutos basadas en estados actuales; no simula todas las respuestas futuras ni garantiza terminar un temario.

Queda pendiente un optimizador integral de calendario por competencias/temas, cobertura oficial y retención calibrada.

### 11.2 Organización académica

Asignaturas privadas con institución y semestre/curso, temas y apuntes; archivo y recuperación. Evaluaciones ponderadas, puntuación máxima y nota opcional; se validan pesos y valores. Las evaluaciones pendientes no redistribuyen su peso ni generan una nota futura ficticia.

No hay importación completa de guías docentes autorizadas ni correspondencia verificada de todos los artículos con planes de estudios y oposiciones. Las plantillas personales no se etiquetan como programas oficiales.

### 11.3 Simulacros y progreso

Simulacros personales con tarjetas test instaladas y no bloqueadas, cantidad, duración y penalización configurables. Congelan las preguntas/revisiones, guardan respuestas y permiten continuar; temporizador, cierre y resultado con aciertos, fallos, blancas y puntuación.

Historial y progreso por mazo, revisiones recientes y proporción de valoraciones. Las soluciones están localmente para corregir offline: no es una plataforma de examen supervisado. Faltan reglas oficiales por convocatoria, bancos autorizados y análisis avanzado de competencias.

## 12. Cuentas, identidad y seguridad de sesión

### 12.1 Identidad disponible

Estudio local sin correo. Cuenta remota invitada y acceso Google Android mediante Firebase Auth/Google Sign-In. Proyecto comunicado: `lexmemoria-aa86a`. El backend verifica token Firebase, firma, emisor, proyecto, fechas y proveedor; no confía solo en un UID recibido.

Vincular una identidad conserva la cuenta compatible; una colisión exige tratamiento explícito. Cancelar el acceso no sube progreso. Cambiar cuenta o servidor no mezcla datos silenciosamente ni reutiliza credenciales de otro ámbito.

### 12.2 Seguridad y recuperación

Sesiones propias con refresh rotatorio, revocación, cierre actual/otras sesiones y última actividad aproximada. Código privado de recuperación con recibo idempotente frente a respuestas perdidas. Las credenciales quedan fuera de copias y exports educativos.

El borrado de cuenta tiene confirmación e identidad fresca, eliminación/anonimización asociada y reintento durable si falla la parte del proveedor. Falta aceptar de extremo a extremo la coordinación con Google real.

### 12.3 Pendiente

Aceptar Google, recuperación y borrado en móviles reales; registrar paquete y certificados definitivos para Play. Apple está aplazado. Google web/iOS, contraseña propia y correo transaccional no están operativos como oferta terminada.

## 13. Sincronización y cambio de dispositivo

Sincronización opcional de mazos, tarjetas, revisiones, eventos y estados privados; perfil/preferencias, objetivos, cursos, temas, notas, seguimientos, marcadores, lectura e historial de simulacros mediante workspace versionado.

Las peticiones de autenticación esperan hasta 90 segundos para tolerar el arranque de la API gratuita; las demás mantienen generalmente 30 segundos. Son límites de espera del cliente, no una promesa de respuesta rápida del proveedor.

La primera sincronización es explícita. Hay consentimiento separado para automatización posterior mientras la aplicación está abierta. No hay servicio nativo que garantice sincronización con la app cerrada.

Se aplican IDs estables, idempotencia, reintentos, espera progresiva, Retry-After y control de revisión. Se suben revisiones de contenido antes de los eventos asociados. Los conflictos conservan ambas versiones y comparaciones por sección; un cambio de cuenta/servidor durante la petición invalida la operación. Una escritura fallida no se presenta como confirmada.

El error 422 por citas privadas a versiones todavía no importadas al servidor tiene regresión y corrección: se conserva referencia completa como `pending_source` sin inventar normas ni declararla verificada. No se ha acreditado aquí que desaparezca en el teléfono con el despliegue actual.

**Aceptación obligatoria pendiente:** crear/estudiar/editar offline en A, sincronizar, recuperar en B, comparar tarjetas/eventos/estados/notas/lectura, provocar conflicto, resolver sin pérdida, reiniciar servidor y repetir. Una pantalla de éxito no basta.

## 14. Perfil, contactos y colaboración

### 14.1 Perfil

Nombre/alias opcional, UID estable, tema, iniciales/avatares y foto propia privada. Alias normalizado, único, con reservados y retención de 30 días del alias retirado. Validación técnica de imagen, bytes/píxeles y retirada de EXIF. La importación de foto de Google está preparada con consentimiento, identidad fresca y hosts permitidos, pendiente de aceptación con el proveedor real. No hay un sistema terminado de clasificación humana/automática de imágenes inapropiadas.

Descubrimiento por alias y por enlaces son opciones independientes, apagadas por defecto. No se publica el correo ni se crea un directorio abierto de usuarios.

### 14.2 Contactos, mazos y grupos

Solicitudes, aceptar/rechazar/cancelar, eliminar y bloquear. Mazos privados por defecto; invitaciones con permisos, caducidad, límite de usos y revocación. Copia personal con IDs propios y atribución; no comparte progreso y no incorpora cambios del autor sin comparación/confirmación.

Grupos privados con nombre, descripción, icono, tema y tipo; roles de administrador, colaborador y miembro; entrada/salida, expulsión, cambios de rol y recursos organizados. Eliminar grupo conserva mazos personales. No se comparten automáticamente notas o calificaciones. Compartir resúmenes de objetivos mediante consentimiento específico está pendiente.

La API comprueba permisos y bloqueos; no se limita a esconder botones. Un enlace revocado no puede borrar una copia legítima previamente descargada.

### 14.3 Catálogo y moderación

Catálogo secundario con búsqueda, filtros, paginación, autor, fecha, preview, copia y denuncia. Publicación explícita, retirada, reportes, restricciones justificadas, apelación y auditoría. Moderar no equivale a aprobar jurídicamente.

Faltan revisión humana operativa, responsables/plazos y gateway MFA real del personal. Los enlaces tienen landing y aceptación pegando el enlace; no hay Android App Links/universal links verificados terminados. No existe compartición general de PDF/archivos.

Para una primera publicación sin equipo de moderación se recomienda desactivar catálogo público y publicación, manteniendo estudio privado. Esa reducción exige implementar y probar el bloqueo de servidor/cliente antes de distribuir una versión que lo anuncie.

## 15. Actualidad y notificaciones

Actualidad muestra eventos, fuente, fechas y estados; carga incremental por cursor. Sigue normas y permite bandeja interna opcional, deduplicación y marcado de lectura. Los conectores BOE tienen checkpoints, recuperación de intervalos y cola de importación.

Los avisos distinguen estudio, jurídica y colaboración; tienen preferencias, silencio Europe/Madrid y límite diario. Los recordatorios de estudio se calculan al consultar, respetando plan y descanso. **Bandeja interna no equivale a push.**

No está aceptado un servicio productivo continuo de actualización con alertas de fallo. Tampoco FCM/APNs, tokens de dispositivo, permisos, recepción con la app cerrada o navegación desde notificación. No se asegura que una pantalla vacía signifique ausencia de cambios legales.

## 16. Almacenamiento, copias y protección de datos

Estado nativo en SQLCipher con clave separada en Keystore/Keychain. Snapshots fragmentados y escritura transaccional para evitar límites de cursor Android. Migración que verifica destino antes de retirar origen. Paquetes públicos separados de datos privados; caché nativa y carga bajo demanda.

Exportación/restauración JSON con validación, sin tokens, claves ni autoridad de sincronización. **El JSON de usuario es legible**, no un archivo cifrado. Borrar/restaurar pide confirmación y no habilita consentimientos remotos heredados. Web no tiene la misma protección SQLCipher y depende del almacenamiento del navegador.

Hay pruebas nativas previas en emulador Android 15 y pruebas de errores/rollback; falta aceptación OPPO real, iOS y escenarios completos de cierre abrupto, almacenamiento escaso y actualizaciones entre versiones.

Las preferencias de analítica y comunicaciones no equivalen a servicios conectados: no hay proveedor de analítica o publicidad operativo incorporado. El audio TTS utiliza la plataforma del dispositivo, con sus condiciones y disponibilidad.

Las herramientas de backup de servidor soportan cifrado e integridad y se probaron con PostgreSQL local. No acreditan copias del proveedor de producción, política de retención ni recuperación operativa periódica.

## 17. Backend y operación

FastAPI/Python, SQLAlchemy, SQLite de desarrollo y PostgreSQL obligatorio en staging/producción. El esquema utiliza agregados JSON y tablas dedicadas de cuentas, tokens, recuperación, idempotencia y auditoría. No equivale al modelo relacional completo aspiracional de todas las especificaciones.

APIs de biblioteca/consulta, versiones, novedades, identidad, mazos, tarjetas, revisiones, workspace, colaboración, reportes, moderación, avisos, simulacros y administración. El anexo generado inventaría rutas presentes en código. Persisten límites de cuerpo, CORS explícito, autorización por recurso, If-Match y transacciones.

Ingestión con originales y hashes, validación de XML, cuarentena, trabajos persistentes, lotes, leases, reintentos y checkpoints. La exportación europea publica objetos y activa manifiesto al final; los lectores verifican tamaños y hash.

Render comunicado por el titular: API `https://lexmemoria-api.onrender.com`, PostgreSQL y API Free, Frankfurt. El titular confirmó una respuesta de salud en una fase anterior. No se acredita desde esta revisión el commit actualmente Live ni toda la operación remota.

El panel aportado indica caducidad de PostgreSQL el **6 de diciembre de 2026**. Debe comprobarse la situación actual y resolver continuidad y restauración antes de esa fecha. No se ha contratado ni cambiado un plan automáticamente. No se incluyen secretos en este documento.

Pendientes operativos: despliegue actual comprobado, backups del proveedor y restauración ensayada, monitorización/alertas, capacidad y pruebas de carga, retención, migraciones versionadas futuras, RPO/RTO y soporte. El arranque en frío de Render Free puede añadir espera aunque la lectura local esté optimizada.

## 18. Rendimiento y límites medidos

Se han retirado descompresiones de normas guardadas antes de Inicio, se reutilizan catálogos/índices y colecciones sin cambios, se selecciona una cola acotada y se descarga Europa por índice/páginas. No se descomprime un anexo de millones de párrafos para abrir una página.

Los informes históricos de host registran mejoras importantes en accesos repetidos al catálogo, lectura de tarjetas y selección de sesiones. El catálogo europeo completo se carga una vez y se reutiliza durante sesión. Estas mediciones no se presentan como latencia del OPPO ni como garantía para redes móviles.

En la revisión actual se evita analizar las definiciones de un artículo para cada tarjeta: se conserva solo el último artículo analizado. En un caso real (BOE-A-2023-11022), la generación QA pasó de 332,2 a 203,3 ms en host bajo carga (medianas de tres ejecuciones alternadas tras calentamiento), con las 851 tarjetas idénticas; los cuatro formatos conservaron exactamente su salida. Es una medición de desarrollo, no del teléfono.

Para publicar se propone medir, todavía sin aceptación: arranque a Inicio sin red, abrir Constitución, abrir una norma europea ya guardada, buscar/paginar, preparar un mazo y guardar un repaso. Registrar p50/p95, memoria y fallos en dispositivo físico con un conjunto fijado; separar primera descarga, caché y espera del proveedor. Los umbrales de aceptación deben aprobarse tras esa medición, no inventarse como resultados.

## 19. Revisión jurídica y evidencia de esta entrega

Contraste online del **9 de noviembre**: inventario BOE completo; veinte fuentes BOE principales idénticas a las archivadas; veintidós registros con metadatos de actualización distintos, descargados y comparados sin cambios de cuerpos, notas o historial. Tres fuentes UE —RGPD, Directiva 2019/1152 y Decisión 2021/914— coinciden con los hashes archivados. No se anuncia esto como consulta en tiempo real del 10 de noviembre.

El diario manual de esta revisión registra **19 artículos leídos completos**, continuando la lectura el 10 de noviembre. Se revisaron casos de Constitución, Código Penal, procedimiento administrativo, LOPDGDD, RGPD y Directiva 2019/1152, y muestras reales de los cuatro formatos de tarjetas. No se ha leído manualmente cada artículo de las 12.457 normas BOE y 184.737 registros UE.

La revisión automática europea recorrió los **149.352 actos** y comprobó los ejercicios de **87.603 ediciones admitidas**, con **713.924 artículos admitidos**. Produjo 2.171.522 tarjetas QA, 116.045 huecos, 87.363 tests y 1.659.666 referencias técnicamente válidas. Son ejercicios derivables, no todos precargados ni jurídicamente certificados. Los motivos de exclusión pueden afectar a un artículo o a una edición; sus contadores no deben sumarse como si fueran obras distintas.

La auditoría BOE final ha validado las 12.457 normas: 1.427.352 tarjetas QA, 31.087 huecos, 79.344 tests y 1.223.774 referencias. El informe está ligado al hash del catálogo y comprueba citas, respuestas y estructura de los cuatro formatos. No equivale a revisión jurídica humana. Suite final registrada del código funcional: **215 pruebas backend y 140 Flutter**, incluida integración europea real; comprobar los informes adjuntos para el análisis y compilaciones posteriores. Los resultados de 0.8.0 se conservan separados.

La base editorial incluye estados de procedencia, revisión de citas y separación entre autor y revisores; la aprobación exige dos revisores distintos sobre la revisión concreta. Las rutas editoriales quedan condicionadas a configurar una pasarela MFA. Esto no instala un proveedor MFA real ni constituye un equipo de revisión. Faltan el backoffice editorial completo, asignación/checklists, RBAC detallado por tenant, auditoría firmada y rollback editorial operativo.

No hay certificación profesional de ausencia de errores, vigencia completa, seguridad integral o accesibilidad universal. El ledger deja las normas completas pendientes de lectura manual y enlaza las lecturas parciales efectivamente hechas.

## 20. Privacidad, eliminación y obligaciones de tienda

Implementadas páginas técnicas `/account/privacy` y `/account/delete`, endpoints de borrado/exportación y flujos del cliente. La página de privacidad devuelve estado pendiente si no se configuran responsable, contacto y URL real. La eliminación web requiere configuración pública web Firebase y dominio autorizado; que exista el HTML no significa que esté operativa.

El titular pidió dejar pendientes nombre del responsable y correo público: **siguen pendientes**. Faltan política definitiva, conservación, menores/público objetivo, encargados del tratamiento y contratos aplicables, canal de derechos y soporte, revisión de licencias y condiciones del servicio. No se deben rellenar con una identidad ficticia.

Para Google Play hay que completar ficha, clasificación, declaración de seguridad de datos, política pública, acceso de revisores, publicidad y audiencia según el comportamiento real. Se deben revisar en Play Console los requisitos vigentes de API objetivo, pruebas y acceso a producción; dependen del tipo/fecha de la cuenta y pueden cambiar. Este documento no da por verificada la cuenta ni inventa plazos de aprobación.

Fuentes oficiales para verificar los requisitos al preparar el envío: Android Developers — requisitos de API objetivo; ayuda Play Console — seguridad de datos, eliminación de cuenta y pruebas de cuentas personales; Apple App Review Guidelines para un futuro iOS. Las URL de referencia aparecen al final. Se intentó consultarlas desde este entorno el 10 de noviembre, pero el proxy rechazó esas conexiones; por ello no se dan umbrales ni plazos actuales como verificados. Deben contrastarse en la consola y documentación oficiales al enviar.

## 21. Monetización y planes

Hay derechos/capacidades Free, Estudiante Plus y Opositor Pro y pantallas informativas. No hay compras reales verificadas de Google Play Billing/StoreKit. El endpoint de validación no concede compras no verificadas. La pantalla actual muestra 3,99 €/mes para Estudiante Plus y 7,99 €/mes para Opositor Pro como propuesta informativa; no son una oferta final aprobada ni una compra habilitada. Existe una promoción interna de 30 días calculada por servidor, sin cobro ni renovación automática.

Primera versión recomendada: gratuita, sin activar pagos ni anunciar suscripciones contratables. No se borran datos ni se retira recuperación/exportación por caducidad de un derecho. Si se monetiza después hacen falta productos, precios, validación oficial servidor, restauración, reembolsos, gracia, revocación, pruebas sandbox y obligaciones comerciales.

## 22. Propuesta concreta de primera versión

| Módulo | Propuesta V1 | Condición |
| --- | --- | --- |
| Biblioteca BOE y europea | Incluir. | Cobertura y excepciones visibles; no anunciar «todo el Derecho vigente». |
| Lector y descarga offline | Incluir. | Prueba física con red cortada y actualización sin pérdida. |
| Tarjetas y SM-2 | Incluir. | Generador revisado, trazabilidad, reportar error y límites claros. |
| Planificador/asignaturas/simulacros | Incluir. | No anunciar temarios o corrección jurídica oficiales. |
| Google y recuperación | Incluir tras aceptación. | Dos dispositivos, conflictos, borrado y persistencia reales. |
| Compartición privada | Incluir solo tras aceptación. | Permisos, invitaciones, bloqueo y soporte comprobados. |
| Publicación pública de mazos | Aplazar si no hay moderación. | Implementar cierre cliente/servidor; no basta ocultar acceso. |
| Actualidad | Incluir si se opera actualizador. | Mostrar última actualización y evitar promesa de cobertura continua no operada. |
| Push, Apple, pagos | Aplazar. | No presentarlos como disponibles. |
| Jurisprudencia/temarios oficiales completos | Aplazar. | Fuentes, derechos y validación profesional antes de anunciarlos. |

Esta tabla propone un alcance; no afirma que las funciones a aplazar ya estén desactivadas en el binario. Cualquier cambio de alcance debe aplicarse y comprobarse antes de producir el AAB.

## 23. Lista de cierre: bloqueos, responsable y aceptación

| ID | Trabajo pendiente | Responsable principal | Se cierra cuando |
| --- | --- | --- | --- |
| B01 | Identidad legal, correo de soporte y política pública. | Titular + asesoría cuando proceda. | URLs públicas finales, contacto válido y política coherente con app/API/Firebase/Render. |
| B02 | Paquete de tienda, custodia de claves y Play App Signing. | Titular; preparación técnica asistida. | Firma/IDs definidos, certificados Firebase registrados y actualización ensayada. |
| B03 | Google y sincronización real. | Desarrollo + titular/dispositivos. | A y B recuperan el mismo progreso, conservan conflictos y sobreviven reinicio/red irregular. |
| B04 | Continuidad PostgreSQL y backups. | Titular/proveedor + desarrollo. | Base sin caducidad incompatible, backup restaurado y datos de prueba comparados. |
| B05 | Rendimiento y navegación física. | Desarrollo + probadores. | Recorridos medidos en OPPO y otro Android; sin recortes, bloqueos o esperas inexplicadas. |
| B06 | Accesibilidad básica. | Desarrollo + probadores. | TalkBack, texto grande, foco, contraste y controles principales aceptados. |
| B07 | Publicación/colaboración segura. | Titular + desarrollo/moderación. | Equipo y proceso operativos, o funciones públicas realmente deshabilitadas en cliente/API. |
| B08 | Borrado/exportación de cuenta. | Desarrollo + titular. | App y vía web aceptadas con Google real y política de retención definida. |
| B09 | Revisión del material que se anuncia. | Responsable de contenido + desarrollo. | Alcance piloto definido, hallazgos resueltos y carácter automático declarado; sin sello editorial ficticio. |
| B10 | Despliegue y observabilidad. | Desarrollo + acceso del titular. | Commit Live identificado, health y pruebas funcionales, alertas y rollback comprobados. |
| B11 | Ficha y formularios Play. | Titular; preparación técnica asistida. | Capturas/textos/datos/privacidad/audiencia/revisores completos y coherentes. |
| B12 | AAB y pruebas de tienda. | Desarrollo + titular Play Console. | Artefacto firmado, API objetivo y requisitos vigentes comprobados; pruebas exigidas y acceso a producción aprobados. |

No es imprescindible un dominio personalizado para que una URL HTTPS pública estable cumpla su función. Sí son imprescindibles páginas accesibles, exactas y bajo control operativo del responsable. Tampoco es imprescindible un Mac propio: para iOS habrá que usar un entorno macOS autorizado y firma Apple, local o CI, con sus cuentas correspondientes.

## 24. Qué puedes hacer tú ahora

1. Elegir nombre del responsable y correo público de soporte. No hace falta enviar contraseñas o claves.
2. Comprobar estado de tu cuenta Play Console y los pasos/pruebas que exige su panel; registrar qué está aprobado y qué falta.
3. Confirmar continuidad y plan de PostgreSQL antes del vencimiento comunicado; no crear otra base borrando la actual sin migración/copia.
4. Definir quién custodiará firma y cuenta de tienda, y confirmar el paquete de publicación.
5. Reservar dos instalaciones/dispositivos de prueba para la aceptación Google y recuperación, conservando antes una copia del progreso único.
6. Decidir si V1 tendrá publicación de mazos o solo contenido privado; si se publica contenido de terceros, designar moderación y soporte.
7. Revisar el alcance propuesto de V1 y los textos comerciales: no prometer preguntas oficiales, revisión humana integral o cobertura universal que no existen.

## 25. Qué puede seguir haciendo desarrollo sin nuevas decisiones

Corregir errores de código y ejercicios, ejecutar suites y auditorías del corpus, conservar fuentes/evidencias, mejorar lector/listas/rendimiento, preparar artefactos y ficha de pruebas, redactar borradores legales con campos pendientes, diseñar la aceptación y arreglar incidencias reproducibles. Puede preparar un despliegue y comprobarlo cuando haya acceso autorizado suficiente.

No puede inventar identidad legal, verificar una cuenta de tienda en tu nombre, custodiar tus claves sin un mecanismo adecuado, aceptar compras o planes de pago por inferencia ni afirmar que ha probado tu móvil sin acceso a él. Los bloqueos externos se mantienen explícitos; el resto del trabajo puede continuar.

## 26. Prueba de aceptación de la V1

- Instalar/actualizar sin perder perfil, tarjetas, estados, notas y sesión.
- Abrir Inicio sin cuenta y sin red; leer Constitución y un texto europeo previamente guardado.
- Buscar y filtrar, cambiar página, volver al lector y recuperar posición de la edición correcta.
- Preparar los cuatro formatos admitidos, comprobar ejemplos contra el artículo original, editar una tarjeta y volver a preparar sin perder esa edición.
- Repasar, cerrar app, reiniciar y continuar; verificar objetivo, descanso y simulacro.
- Exportar/restaurar con datos de prueba; rechazar archivo inválido sin sustituir el estado correcto.
- Iniciar Google y recuperar en segundo dispositivo; repetir con red irregular y edición concurrente, sin duplicados ni desaparición de historia.
- Revocar sesión, cambiar cuenta y borrar cuenta de prueba mediante app y vía web; verificar aislamiento y resultado del proveedor.
- Si hay compartición, intentar acceso sin permiso, revocar enlace, bloquear, denunciar y comprobar retirada remota.
- Verificar TalkBack, texto grande, teclado, scroll inferior y ausencia de información cortada.
- Reiniciar API, restaurar backup en entorno separado y comparar datos; comprobar alertas de fallo.
- Instalar el AAB mediante el canal de pruebas de Play y repetir acceso, actualización y restauración con la firma de tienda.

Cada escenario debe registrar versión/hash, dispositivo, cuenta de prueba, fecha, resultado y evidencia sin credenciales. Un fallo que afecte a pérdida de datos, acceso ajeno o recuperación bloquea publicación.

## 27. Fuentes, trazabilidad y anexos

Código principal: `mobile/lib/`, `backend/app/`, `scripts/`, `render.yaml`, `.github/workflows/ci.yml`. Pruebas: `mobile/test/`, `mobile/integration_test/`, `backend/tests/`.

Evidencia de revisión actual: `docs/validation/content-review-2026-11-09/`. Incluye contraste BOE/UE, diario de lectura manual y ledger de normas pendientes. Los resultados históricos 0.8.0 siguen en `docs/validation/0.8.0/`. La matriz de cuentas conserva detalle de implementación y límites en `docs/accounts/MATRIZ_0_6_0.md`; sus notas de publicación son históricas, no el estado actual de GitHub.

Lista de cierre editable para seguimiento: `CIERRE_PRIMERA_VERSION_2026-11-10.csv`. Contrato API actual: `validation/content-review-2026-11-09/openapi-0.8.1.json`.

Anexo técnico de rutas y pantallas: `ANEXO_TECNICO_2026-11-10.md`. Los nombres de pantallas/rutas acreditan existencia en código, no aceptación real de todos los flujos.

Referencias oficiales para la preparación final:

- BOE: https://www.boe.es/datosabiertos/ y https://www.boe.es/buscar/legislacion.php
- EUR-Lex: https://eur-lex.europa.eu/homepage.html?locale=es
- Google Play, API objetivo: https://developer.android.com/google/play/requirements/target-sdk
- Play Console, seguridad de datos: https://support.google.com/googleplay/android-developer/answer/10787469
- Play Console, eliminación de cuenta: https://support.google.com/googleplay/android-developer/answer/13327111
- Play Console, pruebas de cuentas personales: https://support.google.com/googleplay/android-developer/answer/14151465
- Apple App Review Guidelines: https://developer.apple.com/app-store/review/guidelines/

La primera publicación debe describir exactamente el producto aceptado. El documento sirve para evaluar ese cierre; no sustituye la revisión de tienda, la aceptación del titular ni una certificación jurídica.
