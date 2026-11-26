#!/usr/bin/env python3
"""Check actual DEX class definitions, not descriptor references, before device install."""
import argparse
import struct
import zipfile

REQUIRED = {
    'com.wangzan101.mika.MikaApp',
    'com.wangzan101.mika.ui.MainActivity',
    'com.wangzan101.mika.woowbot.BotServiceActivity',
    'com.wangzan101.mika.woowbot.BotServicesActivity',
    'com.wangzan101.mika.woowbot.push.BotPushSettingsActivity',
    'com.wangzan101.mika.woowbot.push.BotFirebaseMessagingService',
}


def class_definitions(data):
    if not data.startswith(b'dex\n'):
        raise ValueError('Unsupported DEX format')
    def uint(offset):
        return struct.unpack_from('<I', data, offset)[0]
    string_table, type_table = uint(60), uint(68)
    count, class_table = uint(96), uint(100)
    for index in range(count):
        type_index = uint(class_table + index * 32)
        string_index = uint(type_table + type_index * 4)
        offset = uint(string_table + string_index * 4)
        while data[offset] & 128:
            offset += 1
        offset += 1
        descriptor = data[offset:data.index(0, offset)].decode('utf-8', errors='replace')
        yield descriptor.removeprefix('L').removesuffix(';').replace('/', '.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apk')
    args = parser.parse_args()
    found = set()
    with zipfile.ZipFile(args.apk) as apk:
        for name in apk.namelist():
            if name.endswith('.dex'):
                found.update(class_definitions(apk.read(name)))
    missing = REQUIRED - found
    if missing:
        parser.exit(1, 'Missing APK class definitions: ' + ', '.join(sorted(missing)) + '\n')
    print(f'APK class check passed: {len(REQUIRED)} required definitions; {len(found)} total classes')


if __name__ == '__main__':
    main()
