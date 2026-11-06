# V3: auditoría y primera entrega incremental (0.4.1+7)

Repositorio examinado inicialmente: `ae712a6`, posterior al `2604a1a` citado por la solicitud. Versión de partida 0.4.0+6. Este incremento conserva la aplicación y sus datos; no reconstruye el producto ni activa servicios, compras o publicación de entorno.

**Ninguna de las fases 1–7 se declara finalizada.** La matriz tiene 100 requisitos/reglas con estados conservadores. COMPLETO se aplica a una capacidad concreta acreditada, no a toda su fase. El inventario offline no acredita ausencia de vulnerabilidades. Las pruebas unitarias y de API local no son pruebas de tiendas, Firebase, dispositivos ni servicios desplegados.

## Orden de implementación

1. Integridad y aislamiento: restauración, escrituras, migración de sesión y autorización. Pruebas negativas antes de ampliar publicación/compartición.
2. Ingesta y contenido: extracción incremental europea y estados de procedencia; después otros formatos, estructura jurídica y distribución móvil. Mantener originales, checkpoints y descargas.
3. Aprendizaje: compatibilidad de respuestas, banco conceptual/editorial y referencias, dificultad y planificación; sin IA comercial ni corrección jurídica automática.
4. Programas/temas compartiendo referencias a artículos/tarjetas; distinguir programa personal de fuente oficial verificada.
5. Comunidad: ACL y revocación antes de invitaciones/publicación; copias y progreso independientes, moderación y privacidad.
6. Staging/producción: servicios elegidos por el titular, pruebas con proveedores, firma y tiendas sandbox. Cobros reales solo tras aprobación expresa.
7. QA transversal desde el primer cambio y aceptación física final; no posponer accesibilidad hasta el lanzamiento.

## Fase 0 — auditoría

- **Requisitos:** V3-F0-* y reglas V3-REG-* en [matriz](MATRIZ_REQUISITOS.md), también [JSON](matriz-requisitos.json). El documento [SOLICITUD_V3.md](SOLICITUD_V3.md) conserva la solicitud exacta; no se transforma en un listado de capacidades terminadas.
- **Archivos revisados:** cliente Flutter, persistencia, sincronización, API FastAPI, modelos y conectores, lockfiles, CI, despliegue propuesto y documentación histórica. [Inventario anterior](../ESTADO_FUNCIONAL_0_4_0.md) mantiene alcance de la versión de partida.
- **Dependencias:** Python/Flutter/JDK/SDK existentes; SQLCipher/almacén seguro y servicios externos según función.
- **Implementación:** generadores reproducibles `scripts/build_v3_matrix.py` y `scripts/audit_repository.py`. Matriz por requisito con archivos, pruebas disponibles, riesgos, dependencias y aceptación. Inventario de 140 componentes desde dos lockfiles y escaneo limitado de tres patrones de secretos sin valores impresos.
- **Pruebas:** partida ejecutada: 94 backend y 63 Flutter aprobadas. `pip check` sin dependencias incompatibles. Un fallo temporal del sistema de aprobación impidió un intento Flutter; no se contabilizó como ejecutado y después se pudo reintentar por la misma vía.
- **Aceptación reproducible:** ejecutar los dos scripts y las suites; verificar que ninguna integración externa aparece aprobada por inferencia. Revisar los estados a medida que cambie el código.
- **Riesgos:** escaneo CVE, historial Git completo, dependencias transitivas nativas y auditoría humana pendientes. Las acciones CI usan tags en lugar de SHA inmutables.
- **Evidencia:** `dependencies-and-pattern-scan.json`, `validation.json`, matriz y registros de pruebas. La huella de lockfiles permite repetir el inventario.
- **Documentación:** esta guía, matriz Markdown/JSON y solicitud conservada.
- **Titular:** no necesario para el inventario local; sí para validar servicios reales, obligaciones legales y decisiones comerciales posteriores.

## Fase 1 — seguridad e integridad

