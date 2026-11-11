# Firma de distribución iOS en GitHub

Workflow: `.github/workflows/apple-signed-build.yml`, rama `release/1.0.0-rc1`.

Usa exclusivamente los secretos `IOS_DISTRIBUTION_P12_BASE64`, `IOS_DISTRIBUTION_P12_PASSWORD` y `IOS_PROVISIONING_PROFILE_BASE64`. No añadirlos a Git ni al chat. El titular confirma haberlos guardado; esa confirmación no acredita que se hayan importado correctamente.

El runner macOS importa la identidad en un llavero temporal y valida caducidad, equipo `ZR9YWRMKC8`, aplicación `es.lexmemoria.app`, distribución App Store y coincidencia del certificado del perfil con una identidad privada válida. Configura solo las tres configuraciones Runner del checkout efímero. No sustituye certificados Apple existentes ni cambia la firma Android. No declara ninguna exención de cifrado.

Después compila `1.0.0+18`, verifica la firma del archivo, el identificador y la ausencia de permiso de depuración. Publica en Artifacts `LexMemoria-1.0.0-SIGNED-IPA-N` con IPA y SHA256SUMS. El artefacto no contiene el P12 ni su contraseña; la IPA incorpora el perfil público necesario. El llavero y los archivos de firma se borran en un paso always; el runner también es efímero. Retención del artefacto: 14 días.

Puede ejecutarse manualmente desde Actions seleccionando esa rama; el primer cambio del workflow también lo activa. No se ejecuta en pull requests ni utiliza claves de subida a Apple. Se necesita permiso para modificar workflows/secretos del repositorio; proteger el acceso de escritura y revisar cualquier cambio futuro antes de ejecutarlo.

Esto **no sube a TestFlight, no publica en App Store y no acredita pruebas físicas**. La subida requerirá autenticación adicional de App Store Connect mediante custodia segura. Un fallo se diagnostica por el paso y el mensaje, sin copiar valores privados. No revocar ni regenerar certificados para corregir nombres de secretos o perfiles sin identificar antes el problema.

Validación local del cambio: 11 pruebas específicas superadas (10 de preflight de firma y una de arranque de simulador); YAML y sintaxis Bash comprobados. Las pruebas usan certificados sintéticos, no los secretos del titular. La firma real solo queda acreditada por una ejecución macOS completada con éxito.

## Primera ejecución real — 11 de noviembre de 2026

Ejecución 43094524563: importación/validación, compilación de IPA y verificación de firma superadas según los estados públicos del job. La subida falló en CreateArtifact al recibir HTML en vez de JSON tras cinco intentos. La limpieza terminó correctamente. No hay IPA descargada ni subida TestFlight acreditada. Evidencia: signed-build-status.json.

Se añade un segundo intento de upload-artifact condicionado al fallo del primero, con overwrite para evitar un artefacto parcial y sin compresión adicional sobre la IPA. Si también falla, el job falla: no se oculta la ausencia del artefacto. Se lanza una ejecución nueva, porque el runner temporal anterior ya no conserva una copia recuperable desde este entorno. La causa concreta de la respuesta HTML no se conoce; el reintento no garantiza resolver una indisponibilidad persistente del servicio.

## Tercera ejecución: IPA disponible

La ejecución 43105880193 del commit c94d95b superó importación del certificado, validación del perfil, compilación, verificación de firma y subida del artefacto. Limpieza completada. Artefacto `LexMemoria-1.0.0-SIGNED-IPA-3`, 38,2 MB según GitHub. No se ha descargado/verificado localmente ni subido a TestFlight. La segunda ejecución no se usa como evidencia de éxito.
