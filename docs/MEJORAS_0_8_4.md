# LexMemoria 0.8.4 — arranque, lectura y edición

El cliente reduce trabajo repetido y mueve el análisis de datos grandes fuera del hilo de interfaz en Android. El esquema de persistencia, las fuentes jurídicas y el servidor no cambian; la API puede seguir mostrando 0.8.2.

## Cambios

El catálogo y el estado privado se cargan en paralelo. Los estados grandes se analizan en un trabajador que también prepara el recuento diario, evitando repetir ese recorrido en la primera pantalla. Se conservan los campos desconocidos y la migración verificada del estado anterior. En web, `compute` no garantiza un trabajador independiente.

Las instancias del lector europeo de una misma sesión comparten descargas pendientes y objetos ya verificados. La caché conserva como máximo cuatro objetos y 16 MiB de tamaño expandido declarado; este límite no equivale a memoria heap medida. Los objetos grandes se descomprimen y analizan fuera del hilo de interfaz en Android. Se siguen verificando ruta, tamaño y hash; una petición fallida puede reintentarse.

El editor actualiza el borrador en memoria inmediatamente y agrupa los guardados tras 250 ms sin cambios. Fuerza el último guardado al cerrar, al pasar a segundo plano y antes de guardar la tarjeta. Se bloquea la edición durante la confirmación y se conserva el texto cuando falla la escritura. Un cierre forzado del proceso antes de completar la escritura puede perder los cambios aún pendientes; no se promete persistencia síncrona de cada tecla.

## Mediciones reproducibles

Misma prueba en 0.8.3 (53e5e4a) y el código nuevo, en este entorno de desarrollo, una observación por versión. Datos sintéticos: 20.000 tarjetas y 100.000 repasos. No son tiempos del teléfono ni de un APK release.

| Medida | Antes | Después |
| --- | ---: | ---: |
| Carga de estado y catálogo | 527,7 ms | 767,7 ms |
| Primera construcción de Inicio | 786,1 ms | 459,7 ms |
| Suma hasta Inicio | 1.313,8 ms | 1.227,4 ms |
| Mayor intervalo del temporizador durante la carga | 528,4 ms | 27,5 ms |

La carga incluye ahora el recuento diario anticipado: su duración aislada aumenta. La mejora principal es reducir el bloqueo del bucle de eventos. El temporizador de 5 ms no mide fotogramas, latencia táctil ni la totalidad del arranque.

Con un objeto europeo de 3.667.791 bytes expandidos y tres aperturas simultáneas desde instancias diferentes:

| Medida | Antes | Después |
| --- | ---: | ---: |
| Peticiones HTTP | 3 | 1 |
| Tres aperturas simultáneas | 97,3 ms | 60,1 ms |
| Reapertura desde otra instancia | 58,1 ms | 0,221 ms |

El SHA-256 del contenido resultante coincide entre versiones. Los informes originales están en `validation/0.8.4/`; el caso reproducible está en `mobile/test/reader_startup_performance_test.dart`.

## Alcance pendiente

La aceptación en el OPPO físico sigue pendiente. No se afirma que toda interacción tarde menos de 100 ms ni que la aplicación sea inmejorable. El arranque en frío de Render gratuito y las transferencias de red tienen costes externos. Esta versión no modifica ni verifica el despliegue de producción. Las pruebas nativas de SQLCipher de 0.8.2 son antecedentes y no se presentan como ejecutadas de nuevo en esta versión.

## Verificación automatizada

159 pruebas Flutter superadas, incluida la integración con la distribución europea real, y analizador sin incidencias. Las regresiones cubren borrador al cerrar, reintento tras fallo, guardado sin resucitar el borrador, metadatos inválidos, peticiones compartidas y expulsión de caché por presupuesto.

APK release y web compilados correctamente. El APK público se ha descargado completo y coincide en tamaño y SHA-256 con el artefacto local. Google y la firma Android están comprobados en la compilación; el acceso real con el proveedor y la latencia del teléfono requieren aceptación en el dispositivo.
