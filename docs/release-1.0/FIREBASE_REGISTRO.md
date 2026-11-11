# Registro Firebase — comprobación del 11 de noviembre de 2026

Proyecto recibido y comprobado en ambos archivos: lexmemoria-aa86a. Los archivos originales se conservan fuera del repositorio, con permisos restringidos; no se publican claves/configuraciones completas en Git. La configuración Android preview instalada en el proyecto no se ha sustituido.

## Android

El JSON incluye el registro definitivo es.lexmemoria.app y el registro preview. El definitivo dispone de cliente OAuth web, pero no de certificado SHA-1 Android registrado. Registro correcto; el acceso Google definitivo sigue pendiente de registrar los certificados de firma correspondientes y probar la instalación desde Play. No se necesita repetir ahora el registro Android ni anticipar una firma de pruebas como definitiva.

Configuración preparada fuera de Git: /workspace/lexmemoria-private-config/firebase/android/google-services.json. El proceso de producción la validará estrictamente antes de compilar; no se declara lista para Google mientras falten los certificados.

## iOS

El segundo plist recibido y comprobado el 11 de noviembre de 2026 corresponde correctamente a es.lexmemoria.app y al proyecto lexmemoria-aa86a. Contiene los campos de configuración Firebase y OAuth de Google necesarios para preparar la integración. La diferencia del primer registro queda resuelta; no se solicita un nuevo registro.

Configuración correcta conservada fuera de Git: /workspace/lexmemoria-private-config/firebase/ios/GoogleService-Info.plist. El archivo anterior de es.lexmemoria.ap se conserva separado como antecedente y no debe utilizarse en la compilación definitiva.

Esta comprobación no equivale a integración o acceso Google operativo en iOS: siguen pendientes el empaquetado del plist, esquema de retorno OAuth, habilitación del cliente iOS y aceptación real. Sign in with Apple y firma Apple son pasos distintos. Los archivos completos no se han publicado en Git ni se han presentado como claves de distribución.

## Estado de publicación

No se ha cambiado la firma, desplegado Render, modificado la base productiva ni generado una entrega firmada nueva. La comprobación acredita únicamente los identificadores y campos presentes en los archivos recibidos; no aceptación real de proveedores o tiendas.
