#!/usr/bin/env python3
"""Open the files CheckDocumentCreation.swift made with libraries that share no
code with the writers: zipfile (every CRC, entry names and stored/deflated),
ElementTree (every XML part is well formed), python-docx, openpyxl,
python-pptx and pypdf. The expected values come from manifest.json.

Run through uv, never from inside the sample folder:
uv run --with python-docx --with openpyxl --with python-pptx --with pypdf python -I validate_created_files.py FOLDER
"""
import hashlib
import json
import re
import sys
import zipfile
from pathlib import Path
from xml.etree import ElementTree

import docx
import openpyxl
import pptx
import pypdf

W = '{http://schemas.openxmlformats.org/wordprocessingml/2006/main}'


class Checks:
    def __init__(self):
        self.count = 0
        self.failures = []

    def expect(self, condition, label):
        self.count += 1
        if not condition:
            self.failures.append(label)


def package(check, path, entry):
    with zipfile.ZipFile(path) as archive:
        check.expect(archive.testzip() is None, f'{path.name}: every CRC matches')
        names = archive.namelist()
        check.expect(len(names) == len(set(names)), f'{path.name}: entry names are unique')
        for info in archive.infolist():
            data = archive.read(info)
            check.expect(len(data) == info.file_size, f'{path.name}/{info.filename}: size')
            check.expect(info.flag_bits & 0x8 == 0, f'{path.name}/{info.filename}: sizes in the local header')
            if not info.filename.isascii():
                check.expect(info.flag_bits & 0x800, f'{path.name}/{info.filename}: UTF-8 name flag')
            if entry['format'] != 'zip' and info.filename.endswith(('.xml', '.rels')):
                try:
                    ElementTree.fromstring(data)
                    check.expect(True, '')
                except ElementTree.ParseError as error:
                    check.expect(False, f'{path.name}/{info.filename}: XML not well formed: {error}')
        if entry['format'] != 'zip':
            check.expect(names[0] == '[Content_Types].xml', f'{path.name}: content types first')


def numbering_formats(document):
    """numId -> its level-0 format, read from numbering.xml directly."""
    root = document.part.numbering_part.element
    abstract = {a.get(W + 'abstractNumId'): a.find(f'{W}lvl/{W}numFmt').get(W + 'val') for a in root.findall(W + 'abstractNum')}
    return {n.get(W + 'numId'): abstract[n.find(W + 'abstractNumId').get(W + 'val')] for n in root.findall(W + 'num')}


def word(check, path, entry):
    document = docx.Document(str(path))
    check.expect(document.core_properties.title == entry['title'], f'{path.name}: title property')
    paragraphs = document.paragraphs
    expected = entry['paragraphs']
    check.expect(len(paragraphs) == len(expected), f'{path.name}: {len(paragraphs)} paragraphs, expected {len(expected)}')
    formats = numbering_formats(document)
    lists = {}
    for paragraph, wanted in zip(paragraphs, expected):
        label = f'{path.name}: paragraph {wanted["text"]!r}'
        check.expect(paragraph.text == wanted['text'], f'{label} reads {paragraph.text!r}')
        check.expect(paragraph.style.name == wanted.get('style', 'Normal'), f'{label} style {paragraph.style.name}')
        for kind in ('bold', 'italic'):
            styled = [run.text for run in paragraph.runs if getattr(run, kind)]
            check.expect(styled == wanted.get(kind, []), f'{label} {kind} runs {styled}')
        code = [run.text for run in paragraph.runs if run.font.name == 'Courier New']
        if 'code' in wanted:
            check.expect(code == wanted['code'], f'{label} code runs {code}')
        number = paragraph._p.pPr.numPr.numId.val if paragraph._p.pPr is not None and paragraph._p.pPr.numPr is not None else None
        check.expect((formats.get(str(number)) if number is not None else None) == wanted.get('numbering'), f'{label} numbering')
        if 'list' in wanted:
            lists.setdefault(wanted['list'], set()).add(number)
    ids = [ids for ids in lists.values()]
    check.expect(all(len(group) == 1 for group in ids), f'{path.name}: one numId per numbered list')
    check.expect(len({next(iter(group)) for group in ids}) == len(ids), f'{path.name}: each numbered list counts from 1')
    tables = [[[cell.text for cell in row.cells] for row in table.rows] for table in document.tables]
    check.expect(tables == entry['tables'], f'{path.name}: tables {tables}')
    for table in document.tables:
        header = [run.bold for cell in table.rows[0].cells for p in cell.paragraphs for run in p.runs]
        check.expect(header and all(header), f'{path.name}: bold header row')


def same(actual, expected):
    """openpyxl's value and the JSON value: equal, and the same kind."""
    if expected is None or actual is None:
        return actual is None and expected is None
    if isinstance(expected, bool) or isinstance(actual, bool):
        return isinstance(actual, bool) and isinstance(expected, bool) and actual == expected
    if isinstance(expected, (int, float)):
        return isinstance(actual, (int, float)) and actual == expected
    return isinstance(actual, str) and actual == expected


