# Francia — preparación del expediente de criptografía

Decisión del titular: mantener Francia en la distribución de LexMemoria. Fecha: 12 de noviembre de 2026. No se ha presentado una declaración a la ANSSI ni se ha obtenido un justificante o una exención.

## Requisito que muestra Apple

Tras declarar algoritmos estándar y disponibilidad en Francia, App Store Connect solicita una copia del «Formulario francés de aprobación de la declaración de encriptación». El informe técnico propio no es ese justificante. No excluir Francia ni responder «No» mientras se mantenga esa distribución.

## Documentación ya preparada

- ENCRYPTION_TECHNICAL_DESCRIPTION.md/PDF: descripción técnica en inglés, fuentes y límites de comprobación.
- ANNEXE_TECHNIQUE_CRYPTOGRAPHIE_FR.md/PDF: anexo técnico preparatorio en francés, sin firma ni afirmación de autorización.
- CIFRADO_APPLE.md: estado de clasificación y restricciones. No se modifica ITSAppUsesNonExemptEncryption ni se inventa ITSAppEncryptionExportComplianceCode.

## Qué falta comprobar con la fuente oficial

Abrir https://cyber.gouv.fr/ y localizar el procedimiento vigente para los medios de criptología. Descargar el formulario y sus instrucciones actuales. Verificar el régimen aplicable a esta distribución, si existe una excepción aplicable y qué justificante reconoce Apple. No deducir una excepción solo por el propósito educativo, algoritmos estándar, licencia abierta o uso de CommonCrypto.

Cuando esté disponible el formulario, trasladar los datos técnicos preparados a sus campos reales. No presentar este documento ni el anexo como formulario oficial. Identificar la persona física/jurídica declarante, la calidad de su representante y los datos requeridos directamente en el formulario privado; no publicar domicilio, documento de identidad o firma en GitHub.

La firma o confirmación de declaraciones legales corresponde al titular cuando el procedimiento la requiera. No se han enviado correos ni documentación a terceros. No se afirma un plazo, coste o resolución favorable sin conocer el procedimiento vigente.

Después de obtener el justificante aplicable, cargarlo en App Store Connect y comprobar la decisión de Apple. Solo si Apple proporciona un código de cumplimiento y procede incorporarlo, usar ese código auténtico en la configuración del build siguiente.

## Bloqueo de consulta y propuesta de red

Las consultas a developer.apple.com y cyber.gouv.fr fallaron con CONNECT 403 desde la política de red del entorno. Se guardó una propuesta de configuración que conserva los 78 dominios anteriores y añade únicamente:

- cyber.gouv.fr
- www.ssi.gouv.fr
- developer.apple.com
- support.apple.com
- www.legifrance.gouv.fr

Resultado de guardado: saved, requires_publish=true. Guardar el borrador no lo aplica. El titular debe revisar, guardar y publicar el entorno desde su configuración. Después hay que volver a comprobar el acceso mediante una conexión nueva. Esto no publica la aplicación ni tramita una declaración administrativa.

Si el acceso continúa bloqueado, el titular puede descargar desde la web oficial el formulario vigente y sus instrucciones y adjuntarlos al chat; así podrán completarse sin inventar sus campos.
