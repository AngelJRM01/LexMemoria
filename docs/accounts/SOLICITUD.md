# LEXMEMORIA — EVOLUCIÓN DE CUENTAS, PERSONALIZACIÓN Y COLABORACIÓN

## 1. OBJETIVO GENERAL

Continuar desarrollando LexMemoria sobre el repositorio actual.

Ya conoces la arquitectura, la especificación V2, la matriz V3 y los cambios realizados hasta la versión 0.5.0. Comprueba el estado actual de `main` antes de realizar cambios.

El objetivo de esta iteración es crear un sistema de cuentas y colaboración completo, seguro, intuitivo y escalable, aprovechando la infraestructura existente de Flutter, FastAPI, PostgreSQL, Firebase y autenticación Google.

**PRINCIPIO FUNDAMENTAL: LexMemoria es una aplicación jurídica y educativa, no una red social.**

La gestión de usuarios debe ser una funcionalidad complementaria que facilite estudiar, conservar el progreso y colaborar.

No reorganices la aplicación alrededor de perfiles, amigos, publicaciones o comunidades.

Las secciones principales deben seguir siendo:

1. Inicio.
2. Estudiar.
3. Biblioteca.
4. Actualidad.
5. Perfil.

Toda funcionalidad nueva debe integrarse de manera coherente en esta navegación, sin introducir pestañas principales innecesarias.

El estudio individual, la legislación y la repetición espaciada siempre tienen prioridad.

---

# 2. PRINCIPIOS DE DISEÑO

Toda la evolución deberá cumplir:

- Diseño minimalista, limpio y profesional.
- Registro opcional: se puede estudiar como invitado local.
- No forzar autenticación para leer legislación pública.
- Sincronización voluntaria y transparente.
- Protección del progreso académico.
- Privacidad por defecto.
- Colaboración opcional.
- Capacidad de compartir mediante enlaces.
- Funciones sociales discretas.
- Ausencia de perfiles públicos obligatorios.
- Sin publicidad invasiva.
- Sin notificaciones sociales innecesarias.
- Compatibilidad con Android, iOS y web.
- Arquitectura preparada para crecimiento futuro.
- Compatibilidad con datos y cuentas existentes.

No crear código duplicado ni nuevos sistemas cuando ya exista una implementación equivalente.

---

# 3. SISTEMA DE CUENTAS

## 3.1. Modalidades de usuario

Deben existir tres situaciones claramente diferenciadas.

### A. Usuario local sin cuenta

Puede:

- Consultar legislación.
- Descargar normas.
- Crear tarjetas y mazos.
- Preparar ejercicios automáticos.
- Estudiar y repasar.
- Guardar progreso local.
- Crear asignaturas y notas.
- Realizar simulacros.
- Exportar y restaurar una copia local.

No necesita correo electrónico ni conexión permanente.

Se le debe explicar discretamente que los datos locales pueden perderse si desinstala la aplicación sin haber realizado una copia.

No mostrar avisos insistentes para que cree una cuenta.

### B. Usuario con cuenta gratuita

Dispone de todas las capacidades locales y, cuando el servicio esté operativo, puede:

- Sincronizar sus datos.
- Recuperar su progreso.
- Utilizar varios dispositivos.
- Gestionar su perfil.
- Compartir mazos según las reglas del producto.
- Participar en grupos de estudio.
- Recibir invitaciones.
- Administrar sus preferencias y privacidad.

### C. Usuario Premium

La arquitectura debe permitir asignar derechos mediante un sistema de entitlements.

Preparar la compatibilidad con Estudiante Plus y Opositor Pro, pero no activar cobros reales ni restricciones comerciales sin autorización del titular.

Las funciones educativas fundamentales nunca deben desaparecer inesperadamente cuando termina una prueba o suscripción.

---

# 4. AUTENTICACIÓN Y GESTIÓN DE SESIONES

## 4.1. Google

Aprovechar la integración existente con Firebase Auth y Google Sign-In.

No crear un segundo sistema de identidad paralelo.

Completar las pruebas y endurecer:

- Inicio de sesión.
- Cierre de sesión.
- Restauración de sesiones.
- Caducidad de tokens.
- Renovación segura.
- Cambio de cuenta.
- Revocación.
- Vinculación con usuario invitado.
- Recuperación de datos en otro dispositivo.
- Tratamiento de conflictos.
- Funcionamiento con mala conexión.

