# Cierre de LexMemoria 1.0 — candidato Android gratuito

Este expediente prioriza estabilidad, integridad y preparación de Google Play. No declara publicada ni aceptada la aplicación. Versión candidata 1.0.0+18; paquete de tienda es.lexmemoria.app. El APK preview existente y su firma no se sustituyen.

## Trabajo realizado

- Editor: indicador veraz, salida que espera y conserva el texto si falla; checkpoint de escritura continua sin volver al guardado por tecla. Detalle: EDITOR_Y_GUARDADO.md.
- Catálogo/publicación pública de mazos desactivados en cliente y servidor, incluido acceso derivado de aprobaciones antiguas. Retirada y permisos privados conservados. Variable del servidor PUBLIC_DECK_PUBLICATION_ENABLED=false; cambiar código no acredita su despliegue real.
- Edición gratuita sin acceso de navegación a suscripciones inactivas; información de versión y privacidad ajustada.
- Firma de subida preparada con clave existente fuera del repositorio y entradas seguras. No se crean ni solicitan claves privadas. Se rechaza la configuración Firebase preview o de administrador como producción.
- Pillow actualizado a 13.0.0 tras detectar avisos de seguridad; 38 dependencias Python fijadas auditadas sin avisos conocidos después de la actualización. No equivale a una auditoría completa de dependencias nativas.
- Ensayo PostgreSQL con datos sintéticos, copia cifrada y restauración en una base separada. No se toca la base productiva.
- Textos de privacidad y eliminación, ficha de tienda, matriz de datos, protocolo físico y recursos gráficos con marca existente.

## Evidencias

La carpeta evidence conserva resultados de servidor, Flutter, comprobaciones nativas y compilaciones cuando se completan. postgresql-integrity.json distingue expresamente la prueba local de Render. external-services.json no presenta un fallo de acceso del entorno como fallo de tu servicio.

Los resultados de pruebas solo se cuentan cuando terminan. Ninguna prueba local de identidad firmada o API equivale a Google real; emulador no equivale a teléfono físico. Los bloqueos se mantienen en BLOQUEOS.csv y el informe final.

## Documentos

- EDITOR_Y_GUARDADO.md: riesgo residual y solución proporcional.
- RENDER_Y_BACKUPS.md: qué comprobar en consola, backup y ensayo sin sobrescribir.
- FIRMA_Y_CAMBIO_DE_PAQUETE.md: conservación de preview, claves y AAB.
- PRIVACIDAD_BORRADOR.md / privacidad-borrador.html: campos personales/legales sin inventar.
- ELIMINACION_DE_CUENTA.md: texto y aceptación con proveedor real.
- FICHA_GOOGLE_PLAY.md: nombre, textos y recursos.
- SEGURIDAD_DE_DATOS_PLAY.csv: matriz para revisar el formulario real, no declaración ya enviada.
- PROTOCOLO_FISICO.md: casos y criterios de bloqueo.
- BLOQUEOS.csv: responsable y evidencia de cierre.
- store-assets/: icono 512×512 y gráfico 1024×500 de la marca existente.
- screenshots/: capturas reales de emulador con datos sintéticos, si el ensayo termina; no contienen éxito inventado de cuentas online.

## Orden mínimo para publicar

1. Resolver identidad/contacto/retención, continuidad de base y custodia de firma.
2. Aplicar backend candidato en Render y comprobar bloqueo público, persistencia y copia/restauración reales.
3. Registrar paquete/certificados definitivos en Firebase y compilar el AAB firmado en el entorno custodio del titular.
4. Instalar desde el canal interno Play, aceptar traslado de datos, Google/sincronización/borrado y protocolo físico.
5. Completar ficha, formularios y requisitos de la cuenta; enviar a revisión el artefacto aceptado.

No hace falta desarrollar módulos grandes adicionales para recorrer este cierre. No se aceptan planes de pago ni se publica en tiendas automáticamente desde este expediente.
