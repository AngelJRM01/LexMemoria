# Compilación Apple de LexMemoria 1.0

Proyecto: es.lexmemoria.app, versión 1.0.0, build 18, mínimo iOS 15. Compilación real mediante Xcode/CocoaPods en un runner macOS de GitHub Actions. El entorno de desarrollo compartido es Linux y no compila iOS localmente.

Workflow: .github/workflows/apple-build.yml. Produce dos artefactos y comprueba Info.plist, versión, plataforma, ejecutable Mach-O, integridad ZIP, tamaño y SHA-256:

- LexMemoria-1.0.0-ios-device-UNSIGNED.zip: Runner.app release para iPhone sin firma de distribución. No es una IPA instalable ni una entrega TestFlight.
- LexMemoria-1.0.0-ios-simulator.zip: Runner.app debug para el simulador de Xcode, con arquitectura indicada en simulator-report.json. No se instala en un iPhone físico.

Los informes device-report.json y simulator-report.json identifican el commit compilado. Los artefactos se conservan en GitHub durante 14 días; descargarlos desde la ejecución completada requiere acceder a GitHub. La existencia del workflow no acredita que una ejecución haya terminado correctamente: revisar el estado y los informes.

## Funciones y límites

Se compila el cliente compartido de lectura, tarjetas y estudio local. Google nativo está habilitado únicamente en Android en el código actual; no se presenta este binario como Google iOS configurado. Sign in with Apple tampoco está implementado/configurado como proveedor activo. No se inventan credenciales, equipo de desarrollo ni certificados.

Compilar no equivale a probar persistencia SQLCipher/Keychain en un iPhone. Las pruebas Android anteriores no acreditan iOS. El recorrido de cuenta, restauración, accesibilidad y segundo plano requiere aceptación Apple específica.

## Instalación física o TestFlight

Requiere cuenta/equipo Apple Developer, registrar el identificador, firma y perfiles válidos mediante custodia segura; para TestFlight, App Store Connect y su aceptación. No enviar claves privadas, certificados privados o contraseñas al chat. El workflow actual no firma, no sube a TestFlight y no publica en App Store.

Antes de distribuir: aceptar almacenamiento/migración en iPhone, identidad que se vaya a anunciar, privacidad/manifiestos de SDK y declaración de cifrado aplicable a SQLCipher. No marcar la declaración de exportación como exenta por suposición. Responsable y contacto público confirmados en CONTACTO_PUBLICO.md; el resto de la política sigue pendiente.

No hace falta un Mac propio para la compilación remota, pero una app de simulador solo se ejecuta en un Mac. Una entrega firmada mediante TestFlight permite probar en iPhone sin que el titular tenga un Mac propio.

## Resultado del 11 de noviembre de 2026

Compilación real completada y ejecución marcada Success: https://github.com/AngelJRM01/LexMemoria/actions/runs/42981920967. Tanto iPhone release sin firma como simulador compilaron y superaron verificación de metadatos, ejecutable y ZIP.

En la sección Artifacts, iniciar sesión en GitHub y descargar LexMemoria-1.0.0-Apple-1 (97,6 MB según GitHub). Contiene los dos ZIP y sus informes. El SHA-256 del artefacto externo informado por GitHub consta en build-status.json; no se presenta como descarga/hash verificados en este entorno Linux. El estado de compilación no acredita instalación física ni firma de distribución.