No considerar completada la función sin pruebas reales cuando sean necesarias.

## 4.2. Apple

Mantener preparada una integración compatible con Sign in with Apple.

No es necesario configurarla ahora si requiere intervención del titular.

## 4.3. Otros proveedores

Diseñar interfaces que permitan incorporar email, Apple u otros métodos autorizados sin migraciones destructivas.

No introducir autenticación por contraseña propia como requisito inmediato.

## 4.4. Gestión de sesiones

Desde Perfil → Cuenta y seguridad:

- Consultar dispositivos o sesiones activas cuando el servidor pueda identificarlos.
- Mostrar última actividad aproximada.
- Revocar sesiones.
- Cerrar sesión en el dispositivo actual.
- Cerrar otras sesiones.
- Gestionar credenciales vinculadas.
- Consultar fecha de creación de la cuenta.
- Solicitar eliminación de la cuenta.

No prometer identificación exacta de dispositivos si solo se dispone de información técnica aproximada.

Al cerrar sesión, aclarar qué datos permanecen localmente y cuáles pertenecen a la cuenta.

No borrar automáticamente datos educativos sin una confirmación explícita.

---

# 5. PERFIL PERSONALIZADO

Implementar o ampliar Perfil → Mi perfil.

Campos:

- Identificador interno estable.
- Nombre para mostrar.
- Alias opcional.
- Imagen de perfil opcional.
- Fecha de creación.
- Idioma preferido.
- Tema claro, oscuro o sistema.
- Objetivo principal de estudio.
- Perfil académico opcional.
- Preferencias de notificación.
- Configuración de privacidad.

No exigir datos personales innecesarios.

## 5.1. Alias

Los usuarios podrán tener un alias reconocible.

Características:

- Normalización y validación.
- Reglas claras de longitud y caracteres.
- Unicidad si se utiliza como identificador para compartir.
- Comprobación de nombres reservados.
- Protección frente a suplantaciones.
- Posibilidad de modificarlo.
- Identidad interna independiente del alias.

El alias no debe utilizarse como clave primaria.

## 5.2. Imagen de perfil

Permitir:

- Avatar predeterminado.
- Iniciales.
- Imagen del proveedor Google cuando corresponda.
- Fotografía personalizada opcional.

Validar tamaño, formato y contenido del archivo.

Eliminar metadatos innecesarios y evitar exponer archivos privados.

No permitir que una URL externa arbitraria se convierta en un vector de seguimiento de otros usuarios.

## 5.3. Perfil académico

Opcionalmente:

- Estudiante universitario.
- Opositor.
- Ambos.
- Otro objetivo educativo.

Para universitarios:

- Universidad opcional.
- Titulación.
- Curso.
- Asignaturas.

Para opositores:

- Cuerpo o proceso seleccionado.
- Convocatoria.
- Fecha de examen cuando exista.
- Objetivos de estudio.

No solicitar información que no se utilice realmente.

Los datos académicos son privados por defecto.

---

# 6. SINCRONIZACIÓN MULTIDISPOSITIVO

Esta es una de las prioridades técnicas más importantes.

Aprovechar los contratos y mecanismos de sincronización existentes.

## 6.1. Datos sincronizables

- Perfil.
- Preferencias.
- Objetivos diarios.
- Asignaturas.
- Temas y subtemas.
- Notas.
- Mazos.
- Tarjetas.
- Revisiones de contenido.
- Historial de repasos.
- Estado de repetición espaciada.
- Simulacros.
- Progreso.
- Marcadores.
- Normas seguidas.
- Preferencias de notificación.
- Punto de lectura cuando corresponda.

Los paquetes públicos de legislación no tienen que duplicarse dentro de la copia privada de cada usuario.

## 6.2. Sincronización transparente

En Perfil → Cuenta y copias, mostrar estados claros:

- Sin sincronizar.
- Sincronizando.
- Sincronizado.
- Cambios pendientes.
- Conflicto.
- Error de conexión.

Mostrar fecha y hora del último resultado confirmado.

No mostrar éxito antes de que el servidor confirme la operación.

## 6.3. Automatización

Incorporar sincronización automática opcional, cuando sea fiable.

Requisitos:

- Primera subida explícita o consentimiento adecuado.
- No reemplazar datos locales silenciosamente.
- Reintentos idempotentes.
- Cola persistente de cambios.
- Sincronización al recuperar conexión.
- Manejo de duplicados.
- Detección de edición concurrente.
- Conflictos resolubles.
- Capacidad de continuar trabajando offline.

