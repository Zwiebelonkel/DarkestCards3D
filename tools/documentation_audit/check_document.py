from pathlib import Path
import json
import re
from PIL import Image, ImageOps, ImageDraw
import pdfplumber
from pypdf import PdfReader

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'docs/game-documentation'
PDF=OUT/'DarkestCards3D_Spieldokumentation.pdf'
MD=OUT/'DarkestCards3D_Spieldokumentation.md'
pages=[]
with pdfplumber.open(PDF) as pdf:
    for index,page in enumerate(pdf.pages,1):
        words=page.extract_words()
        overflow=[w['text'] for w in words if w['x0']<45 or w['x1']>page.width-45 or w['top']<10 or w['bottom']>page.height-10]
        pages.append({'page':index,'words':len(words),'text_characters':len(page.extract_text() or ''),'overflow_words':overflow})
assert all(p['words']>20 for p in pages),'Blank or nearly blank page'
assert not any(p['overflow_words'] for p in pages),'Text outside page margins'
text=MD.read_text(encoding='utf-8')
assert not re.search(r'{{[A-Z_]+}}',text),'Unresolved source token'
catalog=json.loads((OUT/'audit/source-snapshot.json').read_text(encoding='utf-8'))
assert catalog['cards']==118 and catalog['combat_cards']==93 and catalog['special_cards']==25
reviewed=json.loads((OUT/'audit/test-results-reviewed.json').read_text(encoding='utf-8'))
assert len(reviewed['results'])==122
QA=OUT/'qa'
images=sorted(QA.glob('final-page-*.png'))
if images:
    for start in range(0,len(images),9):
        sheet=Image.new('RGB',(1530,2070),'#dadada')
        draw=ImageDraw.Draw(sheet)
        for slot,path in enumerate(images[start:start+9]):
            im=Image.open(path).convert('RGB');im.thumbnail((490,645))
            x=(slot%3)*510+10;y=(slot//3)*690+28
            sheet.paste(im,(x,y))
            draw.text((x,y-20),f'Seite {int(path.stem.split("-")[-1])}',fill='black')
        sheet.save(QA/f'final-contact-{start//9+1}.png')
report={'pages':pages,'outline_entries':len(PdfReader(PDF).outline),'page_count':len(pages),'margin_check':'passed','catalog_check':'118 total, 93 combat, 25 special','test_suite_count':len(reviewed['results']),'rendered_page_count':len(images)}
(QA/'document-check.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({k:v for k,v in report.items() if k!='pages'},ensure_ascii=False))
