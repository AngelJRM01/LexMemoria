# Archivo masivo de legislación oficial

La descarga está separada del APK y de la base con cuentas/progreso. No mete el corpus completo en preferencias móviles ni en Git. El archivo de esta sesión está en `/workspace/lexmemoria-corpus`.

## Alcance medido

El inventario observado del catálogo de legislación consolidada del BOE con corte civil 2026-11-05 contiene **12.451 documentos únicos**: 8.831 de ámbito estatal y 3.620 autonómicos. Incluye documentos derogadas/desactualizados cuando la API los expone; no se filtran como si no existieran. No equivale a toda la legislación autonómica, local o europea, ni a todos los documentos históricos publicados en el BOE.

La API documenta `limit=-1` para obtener todos, pero la respuesta observada contiene 10.000 registros. El offset 10.000 devuelve más documentos. Por tanto, el descargador continúa paginando hasta la última página corta; nunca interpreta el primer resultado de 10.000 como todo el inventario. Los identificadores autonómicos (p. ej. `DOCM-q-…` y `DOGC-f-…`) se conservan, en vez de descartarlos por no empezar por BOE-A.

Cada petición a `/datosabiertos/api/legislacion-consolidada/id/{id}` descarga la respuesta completa ofrecida por el proveedor: metadatos, análisis, metadata ELI y texto con sus versiones de bloque. No crea tarjetas educativas públicas ni acredita vigencia o revisión profesional.

## Persistencia y límites

- `archive.sqlite3`: inventario, checkpoints, estados, intentos, snapshots, incidentes y hashes. WAL permite consultar el estado mientras se descarga.
- `objects/aa/<sha256>.xml.gz`: respuesta original comprimida. El SHA-256 corresponde a los bytes originales, sin normalizar su contenido. Publicación del archivo mediante escritura temporal, fsync y renombrado; metadatos después de guardar el objeto.
- `status.json`: progreso de la descarga; `verification.json`: comprobación independiente de archivos y snapshots en el momento indicado.
- `inventory-audit.json`: distribución del inventario observado por ámbito, boletín y estado de consolidación.

Dos trabajadores como máximo, con un límite compartido de dos inicios de petición por segundo dentro del proceso. Se respetan TLS y la CA del entorno, errores 429/Retry-After y pausas por errores transitorios. Nunca se ejecutan dos instancias de descarga sobre el mismo archivo: un lock de proceso lo impide. Un 401/403 o falta de disco registra un bloqueo que exige diagnóstico; no se fuerza el acceso ni se golpea todo el catálogo repetidamente.

Los trabajos pendientes y leases de diez minutos permiten recuperar interrupciones. Las versiones de fuente anteriores son inmutables y los cambios de inventario posteriores pueden volver a encolar una descarga. Un error XML o de identidad deja el objeto en cuarentena; no se presenta como texto completo. `metadata_only` significa que se archivó una respuesta oficial que no contiene bloques de texto, y se cuenta separado.

## Ejecución y seguimiento

```bash
cd /workspace/LexMemoria
./scripts/download_corpus.sh --day 2026-11-05

cd backend
/workspace/lexmemoria-venv/bin/python -m app.bulk status
/workspace/lexmemoria-venv/bin/python -m app.bulk verify
```

Para reanudar una descarga cuyo inventario ya existe:

```bash
cd /workspace/LexMemoria/backend
/workspace/lexmemoria-venv/bin/python -m app.bulk run --workers 2
```

El directorio alternativo se selecciona con `LEXMEMORIA_CORPUS_ROOT` en el script o `--root` antes del subcomando Python. No se eliminan automáticamente objetos anteriores ni bases de usuarios.

Un resultado `verification_passed=true` valida los objetos registrados comprobados, no demuestra que terminó la descarga. `all_available_sources_archived` exige que todos los identificadores inventariados tengan respuesta completa o solo metadatos archivada; `all_downloads_successful` exige además texto en todos. Los contadores fallidos, pendientes, en ejecución y cuarentena permanecen separados. La CLI devuelve error si el proceso termina con huecos o la verificación detecta corrupción.

## Otras fuentes y continuidad

La consulta a EUR-Lex fue rechazada por el proxy (CONNECT 403). Se ha guardado una ampliación de red para `eur-lex.europa.eu`, `publications.europa.eu` y `op.europa.eu`, preservando los dominios anteriores. Guardar ese borrador no habilita los destinos en la máquina actual. Queda pendiente revisión y aplicación/publicación del entorno por el titular; el agente no ha publicado cambios.

Las descargas de fuentes europeas y de boletines adicionales requieren acceso y revisar sus interfaces/licencias. El archivo del catálogo BOE no debe anunciarse como cobertura universal. La persistencia en disco permite reanudar, pero no garantiza ejecución indefinida si la plataforma apaga o reemplaza esta máquina. Una operación permanente requiere desplegar el trabajador en un servidor con almacenamiento persistente.

Fuente y condiciones: Agencia Estatal Boletín Oficial del Estado, https://www.boe.es/datosabiertos/api/api.php y https://www.boe.es/informacion/aviso_legal/index.php#reutilizacion. Los textos consolidados son informativos.