No implementar un sistema que borre el contenido más reciente por aplicar indiscriminadamente la regla de último escritor.

## 6.4. Recuperación

Caso de aceptación obligatorio:

1. Crear un usuario.
2. Crear mazos y tarjetas.
3. Estudiar varias tarjetas.
4. Crear notas y asignaturas.
5. Sincronizar.
6. Iniciar sesión en otro dispositivo o instalación limpia.
7. Recuperar el contenido.
8. Comparar identificadores, tarjetas, historial, notas, estados de repaso y progreso.
9. Modificar contenido en ambos dispositivos.
10. Resolver correctamente la divergencia.

Los datos personales de distintas cuentas nunca se deben mezclar.

---

# 7. SISTEMA DE CONTACTOS

Introducir una función sencilla de contactos para facilitar la colaboración.

No desarrollar una red social completa.

## 7.1. Añadir contactos

Permitir:

- Buscar por alias exacto.
- Invitar mediante enlace.
- Aceptar o rechazar una invitación.
- Eliminar un contacto.
- Bloquear un usuario.

El sistema debe respetar las preferencias de descubrimiento.

No exponer listas de usuarios, direcciones de correo ni datos personales mediante búsquedas abiertas.

Aplicar limitación de solicitudes y protección frente a enumeración de cuentas.

## 7.2. Lista de contactos

Ubicar en Perfil → Compañeros.

Mostrar:

- Avatar.
- Nombre o alias permitido.
- Opciones para compartir un mazo.
- Acceso a invitaciones pendientes.

No mostrar:

- Correo privado.
- Progreso académico sin autorización.
- Fecha de nacimiento.
- Información de sesiones.
- Datos no necesarios.

## 7.3. Visibilidad

Opciones:

- No permitir que me encuentren mediante alias.
- Permitir invitaciones mediante alias.
- Permitir invitaciones por enlace.

La elección debe ser reversible.

---

# 8. COMPARTIR MAZOS

Funcionalidad prioritaria de esta evolución.

## 8.1. Modos de visibilidad

Cada mazo puede ser:

### Privado

Solo su propietario puede verlo.

### Compartido por invitación

Acceden únicamente usuarios autorizados o mediante un enlace de invitación sujeto a controles de acceso.

### Público

Puede aparecer en el catálogo de mazos compartidos.

La publicación pública requiere confirmación explícita.

## 8.2. Permisos

Definir roles independientes:

- Propietario.
- Editor.
- Lector.

El propietario administra permisos y visibilidad.

El editor puede modificar contenido según los permisos concedidos.

El lector puede estudiar sin modificar el mazo original.

Ningún rol debe acceder automáticamente al historial privado de estudio de los demás.

## 8.3. Progreso individual

Cada participante mantiene sus propios:

- Repasos.
- Intervalos.
- Fallos.
- Estadísticas.
- Favoritos.
- Estados de aprendizaje.

Un mazo compartido no implica progreso compartido.

## 8.4. Copias personales

Permitir copiar un mazo a la biblioteca personal.

La copia debe:

- Mantener atribución de origen cuando corresponda.
- Tener identidad y versiones propias.
- Ser editable de forma independiente.
- No cambiar automáticamente cuando el autor modifica el original.
- No romper la trazabilidad de las fuentes jurídicas.

## 8.5. Actualizaciones del mazo

Cuando un autor modifica tarjetas compartidas:

- Conservar versiones.
- Mostrar cambios relevantes.
- Proteger las revisiones históricas.
- No destruir el progreso.
- Evitar conflictos de edición.
- Permitir resolver cambios incompatibles.

## 8.6. Enlaces de invitación

Crear enlaces compartibles mediante WhatsApp, correo u otras aplicaciones.

Los enlaces deben:

- Ser difíciles de adivinar.
- Poder revocarse.
- Admitir caducidad opcional.
- Admitir límites de uso cuando corresponda.
- No revelar información privada.
- Abrir una página informativa en web cuando la app no esté instalada.

No utilizar identificadores secuenciales como mecanismo de autorización.

---

# 9. GRUPOS DE ESTUDIO

Implementar grupos privados y sencillos.

Un grupo no es un foro social: es un espacio para compartir materiales y organizar el aprendizaje.

## 9.1. Crear grupo

Campos:

