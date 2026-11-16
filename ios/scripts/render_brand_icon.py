#!/usr/bin/env python3
"""Render a brand's iOS app icon from its pinned Android launcher vector.

Like scripts/render_app_icon.swift did for the WOOW icon: the Android vector's
viewport, group transform and paths are kept unchanged (no new logo is drawn),
over the adaptive icon's background colour, as an opaque 1024-pixel PNG.

    python3 scripts/render_brand_icon.py apporo           # writes icon/AppIcon.svg, AppIcon.png, SOURCE.json
    python3 scripts/render_brand_icon.py apporo --check   # re-renders and compares the committed pixels

Uses only local tools: rsvg-convert (librsvg) draws the SVG, and Python removes
the alpha channel after checking that every pixel is opaque (App Store icons
must have none). The PNG is written deterministically (sRGB chunk, one IDAT).
"""
import argparse
import hashlib
import json
import shutil
import struct
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ElementTree
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ANDROID = '{http://schemas.android.com/apk/res/android}'
PNG_SIGNATURE = b'\x89PNG\r\n\x1a\n'


class IconError(Exception):
    pass


def _number(text):
    """The attribute as written, so the geometry is copied exactly."""
    float(text)
    return text.strip()


def _android_color(text):
    value = text.strip().lstrip('#').upper()
    if len(value) == 8:
        if value[:2] != 'FF':
            raise IconError('translucent fill colours are not supported: #' + value)
        value = value[2:]
    if len(value) != 6 or any(c not in '0123456789ABCDEF' for c in value):
        raise IconError('unsupported colour: ' + text)
    return '#' + value


def vector_to_svg(xml_bytes, background, foreground, size, note=''):
    """The Android vector as an SVG, unchanged geometry, over an opaque background."""
    root = ElementTree.fromstring(xml_bytes)
    if root.tag != 'vector':
        raise IconError('not an Android vector drawable')
    width = root.get(ANDROID + 'viewportWidth')
    height = root.get(ANDROID + 'viewportHeight')
    if not width or not height:
        raise IconError('the vector has no viewport')
    groups = list(root)
    if len(groups) != 1 or groups[0].tag != 'group':
        raise IconError('expected exactly one group')
    group = groups[0]
    for unsupported in ('rotation', 'pivotX', 'pivotY'):
        if float(group.get(ANDROID + unsupported, '0')) != 0:
            raise IconError('group ' + unsupported + ' is not supported')
    tx, ty = (_number(group.get(ANDROID + k, '0')) for k in ('translateX', 'translateY'))
    sx, sy = (_number(group.get(ANDROID + k, '1')) for k in ('scaleX', 'scaleY'))
    paths = []
    for path in group:
        if path.tag != 'path' or set(path.attrib) - {ANDROID + 'fillColor', ANDROID + 'pathData', ANDROID + 'fillType'}:
            raise IconError('only filled paths are supported')
        fill = _android_color(path.get(ANDROID + 'fillColor', ''))
        if fill != foreground.upper():
            raise IconError('the vector colour %s is not the brand foreground %s' % (fill, foreground))
        rule = {'evenOdd': ' fill-rule="evenodd"', 'nonZero': '', None: ''}.get(path.get(ANDROID + 'fillType'))
        if rule is None:
            raise IconError('unknown fillType')
        data = ' '.join(path.get(ANDROID + 'pathData', '').split())
        if not data or any(c in data for c in '"<>&'):
            raise IconError('unexpected path data')
        paths.append('    <path fill="%s"%s d="%s"/>' % (fill, rule, data))
    if not paths:
        raise IconError('the vector has no paths')
    lines = ['<?xml version="1.0" encoding="UTF-8"?>']
    if note:
        lines.append('<!-- %s -->' % note.replace('--', '-'))
    lines += ['<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %s %s">'
              % (size, size, _number(width), _number(height)),
              '  <rect width="%s" height="%s" fill="%s"/>' % (_number(width), _number(height), background.upper()),
              '  <g transform="translate(%s %s) scale(%s %s)">' % (tx, ty, sx, sy)]
    lines += paths + ['  </g>', '</svg>', '']
    return '\n'.join(lines).encode('utf-8')


def _chunks(data):
    if not data.startswith(PNG_SIGNATURE):
        raise IconError('not a PNG')
    index = len(PNG_SIGNATURE)
    while index < len(data):
        length, = struct.unpack('>I', data[index:index + 4])
        kind = data[index + 4:index + 8]
        body = data[index + 8:index + 8 + length]
        if zlib.crc32(kind + body) != struct.unpack('>I', data[index + 8 + length:index + 12 + length])[0]:
            raise IconError('PNG checksum error')
        yield kind, body
        index += 12 + length


def _paeth(a, b, c):
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    return b if pb <= pc else c


def decode_png(data):
    """(width, height, channels, rows) for 8-bit RGB or RGBA, non-interlaced."""
    header, compressed = None, []
    for kind, body in _chunks(data):
        if kind == b'IHDR':
            header = struct.unpack('>IIBBBBB', body)
        elif kind == b'IDAT':
            compressed.append(body)
    if header is None:
        raise IconError('PNG without IHDR')
    width, height, depth, color, _, _, interlace = header
    if depth != 8 or color not in (2, 6) or interlace:
        raise IconError('only 8-bit non-interlaced RGB(A) PNGs are supported')
    channels = 3 if color == 2 else 4
    raw = zlib.decompress(b''.join(compressed))
    stride = width * channels
    if len(raw) != height * (stride + 1):
        raise IconError('PNG data size mismatch')
    rows, previous = [], bytearray(stride)
    for y in range(height):
        start = y * (stride + 1)
        kind, line = raw[start], bytearray(raw[start + 1:start + 1 + stride])
        if kind == 1:
            for i in range(channels, stride):
                line[i] = (line[i] + line[i - channels]) & 0xFF
        elif kind == 2:
            for i in range(stride):
                line[i] = (line[i] + previous[i]) & 0xFF
        elif kind == 3:
            for i in range(stride):
                left = line[i - channels] if i >= channels else 0
                line[i] = (line[i] + ((left + previous[i]) >> 1)) & 0xFF
        elif kind == 4:
            for i in range(stride):
                left = line[i - channels] if i >= channels else 0
                upper_left = previous[i - channels] if i >= channels else 0
                line[i] = (line[i] + _paeth(left, previous[i], upper_left)) & 0xFF
        elif kind != 0:
            raise IconError('unknown PNG filter')
        rows.append(bytes(line))
        previous = line
    return width, height, channels, rows