- **Requisitos:** V3-F1-01 a V3-F1-10.
- **Archivos modificados:** `mobile/lib/backup.dart`, `store.dart`, `remote.dart`, `profile.dart`; `backend/app/main.py`; nuevas pruebas `backup_integrity_test.dart`, ampliación `remote_test.dart`, `test_authorization_v3.py`.
- **Dependencias:** almacén SQLCipher existente, Keychain/Keystore y API compatible; no se añade servicio de pago ni clave al cliente.
- **Implementación:** validar tipos/identificadores duplicados, opciones, estados, sesiones, vacaciones y ponderaciones de la copia antes de sustituir datos; conservar campos desconocidos; quitar autoridad de sincronización de la copia. Restauración/reset confirman escritura antes de publicar el estado en memoria. Restaurar conserva un checkpoint anterior recuperable desde Ajustes, sin anidamiento recursivo de checkpoints. Repasos, edición de tarjetas, deshacer, nuevas tarjetas, perfil y adiciones usan una cola de mutaciones calculadas sobre el último estado confirmado, evitando duplicar repasos o perder cambios al fallar la escritura.
- **Sesiones:** sobre único de credenciales en almacén seguro, vinculado a servidor/cuenta y procedencia local. Restore/reset no autorizan reutilizar credenciales sobrantes. Logout conserva la procedencia y cambiar de cuenta requiere confirmación explícita antes de consumir un código o crear cuenta. Peticiones privadas no siguen redirecciones. Se rechazan respuestas de otra cuenta o tras cambio de servidor; el refresh paralelo se deduplica. Sesiones antiguas se verifican mediante `GET /v1/auth/session`; si el acceso caducó, se valida la identidad devuelta por refresh. No se reasigna contenido por confiar solo en tokens antiguos.
- **Recuperación:** si el servidor ya consumió un código y falla el guardado local de la sesión, se muestra el código sustituto con advertencia; su valor no se incluye en mensajes de excepción, logs ni copias. Esto no resuelve todavía una pérdida total de la respuesta de red después de que el servidor consuma el código.
- **Pruebas unitarias/integración:** fallo de disco, copia malformada, restauración con edición concurrente, checkpoint tras reapertura, mutaciones consecutivas, fallo de repaso/edición/undo, vínculo de sesión, redirecciones, cuenta equivocada, refresh paralelo, migración antigua válida/caducada y rechazo de prueba de identidad incorrecta. API local con dos cuentas: historial/edición/revisión/simulacro/notas/workspace/borrado aislados.
- **Aceptación reproducible:** suites abajo. En dispositivo de prueba, guardar notas/tarjetas/repasos con la versión anterior, actualizar con la misma firma, abrir/revisar/exportar/restaurar, reiniciar y comprobar igualdad de datos. No desinstalar la app original ni borrar sus datos para simular una migración.
- **Riesgos:** pruebas nativas SQLCipher/Keychain/Keystore y OPPO no ejecutadas localmente; siguen pendientes cierre abrupto a nivel de sistema, fallos de hardware y sincronización real en redes inestables. La copia JSON no es cifrada; contiene el checkpoint privado anterior. El lector debe saberlo al exportar. Código de recuperación perdido durante la respuesta requiere protocolo adicional de recuperación idempotente.
- **Evidencia/documentación:** tests, `validation.json`, contrato OpenAPI regenerado, este cambio y reporte del APK. Las garantías se limitan a lo ejecutado.
- **Titular:** dispositivo OPPO para aceptación; firma estable y servidor actualizado para la migración de sesiones. No enviar claves al chat.

## Fase 2 — biblioteca y actualización jurídica