def spreadsheet(check, path, entry):
    workbook = openpyxl.load_workbook(str(path))
    check.expect(workbook.properties.title == entry['title'], f'{path.name}: title property')
    check.expect(workbook.sheetnames == [s['name'] for s in entry['sheets']], f'{path.name}: sheet names {workbook.sheetnames}')
    for sheet, wanted in zip(workbook.worksheets, entry['sheets']):
        rows = [list(row) for row in sheet.iter_rows(values_only=True)]
        if rows == [[None]]:
            rows = []
        label = f'{path.name}/{sheet.title}'
        if 'rows' in wanted:
            width = max([len(r) for r in wanted['rows']] or [0])
            expected = [row + [None] * (width - len(row)) for row in wanted['rows']]
            check.expect(len(rows) == len(expected), f'{label}: {len(rows)} rows')
            for index, (row, want) in enumerate(zip(rows, expected)):
                check.expect(len(row) == len(want) and all(same(a, e) for a, e in zip(row, want)), f'{label}: row {index + 1} {row} != {want}')
            for row in sheet.iter_rows():
                for cell in row:
                    if isinstance(cell.value, str):
                        check.expect(cell.data_type == 's', f'{label}!{cell.coordinate}: text stays text')
        else:
            check.expect(len(rows) == wanted['rows_count'], f'{label}: {len(rows)} rows')
            check.expect(all(same(a, e) for a, e in zip(rows[0], wanted['first'])), f'{label}: first row')
            check.expect(all(same(a, e) for a, e in zip(rows[-1], wanted['last'])), f'{label}: last row')
        if rows:
            check.expect(all(cell.font.b for cell in sheet[1] if cell.value is not None), f'{label}: bold header')
        if len(rows) > 1:
            check.expect(sheet.freeze_panes == 'A2', f'{label}: header row kept in view')


def presentation(check, path, entry):
    deck = pptx.Presentation(str(path))
    check.expect(deck.core_properties.title == entry['title'], f'{path.name}: title property')
    slides = list(deck.slides)
    check.expect(len(slides) == len(entry['slides']), f'{path.name}: {len(slides)} slides')
    for number, (slide, wanted) in enumerate(zip(slides, entry['slides']), 1):
        check.expect(slide.shapes.title is not None and slide.shapes.title.text == wanted['title'],
                     f'{path.name}: slide {number} title')
        body = [shape for shape in slide.placeholders if shape.placeholder_format.idx == 1]
        bullets = [p.text.replace('\v', '\n') for p in body[0].text_frame.paragraphs] if body else []
        check.expect(bullets == wanted['bullets'], f'{path.name}: slide {number} bullets {bullets}')
        sizes = [run.font.size for p in body[0].text_frame.paragraphs for run in p.runs] if body else []
        if 'bullet_points_at_most' in wanted:
            check.expect(sizes and all(size is not None and size.pt <= wanted['bullet_points_at_most'] for size in sizes),
                         f'{path.name}: slide {number} set smaller to fit')
        else:
            check.expect(all(size is None for size in sizes), f'{path.name}: slide {number} keeps the theme size')


def pdf(check, path, entry):
    reader = pypdf.PdfReader(str(path))
    check.expect(len(reader.pages) >= 1, f'{path.name}: pages')
    check.expect(reader.metadata is not None and reader.metadata.title == entry['title'], f'{path.name}: title')
    text = re.sub(r'\s+', '', ''.join(page.extract_text() or '' for page in reader.pages))
    for wanted in entry['text']:
        check.expect(re.sub(r'\s+', '', wanted) in text, f'{path.name}: text {wanted!r}')


def archive(check, path, entry, folder):
    with zipfile.ZipFile(path) as zipped:
        infos = {info.filename: info for info in zipped.infolist()}
        check.expect(zipped.namelist() == [e['name'] for e in entry['entries']], f'{path.name}: names {zipped.namelist()}')
        for wanted in entry['entries']:
            data = zipped.read(wanted['name'])
            if 'text' in wanted:
                check.expect(data.decode('utf-8') == wanted['text'], f'{path.name}/{wanted["name"]}: text')
            if 'same_as' in wanted:
                check.expect(data == (folder / wanted['same_as']).read_bytes(), f'{path.name}/{wanted["name"]}: bytes')
            if 'sha256_of' in wanted:
                digest = hashlib.sha256((folder / wanted['sha256_of']).read_bytes()).hexdigest()
                check.expect(hashlib.sha256(data).hexdigest() == digest, f'{path.name}/{wanted["name"]}: sha256')
        for name in entry['stored']:
            check.expect(infos[name].compress_type == zipfile.ZIP_STORED, f'{path.name}/{name}: stored')
        for name in entry['deflated']:
            info = infos[name]
            check.expect(info.compress_type == zipfile.ZIP_DEFLATED and info.compress_size < info.file_size,
                         f'{path.name}/{name}: deflated')


def main():
    folder = Path(sys.argv[1]).resolve()
    manifest = json.loads((folder / 'manifest.json').read_text())
    check = Checks()
    for entry in manifest['files']:
        path = folder / entry['path']
        try:
            if entry['format'] != 'pdf':
                package(check, path, entry)
            {'docx': word, 'xlsx': spreadsheet, 'pptx': presentation, 'pdf': pdf}.get(entry['format'], lambda *a: None)(check, path, entry)
            if entry['format'] == 'zip':
                archive(check, path, entry, folder)
        except Exception as error:  # a file the library cannot open at all
            check.expect(False, f'{path.name}: cannot be opened: {type(error).__name__}: {error}')
    for failure in check.failures:
        print('FAIL: ' + failure)
    print(json.dumps({'checks': check.count, 'failures': len(check.failures), 'files': len(manifest['files'])}))
    raise SystemExit(1 if check.failures else 0)


if __name__ == '__main__':
    main()