def opaque_rgb(rows, channels):
    """Drop alpha after checking that no pixel is translucent."""
    if channels == 3:
        return list(rows)
    result = []
    for row in rows:
        if row[3::4].count(255) != len(row) // 4:
            raise IconError('the rendered icon has translucent pixels')
        rgb = bytearray(len(row) // 4 * 3)
        rgb[0::3], rgb[1::3], rgb[2::3] = row[0::4], row[1::4], row[2::4]
        result.append(bytes(rgb))
    return result


def encode_png(width, height, rows):
    """An opaque 8-bit RGB PNG with an sRGB chunk; same input, same bytes."""
    def chunk(kind, body):
        return struct.pack('>I', len(body)) + kind + body + struct.pack('>I', zlib.crc32(kind + body))
    raw = b''.join(b'\x00' + row for row in rows)
    return (PNG_SIGNATURE + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0))
            + chunk(b'sRGB', b'\x00') + chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b''))


def rsvg_version(tool):
    output = subprocess.run([tool, '--version'], capture_output=True, text=True, check=True, timeout=30).stdout
    return output.splitlines()[0].strip()


def rasterize(svg, size, tool):
    with tempfile.TemporaryDirectory(prefix='brand-icon-') as folder:
        source, target = Path(folder) / 'icon.svg', Path(folder) / 'icon.png'
        source.write_bytes(svg)
        subprocess.run([tool, '--width', str(size), '--height', str(size), '--format', 'png',
                        '--output', str(target), str(source)], check=True, capture_output=True, timeout=120)
        return target.read_bytes()


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def render(brand_dir, tool):
    """(svg, png, provenance) for the brand's icon section."""
    brand = json.loads((brand_dir / 'brand.json').read_text(encoding='utf-8'))
    icon = brand['icon']
    vector = (brand_dir / icon['vector']).read_bytes()
    if sha256(vector) != icon['source']['sha256']:
        raise IconError('the pinned vector differs from icon.source.sha256')
    note = ('Generated by ios/scripts/render_brand_icon.py from %s (sha256 %s); do not edit by hand.'
            % (icon['source']['path'], icon['source']['sha256']))
    svg = vector_to_svg(vector, icon['background'], icon['foreground'], icon['size'], note)
    width, height, channels, rows = decode_png(rasterize(svg, icon['size'], tool))
    if (width, height) != (icon['size'], icon['size']):
        raise IconError('rendered %dx%d, expected %d' % (width, height, icon['size']))
    png = encode_png(width, height, opaque_rgb(rows, channels))
    provenance = dict(icon['source'])
    provenance.update({
        'background': icon['background'], 'foreground': icon['foreground'],
        'geometry': 'Original Android viewport/group/paths retained; opaque %dpx iOS render.' % icon['size'],
        'svg': Path(icon['svg']).name, 'svg_sha256': sha256(svg),
        'png': Path(icon['png']).name, 'png_sha256': sha256(png),
        'renderer': rsvg_version(tool) + ' via ios/scripts/render_brand_icon.py; alpha removed after an all-opaque check',
    })
    return svg, png, (json.dumps(provenance, ensure_ascii=False, indent=2) + '\n').encode('utf-8')


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('brand')
    parser.add_argument('--root', type=Path, default=ROOT)
    parser.add_argument('--check', action='store_true', help='compare a fresh render with the committed files')
    args = parser.parse_args(argv)
    tool = shutil.which('rsvg-convert')
    if not tool:
        print('render_brand_icon: rsvg-convert (librsvg) is required', file=sys.stderr)
        return 2
    brand_dir = args.root.resolve() / 'brands' / args.brand
    try:
        svg, png, provenance = render(brand_dir, tool)
    except (IconError, subprocess.CalledProcessError, KeyError, ValueError) as error:
        print('render_brand_icon: ' + str(error), file=sys.stderr)
        return 1
    icon = json.loads((brand_dir / 'brand.json').read_text(encoding='utf-8'))['icon']
    targets = {icon['svg']: svg, icon['png']: png, icon['provenance']: provenance}
    if args.check:
        committed = brand_dir / icon['png']
        same_svg = (brand_dir / icon['svg']).is_file() and (brand_dir / icon['svg']).read_bytes() == svg
        same_pixels = committed.is_file() and decode_png(committed.read_bytes())[3] == decode_png(png)[3]
        print('render_brand_icon: svg %s, pixels %s' % ('same' if same_svg else 'DIFFERENT',
                                                     'same' if same_pixels else 'DIFFERENT'))
        return 0 if same_svg and same_pixels else 1
    for relative, data in targets.items():
        (brand_dir / relative).write_bytes(data)
    print('render_brand_icon: wrote ' + ', '.join(sorted(targets)) + ' (png sha256 ' + sha256(png) + ')')
    return 0


if __name__ == '__main__':
    sys.exit(main())