- Nombre.
- Descripción opcional.
- Imagen o icono opcional.
- Asignatura o temática opcional.
- Tipo: universitario, oposiciones o general.
- Privacidad.
- Miembros.

## 9.2. Funcionalidades

Cada grupo podrá:

- Invitar participantes.
- Compartir mazos.
- Compartir material permitido.
- Organizar recursos por tema.
- Consultar mazos disponibles.
- Retirar materiales.
- Gestionar miembros.
- Abandonar el grupo.

## 9.3. Roles

- Administrador.
- Colaborador.
- Miembro.

Controlar las operaciones en el backend.

No confiar únicamente en los botones ocultos de Flutter.

## 9.4. Progreso

Por defecto, el grupo no comparte notas ni estadísticas individuales.

Puede ofrecerse, más adelante, una opción voluntaria para compartir objetivos o progreso resumido.

Nunca publicar las calificaciones personales sin consentimiento específico.

## 9.5. Qué no implementar

No incorporar:

- Feed de publicaciones.
- Mensajería privada.
- Chat grupal en tiempo real.
- Seguidores.
- Reacciones sociales.
- Rankings públicos obligatorios.
- Publicación de fotos.
- Vídeos sociales.
- Sistemas de popularidad agresivos.

La colaboración debe ser una herramienta, no el producto principal.

---

# 10. CATÁLOGO DE MAZOS COMPARTIDOS

Crear una sección secundaria dentro de Estudiar o de la biblioteca de mazos.

No crear una sexta pestaña principal.

Permitir:

- Buscar mazos públicos.
- Filtrar por materia.
- Filtrar por norma.
- Filtrar por oposición cuando exista una correspondencia verificada.
- Consultar número de tarjetas.
- Consultar autor o alias.
- Consultar fecha de actualización.
- Previsualizar tarjetas.
- Añadir una copia personal.
- Reportar contenido.

Distinguir claramente:

- Contenido generado automáticamente desde legislación.
- Contenido de usuarios.
- Contenido editorialmente revisado.
- Contenido oficial cuando realmente lo sea.

No presentar una tarjeta creada por un estudiante como una explicación jurídica verificada.

No mostrar información pública que permita inferir notas o historiales privados.

---

# 11. ORGANIZACIÓN DEL ESTUDIO POR USUARIO

Aprovechar el planificador existente.

Cada usuario podrá configurar:

- Objetivo de tarjetas diarias.
- Días de estudio.
- Días de descanso.
- Vacaciones.
- Fecha de examen.
- Horas disponibles.
- Asignaturas.
- Temas.
- Prioridades.
- Tipos de ejercicio preferidos.

Completar progresivamente la capacidad de generar un calendario útil y realista a partir de esas preferencias.

No convertir la pantalla Perfil en una segunda pantalla de planificación.

Los ajustes se administran en Perfil, pero el trabajo de estudio se realiza en Inicio y Estudiar.

---

# 12. NOTIFICACIONES PERSONALIZADAS

Distinguir las notificaciones por finalidad.

## 12.1. Estudio

- Recordatorio de repasos.
- Objetivos diarios configurados.
- Exámenes próximos.
- Planificación pendiente.

## 12.2. Jurídicas

- Actualización de una norma seguida.
- Posible desactualización de tarjetas.
- Nueva redacción disponible.
- Incidencia relevante en contenido guardado.

No afirmar que una reforma afecta jurídicamente al usuario sin análisis suficiente.

## 12.3. Colaboración

- Invitación a un grupo.
- Mazo compartido.
- Solicitud de contacto.
- Cambios relevantes de permisos.

Cada categoría debe poder activarse o desactivarse por separado.

Añadir horarios de silencio y controles de frecuencia.

Las notificaciones de colaboración no deben activarse agresivamente por defecto.

Preparar FCM/APNs e integrar solo después de pruebas reales.

---

# 13. PRIVACIDAD Y PROTECCIÓN DE DATOS

Requisitos fundamentales:

- Datos privados por defecto.
- Autorización del servidor para cada recurso.
- Comprobación de pertenencia a grupos.
- Validación de permisos de mazos.
- Protección frente a acceso entre cuentas.
- Rate limiting.
- Registros de seguridad sin secretos.
- Exportación de datos personales.
- Eliminación de cuenta.
- Eliminación o anonimización de datos asociados conforme a la política aplicable.
- Política de privacidad accesible.
- Consentimientos y preferencias documentados.
- Revisión de retención y copias de seguridad.

