# Búsqueda y filtro por publicación en la biblioteca

13 de noviembre de 2026. Cambio solicitado por el titular; preparado para la candidata 1.0.0 (21), no disponible todavía en los builds anteriores instalados.

El buscador general de biblioteca reconoce la fecha de publicación como DD/MM/AAAA, AAAA-MM-DD o AAAAMMDD. La información procede exclusivamente de publicationDate; no se deduce del identificador, de la fecha de entrada en vigor ni de la última actualización de un texto consolidado.

En Filtros de biblioteca se puede elegir un intervalo de fecha de publicación, con ambos extremos incluidos, combinarlo con materia, ámbito, comunidad y guardadas, y retirarlo desde el filtro o su chip visible. Aplicar o quitar el intervalo vuelve a la primera página sin borrar la consulta de búsqueda. Cada resultado que tiene una fecha válida muestra Publicada: DD/MM/AAAA. No se añaden horas ni segundos.

Los metadatos BOE en AAAAMMDD y EUR-Lex en AAAA-MM-DD se normalizan por día, con comprobación real de calendario y años bisiestos. Las fechas ausentes o inválidas no se inventan; esas normas siguen presentes sin intervalo y se excluyen al exigir uno. El filtro no modifica el texto jurídico, su vigencia ni sus versiones. No se realizan descargas adicionales para aplicar fechas.

Las opciones de fecha solo se muestran en el filtro de la biblioteca, no en el selector compartido de mazos preparados. La biblioteca europea completa conserva su filtro existente por año.

Validación: cuatro pruebas nuevas de normalización, calendario, límites inclusivos, formatos de búsqueda y recorrido de aplicar/quitar con paginación. La suite Flutter completa supera 178 pruebas, con una omitida; análisis limpio. Las cuatro regresiones del foco/teclado siguen incluidas y superadas. No se atribuye aceptación física iOS a estos tests.

La firma de la candidata sigue bloqueada por IOS_FIREBASE_CONFIG_BASE64 ausente según el preflight 43383609257. El perfil Apple está presente, pero su nueva capacidad no llegó a validarse. No se ha compilado ni subido esta funcionalidad a TestFlight.
