# LexMemoria 0.6.0 — entrega local de cuentas y colaboración

Esta iteración conserva las cinco pestañas y el estudio local. Añade perfil privado, seguridad y sesiones, sincronización opcional, contactos, invitaciones, grupos privados, copias de mazos, catálogo y herramientas de moderación. No incorpora pagos ni envíos push.

**El APK y el backend deben aceptarse juntos.** El APK 0.6.0 puede estudiar localmente, pero sus nuevas funciones remotas necesitan el servidor 0.6.0. Este trabajo no acredita que Render esté desplegado con esa versión. No se han publicado estos cambios en GitHub, Render ni tiendas.

- [Matriz detallada de requisitos y límites](MATRIZ_0_6_0.md).
- [Arquitectura, contratos, migración, backup y operación](ARQUITECTURA_Y_OPERACION.md).
- [Solicitud íntegra](SOLICITUD.md).
- [OpenAPI 0.6.0](openapi-0.6.0.json).
- [Informe de validación](validacion.json) y [evidencias](evidencia/).
- [Manifest, firma y hash del APK](apk-0.6.0.json).
- [Prueba PostgreSQL local](postgres-local.json), [colaboración/concurrencia](postgres-collaboration.json) y [backup cifrado](postgres-encrypted-backup.json).
- [Instantánea de descargas europeas](descargas-europeas.json): proceso independiente aún incompleto; no equivale a contenido europeo integrado en el cliente.

## Dónde están las funciones

Perfil → Mi perfil: nombre/alias, apariencia, foto privada y preferencias de privacidad/avisos. El perfil académico y los objetivos se mantienen en el planificador.

Perfil → Cuenta y copias: sesión Google existente, subida/recuperación explícitas, comparación de notas y plan e interruptores automáticos posteriores. La automatización funciona mientras la app está abierta; los conflictos exigen comparar.

Perfil → Cuenta y seguridad: sesiones aproximadas, revocación, identidad y eliminación. Compañeros e invitaciones son accesos secundarios opcionales.

Estudiar → materiales compartidos: mazos propios/remotos, catálogo, grupos, copia personal y versiones. Las copias no comparten progreso ni reciben cambios del autor automáticamente. Enlaces: abrir la página informativa y pegar el enlace en Invitaciones; no se promete apertura automática de la app.

## Aceptación pendiente

Los dos móviles deben usar la misma cuenta y el mismo servidor 0.6.0. Crear tarjetas, estudiar, guardar notas/asignaturas, sincronizar y recuperar en la segunda instalación; comparar IDs, eventos y estados. Después editar en ambos y resolver la divergencia. Verificar también cerrar/revocar sesión, reconectar y eliminar una cuenta de prueba con Google fresco.

No realizar esta aceptación con datos únicos sin conservar previamente una copia. No borrar ni desinstalar la aplicación del titular como método de diagnóstico.

El nombre del responsable y correo de soporte se mantienen pendientes por decisión del titular. La página de privacidad, Google web/eliminación, gateway MFA del personal, push, firma de tienda e iOS tienen dependencias externas detalladas en la matriz. No se afirma aceptación legal, de proveedor o de teléfono físico.
