#!/usr/bin/env python3
"""Render the reviewed V3 requirement inventory; statuses are human assessments."""
import json
from pathlib import Path
import re
ROOT=Path(__file__).resolve().parents[1]
DOC=ROOT/'docs/v3'

# Indexes follow the literal bullet order in SOLICITUD_V3.md.
CONFIG={
 0:('docs/ESTADO_FUNCIONAL_0_4_0.md; docs/v3/; scripts/audit_repository.py',
    'Baseline: 94 backend + 63 Flutter; dependency inventory and pip check',
    'No equivalencia entre código y operación; evidencia externa ausente',
    'Repositorio, runtimes y lectura de lockfiles',
    'Matriz cubre solicitud y enlaza pruebas, riesgos, dependencias y aceptación sin ocultar lagunas'),
 1:('mobile/lib/{persistence,backup,store,remote,profile}.dart; backend/app/{main,identity,backup}.py',
    'mobile/test/{backup_integrity,remote,persistence,startup}_test.dart; backend/tests/test_{authorization_v3,cloze_v3,identity_backup,recovery}.py',
    'Pérdida de estado, cruce de cuentas, migración nativa no ejecutada y credenciales externas',
    'SQLCipher/Keystore/Keychain, dispositivo nativo; API HTTPS para sesiones reales',
    'Restaurar/reabrir datos previos; inyectar fallos y concurrencia; negar accesos cruzados; probar actualización real sin pérdida'),
 2:('mobile/lib/{library,reading,store}.dart; backend/app/{boe,bulk,eu_bulk,eu_supervisor,eu_processing,monitor,jobs,temporal,notifications}.py',
    'mobile/test/{corpus,reading,temporal_planning,browsing_exercises}_test.dart; backend/tests/test_{bulk,eu_bulk,eu_supervisor,eu_processing,jobs_monitor,temporal,distribution}.py',
    'Confundir descarga con integración, vigencia o revisión; consolidación atrasada; tablas y referencias incompletas',
    'Fuentes oficiales y licencias; planificador desplegado y revisión jurídica',
    'Cotejar fuente/versiones; fallo no sustituye texto válido; historial permanece; evento y tarjeta afectada trazables'),
 3:('mobile/lib/{prepared,exercises,study,models,planning}.dart; backend/app/{learning,exercises}.py',
    'mobile/test/{learning,product_v2,browsing_exercises,temporal_planning}_test.dart; backend/tests/test_cloze_v3.py; docs/validation/boe-exercises-0.4.0.json',
    'Recuerdo literal no acredita comprensión; ningún ejercicio automático tiene revisión jurídica humana',
    'Fuentes y banco editorial revisado, sin IA comercial',
    'Respuesta y referencia reproducibles; contenido distinguido por procedencia; no atribuir validación humana a generación automática'),
 4:('mobile/lib/{university,planning,workspace,models}.dart; backend/app/main.py',
    'mobile/test/{product_v2,temporal_planning}_test.dart; backend/tests/test_product_v2.py',
    'Programa personal confundido con guía/convocatoria oficial; duplicación de contenido',
    'Convocatorias y guías autorizadas, fuente/fecha y validación humana',
    'Programa versionado enlaza fuente y fecha; varios temas apuntan al mismo artículo/tarjeta sin duplicarlo'),
 5:('backend/app/main.py; backend/app/db.py; mobile/lib/{study,remote}.dart; módulos de comunidad aún por crear',
    'Solo mazos privados y aislamiento actual: backend/tests/test_authorization_v3.py; no pruebas E2E de compartición existentes',
    'Fuga de notas privadas, permiso revocado aún válido, edición pública y moderación incompletas',
    'Modelo ACL, política de moderación, API desplegada y acción explícita del propietario',
    'Probar propietario/editor/lector, invitación, revocación y copia independiente; ninguna nota privada se publica implícitamente'),
 6:('render.yaml; docs/DESPLIEGUE.md; .github/workflows/ci.yml; backend/app/{main,db,backup,identity}.py; mobile/lib/{remote,profile}.dart',
    'Pruebas locales de adaptadores; ningún servicio productivo/pago/push real validado',
    'Coste, credenciales, permisos de tienda, recuperación real y obligaciones legales pendientes',
    'Titular: proveedor/región/presupuesto, identidad, firma, cuentas/productos de tienda y textos legales',
    'Ensayo staging con servicios reales, restauración, sincronización y tiendas sandbox; cobros solo tras aprobación expresa'),
 7:('mobile/lib/; mobile/test/usability_test.dart; mobile/test/product_v2_test.dart; mobile/integration_test/startup_test.dart; .github/workflows/ci.yml',
    'Widget tests, escalado/rotación seleccionados y builds; pruebas físicas y lectores reales no ejecutados',
    'Build correcto no acredita accesibilidad, bajo consumo o compatibilidad de dispositivos',
    'OPPO/Android, macOS/iOS, TalkBack/VoiceOver y dispositivos/mediciones reales',
    'Recorrer matriz móvil/tablet/web con teclado, rotación, 200% texto, lector de pantalla, carga/error/offline y medición de memoria'),
}
EXTRA={
 0:['Inspeccionar arquitectura y módulos actuales.', 'Inventariar contratos API y persistencia.',
    'Inventariar dependencias, automatizaciones y documentación.', 'Ejecutar pruebas disponibles e identificar su tipo.',
    'Generar matriz con identificador, requisito, estado, archivos, pruebas, riesgos, dependencias y aceptación.',
    'Clasificar cada requisito como COMPLETO, PARCIAL, PENDIENTE o BLOQUEADO.',
    'Distinguir pruebas unitarias, integración, nativas y servicios reales desplegados.'],
 2:['Completar y procesar incrementalmente archivo europeo sin detener descargas ni falsear cobertura.'],
 4:['Implementar asignaturas, temas y evaluaciones.', 'Implementar programas y calendarios.',
    'Implementar convocatorias y temarios versionados.',
    'Vincular artículos y tarjetas a varios temas sin duplicar contenido.',
    'Programas oficiales conservan fuente y fecha de verificación.',
    'No declarar completa una oposición sin temario y requisitos contrastados.'],
 7:['Verificar todos los flujos en móvil, tablet y web.', 'Verificar tamaños de pantalla y orientación.',
    'Verificar textos ampliados y accesibilidad.', 'Verificar TalkBack y VoiceOver.',
    'Verificar carga, errores, navegación y teclado.', 'Medir rendimiento y consumo de memoria.',
    'Mantener interfaz minimalista con prioridad en lectura y estudio.'],
}
# Deliberately conservative. COMPLETO is reserved for a narrowly evidenced item.
STATUS={
 0:['COMPLETO','COMPLETO','PARCIAL','COMPLETO','COMPLETO','COMPLETO','COMPLETO'],
 1:['PARCIAL']*10,
 2:['PARCIAL']*15,
 3:['COMPLETO','PENDIENTE','PENDIENTE','PENDIENTE','PARCIAL','PENDIENTE','PARCIAL','PENDIENTE','PARCIAL','PARCIAL','PARCIAL','PARCIAL'],
 4:['PARCIAL','PARCIAL','PARCIAL','PARCIAL','PENDIENTE','PENDIENTE','PENDIENTE','PARCIAL'],
 5:['PARCIAL','PENDIENTE','PENDIENTE','PENDIENTE','PENDIENTE','PENDIENTE','PARCIAL','PARCIAL','PENDIENTE','PARCIAL','PENDIENTE','PARCIAL','PARCIAL'],
 6:['BLOQUEADO','PARCIAL','PARCIAL','BLOQUEADO','PARCIAL','BLOQUEADO','PARCIAL','PARCIAL','BLOQUEADO','BLOQUEADO','BLOQUEADO','BLOQUEADO','BLOQUEADO'],
 7:['PARCIAL','PARCIAL','PARCIAL','BLOQUEADO','PARCIAL','PENDIENTE','PARCIAL'],
}
NOTES={
 (1,5):'Restauración endurecida con validación previa, checkpoint y commit antes de publicar; falta aceptación nativa.',
 (1,7):'Pruebas negativas de API y sesión vinculada a cuenta/servidor; sin aceptación productiva.',
 (1,8):'Sobre de credenciales único y refresh concurrente deduplicado; migración antigua exige prueba autenticada.',
 (1,9):'140 componentes inventariados y tres patrones sin hallazgos; no escaneo CVE ni historial Git completo.',
 (2,1):'Corte BOE 12.451 normas verificado; no cobertura universal ni actualización productiva garantizada.',
 (2,5):'Comparación textual por párrafos; análisis jurídico semántico pendiente.',
 (2,11):'Bandeja interna y seguimiento por norma; push y granularidad completa pendientes.',
 (2,15):'Descarga supervisada y extracción incremental HTML activas; otros formatos, estructura jurídica e integración móvil pendientes.',
 (3,1):'684.375 ejercicios base de recuerdo; formatos automáticos técnicamente auditados, no revisión jurídica.',
 (3,5):'Editor personal disponible; falta banco profesional revisado y evaluación jurídica.',
 (5,1):'Mazos de propietario en API actual; no comunidad operativa.',
 (6,8):'Promoción interna 30 días sin renovación ni cobro automático; no producto real de tienda.',
}

