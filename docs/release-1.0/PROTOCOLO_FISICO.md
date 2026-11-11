# Aceptación física de LexMemoria 1.0

Estado inicial: pendiente. El titular comunicó una gran mejora de 0.8.4 en OPPO Reno 10 Pro/Android 15, sin mediciones de latencia. Este protocolo no convierte esa valoración en prueba de todos los recorridos de 1.0.

Registrar por caso: versión/código/hash, paquete, origen de instalación, dispositivo/Android, fecha, red, datos sintéticos usados, resultado, incidencia y evidencia sin información personal. Añadir al menos otro Android. Los emuladores no sustituyen estos dispositivos ni el canal Play.

| ID | Caso | Resultado que permite aceptar |
| --- | --- | --- |
| F01 | Actualizar preview sin desinstalar | Conserva perfil, tarjetas, estados, notas, plan, sesión y borradores. |
| F02 | Cambio preview → paquete Play | Exportación válida; importación/recuperación comparada y preview conservado. |
| F03 | Abrir sin red, Constitución y texto europeo guardado | Lectura/repaso local no esperan a Render. |
| F04 | Buscar, filtrar comunidad, paginar, volver y continuar lectura | Resultados coherentes, posición de edición correcta, filtros accesibles. |
| F05 | Editor: escribir, esperar guardado, Atrás y volver | Se conserva exactamente el texto confirmado. |
| F06 | Editor: escritura continua y cierre forzado | Medir ventana pendiente; ningún estado confirmado como guardado se pierde. No exigir conservar texto nunca confirmado. |
| F07 | Editor: poco espacio o fallo de escritura | Informa de fallo, no muestra guardado y no permite una salida normal que descarte texto. |
| F08 | Tarjetas/huecos/tests/repaso | Respuesta literal contrastada, evento único ante doble toque, sesión persistente. |
| F09 | Copia JSON/restauración | Conserva Unicode/citas/estados; archivo inválido no reemplaza datos. |
| F10 | Google del AAB instalado desde Play | Acceso con certificado final; cancelar/cambiar cuenta no mezcla propietarios. |
| F11 | Sincronizar A → recuperar B | Comparar tarjetas, estados, eventos, notas, cursos, marcadores, lectura y simulacros. |
| F12 | Red interrumpida, conflicto, reinicio API | Reintento sin duplicados; conflicto visible y sin sobrescritura silenciosa. |
| F13 | Cuenta y eliminación web/app | Revocación y coordinación Firebase/API; otra cuenta permanece aislada. |
| F14 | Público desactivado | No hay publicar/explorar; API deniega catálogo y acceso por vieja aprobación. |
| F15 | Privado si se incluye | Invitación, lectura/copia, rol, revocación/bloqueo y denuncia sin exponer progreso. |
| F16 | Plan, asignaturas, simulacro | Persistencia tras cierre, temporizador y corrección coherentes. |
| F17 | Accesibilidad | TalkBack, texto grande, foco, teclado, rotación y margen inferior aceptados. |
| F18 | Fluidez | Medir arranque frío/caliente y p50/p95 de abrir, buscar, paginar y repasar; separar descargas, Render frío y uso local. |
| F19 | Canal interno Play | Instalar/actualizar AAB con Play App Signing; repetir F02, F10–F13. |

Bloquean publicación: pérdida de datos confirmados, acceso a datos de otra cuenta, borrado erróneo, migración insegura, caída en recorridos principales, privacidad/eliminación anunciadas pero no operativas. Un fallo no se cierra con una pantalla de éxito sin comparar los datos.

El cierre forzado puede matar una escritura pendiente y no entrega un evento fiable de ciclo de vida. El indicador del editor es la frontera: «Borrador guardado» significa que la escritura terminó; «Guardando» no es confirmación. No se promete conservación de teclas que el sistema aún no permitió persistir.
