"""render_brand_icon.py: the SVG keeps the Android geometry, the PNG is opaque and reproducible."""
import hashlib
import json
from pathlib import Path
import shutil
import struct
import unittest
import zlib

import render_brand_icon as icon

ROOT = Path(__file__).resolve().parents[1]
VECTOR = b'''<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="108dp" android:height="108dp"
    android:viewportWidth="108" android:viewportHeight="108">
<group android:translateX="13.27" android:translateY="25.36" android:scaleX="0.07955" android:scaleY="0.07955">
<path android:fillColor="#FFFFFFFF" android:pathData="M 1 1 A 2 2 0 1 0 5 1 Z" />
<path android:fillColor="#FFFFFFFF" android:pathData="M10,10l-2.5-1.5c0,0 1,1 2,2Z" />
</group></vector>'''


def png_with_filters(width, rows, channels):
    """A PNG whose rows use filters 0-4 in turn, to exercise the decoder."""
    color = 2 if channels == 3 else 6
    raw, previous = bytearray(), bytes(width * channels)
    for y, row in enumerate(rows):
        kind = y % 5
        encoded = bytearray()
        for i, value in enumerate(row):
            left = row[i - channels] if i >= channels else 0
            up = previous[i]
            upper_left = previous[i - channels] if i >= channels else 0
            predictor = [0, left, up, (left + up) >> 1, icon._paeth(left, up, upper_left)][kind]
            encoded.append((value - predictor) & 0xFF)
        raw += bytes([kind]) + encoded
        previous = row

    def chunk(kind, body):
        return struct.pack('>I', len(body)) + kind + body + struct.pack('>I', zlib.crc32(kind + body))
    return (icon.PNG_SIGNATURE + chunk(b'IHDR', struct.pack('>IIBBBBB', width, len(rows), 8, color, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(bytes(raw))) + chunk(b'IEND', b''))


class SvgTests(unittest.TestCase):
    def test_android_geometry_is_kept(self):
        svg = icon.vector_to_svg(VECTOR, '#4d4d4d', '#FFFFFF', 1024, 'note').decode()
        self.assertIn('viewBox="0 0 108 108"', svg)
        self.assertIn('<rect width="108" height="108" fill="#4D4D4D"/>', svg)
        self.assertIn('<g transform="translate(13.27 25.36) scale(0.07955 0.07955)">', svg)
        self.assertIn('<path fill="#FFFFFF" d="M 1 1 A 2 2 0 1 0 5 1 Z"/>', svg)
        self.assertIn('d="M10,10l-2.5-1.5c0,0 1,1 2,2Z"', svg)

    def test_unexpected_vectors_are_rejected(self):
        for bad in [VECTOR.replace(b'#FFFFFFFF', b'#FF6183FC'), VECTOR.replace(b'#FFFFFFFF', b'#80FFFFFF'),
                    VECTOR.replace(b'android:scaleX', b'android:rotation="10" android:scaleX'),
                    VECTOR.replace(b'android:fillColor="#FFFFFFFF" android:pathData', b'android:strokeColor="#FFFFFFFF" android:pathData')]:
            with self.subTest(bad=bad[200:320]), self.assertRaises(icon.IconError):
                icon.vector_to_svg(bad, '#4D4D4D', '#FFFFFF', 1024)


class PngTests(unittest.TestCase):
    def test_decoder_handles_every_filter(self):
        rows = [bytes((x * 37 + y * 11 + c * 5) % 256 for x in range(7) for c in range(4)) for y in range(10)]
        width, height, channels, decoded = icon.decode_png(png_with_filters(7, rows, 4))
        self.assertEqual((width, height, channels), (7, 10, 4))
        self.assertEqual(decoded, rows)

    def test_alpha_is_removed_only_when_every_pixel_is_opaque(self):
        opaque = [bytes([1, 2, 3, 255, 4, 5, 6, 255])]
        self.assertEqual(icon.opaque_rgb(opaque, 4), [bytes([1, 2, 3, 4, 5, 6])])
        with self.assertRaises(icon.IconError):
            icon.opaque_rgb([bytes([1, 2, 3, 254, 4, 5, 6, 255])], 4)

    def test_encoder_is_deterministic_rgb_with_srgb(self):
        rows = [bytes([77, 77, 77] * 4), bytes([255, 255, 255] * 4)]
        first, second = icon.encode_png(4, 2, rows), icon.encode_png(4, 2, rows)
        self.assertEqual(first, second)
        kinds = [kind for kind, _ in icon._chunks(first)]
        self.assertEqual(kinds, [b'IHDR', b'sRGB', b'IDAT', b'IEND'])
        self.assertEqual(icon.decode_png(first), (4, 2, 3, rows))


class CommittedIconTests(unittest.TestCase):
    brand_dir = ROOT / 'brands' / 'apporo'

    def test_committed_files_match_their_provenance(self):
        brand = json.loads((self.brand_dir / 'brand.json').read_text(encoding='utf-8'))['icon']
        source = json.loads((self.brand_dir / brand['provenance']).read_text(encoding='utf-8'))
        png = (self.brand_dir / brand['png']).read_bytes()
        svg = (self.brand_dir / brand['svg']).read_bytes()
        vector = (self.brand_dir / brand['vector']).read_bytes()
        self.assertEqual(hashlib.sha256(png).hexdigest(), source['png_sha256'])
        self.assertEqual(hashlib.sha256(svg).hexdigest(), source['svg_sha256'])
        self.assertEqual(hashlib.sha256(vector).hexdigest(), source['sha256'])
        self.assertEqual(source['sha256'], brand['source']['sha256'])
        self.assertEqual(icon.vector_to_svg(vector, brand['background'], brand['foreground'], brand['size'],
                                            svg.decode().splitlines()[1][5:-4]), svg)
        width, height, channels, rows = icon.decode_png(png)
        self.assertEqual((width, height, channels), (1024, 1024, 3), 'App Store icons are opaque 1024px squares')
        self.assertEqual(rows[0][:3], bytes([0x4D, 0x4D, 0x4D]))
        # The mark's centre dot: (512, 407.61) in the vector, at pixel (512, 548).
        self.assertEqual(rows[548][512 * 3:513 * 3], bytes([255, 255, 255]))

    @unittest.skipUnless(shutil.which('rsvg-convert'), 'rsvg-convert (librsvg) is not installed')
    def test_a_fresh_render_has_the_same_pixels(self):
        svg, png, _ = icon.render(self.brand_dir, shutil.which('rsvg-convert'))
        committed = json.loads((self.brand_dir / 'brand.json').read_text(encoding='utf-8'))['icon']
        self.assertEqual(svg, (self.brand_dir / committed['svg']).read_bytes())
        self.assertEqual(icon.decode_png(png)[3], icon.decode_png((self.brand_dir / committed['png']).read_bytes())[3])


if __name__ == '__main__':
    unittest.main()
