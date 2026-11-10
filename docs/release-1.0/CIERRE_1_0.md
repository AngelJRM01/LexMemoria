# LexMemoria 1.0 — informe de cierre y bloqueos de Google Play

Fecha: 10 de noviembre de 2026. Candidato Android gratuito 1.0.0+18; paquete definitivo es.lexmemoria.app. Este informe recoge trabajo ejecutado y evidencia. No acredita publicación en tienda ni aceptación de servicios externos.

## 1. Dictamen

El trabajo se ha limitado al cierre de la primera versión: integridad, seguridad, preparación de distribución y documentación. No se incorporan módulos grandes. La publicación sigue bloqueada por firma/registro definitivo, operación real de Render, datos legales y aceptación con Google, Play y dispositivos reales. La aplicación de pruebas y su firma se conservan.

## 2. Resultado de los ocho puntos solicitados

| Punto | Resultado verificable | Pendiente real |
| --- | --- | --- |
| Alcance 1.0 | Candidato gratuito sin módulos nuevos; navegación a suscripciones inactivas retirada. | Aceptación del alcance de la ficha y soporte de colaboración privada. |
| Editor | Guardado agrupado, checkpoint continuo, indicador veraz y Atrás esperando a persistencia. Error conserva el editor y el texto. | Cierre forzado y poco espacio en teléfonos físicos; no se promete conservar teclas aún pendientes. |
| Integridad y seguridad | 221 pruebas backend, 163 Flutter, analizador limpio, dos pruebas SQLCipher Android emulado y ensayo de capturas. | Google real, dispositivo físico, Play y despliegue productivo. |
| Render/PostgreSQL | Protección productiva, procedimiento de backup cifrado y ensayo íntegro en PostgreSQL 18 local separado. | Estado Live, plan/caducidad, backup y restauración real del proveedor. |
| Público/privado | Público desactivado por defecto en cliente y servidor, incluidas aprobaciones antiguas; permisos privados y retirada conservados. | Desplegar y comprobar el flag en Render y aceptar los recorridos privados anunciados. |
| Paquete y AAB | es.lexmemoria.app, código 18, configuración segura de firma de subida y validación separada sin firma. | Clave custodiada por el titular, Firebase del paquete de tienda, firma y aceptación de Play. |
| Documentación | Política borrador, eliminación, ficha, matriz de datos, protocolo físico, icono y gráfico de la marca y capturas reales. | Identidad/contacto, audiencia, bases/retención y páginas públicas finales verificadas. |
| Bloqueos | Matriz BLOQUEOS.csv con responsables y evidencias para cerrar. | Ningún punto externo se marca aprobado por inferencia. |

## 3. Guardado del editor

Se conserva la espera de 250 ms tras escribir y se añade un checkpoint al segundo de escritura continua. El estado del guardado se actualiza en un indicador independiente; no se vuelve a serializar todo el historial con cada tecla. La salida normal mediante Atrás espera la última escritura; si falla, informa y mantiene texto y editor. Antes de confirmar una tarjeta se ordena el borrador, evitando que reaparezca después.

Un cierre forzado puede matar una escritura pendiente sin notificar a la aplicación. «Borrador guardado» solo se muestra tras completar la última revisión; «Guardando» no es confirmación. El límite residual se explica en EDITOR_Y_GUARDADO.md. Se ha evitado una reestructuración de almacenamiento que amplíe el riesgo de migración de 1.0.

## 4. Pruebas ejecutadas

- 221 pruebas del backend: identidad/sesiones, permisos y propietarios, sincronización/conflictos, idempotencia, recuperación, borrado/exportación, fuentes, editorial y controles de producción/publicación/firma.
- 163 pruebas Flutter con integración del catálogo europeo real: copias, restauración, migración, escritura fallida, estado y navegación, sincronización, borradores y ejercicios.
- Dos pruebas nativas SQLCipher en emulador Android 15: contenido de varios MiB y Unicode, migración de fila antigua, fragmentos sin cambios, cambio de cola, reducción, rollback y reapertura. La generación del mismo contenido de prueba se agrupa por bloques para reducir coste del emulador, conservando tamaño.
- Escenario nativo de capturas con datos sintéticos y cinco imágenes directas de la app. El emulador sin aceleración sirve para integridad/renderizado; sus tiempos no son latencia del OPPO ni un benchmark release.
- PostgreSQL 18 local: dos propietarios aislados, idempotencia de repaso, conflicto de workspace, reinicio, backup AES-256-GCM, restauración en base nueva con todas las tablas iguales, API restaurada y rechazo de destino ocupado/origen/backup alterado.
- Inventario y escaneo acotado de patrones de secretos: no demuestra ausencia de todo secreto en todo historial ni equivale a una auditoría de seguridad integral.
- Auditoría de 38 dependencias Python fijadas: detectó avisos de Pillow 12.0.0. Se actualizó a 13.0.0, se repitieron las 221 pruebas y el nuevo análisis no presenta avisos conocidos ni paquetes omitidos. No cubre exhaustivamente todas las dependencias Android/iOS o vulnerabilidades no publicadas.

