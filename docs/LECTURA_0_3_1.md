# Lectura y búsqueda · 0.3.1+5

La biblioteca permite buscar dentro del texto descargado de una norma. El selector **Índice / Texto** conserva el término escrito; la búsqueda de texto ignora mayúsculas y tildes y consulta la última redacción de cada bloque. No mezcla redacciones históricas con el resultado actual. Al abrir una coincidencia, el lector muestra el fragmento donde aparece y conserva la búsqueda para resaltarlo.

En Android/iOS el índice de texto se prepara fuera del hilo de interfaz y se reutiliza mientras la pantalla permanece abierta. Tanto el índice de artículos como el artículo completo construyen sus filas según se necesitan. La búsqueda funciona con los textos guardados sin necesitar servidor ni conexión.

El lector guarda el último fragmento visitado por artículo y ofrece **Continuar** en el índice de la norma. El punto de lectura conserva el identificador de norma, artículo, versión de norma y hash de la redacción. Solo se recupera cuando coinciden; una actualización no reutiliza a ciegas el número de fragmento anterior. La consulta por fecha de estudio no sustituye el punto de lectura guardado.

Al cambiar de fragmento, redacción o modo de lectura se vuelve al principio del contenido visible. Vaciar la búsqueda del artículo recupera la posición de lectura en vez de desplazar al usuario al primer apartado.

La posición se incluye en la copia JSON del progreso y usa el almacén privado existente: cifrado en Android/iOS, preferencias locales en web. Esta mejora no activa sincronización de lectura entre dispositivos ni despliega las cuentas de producción.

## Descarga europea

El archivador acepta documentos Word antiguos cuando la fuente no ofrece los formatos preferidos HTML, Formex o PDF. Exige el tipo `application/msword` y la cabecera binaria OLE; conserva los bytes originales, SHA-256 y atribución, sin ejecutar el documento ni inventar texto convertido.

`python -m app.eu_bulk requeue-supported` devuelve a la cola únicamente registros anteriormente excluidos cuyo formato ya se soporta. No modifica registros completos ni borra checkpoints. Se ha recuperado y comprobado el documento oficial CELEX `32015M7836`: [evidencia](validation/eu-word-0.3.1.json). La descarga general continúa y sigue incompleta; el catálogo móvil no anuncia una integración europea completa.

## Validación

- 54 pruebas Flutter pasan, incluidas recuperación del fragmento, rechazo de posiciones con fuente distinta, copia JSON, búsqueda con tildes, exclusión del texto histórico y apertura de coincidencias.
- Se prueban un índice de 10.000 artículos y una vista completa de 10.001 fragmentos, comprobando que construyen solo las filas visibles. Se verifica el reinicio del desplazamiento al pasar de un fragmento largo al siguiente.
- 73 pruebas backend pasan; tras añadir selección de un documento concreto se repitieron las siete pruebas del archivador europeo, todas correctas.
- Análisis Flutter sin incidencias. Compilaciones web JavaScript release y APK Android release correctas. El APK conserva el identificador de prueba `es.lexmemoria.app.preview`, sin `application-debuggable` y con firma de pruebas verificada: [datos y SHA-256](validation/android-0.3.1.json).

No se ha realizado un recorrido físico en el OPPO ni compilación iOS en esta entrega. La firma local de pruebas no garantiza compatibilidad con la de un runner temporal de GitHub; conservar el progreso y su copia antes de cambiar de instalación. Los resultados de GitHub Actions se consultan por separado.