Implementar mecanismos de bloqueo y denuncia para usuarios y contenido compartido.

No mostrar correos electrónicos privados en grupos ni en enlaces públicos.

Las copias JSON actuales contienen información legible: advertirlo claramente y valorar exportaciones cifradas opcionales.

Preparar un mecanismo de eliminación de cuentas desde la aplicación y la vía web necesaria para publicación.

No afirmar cumplimiento legal integral sin revisión correspondiente.

---

# 14. MODERACIÓN Y SOPORTE

Crear la base de herramientas administrativas que permitan:

- Consultar reportes.
- Clasificar incidencias.
- Revisar mazos públicos.
- Ocultar material denunciado.
- Retirar contenido infractor.
- Gestionar bloqueos justificados.
- Registrar decisiones.
- Resolver apelaciones o reclamaciones de usuarios.
- Consultar incidencias técnicas.

Distinguir la moderación de contenido compartido de la validación jurídica.

Una tarjeta puede ser admisible para compartir y, aun así, no estar revisada jurídicamente.

Las herramientas administrativas deben protegerse con autorización fuerte y auditoría.

---

# 15. MONETIZACIÓN FUTURA

Mantener la arquitectura Free / Estudiante Plus / Opositor Pro.

No activar pagos reales en esta iteración.

Preparar derechos configurables desde el servidor.

Principios:

- La lectura básica y el estudio individual deben seguir siendo accesibles.
- La colaboración básica debe ser gratuita.
- No bloquear la recuperación de datos personales tras terminar una suscripción.
- No eliminar mazos ni tarjetas cuando caduca Premium.
- Los límites comerciales deben aplicarse desde el servidor cuando afecten a recursos remotos.
- Nunca confiar en una variable Premium almacenada únicamente en el cliente.

Las funciones avanzadas de planificación, análisis y contenido especializado pueden estudiarse como ventajas Premium en el futuro.

No fijar los límites finales sin una decisión comercial del titular.

---

# 16. DISEÑO DE LA INTERFAZ

Mantener los cinco destinos actuales.

Propuesta de integración:

**Inicio**
- Continuar estudiando.
- Repasos pendientes.
- Objetivo diario.
- Acceso discreto a materiales compartidos recientes.

**Estudiar**
- Mis mazos.
- Mazos compartidos conmigo.
- Grupos de estudio.
- Explorar mazos públicos.
- Simulacros.
- Repasos.

**Biblioteca**
- Legislación y lector jurídico existentes.
- Sin introducir contenido social en el lector.

**Actualidad**
- Cambios normativos.
- Normas seguidas.
- Notificaciones jurídicas.

**Perfil**
- Mi perfil.
- Mi cuenta.
- Seguridad y sesiones.
- Compañeros.
- Invitaciones.
- Privacidad.
- Sincronización y copias.
- Ajustes.

No mostrar todas las opciones simultáneamente.

Usar navegación progresiva, agrupaciones claras y pantallas sencillas.

No aumentar innecesariamente el número de clics para empezar a estudiar.

---

# 17. ARQUITECTURA BACKEND

Reutilizar FastAPI, SQLAlchemy, PostgreSQL y los mecanismos existentes de identidad, permisos, revisiones e idempotencia.

Diseñar entidades o equivalentes para:

- UserProfile.
- UserSettings.
- LinkedIdentity.
- UserSession.
- UserConnection.
- ContactInvitation.
- StudyGroup.
- GroupMember.
- StudyDeck.
- DeckShare.
- DeckMembership.
- DeckRevision.
- ShareInvitation.
- ContentReport.
- NotificationPreference.
- NotificationDelivery.
- UserEntitlement.

No crear tablas sin antes comprobar si el dominio existente ya cubre esas responsabilidades.

Usar identificadores estables, claves foráneas, restricciones de unicidad y migraciones reversibles cuando sea posible.

Evitar condiciones de carrera al aceptar invitaciones, revocar accesos o editar contenido compartido.

Los permisos deben verificarse de forma centralizada y coherente.

Evaluar índices, paginación, consultas y costes de almacenamiento.

---

# 18. PRUEBAS OBLIGATORIAS

Como mínimo, cubrir los siguientes escenarios.