- **Requisitos:** V3-F2-01 a V3-F2-15; incluye conversión incremental europea añadida como tarea explícita de continuación.
- **Archivos:** existentes `boe.py`, `bulk.py`, `jobs.py`, `monitor.py`, `temporal.py`, `eu_bulk.py`, `eu_supervisor.py`, lector/biblioteca; nuevos `backend/app/eu_processing.py` y `backend/tests/test_eu_processing.py`.
- **Dependencias:** archivo europeo disponible, SQLite de solo lectura para originales, carpeta distinta para derivados y espacio de disco. No necesita nuevas descargas ni cuentas externas para HTML ya archivado.
- **Implementación de este incremento:** extracción incremental de HTML/XHTML a párrafos de texto; ignora scripts/estilos y no ejecuta documentos. Coteja SHA-256 del original antes de extraer y del objeto derivado persistido antes de confirmar su índice. Checkpoint y archivos gzip atómicos, lock de instancia, estados extracted/deferred/failed. Archivo de origen abierto solo lectura. Los formatos no HTML y los errores no cuentan como extraídos. Salida marcada automática, pendiente de revisión, sin inferir vigencia ni llamar artículos jurídicos a los párrafos. Trabajador independiente en paralelo a la descarga.
- **Pruebas:** extracción, rechazo de codificación/documento inválido, no ejecución de scripts, trazabilidad, reanudación, inmutabilidad del archivo original, hash incorrecto y PDF diferido. Se ejecutó además un lote real de 100 archivos: 87 extraídos y 13 diferidos; después otro lote y modo continuo. Recuento cambiante en `/workspace/lexmemoria-eu-processed/status.json`.
- **Aceptación reproducible:** comandos abajo; verificar original/derivado e índice, reiniciar y comprobar que no duplica. Para dar por integrado: lectores, versiones, paquetes, catálogo móvil y ejercicios deben recorrer el mismo CELEX con procedencia y estado correctos.
- **Riesgos:** PDF/Formex/Word/ZIP aún sin convertir; límites de tamaño, errores y texto insuficiente quedan registrados. Falta estructura por artículos, relaciones entre normas, traducciones/versiones, distribución al cliente y revisión editorial. El proceso no tiene aún supervisor propio que lo reponga tras un fallo inesperado; sí checkpoint y lock para reanudar. No confundir el supervisor de descarga con el extractor.
- **Evidencia/documentación:** tests, estado real del archivo derivado y `eu-processing-sample.json`. No se altera el catálogo BOE de 12.451 normas ni se presenta Europa como integrada.
- **Titular:** fuentes/licencias comerciales y responsables editoriales cuando proceda; el procesamiento local puede avanzar sin ellos.

## Fase 3 — aprendizaje y flashcards

- **Requisitos:** V3-F3-*; literal ya disponible, comprensión/excepciones/comparaciones/integración normativa pendientes de banco editorial.
- **Archivos:** `prepared.dart`, `exercises.dart`, `study.dart`, `models.dart`, `planning.dart`, `backend/app/exercises.py` y `main.py`; nuevas pruebas `test_cloze_v3.py` y subida Flutter de respuesta por hueco.
- **Dependencias:** fuentes legales verificables y revisión humana para contenido conceptual; no IA comercial.
- **Implementación:** se corrige una incompatibilidad real: las respuestas de huecos ya eran mapas numerados en Flutter, pero el servidor solo aceptaba entero/lista. Ahora acepta el mapa, valida los números/longitud y calcula corrección literal conservando ñ y tildes. Repeticiones idempotentes conservan un solo repaso y su respuesta. Un mismo número de hueco no puede tener respuestas contradictorias al crear una tarjeta.
- **Pruebas:** respuestas correctas/incorrectas/incompletas, tildes, números extra, tipos inválidos, huecos repetidos incompatibles, contrato HTTP y evento único, subida Flutter intacta.
- **Aceptación reproducible:** crear un cloze con dos huecos, contestar, sincronizar dos veces y comprobar respuesta/resultado y un solo evento; no etiquetar ese resultado como interpretación jurídica.
- **Riesgos:** banco conceptual, casos revisados, clasificación de dificultad, analítica avanzada y planificador adaptativo completos siguen pendientes. No se cambia el generador que pasó la auditoría exhaustiva 0.4.0.
- **Evidencia/documentación:** fixtures y tests, OpenAPI y este informe.
- **Titular:** responsable editorial y derechos sobre preguntas de terceros; no necesario para la compatibilidad de respuestas implementada.

