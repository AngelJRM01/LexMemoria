# Firma, AAB y transición a es.lexmemoria.app

## Paquetes separados y conservación

El APK instalado de pruebas usa es.lexmemoria.app.preview y certificado de pruebas SHA-1 967643569eddb573c9153ce97b4b789671c29008. La edición de Play usa es.lexmemoria.app, versión 1.0.0, código 18. Son instalaciones distintas. Android no transfiere automáticamente la base cifrada ni su clave entre paquetes.

No se ha sustituido la firma preview, desinstalado la app ni copiado su base a otro paquete. Para el traslado: exportar JSON y comprobar el archivo; opcionalmente sincronizar con Google y verificar recuperación. Instalar la edición de tienda en paralelo, importar la copia o recuperar la cuenta y comparar tarjetas, historial, notas, plan y sesión. Mantener preview y la copia hasta aceptar los resultados. No mezclar una importación y una descarga remota sin revisar conflictos. Si ya existe una instalación antigua es.lexmemoria.app firmada para depuración, puede ser incompatible con la firma Play: no desinstalarla ni borrar sus datos sin exportación comprobada y un ensayo de transferencia.

## Dos certificados que no deben confundirse

Play App Signing gestiona el certificado de firma con el que Google distribuye la aplicación. La clave de subida firma el AAB enviado a Play. Pueden ser diferentes. Registrar en Firebase la aplicación Android es.lexmemoria.app y los certificados de firma de la app que muestre Play Console; los de subida/pruebas solo cuando sean necesarios para sus recorridos. El JSON preview no sirve automáticamente para el paquete definitivo.

## Compilación preparada

`scripts/build_play_bundle.py --preflight` comprueba presencia de configuración sin imprimir secretos. Modo normal: exige clave existente del titular fuera del checkout, variables seguras y configuración Firebase del paquete definitivo. No genera claves ni usa debug/preview como sustitución.

Variables que lee Gradle en el entorno seguro del titular:

- LEXMEMORIA_UPLOAD_STORE_FILE: ruta a un archivo ya custodiado fuera del repositorio.
- LEXMEMORIA_UPLOAD_STORE_PASSWORD, LEXMEMORIA_UPLOAD_KEY_ALIAS, LEXMEMORIA_UPLOAD_KEY_PASSWORD.

No enviar archivos de firma, contraseñas o sus contenidos al chat. No incluirlos en Git, capturas, argumentos de comandos ni artefactos públicos. La custodia y recuperación pertenecen al titular.

Colocar únicamente el google-services.json público de la app Android definitiva en el archivo ignorado mobile/android/app/google-services.json dentro del entorno de compilación correspondiente. Conservar separadamente el de preview para poder seguir generando sus actualizaciones. El proceso no debe publicar ninguno en Git.

`python scripts/build_play_bundle.py`

Produce el AAB de subida firmado si todos los requisitos están disponibles; verifica la firma JAR y conserva un informe de hash/tamaño. No publica en Play ni sustituye la aceptación del canal interno. La política de certificados y la instalación desde Play deben verificarse con el proveedor real.

## Artefacto de validación sin firma

`python scripts/build_play_bundle.py --unsigned-validation`

Este modo omite la configuración Google preview, desactiva acceso Google en el artefacto y no utiliza ninguna clave. El resultado UNSIGNED-validation prueba la compilación del paquete definitivo. NO es el AAB final ni se puede enviar como edición terminada. El informe deja signed=false y readyForPlaySubmission=false.

## Bloqueos externos de esta sesión

No hay clave de subida del titular configurada mediante un mecanismo seguro, ni registro/configuración Firebase de es.lexmemoria.app acreditados. No se ha accedido a Play Console. Por tanto no se afirma disponer de un AAB final firmado, de firma aceptada por Play ni de Google funcionando en el paquete definitivo. No se pedirá una clave privada para quitar estos bloqueos.

## Resultado de validación local

AAB unsigned de validación compilado y verificado con bundletool 1.18.3: paquete es.lexmemoria.app, versión 1.0.0/código 18, min SDK 24, target SDK 36, no depurable y backup Android deshabilitado. Todas las bibliotecas de 64 bits superan alineación estática de segmentos de 16 KiB; la ejecución en dispositivo de páginas 16 KiB sigue pendiente.

El manifiesto fusionado declara permisos normales de red y soporte biométrico procedentes de SDK. La app no ofrece una función propia de captura/lectura de huellas ni recoge plantillas biométricas; la presencia de un permiso de SDK no prueba recopilación. No hay permiso de identificador publicitario en este artefacto de validación. Revisar de nuevo el manifiesto y la declaración de SDK del AAB final firmado, no copiar automáticamente una declaración de seguridad de datos.
