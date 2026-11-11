# Descripción técnica del cifrado para Apple

No se ha presentado documentación ni se ha fijado una exención legal de exportación.

## Hechos técnicos del producto

- El estado local usa SQLCipher, que incorpora cifrado AES de la base de datos fuera de las API criptográficas exclusivamente proporcionadas por iOS.
- La clave local se almacena separadamente mediante Keychain en iOS. No se solicita una clave al usuario para abrir la app ni se publica esa clave en los backups educativos.
- Las comunicaciones remotas usan HTTPS/TLS del entorno de plataforma.
- No se desarrolla un algoritmo criptográfico propio ni se ofrece una herramienta de propósito general para que terceros implementen cifrado.
- La exportación educativa JSON es legible; no debe describirse como un archivo cifrado.

## Qué responder con estos hechos

La app utiliza cifrado: no se debe responder «no» únicamente porque no sea una VPN o aplicación de mensajería. Tampoco se debe afirmar que todo el cifrado es exclusivamente del sistema operativo, ya que está SQLCipher.

La aplicabilidad de una exención, declaración o documentación depende de las preguntas exactas de App Store Connect y la distribución. El uso de algoritmos estándar no permite fijar por sí solo ITSAppUsesNonExemptEncryption=false. Este valor no se ha cambiado para ocultar el aviso.

Antes de completar el cuestionario, revisar sus opciones concretas con esta descripción técnica y resolver las obligaciones aplicables del titular. No cargar un certificado vacío ni una declaración ficticia para pasar de pantalla. La compilación sin firma no acredita cumplimiento de exportación ni aceptación de Apple.
