# LEXMEMORIA — AUDITORÍA TÉCNICA Y PLAN DE DESARROLLO V3

Actúa como arquitecto principal de software, ingeniero Flutter, ingeniero backend, especialista en seguridad, diseñador UX/UI y responsable de calidad de LexMemoria.

## CONTEXTO

LexMemoria es una plataforma multiplataforma para estudiantes universitarios de Derecho, Criminología y opositores. Su objetivo es combinar legislación oficial, lectura jurídica, flashcards, repetición espaciada, planificación del estudio, exámenes y colaboración.

Existe un repositorio funcional con cliente Flutter, backend FastAPI, biblioteca BOE, generación de ejercicios, persistencia local y módulos de sincronización parcialmente implementados.

La versión inventariada es 0.4.0+6, commit 2604a1a. No presupongas que sigue siendo la versión actual: inspecciona el repositorio y determina el estado real.

## REGLAS FUNDAMENTALES

1. No reconstruyas la aplicación desde cero.
2. No elimines funcionalidades existentes sin justificarlo.
3. Conserva compatibilidad con los datos ya almacenados.
4. Nunca sacrifiques integridad de datos para acelerar el desarrollo.
5. No confundas código existente con funcionalidad operativa.
6. No declares terminado un módulo sin ejecutar sus pruebas.
7. No inventes legislación, jurisprudencia, convocatorias ni referencias jurídicas.
8. No presentes ejercicios generados automáticamente como material jurídicamente revisado.
9. No introduzcas servicios de pago sin necesidad.
10. Mantén Android, iOS y web como plataformas objetivo, documentando las diferencias.
11. Toda operación con datos personales debe disponer de controles de autorización.
12. No incluyas claves secretas en el código cliente.
13. No implementes todavía generación de flashcards mediante IA comercial.
14. Si una operación requiere credenciales, cuentas externas o decisiones legales, prepara la integración y documenta exactamente qué debe aportar el titular.
15. No afirmes que una prueba externa ha pasado si no se ha ejecutado.

## FASE 0: AUDITORÍA DEL CÓDIGO ACTUAL

Inspecciona la arquitectura, módulos, contratos API, persistencia, dependencias, automatizaciones, documentación y tests.

Genera una matriz con identificador, requisito, estado real, archivos relacionados, pruebas disponibles, riesgos, dependencias y criterio de aceptación.

Clasifica cada requisito como COMPLETO, PARCIAL, PENDIENTE o BLOQUEADO.

Distingue entre pruebas unitarias, integración, pruebas nativas y pruebas reales de servicios desplegados.

## FASE 1: SEGURIDAD E INTEGRIDAD

Prioriza:
- Persistencia SQLCipher y almacenamiento seguro.
- Migraciones desde versiones anteriores.
- Recuperación tras cierre inesperado.
- Protección contra escritura parcial.
- Exportación y restauración de datos.
- Gestión de conflictos.
- Aislamiento de información entre usuarios.
- Autenticación y sesiones seguras.
- Revisión de dependencias y secretos.
- Pruebas automatizadas de integridad y autorización.

La aplicación no puede perder tarjetas, historial, notas ni progreso tras actualizarse.

## FASE 2: BIBLIOTECA Y ACTUALIZACIÓN JURÍDICA

Completa y verifica:
- Catálogo de legislación estatal y autonómica.
- Importación estructurada desde el BOE.
- Lectura y búsqueda jurídica.
- Versiones históricas y fechas de vigencia.
- Comparación de redacciones.
- Vigilancia programada de publicaciones.
- Detección de reformas y actualización de textos.
- Referencias entre normas.
- Detección de tarjetas potencialmente desactualizadas.
- Bandeja de novedades.
- Notificaciones personalizadas.
- Auditoría de procedencia y estado editorial.
- Recuperación ante errores de importación.
- Supervisión y alertas operativas.

Distingue publicación, vigencia, consolidación y revisión editorial.

