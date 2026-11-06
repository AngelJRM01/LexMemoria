# Descarga europea continua · 6 de noviembre de 2026

El archivo europeo conserva los originales de la Oficina de Publicaciones, con SHA-256, metadatos, checkpoints y atribución. El alcance actual son obras CELEX de los sectores **0 y 3 con expresión en español**: consolidaciones y legislación. No se declara cobertura de todos los idiomas, tratados, jurisprudencia ni de todo el Derecho europeo.

## Ejecución supervisada

```bash
./scripts/start_eu_download.sh
```

El comando mantiene un supervisor en primer plano. `LEXMEMORIA_VENV` selecciona el entorno Python y `LEXMEMORIA_EU_ARCHIVE` la carpeta del archivo. El proceso usa el proxy y certificados configurados, sin debilitar TLS. Para continuar tras un reinicio se ejecuta el mismo comando; no se borran los avances.

El supervisor adopta un trabajador existente y evita iniciar otro mediante locks exclusivos. Si el trabajador termina inesperadamente, lo repone con pausas progresivas. Conserva los tiempos de espera de la fuente al reiniciar y abre nuevas rondas para fallos temporales agotados, dejando una incidencia de auditoría. Los errores de acceso, destinos no permitidos, falta de espacio o integridad requieren atención y no se eliminan automáticamente.

Los documentos terminados y los adjuntos ya guardados no se vuelven a descargar al reanudar un trabajo parcial. La cola usa un índice ordenado para no ordenar todos los registros pendientes en cada selección. La espera por el lock del inventario puede cancelarse sin modificar checkpoints.

Al vaciarse la cola, se vuelve a comprobar el inventario después de la última descarga. Se revisan también los registros que antes no tenían texto disponible: si la fuente ofrece posteriormente una traducción o formato compatible, se incorporan a la cola. Solo después se coteja el recuento oficial y se verifica la integridad de los objetos.

Después de verificar todos los registros disponibles, el supervisor pasa a `watching_source` y permanece activo. Por defecto vuelve a recorrer el catálogo diariamente. Esto mantiene separados «todos los registros disponibles archivados» y «todos los registros con texto»: un registro exclusivamente de metadatos nunca se cuenta como texto descargado.

**La supervisión funciona mientras el entorno está encendido.** No es un servicio externo a la plataforma: suspender o apagar el entorno detiene sus procesos. Los checkpoints permiten reanudarlos. No se ha modificado ni publicado la configuración de arranque del entorno.

## Comprobación

```bash
cat /workspace/lexmemoria-eu-corpus/supervisor.json
cd backend
python -m app.eu_bulk status
python -m app.eu_bulk verify
```

`supervisor.json` muestra el trabajador adoptado, estado y último avance. `status.json` distingue inventario, registros, archivos, pendientes, errores y cobertura. La verificación recorre una instantánea consistente del índice mientras pueden continuar las descargas; no convierte una descarga parcial en completa.

Reconciliación y actualización manual, cuando se necesiten:

```bash
python -m app.eu_bulk reconcile-inventory
python -m app.eu_bulk refresh-inventory
```

La reconciliación conserva el recuento inicial y archiva la nueva respuesta oficial. Una discrepancia no se corrige inventando un total local: se recorre de nuevo la fuente. La actualización usa un lock propio para no duplicar enumeraciones y mantiene los documentos ya archivados. Los formatos previamente no disponibles se consultan otra vez.

## Evidencia de esta intervención

- 89 pruebas backend pasan. Incluyen adopción de un trabajador, recuperación con backoff, bloqueos, persistencia de pausas, orden de la cola, deriva del catálogo, traducciones aparecidas después y vigilancia posterior a la verificación.
- Se observó en el archivo real el relevo del trabajador desde sus checkpoints y la adopción por el supervisor, conservando los objetos existentes.
- La verificación real pasó para **47.532 objetos y 49.369 archivos** de la instantánea examinada, sin errores. Las descargas posteriores siguen incorporando archivos. [Informe](validation/eu-integrity-2026-11-06.json).
- El primer recuento oficial fue 184.706, el inventario inicial terminó con 184.708 y una consulta posterior devolvió 184.726. La actualización estaba en curso al registrar esta evidencia. [Reconciliación](validation/eu-reconciliation-2026-11-06.json).

La descarga continúa incompleta. Estos controles no constituyen revisión jurídica ni activan aún la integración del corpus europeo en el cliente móvil.


## Ajuste de rendimiento y reintentos

El trabajador utiliza cuatro descargas concurrentes por defecto, manteniendo el limitador compartido de 0,6 segundos entre comienzos de peticiones. La concurrencia se puede limitar con `python -m app.eu_bulk run --workers N` (entre 1 y 8). Las páginas de identificadores contienen hasta 1.000 registros; la consulta de manifestaciones sigue dividiéndose en grupos de 50 y páginas de 1.000 filas. Las consultas SQLite de identificadores se dividen en grupos de 500 parámetros.

Cuando hay registros nuevos pendientes, se da una oportunidad cada cinco minutos a un reintento vencido. Esto evita que un error temporal espere hasta el final de todo el inventario, sin convertir los errores en un bucle que monopolice la cola. Se respetan las fechas de reintento y se conservan los contadores e incidencias.

94 pruebas backend pasan tras este ajuste. Una prueba con barrera verifica que se ejecutan cuatro trabajos simultáneos sin cambiar el intervalo del limitador; otra comprueba la alternancia entre registros nuevos y reintentos. Se recuperaron y verificaron 473 archivos (469 objetos únicos) correspondientes a los registros CELEX `31987R0335`, `02013D0255-20170321` y `02002R1774-20050101`, reutilizando los adjuntos ya guardados. Los demás reintentos siguen en la cola supervisada y no se presentan como completos.


La espera del limitador no retiene su mutex y puede interrumpirse para guardar un checkpoint. Una interrupción controlada devuelve el trabajo a pendiente sin gastar un reintento ni descartar adjuntos. Cada petición comprueba el plazo compartido de espera de la fuente, incluso cuando otra instancia lo ha ampliado. Un HTTP 429 incrementa de forma persistente el intervalo entre peticiones para reducir presión; nunca reduce un intervalo más conservador configurado por el operador. Durante una pausa de la fuente, el estado del supervisor es `waiting_source` o `retry_scheduled`, con la fecha de reanudación, en vez de aparentar actividad de red.

[Comprobación de los tres registros recuperados](validation/eu-recovered-2026-11-06.json). El intervalo operativo se ajustó conservadoramente a un segundo por petición tras observar la pausa de la fuente; cuatro transferencias simultáneas no significan cuatro peticiones por segundo.

[Verificación posterior de los 55.171 archivos guardados](validation/eu-integrity-update-2026-11-06.json): integridad correcta y descarga global todavía incompleta.
