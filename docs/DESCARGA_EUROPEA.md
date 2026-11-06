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
