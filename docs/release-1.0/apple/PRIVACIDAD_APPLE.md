# Privacidad de la app en App Store Connect — preparación

Responsable: Ángel Joaquín Rodríguez Mercado. Contacto: armcode.dev@gmail.com. Audiencia desde los 16 años. No se ha enviado una declaración a Apple.

## Clasificación del comportamiento implementado

- Estudio sin cuenta: datos locales en almacenamiento de la app; la exportación JSON es legible y bajo control de quien la conserva.
- Cuenta/sincronización: identificador estable y contenido de estudio transmitidos a la API cuando se solicita o consiente. Es opcional, pero no permite declarar globalmente «no se recopilan datos».
- Perfil: nombre/alias y foto opcionales según acciones del usuario. La disponibilidad concreta de proveedores de identidad depende de la plataforma y el binario.
- Contenido de usuario: tarjetas, notas, cursos, planes, respuestas y otros elementos de workspace admitidos por sincronización.
- Actividad de estudio: eventos y estados de repaso y simulacros para prestar progreso/recuperación; no se anuncia un proveedor de analítica publicitaria activo.
- Colaboración privada: relaciones, invitaciones y los recursos expresamente compartidos. Los repasos/calificaciones no se comparten automáticamente.
- Datos técnicos: los proveedores y el servidor pueden procesar información necesaria para entregar y proteger las peticiones. Verificar SDK y retención del despliegue final.

## Cómo preparar el formulario

Revisar las categorías equivalentes a identificadores, información de contacto, contenido de usuario e interacción con el producto según las opciones que muestre Apple. Los datos guardados por cuenta para recuperar el estudio están asociados a esa cuenta; no declararlos anónimos por usar un UID en vez de mostrar un nombre.

Las relaciones internas de compañeros/grupos pueden encajar en Contactos o grafo social según la definición de Apple, aunque la app no lea la agenda del teléfono; comprobar esa categoría en el formulario.

Finalidad principal: funciones de la app y, cuando corresponda, seguridad/soporte. No hay publicidad ni compras activas en la primera edición. No hay seguimiento publicitario entre apps implementado en el cliente actual; confirmar los SDK y el comportamiento del build final antes de responder sobre tracking.

Una preferencia de analítica no equivale a un proveedor conectado. No afirmar tampoco que todos los proveedores carecen de registros técnicos. La revisión tiene que incluir Firebase, Render y los SDK realmente empaquetados.

## Pendiente para una declaración definitiva

- Aprobar e implantar conservación de cuentas, backups y registros.
- Revisar bases jurídicas y condiciones para adolescentes de 16–17 años.
- Publicar política HTTPS completa y comprobar eliminación de cuenta/identidad web y app.
- Validar el binario firmado y los manifiestos de privacidad/reason APIs de sus dependencias.
- Resolver condición de comerciante del titular y acuerdos cuando Apple los solicite.

Estos puntos no pueden completarse eligiendo casillas por suposición. La página de soporte pública es distinta de la política definitiva.