Ninguna actualización debe sobrescribir silenciosamente una versión histórica ni una tarjeta personal.

## FASE 3: APRENDIZAJE Y FLASHCARDS

Amplía los motores existentes para incluir:
- Memorización literal.
- Comprensión conceptual.
- Identificación de excepciones.
- Comparaciones entre instituciones jurídicas.
- Casos prácticos.
- Preguntas de integración normativa.
- Explicaciones y referencias verificables.
- Clasificación de dificultad.
- Análisis de errores.
- Repaso espaciado configurable.
- Seguimiento del progreso.
- Objetivos y planificación adaptativa.

Mantén separación entre contenido oficial, contenido editorial revisado, contenido automático y contenido de usuarios.

No implementes evaluación jurídica automática basada en IA en esta fase.

## FASE 4: UNIVERSIDAD Y OPOSICIONES

Crea experiencias diferenciadas para:
- Estudiantes de Derecho y materias jurídicas de Criminología.
- Opositores de cuerpos jurídicos y administrativos.

Implementa asignaturas, temas, evaluaciones, programas, calendarios, convocatorias y temarios versionados.

Permite vincular artículos y tarjetas a varios temas sin duplicar innecesariamente el contenido.

Los programas oficiales deben conservar fuente y fecha de verificación.

No declares completa una oposición hasta disponer de temario y requisitos contrastados.

## FASE 5: COMUNIDAD Y MAZOS COMPARTIDOS

Implementa:
- Mazos privados.
- Mazos accesibles por invitación.
- Mazos públicos.
- Compartición mediante enlaces.
- Permisos de propietario, editor y lector.
- Copias personales independientes.
- Versionado y conflictos de edición.
- Progreso individual por estudiante.
- Revocación de permisos.
- Denuncia de contenido.
- Moderación y retirada.
- Protección de datos personales.
- Referencias legales y advertencias de desactualización.

Nunca compartas notas privadas ni archivos personales sin una acción explícita del propietario.

## FASE 6: PRODUCCIÓN Y MONETIZACIÓN

Prepara:
- Backend productivo y PostgreSQL.
- Entornos desarrollo, pruebas y producción.
- Backups, recuperación y monitorización.
- Autenticación real.
- Sincronización multidispositivo.
- Google Play Billing y StoreKit.
- Plan gratuito y planes Premium.
- Promociones gratuitas sin cobro automático cuando se diseñen como acceso promocional.
- Validación de compras en servidor.
- Restauración, cancelaciones, reembolsos y caducidades.
- Política de privacidad y gestión de datos.
- Compilaciones firmadas.
- Pruebas beta y preparación de publicación.

No actives cobros reales sin aprobación del titular.

## FASE 7: EXPERIENCIA Y CALIDAD

Verifica todos los flujos en móvil, tablet y web.

Comprueba tamaños de pantalla, orientación, textos ampliados, accesibilidad, TalkBack, VoiceOver, carga, errores, navegación, teclado, rendimiento y consumo de memoria.

Mantén una interfaz minimalista, clara y profesional, con prioridad absoluta en la lectura y el estudio.

## ENTREGABLES OBLIGATORIOS

Para cada fase:
1. Lista exacta de requisitos.
2. Archivos que se deben modificar.
3. Dependencias técnicas.
4. Implementación.
5. Pruebas unitarias y de integración.
6. Pruebas de aceptación reproducibles.
7. Riesgos pendientes.
8. Evidencias verificables.
9. Cambios en la documentación.
10. Decisiones que requieren intervención del titular.

Comienza inspeccionando el repositorio y ejecutando las pruebas disponibles.

Después presenta el orden de implementación y trabaja primero sobre los errores que puedan causar pérdida de datos, vulneraciones de seguridad o información jurídica incorrecta.

No marques una fase como finalizada hasta cumplir sus criterios de aceptación. Trabaja de forma incremental, manteniendo el proyecto compilable y el historial de cambios auditable.