Los primeros ensayos detectaron poco espacio de trabajo y se repitieron tras retirar cachés regenerables; no se eliminaron corpus ni datos del usuario. Una ejecución nativa inicial interrumpida no se cuenta como superada. Los resultados finales completos están en evidence/.

## 5. Render y continuidad de datos

El entorno no dispone de consola Render ni credenciales de PostgreSQL productivo. La consulta pública HTTPS fue bloqueada antes de obtener respuesta del origen; no permite deducir que tu servicio esté caído o correcto. No se ha tomado un backup de producción ni se ha cambiado una URL de base, plan o región.

El titular debe comprobar API/base, commit Live, PostgreSQL, proyecto Firebase y PUBLIC_DECK_PUBLICATION_ENABLED=false. El panel anterior indicaba caducidad de PostgreSQL Free el 6 de diciembre de 2026: hay que confirmar la situación actual y resolver continuidad antes de exponer datos reales.

El ensayo local no sustituye una copia real. RENDER_Y_BACKUPS.md describe cómo crearla cifrada y restaurar SOLO en una base nueva y vacía, sin --clean ni sobrescribir el origen. Frecuencia, retención, ubicación separada, alertas y objetivos de recuperación deben aprobarse e implantarse.

## 6. Distribución y cambio de paquete

La versión preview sigue usando es.lexmemoria.app.preview y su certificado de pruebas. El paquete definitivo es.lexmemoria.app es otra instalación. La clave cifrada no se copia entre ellos. Exportar y comprobar una copia, instalar en paralelo, importar o recuperar y comparar antes de retirar nada. Si existe un paquete base antiguo firmado para depuración, tampoco debe desinstalarse sin traslado comprobado.

El proceso de firma preparado exige una clave ya custodiada fuera del repositorio, mediante variables seguras, y Firebase de es.lexmemoria.app. No crea una clave ni usa debug como firma de producción. No se solicitan claves privadas ni contraseñas al chat. Play App Signing y certificado de subida son piezas diferentes; Firebase debe reconocer el certificado con el que se instala desde Play.

La preparación de compilación está disponible; la validación del AAB se registrará en evidence/play-bundle.json al terminar. No hay AAB final firmado acreditado.

## 7. Documentación y recursos listos para revisar

PRIVACIDAD_BORRADOR.md y privacidad-borrador.html; ELIMINACION_DE_CUENTA.md; FICHA_GOOGLE_PLAY.md; SEGURIDAD_DE_DATOS_PLAY.csv; PROTOCOLO_FISICO.md; FIRMA_Y_CAMBIO_DE_PAQUETE.md; RENDER_Y_BACKUPS.md; EDITOR_Y_GUARDADO.md; BLOQUEOS.csv. Recursos originales de tienda en store-assets/ y capturas en screenshots/.

Los datos personales y legales pendientes se mantienen visibles: nombre del responsable, correo público, información aplicable de contacto, audiencia/menores, bases de tratamiento, retención real y URLs definitivas. No se han rellenado con información de Git ni identidades inventadas.

La página de eliminación necesita Firebase web/dominio y aceptación real. No basta un HTML que cargue o una respuesta de salud. La ficha propone una edición gratuita, sin publicidad ni compras activas, y declara el carácter automático/literal del material. No promete preguntas oficiales ni revisión jurídica universal.

## 8. Bloqueos finales y responsables

| Bloqueo | Trabajo autónomo completado | Intervención necesaria |
| --- | --- | --- |
| Identidad y privacidad | Borradores y matriz preparados. | Titular: identidad/contacto, audiencia y política/retención aprobadas; publicar páginas exactas. |
| Firma y Firebase de tienda | Configuración, preflight y compilación de validación. | Titular en entorno custodio: clave de subida, Play App Signing, registro es.lexmemoria.app/certificados Firebase; no enviar claves al chat. |
| Render/PostgreSQL | Código y ensayo local con restauración protegida. | Titular/proveedor: consola, continuidad, commit Live y backup/restauración reales. Desarrollo puede asistir cuando exista acceso seguro suficiente. |
| Google y dispositivos | Regresiones y protocolo listos. | Dos instalaciones reales: traslado, Google, sync/conflictos, borrado, red irregular, cierre forzado y accesibilidad; desarrollo corrige hallazgos. |
| Play Console | Ficha, recursos y proceso de bundle preparados. | Cuenta verificada, formularios/revisores, requisitos vigentes de pruebas, instalación interna y envío aceptados. |
| Colaboración privada | Aislamiento, permisos, revocación y bloqueo probados localmente. | Soporte responsable y aceptación real de los recorridos si se incluyen en la ficha. |

No quedan módulos grandes que sea necesario desarrollar por esta preparación. Los bloqueos externos no se ocultan como tareas técnicas ya resueltas. El candidato podrá enviarse cuando se cierren con evidencia; no se afirma una fecha de aprobación de Google Play.
