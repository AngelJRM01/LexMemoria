# Descripción técnica del cifrado para Apple

No se ha presentado documentación ni se ha fijado una exención legal de exportación.

## Hechos técnicos del producto

- El estado local usa SQLCipher con cifrado AES de la base de datos. El podspec publicado de SQLCipher 4.10.0, versión fijada por el plugin, selecciona SQLCIPHER_CRYPTO_CC (CommonCrypto) en el subspec común. Esto describe su backend publicado, no clasifica jurídicamente todo el binario.
- La clave local se almacena separadamente mediante Keychain en iOS. No se solicita una clave al usuario para abrir la app ni se publica esa clave en los backups educativos.
- Las comunicaciones remotas usan HTTPS/TLS del entorno de plataforma.
- No se desarrolla un algoritmo criptográfico propio ni se ofrece una herramienta de propósito general para que terceros implementen cifrado.
- La exportación educativa JSON es legible; no debe describirse como un archivo cifrado.

## Qué responder con estos hechos

La app utiliza cifrado: no se debe responder «no» únicamente porque no sea una VPN o aplicación de mensajería. Tampoco se debe deducir que todo el cifrado del binario sea exclusivamente del sistema operativo por el backend CommonCrypto de SQLCipher: hay que revisar también TLS y el resto de dependencias del cliente. La mera presencia de una biblioteca de terceros tampoco determina por sí sola la exención.

La aplicabilidad de una exención, declaración o documentación depende de las preguntas exactas de App Store Connect y la distribución. El uso de algoritmos estándar no permite fijar por sí solo ITSAppUsesNonExemptEncryption=false. Este valor no se ha cambiado para ocultar el aviso.

Antes de completar el cuestionario, revisar sus opciones concretas con esta descripción técnica y resolver las obligaciones aplicables del titular. No cargar un certificado vacío ni una declaración ficticia para pasar de pantalla. La compilación sin firma no acredita cumplimiento de exportación ni aceptación de Apple.

## Fuente técnica contrastada

Podspec publicado en CocoaPods Specs: https://raw.githubusercontent.com/CocoaPods/Specs/master/Specs/1/2/7/SQLCipher/4.10.0/SQLCipher.podspec.json

El subspec estándar depende del común, que declara SQLCIPHER_CRYPTO_CC y los frameworks Foundation/Security. Deben contrastarse los ajustes y componentes del artefacto firmado antes de fijar su declaración.
