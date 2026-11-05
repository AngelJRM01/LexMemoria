# Revisión de la experiencia de estudio · 0.2.0+3

Cambios solicitados el 5 de noviembre de 2026:

| Petición | Resultado |
| --- | --- |
| Pantallas minimalistas | Inicio con sesión diaria y accesos a tareas. Perfil dividido en cuenta/copias, plan, progreso y ajustes. Descansos, vacaciones, previsiones, fuentes e historiales desplegables. Opciones secundarias de tarjetas en menú. |
| Aclarar universidad/oposiciones | Se pregunta qué se quiere hacer: leer y repasar, preparar un examen o seguir asignaturas. El objetivo se puede cambiar en ajustes sin borrar progreso ni limitar herramientas. Materia principal y planificación se piden por separado. |
| Espacio inferior | SafeArea, margen adicional y espacio de desplazamiento en páginas. Navegación por fragmentos y guardar plan protegidos por el área segura. |
| Tarjetas preparadas | 13.914 tarjetas literales distribuidas en 20 mazos. Primeras 20 listas al iniciar. Añadir un mazo conserva tarjetas editadas y repasos, sin duplicarlos. Cada respuesta cita norma, bloque, versión y hash. No se presenta como revisión editorial. |
| Fechas funcionales | Fechas DD/MM/AAAA y sincronizaciones con HH:MM. Las marcas precisas se mantienen en almacenamiento e intercambios; el cronómetro del simulacro conserva segundos útiles. |
| Filtros fijos | Biblioteca, estudio, índice, lector, mazos preparados, lista de tarjetas, actualidad y asignaturas mantienen controles sobre los resultados. En poca altura se permite desplazar la página completa para que el teclado no bloquee el contenido. |
| Progreso entre dispositivos | Pantalla de cuenta y copias; subida y recuperación con código cuando existe servidor HTTPS. Copia como archivo JSON para evitar el límite de tamaño de intents Android; restauración hasta 64 MiB. No hay servidor de producción desplegado, ni se simula acceso Google/Apple. |
| Artículos legibles | Fragmentos o artículo completo; párrafos separados, numeración resaltada, búsqueda resaltada y tamaño de letra persistente. Historial, fuente y fecha de estudio en opciones; notas en una hoja aparte. No se reescribe el contenido jurídico. |

## Validación

- 45 pruebas Flutter, incluidas persistencia, actualización sin pérdida de historial, filtros fijos, navegación del lector, área segura, copias grandes y pantallas con texto al 200 % en 390×844 y 700×360.
- Análisis Flutter sin incidencias.
- 70 pruebas backend. La prueba de recursos contrasta todas las respuestas preparadas con su fuente BOE, sus hashes y sus referencias, e incluye los artículos del Código Civil denominados «Art».
- Revisión de renders reales de las pantallas en `/workspace/lexmemoria-preview`. No sustituye una prueba en el OPPO físico.
- APK privado release, identificador `es.lexmemoria.app.preview`, firma de pruebas; no es una firma para tiendas. Deben conservarse los datos de instalaciones anteriores.

## Descargas: alcance y límites actuales

El archivo BOE ya verificado mantiene los 12.451 identificadores del catálogo consolidado observado. Ese archivo no se ha insertado entero en el APK: los paquetes de lectura incluidos siguen siendo las 20 normas de la biblioteca inicial.

`python -m app.eu_bulk run` descarga mediante la interfaz pública CDM de la Oficina de Publicaciones. El recuento inicial identifica 184.706 obras CELEX de los sectores 0 y 3 con expresión española; no significa que todas estén descargadas ni que sean todas leyes vigentes. El inventario y las descargas se ejecutan en paralelo, con límite compartido de peticiones. Se conserva una manifestación textual y todos sus archivos asociados. Los estados completos, solo metadatos, pendientes y fallidos son distintos; la integridad y la cobertura se informan por separado.

Archivo europeo: `/workspace/lexmemoria-eu-corpus`. Estado: `status.json`; objetos originales comprimidos con SHA-256; base e inventarios en `archive.sqlite3`. El lock impide duplicar el trabajador y los trabajos interrumpidos vuelven a encolarse al reanudar. `python -m app.eu_bulk status` y `python -m app.eu_bulk verify` permiten inspeccionarlo. No se eluden respuestas de protección de EUR-Lex; CDM es otra interfaz oficial del mismo organismo.

El primer recorrido de los 73 enlaces de otros boletines conserva 123 documentos enlazados: 120 PDF, 2 XML y 1 RSS. También archiva páginas de entrada y reglas de acceso. **No es una descarga de sus catálogos históricos.** Hay fuentes excluidas por robots, respuestas restringidas y destinos redirigidos. El informe individual está en `/workspace/lexmemoria-additional-sources/status.json`.

Se ha guardado, sin aplicar ni publicar, un borrador que añade únicamente los destinos oficiales redirigidos `docm.jccm.es`, `web.larioja.org`, `app.dipalme.org` y `bop.dipgra.es`. Requiere revisión y publicación por el titular para habilitar esos destinos. Las restricciones de robots o del propio proveedor no se resuelven ampliando la red.

Los datos públicos descargados quedan fuera de Git y de las bases personales del móvil. Una descarga en segundo plano depende de que esta máquina siga encendida; operación permanente y cuentas de producción requieren servidor y almacenamiento persistentes.

Para reintentar exclusivamente destinos redirigidos tras aplicar el borrador de red: `python scripts/archive_official_sources.py --retry-network-blocked`. Se conservan los resultados anteriores; no se vuelve a recorrer automáticamente una fuente excluida por robots.
