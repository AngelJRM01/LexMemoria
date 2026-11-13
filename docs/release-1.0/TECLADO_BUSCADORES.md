# Reparación del foco de los buscadores

13 de noviembre de 2026. El titular confirmó que el editor abre el teclado en iPhone, pero los buscadores de biblioteca y tarjetas no lo mantienen.

Causa reproducida en widgets: SearchPageBody cambiaba de estructura al bajar de 440 píxeles de altura disponible. La apertura del teclado cruza ese umbral; el TextField pasa de una columna fija a un ListView.builder distinto, se destruye su EditableTextState y se pierde la conexión/foco. Ambos buscadores usan ese componente. Las dos pruebas iniciales fallaron con el código anterior al comprobar la identidad del campo después de abrir el teclado.

Corrección: una sola estructura estable para cabecera y resultados, con reparto de altura adaptable. Cabecera y pie pueden desplazarse en espacios reducidos. El campo mantiene su elemento, foco, conexión de entrada y consulta durante la animación del teclado y la rotación. Se mantienen filtros fijos y desplazamiento independiente de resultados en pantalla normal. El pie tiene altura limitada y desplazable para no desbordar el espacio restante.

Pruebas finales: cuatro casos superados (biblioteca/tarjetas con variantes de plataforma iOS/Android), apertura y variación de insets, escritura, rotación y cierre del teclado. Suite completa: 174 superadas, una omitida. Análisis Flutter limpio. Son pruebas de widgets con teclado simulado: no acreditan todavía el comportamiento sobre un iPhone físico.

La corrección se incluye en la candidata 1.0.0 (21), aún pendiente de configuración y compilación. No afirmar que el build 19/20 instalado la contiene. El perfil actualizado con Sign in with Apple y IOS_FIREBASE_CONFIG_BASE64 de la integración anterior son requisitos para compilar esa candidata. Se añade un preflight remoto que valida presencia/configuración y capacidad del perfil sin compilar, importar claves privadas, subir a Apple ni publicar. Si pasa, se podrá lanzar la firma; si falla, atender el requisito real mostrado antes de compilar.