def build():
    by_phase={p:[] for p in CONFIG}; phase=None
    source=(DOC/'SOLICITUD_V3.md').read_text()
    for line in source.splitlines():
        heading=re.match(r'## FASE (\d+):',line)
        if heading:phase=int(heading[1])
        if line.startswith('## ENTREGABLES'):phase=None
        if phase is not None and line.startswith('- '):by_phase[phase].append(line[2:])
    for p,items in EXTRA.items():by_phase[p].extend(items)
    rows=[]
    for phase,requirements in by_phase.items():
        assert len(requirements)==len(STATUS[phase]),(phase,len(requirements),len(STATUS[phase]))
        files,tests,risks,dependencies,acceptance=CONFIG[phase]
        for number,req in enumerate(requirements,1):
            rows.append({'id':f'V3-F{phase}-{number:02}', 'phase':phase,'requirement':req,
                'status':STATUS[phase][number-1], 'relatedFiles':files,'availableTests':tests,
                'testTypes':['unit','local integration'] if phase<6 else ['unit/local integration only; real external NOT RUN'],
                'risks':risks,'dependencies':dependencies,
                'acceptance':f'{req} — {acceptance}. Caso reproducible y evidencia exigidos para este requisito.',
                'assessment':NOTES.get((phase,number),'Alcance y límites en docs/ESTADO_FUNCIONAL_0_4_0.md y docs/v3/PLAN_Y_EVIDENCIAS.md.')})
    rules=[]
    in_rules=False
    for line in source.splitlines():
        if line.startswith('## REGLAS'):in_rules=True;continue
        if line.startswith('## FASE'):in_rules=False
        if in_rules and re.match(r'^\d+\. ',line):rules.append(re.sub(r'^\d+\. ','',line))
    for n,rule in enumerate(rules,1):
        rows.append({'id':f'V3-REG-{n:02}','phase':'transversal','requirement':rule,
            'status':'PARCIAL','relatedFiles':'Todo el repositorio; docs/v3/PLAN_Y_EVIDENCIAS.md',
            'availableTests':'Suites locales y revisión; no aceptación universal de plataformas/servicios',
            'testTypes':['review','unit','local integration'],
            'risks':'Una regla transversal no queda probada universalmente por una sola prueba.',
            'dependencies':'Revisión por incremento y pruebas externas cuando correspondan.',
            'acceptance':'Cumplir esta regla en cada cambio y documentar cualquier limitación antes de publicar.',
            'assessment':'Regla vigente; no se marca satisfecha para todo el producto futuro.'})
    (DOC/'matriz-requisitos.json').write_text(json.dumps({'baselineCommit':'ae712a6',
        'appVersionAtAudit':'0.4.0+6','request':'SOLICITUD_V3.md','requirements':rows},ensure_ascii=False,indent=2)+'\n')
    out=['# Matriz de requisitos V3','',
        'Inventario revisado de requisitos explícitos, párrafos funcionales y reglas transversales. No es aceptación automática del producto ni del despliegue. Estados conservadores; las fases completas siguen abiertas.','','| ID | Requisito | Estado | Archivos | Pruebas disponibles | Riesgos | Dependencias | Aceptación | Evaluación |','| --- | --- | --- | --- | --- | --- | --- | --- | --- |']
    for r in rows:
        values=[r[k] for k in ('id','requirement','status','relatedFiles','availableTests','risks','dependencies','acceptance','assessment')]
        out.append('| '+' | '.join(str(v).replace('|','/').replace('\n',' ') for v in values)+' |')
    (DOC/'MATRIZ_REQUISITOS.md').write_text('\n'.join(out)+'\n')
    print(json.dumps({'requirements':len(rows),'states':{s:sum(r['status']==s for r in rows) for s in ('COMPLETO','PARCIAL','PENDIENTE','BLOQUEADO')}}))
if __name__=='__main__':build()
