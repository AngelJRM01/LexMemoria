#!/usr/bin/env python3
"""Export a Markdown specification to Word/PDF; optional python-docx/reportlab."""
import argparse
import ast
from pathlib import Path
import re
from html import escape

ROOT = Path(__file__).resolve().parents[1]


def appendix(output):
    rows = []
    for path in sorted((ROOT / 'backend/app').glob('*.py')):
        tree = ast.parse(path.read_text())
        for node in ast.walk(tree):
            if not isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
                continue
            for decorator in node.decorator_list:
                if (isinstance(decorator, ast.Call) and isinstance(decorator.func, ast.Attribute)
                    and decorator.func.attr in {'get', 'post', 'put', 'patch', 'delete'}
                    and decorator.args and isinstance(decorator.args[0], ast.Constant)
                    and isinstance(decorator.args[0].value, str)):
                    rows.append((decorator.func.attr.upper(), decorator.args[0].value,
                                 str(path.relative_to(ROOT)), node.name))
    screens = []
    for path in sorted((ROOT / 'mobile/lib').glob('*.dart')):
        for name, parent in re.findall(r'^class (\w+) extends (\w+)', path.read_text(), re.M):
            if not name.startswith('_') and parent in {'StatelessWidget', 'StatefulWidget'}:
                screens.append((name, str(path.relative_to(ROOT))))
    lines = ['# Anexo técnico de LexMemoria — 10 de noviembre de 2026', '',
             'Inventario generado por lectura del código, sin conectar a servicios privados. Una ruta o componente no acredita aceptación de producción. Las rutas auxiliares pueden tener condiciones de configuración y autorización.', '',
             f'## API: {len(rows)} declaraciones de ruta', '',
             '| Método | Ruta | Archivo | Función |', '| --- | --- | --- | --- |']
    lines += [f'| {a} | `{b}` | `{c}` | `{d}` |' for a,b,c,d in sorted(rows)]
    lines += ['', f'## Cliente: {len(screens)} componentes públicos de interfaz', '',
              'Incluye páginas y componentes reutilizables; no son necesariamente destinos de navegación independientes.', '',
              '| Componente | Archivo |', '| --- | --- |']
    lines += [f'| `{a}` | `{b}` |' for a,b in screens]
    lines += ['', '## Entidades y almacenamiento', '',
              'Servidor: Record, Account, Token, RecoveryCode, Mutation y Audit, con agregados por tipo, historial e índices auxiliares. No se presenta como modelo relacional V2 íntegro.', '',
              'Cliente: estado privado, tarjetas, estados SM-2, revisiones, notas, cursos, plan, lectura, simulacros, colas y referencias. Credenciales separadas; corpus público fuera del backup privado.', '',
              'Pruebas automatizadas en backend/tests y mobile/test; nativas en mobile/integration_test. CI declarada en .github/workflows/ci.yml. La ejecución remota de esa CI no se infiere de su existencia.', '']
    output.write_text('\n'.join(lines))


def blocks(text):
    lines = text.splitlines(); i = 0
    while i < len(lines):
        line = lines[i].strip()
        if not line: i += 1; continue
        if line.startswith('|'):
            table = []
            while i < len(lines) and lines[i].strip().startswith('|'):
                row = [v.strip() for v in lines[i].strip().strip('|').split('|')]
                if not all(re.fullmatch(r'[:\- ]+', v) for v in row): table.append(row)
                i += 1
            yield ('table', table); continue
        match = re.match(r'^(#{1,3})\s+(.+)', line)
        if match: yield ('heading', (len(match[1]), match[2])); i += 1; continue
        if line.startswith('- '): yield ('bullet', line[2:]); i += 1; continue
        if re.match(r'^\d+\. ', line): yield ('number', re.sub(r'^\d+\. ', '', line)); i += 1; continue
        para = [line]; i += 1
        while i < len(lines) and lines[i].strip() and not lines[i].lstrip().startswith(('#', '|', '- ')):
            para.append(lines[i].strip()); i += 1
        yield ('paragraph', ' '.join(para))


def plain(value):
    return value.replace('**', '').replace('`', '')


