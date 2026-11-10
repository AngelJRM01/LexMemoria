# Cierre del riesgo de borrador en 1.0

## Riesgo revisado

0.8.4 agrupaba guardados a los 250 ms sin cambios y lanzaba un último guardado al salir/cambiar de estado. Un cierre forzado no garantiza una notificación de ciclo de vida; si mataba el proceso antes de acabar, las modificaciones pendientes podían perderse. Es una propiedad de la escritura asíncrona, no una razón para guardar todo el historial con cada tecla.

## Solución proporcional aplicada

- Se conserva la agrupación de 250 ms y el almacenamiento cifrado existente; no se crea otra base ni una nueva migración de datos.
- Se añade un checkpoint como máximo tras un segundo de escritura continua, sin esperar indefinidamente a una pausa.
- Un indicador pequeño e independiente muestra «Guardando borrador…», «Borrador guardado» o fallo. No reconstruye todo el formulario con cada tecla.
- «Borrador guardado» solo aparece si se ha completado la escritura de la última revisión; no confirma una revisión más reciente que todavía esté pendiente.
- La salida normal mediante Atrás espera a guardar. Si falla, conserva el editor abierto y el texto. Se bloquea entrada durante esa salida o la confirmación de tarjeta.
- El último guardado al cambiar a segundo plano sigue siendo un intento adicional; no se presenta como garantía de supervivencia a cualquier cierre forzado.
- Antes de guardar la tarjeta se ordena la escritura del borrador; la confirmación no lo resucita después.

## Límite honesto

El sistema puede detener el proceso antes del primer guardado o durante una escritura pendiente. No se garantiza recuperar teclas aún no confirmadas. Para abandonar con certeza, esperar a «Borrador guardado» o usar Atrás y dejar completar la salida. Una futura necesidad de guardar cada pulsación exigiría medir un diario cifrado de cambios; no se introduce esa reestructuración en el cierre de 1.0.

## Evidencia

Pruebas automatizadas: agrupación, salida, reintento tras error, no resurrección tras confirmar tarjeta, escritura retenida que no se anuncia guardada, checkpoint en escritura continua y Atrás con fallo sin descartar el texto. SQLCipher se prueba por separado en Android emulado. Falta la aceptación de cierre forzado y poco almacenamiento en teléfonos físicos con el artefacto de Play.

El rendimiento del editor con bases enormes y el objetivo de latencia táctil no se certifican por una prueba de persistencia. Mantener esa medición dentro del protocolo físico, sin volver a guardar el estado completo en cada pulsación.