## Fase 4 — universidad y oposiciones

- **Requisitos:** V3-F4-*; recorridos, programas, calendarios, convocatorias/temarios versionados y referencias compartidas.
- **Archivos previstos:** `university.dart`, `planning.dart`, `workspace.dart`, modelos cliente y modelo/API de programas/temas por crear.
- **Dependencias:** esquema de enlaces artículo/tarjeta-tema y fuentes oficiales autorizadas con fecha de cotejo.
- **Implementación existente:** asignaturas/temas/apuntes y evaluaciones ponderadas, archivo de asignaturas y plan personal. En este incremento no se añade un catálogo ficticio de convocatorias ni guías oficiales.
- **Pruebas disponibles:** ponderaciones y pendientes en `product_v2_test.dart`, planificación temporal y workspace. No hay aceptación de temarios oficiales o vinculación múltiple completa.
- **Aceptación:** una tarjeta/artículo enlazable a dos temas sin duplicar contenido ni progreso; versiones de programas conservadas con fuente/fecha. Modificar un programa no borra el anterior.
- **Riesgos:** confundir objetivos personales con contenido oficial, licencias y ponderaciones diferentes entre cursos.
- **Evidencia/documentación:** matriz y alcance anterior; no se marca implementado el trabajo futuro.
- **Titular:** prioridades de oposiciones/universidades y fuentes autorizadas; código de enlaces puede desarrollarse sin credenciales.

## Fase 5 — comunidad y mazos compartidos

- **Requisitos:** V3-F5-* completos en matriz.
- **Archivos previstos:** nuevos modelos ACL/invitación/compartición/moderación y APIs; ampliar mazos, revisiones, cliente y pruebas de autorización. No convertir directamente la visibilidad del mazo en autorización.
- **Dependencias:** permisos propietario/editor/lector, revocación, publicación explícita y política de moderación.
- **Implementación existente:** mazos privados y progreso por propietario. Invitación, mazo público, enlaces y comunidad no están implementados.
- **Pruebas previstas:** matriz de permisos con tres usuarios; enlace caducado/revocado, copia independiente, ediciones concurrentes, progreso separado, retirada y denuncia. Las pruebas negativas actuales son base, no validación de compartición inexistente.
- **Aceptación:** propietario comparte un mazo concreto sin notas/archivos privados; editor modifica solo contenido autorizado; lector no edita; revocar corta acceso; copia y progreso siguen siendo personales.
- **Riesgos:** publicación accidental, filtrado de notas, permisos cacheados y contenido sin licencia/moderación.
- **Evidencia/documentación:** estados PENDIENTE/PARCIAL en matriz y diseño antes de habilitar publicación.
- **Titular:** normas de comunidad, contacto y responsables de moderación; sin publicación de datos reales en este incremento.

## Fase 6 — producción y monetización

- **Requisitos:** V3-F6-*.
- **Archivos previstos:** `render.yaml`, despliegue, esquema/migraciones PostgreSQL, adaptadores de identidad/pago, CI y configuración de plataformas.
- **Dependencias:** proveedor/región/presupuesto, proyecto de identidad, cuentas de tienda, firma y textos legales del titular.
- **Implementación existente:** blueprint y adaptadores, servidor de desarrollo, promoción interna sin cobro, rechazo de compras no verificadas. Servicios productivos, Google/Apple, pagos/push y tiendas no activados.
- **Pruebas:** desarrollo SQLite y adaptadores; faltan PostgreSQL/staging y proveedores reales, sandbox de compras, restauración/reembolso/caducidad reales.
- **Aceptación:** staging aislado, backup/restauración y alertas ensayados, identidad/sync reales y compras sandbox. No activar cobros sin aprobación explícita del titular.
- **Riesgos:** costes, pérdida de claves, retención de datos, recuperación y derechos de tienda.
- **Evidencia/documentación:** `DESPLIEGUE.md` es propuesta; no URL productiva inventada ni certificado de aceptación externa.
- **Titular:** aportar los identificadores/accesos mediante configuración segura y decisiones legales/comerciales; nunca secretos al chat/Git.

