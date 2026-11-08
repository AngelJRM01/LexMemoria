# Integración europea en curso

La descarga original, la extracción de párrafos HTML y la clasificación estructural son etapas separadas. El nuevo módulo `backend/app/eu_structure.py` conserva exactamente cada párrafo y su ancla, URL y hash original. No modifica el archivo de descarga ni el índice del extractor activo.

## Muestra inicial real

Se ejecutó `scripts/prepare_eu_structure.py` sobre los objetos HTML ya archivados:

| CELEX | Documento | Párrafos conservados | Artículos candidatos |
| --- | --- | ---: | ---: |
| 32016R0679 | RGPD, acto original | 1791 | 99 |
| 32019L1152 | Condiciones laborales transparentes | 329 | 26 |
| 32021D0914 | Cláusulas de transferencia de datos | 623 | 4 |

El informe reproducible está en `validation/eu-integration/initial-sample.json`. Los paquetes derivados locales están fuera del repositorio, en `/workspace/lexmemoria-eu-structured`. El script comprueba el hash del objeto de párrafos y verifica conservación exacta y orden de todos ellos antes de escribir. Su selección es determinista por URL dentro de cada CELEX; no pretende elegir automáticamente la versión vigente.

Se reconocen encabezamientos completos de artículo; menciones a artículos dentro de una frase no crean artículos. Una vez iniciado un anexo, sus encabezamientos de artículo permanecen dentro del anexo. Las firmas se separan al reconocer «Hecho en…». Las notas no reconocidas conservan su contenido, sin convertirlas en artículos. Las numeraciones de artículo duplicadas producen una advertencia. Las formas no reconocidas requieren ampliar y probar las reglas, no asumir una clasificación correcta.

## Límites y pasos pendientes

Todos los objetos llevan `clientReady: false`, `currency: not_verified`, `legalReview: not_performed` y `automaticStudyEligible: false`. Reconocer 99 encabezamientos no acredita por sí mismo el contenido correcto de cada artículo. No hay todavía publicación europea en el móvil ni generación de ejercicios europeos.

Queda contrastar cuerpos y límites con el HTML estructural original, ampliar la muestra a documentos históricos, textos consolidados, correcciones y actos modificativos, resolver notas/tablas/citas de actos dentro de artículos y comprobar relaciones de versiones y vigencia. Después se prepararán catálogo, búsqueda y paquetes móviles; se mantendrán considerandos y anexos separados de los artículos estudiables. PDF y otros formatos siguen pendientes de extracción específica.

## Ejecución

Desde la raíz, usando el Python del proyecto:

```
python scripts/prepare_eu_structure.py
```

Desde `backend`, las pruebas relevantes son:

```
python -m pytest tests/test_eu_structure.py tests/test_eu_processing.py -q
```

Resultado inicial: 11 pruebas superadas. La descarga y el procesador de párrafos continúan independientemente; este paso no los reinicia ni detiene.