## Identidad
- Invitado local.
- Primer inicio de sesión.
- Inicio de sesión repetido.
- Cambio de cuenta.
- Cierre de sesión.
- Sesión caducada.
- Vinculación de identidad.
- Conflicto de identidad.
- Revocación.

## Sincronización
- Datos locales a nube.
- Nube a dispositivo nuevo.
- Trabajo offline.
- Reconexión.
- Operaciones duplicadas.
- Ediciones simultáneas.
- Conflictos.
- Reinicio de servidor.
- Recuperación desde backup.
- Aislamiento entre usuarios.

## Contactos
- Invitación.
- Aceptación.
- Rechazo.
- Cancelación.
- Bloqueo.
- Usuario no descubrible.
- Intentos abusivos.

## Mazos
- Compartición privada.
- Compartición por enlace.
- Revocación.
- Lectura.
- Edición autorizada.
- Edición no autorizada.
- Copia independiente.
- Eliminación del original.
- Progreso individual.
- Reforma jurídica.
- Conservación de revisiones históricas.

## Grupos
- Crear.
- Invitar.
- Unirse.
- Salir.
- Expulsión.
- Cambiar roles.
- Eliminar grupo.
- Acceso no autorizado.
- Retirada de materiales.

## Privacidad
- Exportación.
- Eliminación.
- Protección de datos.
- Comprobación de permisos.
- Archivos maliciosos.
- Recursos inaccesibles tras revocación.

No considerar una función terminada solo porque su pantalla aparece o una prueba utiliza mocks.

---

# 19. PRIORIZACIÓN DEL DESARROLLO

Implementar en este orden:

**P0 — Estabilidad previa**
- Confirmar el despliegue que resuelve el error 422.
- Verificar PostgreSQL real.
- Preparar backups y restauración.
- Probar cuentas Google y recuperación de progreso.
- Resolver problemas de migración y persistencia.

**P1 — Cuentas y personalización**
- Mejorar perfil.
- Seguridad de sesiones.
- Sincronización transparente.
- Preferencias.
- Eliminación/exportación de cuenta.

**P2 — Compartición**
- Compartir mazos.
- Invitaciones por enlace.
- Roles y permisos.
- Progreso individual.
- Copias independientes.

**P3 — Colaboración**
- Contactos.
- Grupos privados.
- Biblioteca de materiales compartidos.
- Moderación y reportes.

**P4 — Personalización avanzada**
- Notificaciones.
- Integración con planificación.
- Recomendaciones de estudio basadas en datos disponibles.
- Exploración de mazos públicos.

No bloquear la publicación inicial por P3 o P4 si P0 y las funciones expuestas en la versión publicada están suficientemente probadas.

---

# 20. ENTREGABLES

Para cada módulo:

1. Revisar implementación existente.
2. Definir contratos y migraciones.
3. Implementar backend.
4. Implementar Flutter.
5. Añadir pruebas.
6. Ejecutar suites disponibles.
7. Revisar seguridad.
8. Documentar decisiones.
9. Señalar dependencias externas.
10. Informar de riesgos pendientes.

Mantener el repositorio compilable y no destruir datos de versiones anteriores.

Al finalizar, entregar una matriz detallada de requisitos con estado:

- Implementado y probado.
- Implementado, pendiente de aceptación.
- Parcial.
- Pendiente.
- Bloqueado por decisión o acceso del titular.

No declarar que Google, Render, PostgreSQL, Firebase o los teléfonos físicos han sido verificados si no existe evidencia.

---

# 21. RESULTADO ESPERADO

LexMemoria debe seguir siendo fundamentalmente una herramienta para estudiar Derecho y preparar oposiciones.

La evolución debe conseguir que:

- Una persona pueda estudiar sola sin cuenta.
- Una persona pueda crear cuenta y recuperar su progreso.
- Un estudiante pueda compartir sus tarjetas con un compañero.
- Varios estudiantes puedan organizar mazos en un grupo privado.
- Cada persona tenga su progreso individual.
- La privacidad esté protegida.
- Los materiales jurídicos conserven sus referencias y versiones.
- Todas las funciones colaborativas sean opcionales.

El usuario no debe sentir que necesita utilizar funciones sociales para aprovechar la aplicación.

**La colaboración debe mejorar el estudio, no sustituirlo.**

Comienza auditando el estado real del repositorio. Resuelve primero los riesgos críticos de datos e identidad y, después, implementa las mejoras por módulos incrementales, sin esperar a completar todo el alcance para generar versiones utilizables.
