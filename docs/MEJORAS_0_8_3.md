# LexMemoria 0.8.3 — historial y navegación con colecciones grandes

Nueva mejora del cliente sobre 0.8.2. No modifica el esquema de base de datos, el algoritmo de repaso, las fuentes jurídicas ni el contrato del servidor. La API puede continuar identificándose como 0.8.2.

## Trabajo eliminado

Inicio dejaba que cada reconstrucción copiara todo el historial y volviera a analizar las fechas para contar el día actual. Ahora recorre directamente los eventos y reutiliza ese recuento mientras no cambien el historial, el día local, el desfase horario o un guardado heredado. Un repaso, deshacer, restaurar o sincronizar invalidan el resultado según los datos actuales; no se pierde el historial para acelerar la vista.

Progreso volvía a recorrer todas las tarjetas y todos los eventos por cada mazo, incluso para preparar los apartados inicialmente cerrados. Ahora calcula las cifras por mazo en una pasada de tarjetas y otra de eventos. Los eventos de tarjetas retiradas siguen incluidos en el total histórico, sin atribuirlos a un mazo activo inexistente.

El índice por mazo incorpora también búsquedas por ID: continuar una sesión, comprobar una tarjeta al repasar/editar y una consulta de sincronización dejan de buscar repetidamente desde el principio. El índice se renueva cuando cambia la colección resuelta, conservando los bloqueos normativos.

El filtro de favoritas usa un conjunto en lugar de buscar cada tarjeta dentro de una lista. Abrir una lista de tarjetas sin consulta deja de normalizar todo su texto; la consulta se normaliza una sola vez fuera del bucle.

## Comparación con la versión anterior

La misma prueba de widgets se ejecutó en una copia aislada de 0.8.2 (commit b41d9bc) y en el código nuevo: 20.000 tarjetas, 200 mazos y 100.000 eventos sintéticos. Cada pantalla se desmonta y monta cuatro veces. Las cifras calientes son la mediana de las tres aperturas posteriores a la inicial.

| Pantalla | Primera apertura antes | Primera apertura después | Mediana posterior antes | Mediana posterior después |
| --- | ---: | ---: | ---: | ---: |
| Inicio | 869,7 ms | 706,4 ms | 526,8 ms | 33,8 ms |
| Progreso | 1.208,9 ms | 88,2 ms | 951,0 ms | 63,8 ms |

Son mediciones de widgets Flutter en el entorno de desarrollo, con datos sintéticos y bajo carga compartida. No son cifras del OPPO, del APK release ni de Render. La primera apertura de Inicio con este historial extremo sigue superando 100 ms: no se oculta esa limitación ni se afirma que toda interacción sea ya instantánea.

## Comprobaciones

150 pruebas Flutter, incluida integración con el catálogo europeo real, y analizador sin incidencias. Las regresiones nuevas cubren recuento por fecha, repasar, deshacer, modificaciones heredadas, edición de tarjeta, ID ausente y borrado de colección. Las fuentes y la persistencia nativa no cambian frente a 0.8.2; no se repiten ni se presentan como nuevas sus pruebas de PostgreSQL/SQLCipher.

Los JSON completos están en `docs/validation/0.8.3/`. El caso reproducible está en `mobile/test/history_performance_test.dart`. El objetivo de respuesta visual local inferior a 100 ms continúa pendiente de aceptación en el teléfono físico.