## Fase 7 — experiencia y calidad

- **Requisitos:** V3-F7-* y criterios por flujo en la matriz.
- **Archivos:** widgets, tests de usabilidad, integración nativa, CI y manual de aceptación física.
- **Dependencias:** Android/iOS/tablet/web, teclado, lectores de pantalla y herramientas de medición.
- **Implementación existente:** tests de flujos seleccionados con texto ampliado, pantalla baja/rotación, listas por demanda, filtros/paginación y lector. No se declara toda la matriz UX completada.
- **Pruebas:** suite Flutter, análisis, builds Android/web; integración Android 15 configurada en CI. iOS, OPPO, TalkBack y VoiceOver reales pendientes.
- **Aceptación:** ejecutar cada flujo con carga/error/offline, escalado 200 %, teclado y lector; comprobar foco, nombres accesibles, botones alcanzables y márgenes; medir memoria y rendimiento con normas/mazos grandes.
- **Riesgos:** pruebas de widgets no acreditan renderizado físico, consumos o compatibilidad de plugins.
- **Evidencia/documentación:** resultados locales y APK identificable; no resultado remoto supuesto.
- **Titular:** prueba en OPPO y acceso a dispositivos/iOS cuando sea necesario.

## Comandos de aceptación reproducibles

Desde `backend/`:

```bash
/workspace/lexmemoria-venv/bin/python -m pytest -q
```

Desde `mobile/`, secuencialmente (no ejecutar tests y build Android a la vez):

```bash
/workspace/tools/flutter/bin/flutter analyze --no-pub
/workspace/tools/flutter/bin/flutter test --no-pub
# Solo con emulador/dispositivo de pruebas disponible y autorizado:
/workspace/tools/flutter/bin/flutter test integration_test/startup_test.dart -d ID_DISPOSITIVO --no-pub
```

Desde la raíz:

```bash
/workspace/lexmemoria-venv/bin/python scripts/build_v3_matrix.py
/workspace/lexmemoria-venv/bin/python scripts/audit_repository.py --output docs/v3/dependencies-and-pattern-scan.json
/workspace/lexmemoria-venv/bin/python scripts/build_android.py --preview-release --no-pub
```

Extractor europeo, desde `backend/` (salida siempre fuera del archivo original):

```bash
/workspace/lexmemoria-venv/bin/python -m app.eu_processing \
  --archive /workspace/lexmemoria-eu-corpus \
  --output /workspace/lexmemoria-eu-processed --limit 100
# --watch mantiene el procesamiento incremental. Lock impide otra instancia.
```

Si el extractor continuo está ejecutándose, no iniciar otro sobre la misma salida. Los tests usan carpetas temporales propias. Ni las pruebas ni el extractor detienen el supervisor de descargas.

## Resultado local de esta entrega

- **120 pruebas backend y 82 Flutter aprobadas**, análisis sin incidencias; registros en `evidence/`.
- APK Android release 0.4.1+7 compilado y verificado, sin modo debug y con el catálogo BOE intacto; [firma y SHA-256](android-0.4.1.json).
- Web JavaScript release compilada correctamente. La compilación avisa de fuentes Cupertino no encontradas y del uso futuro de Kotlin en plugins; no equivalen a pruebas físicas ni se ocultan como aceptación completa.
- [Muestra de 100 extracciones europeas](eu-processing-sample.json) cotejada de forma independiente con originales y objetos derivados, todas correctas. Los errores por tamaño permanecen registrados y los formatos no HTML se difieren.
- [Instantánea de procesos de descarga y extracción](eu-running-snapshot.json), ambos activos; cifras cambiantes y archivo completo aún pendiente.
- [Resumen de validación y pruebas no ejecutadas](validation.json). Ninguna fase completa se cierra con estos resultados locales.
