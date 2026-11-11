# Registro Firebase — comprobación del 11 de noviembre de 2026

Proyecto recibido y comprobado en ambos archivos: lexmemoria-aa86a. Los archivos originales se conservan fuera del repositorio, con permisos restringidos; no se publican claves/configuraciones completas en Git. La configuración Android preview instalada en el proyecto no se ha sustituido.

## Android

El JSON incluye el registro definitivo es.lexmemoria.app y el registro preview. El definitivo dispone de cliente OAuth web, pero no de certificado SHA-1 Android registrado. Registro correcto; el acceso Google definitivo sigue pendiente de registrar los certificados de firma correspondientes y probar la instalación desde Play. No se necesita repetir ahora el registro Android ni anticipar una firma de pruebas como definitiva.

Configuración preparada fuera de Git: /workspace/lexmemoria-private-config/firebase/android/google-services.json. El proceso de producción la validará estrictamente antes de compilar; no se declara lista para Google mientras falten los certificados.

## iOS

El plist recibido corresponde a es.lexmemoria.ap; el proyecto de iPhone usa es.lexmemoria.app. Falta una p al final en el registro recibido. El archivo no se ha añadido al proyecto ni se ha habilitado el acceso Google con una identidad de otra aplicación.

En Firebase → Configuración del proyecto → General → Añadir aplicación → iOS, registrar exactamente es.lexmemoria.app y descargar su GoogleService-Info.plist. El identificador de un registro Firebase existente no se arregla editando manualmente el plist. No es necesario borrar el registro anterior para crear el correcto.

Archivo recibido conservado para comprobación: /workspace/lexmemoria-private-config/firebase/ios-pending/GoogleService-Info.plist. La integración de Google iOS y Sign in with Apple siguen pendientes; registrar una aplicación no activa por sí solo esos proveedores ni la firma Apple.

## Estado de publicación

No se ha cambiado la firma, desplegado Render, modificado la base productiva ni generado una entrega firmada nueva. La comprobación acredita únicamente los identificadores y campos presentes en los archivos recibidos; no aceptación real de proveedores o tiendas.