def word(source, output):
    from docx import Document
    from docx.shared import Inches, Mm, Pt, RGBColor
    from docx.oxml import OxmlElement
    from docx.oxml.ns import qn
    doc = Document(); section = doc.sections[0]
    section.page_width = Mm(210); section.page_height = Mm(297)
    section.header.paragraphs[0].text = 'LEXMEMORIA  |  Especificación y preparación de publicación'
    section.top_margin = section.bottom_margin = Inches(.7)
    section.left_margin = section.right_margin = Inches(.7)
    style = doc.styles['Normal']; style.font.name = 'Calibri'; style.font.size = Pt(10)
    style.paragraph_format.space_after = Pt(6)
    for name in ['Title', 'Heading 1', 'Heading 2', 'Heading 3']:
        doc.styles[name].font.color.rgb = RGBColor.from_string('193957')
    for kind, value in blocks(source.read_text()):
        if kind == 'heading':
            level, text = value
            doc.add_heading(plain(text), 0 if level == 1 else level - 1)
        elif kind == 'table':
            table = doc.add_table(rows=1, cols=len(value[0])); table.style = 'Light Shading Accent 1'
            for idx, row in enumerate(value):
                cells = table.rows[0].cells if idx == 0 else table.add_row().cells
                for cell, text in zip(cells, row):
                    cell.text = plain(text)
                    for para in cell.paragraphs:
                        for run in para.runs: run.font.size = Pt(8)
            trPr = table.rows[0]._tr.get_or_add_trPr(); repeat = OxmlElement('w:tblHeader'); trPr.append(repeat)
            doc.add_paragraph()
        else:
            paragraph = doc.add_paragraph(style='List Bullet' if kind == 'bullet' else 'List Number' if kind == 'number' else 'Normal')
            for token in re.split(r'(\*\*.*?\*\*|`[^`]+`)', value):
                run = paragraph.add_run(plain(token)); run.bold = token.startswith('**')
    footer = section.footer.paragraphs[0]; footer.add_run('LexMemoria · 10/11/2026 · ')
    fld = OxmlElement('w:fldSimple'); fld.set(qn('w:instr'), 'PAGE'); footer._p.append(fld)
    doc.core_properties.title = 'LexMemoria — especificación actual y primera publicación'
    doc.core_properties.subject = 'Inventario funcional, evidencias, pendientes y aceptación V1'
    doc.save(output)


def pdf(source, output):
    from reportlab.lib import colors
    from reportlab.lib.pagesizes import A4
    from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
    from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, LongTable, TableStyle
    from reportlab.pdfbase import pdfmetrics
    from reportlab.pdfbase.ttfonts import TTFont
    fontroot = Path('/usr/share/fonts/truetype/dejavu')
    pdfmetrics.registerFont(TTFont('DejaVu', str(fontroot/'DejaVuSans.ttf')))
    pdfmetrics.registerFont(TTFont('DejaVuBold', str(fontroot/'DejaVuSans-Bold.ttf')))
    pdfmetrics.registerFontFamily('DejaVu', normal='DejaVu', bold='DejaVuBold')
    styles = getSampleStyleSheet()
    for name in ['Normal', 'Title', 'Heading1', 'Heading2', 'Heading3']:
        styles[name].fontName = 'DejaVu'; styles[name].textColor = colors.HexColor('#193957' if name != 'Normal' else '#222222')
    styles['Normal'].fontSize = 9; styles['Normal'].leading = 13; styles['Normal'].spaceAfter = 7
    styles['Title'].fontSize = 23; styles['Title'].leading = 29
    styles['Heading1'].fontSize = 14; styles['Heading1'].leading = 19
    styles['Heading2'].fontSize = 11; styles['Heading2'].leading = 15
    small = ParagraphStyle('cell', parent=styles['Normal'], fontSize=7.1, leading=10, spaceAfter=3)
    def rich(text):
        value = escape(text.replace('`', ''))
        return re.sub(r'\*\*(.*?)\*\*', r'<b>\1</b>', value)
    story = []
    for kind, value in blocks(source.read_text()):
        if kind == 'heading':
            level, text = value; story.append(Paragraph(rich(text), styles['Title' if level == 1 else 'Heading'+str(level-1)]))
        elif kind == 'table':
            width = A4[0]-80; cols = len(value[0])
            widths = ([width*.19, width*.24, width*.57] if cols == 3 else [width/cols]*cols)
            table = LongTable([[Paragraph(rich(c), small) for c in row] for row in value], colWidths=widths, repeatRows=1, hAlign='LEFT')
            table.setStyle(TableStyle([('BACKGROUND',(0,0),(-1,0),colors.HexColor('#dae5ee')),('VALIGN',(0,0),(-1,-1),'TOP'),('GRID',(0,0),(-1,-1),.3,colors.HexColor('#c4cdd5')),('LEFTPADDING',(0,0),(-1,-1),5),('RIGHTPADDING',(0,0),(-1,-1),5),('TOPPADDING',(0,0),(-1,-1),5),('BOTTOMPADDING',(0,0),(-1,-1),5)]))
            story.extend([table, Spacer(1,10)])
        else:
            story.append(Paragraph(('• ' if kind in {'bullet','number'} else '')+rich(value), styles['Normal']))
    def footer(canvas, doc):
        canvas.setFont('DejaVu', 7); canvas.setFillColor(colors.HexColor('#556677'))
        canvas.drawString(40, 24, 'LexMemoria · Especificación y publicación · 10/11/2026')
        canvas.drawRightString(A4[0]-40,24,str(doc.page))
    SimpleDocTemplate(str(output), pagesize=A4, leftMargin=40, rightMargin=40, topMargin=38, bottomMargin=42,
        title='LexMemoria — especificación actual y primera publicación', author='LexMemoria').build(story, onFirstPage=footer, onLaterPages=footer)


def main():
    p = argparse.ArgumentParser(description=__doc__); p.add_argument('source', type=Path); args = p.parse_args()
    appendix(args.source.parent/'ANEXO_TECNICO_2026-11-10.md')
    word(args.source, args.source.with_suffix('.docx')); pdf(args.source, args.source.with_suffix('.pdf'))
    print(args.source.with_suffix('.docx')); print(args.source.with_suffix('.pdf'))

if __name__ == '__main__': main()
