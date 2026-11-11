#!/usr/bin/env python3
"""Render a fixed-size store graphic from the existing app branding.

Uses reportlab and pdftoppm only as document/layout renderers; does not change
the application icon. No user data, synthetic product claims or external assets.
"""
from pathlib import Path
import shutil,subprocess
from reportlab.pdfgen import canvas
from reportlab.lib.colors import HexColor
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
ROOT=Path(__file__).resolve().parents[1]
out=ROOT/'docs/release-1.0/store-assets';out.mkdir(parents=True,exist_ok=True)
shutil.copyfile(ROOT/'mobile/web/icons/Icon-512.png',out/'icon-512.png')
pdfmetrics.registerFont(TTFont('LexGraphic','/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'))
pdfmetrics.registerFont(TTFont('LexGraphicBold','/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'))
c=canvas.Canvas(str(out/'feature-graphic.pdf'),pagesize=(1024,500))
c.setFillColor(HexColor('#17365d'));c.rect(0,0,1024,500,fill=1,stroke=0)
c.setFillColor(HexColor('#ccf3e7'));c.setFont('LexGraphicBold',64);c.drawString(64,265,'LexMemoria')
c.setFillColor(HexColor('#ffffff'));c.setFont('LexGraphic',24);c.drawString(64,203,'Legislación. Tarjetas. Repaso.')
c.drawImage(str(out/'icon-512.png'),700,120,width=260,height=260,mask='auto');c.save()
subprocess.run(['pdftoppm','-singlefile','-r','72','-png',str(out/'feature-graphic.pdf'),str(out/'feature-graphic-1024x500')],check=True)
print(out/'feature-graphic-1024x500.png')
