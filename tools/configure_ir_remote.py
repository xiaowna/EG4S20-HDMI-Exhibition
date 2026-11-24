"""Compile actually captured NEC navigation and optional 3D keys into reset defaults."""
from pathlib import Path
import argparse, json, re

ROOT = Path(__file__).resolve().parents[1]
KEYS = ('right', 'ok', 'left', 'settings', 'home')
EXTRAS = ('back', 'zoom', 'model')
DIRECTIONS = ('up', 'down')


def parse_code(text):
    text = text.strip().replace('.', '').removeprefix('0x').removeprefix('0X')
    if not re.fullmatch(r'[0-9a-fA-F]{4}', text):
        raise ValueError('Each captured code must contain exactly four hex digits, e.g. 00.5A')
    return int(text[:2],16), int(text[2:],16)


def build_profile(codes, extra_codes=None, direction_codes=None):
    values = [parse_code(codes[n]) for n in KEYS]
    if len({a for a,c in values}) != 1:
        raise ValueError('All five keys must come from one NEC address')
    if len({c for a,c in values}) != 5:
        raise ValueError('Five different command bytes are required')
    profile = dict(schema_version=1, configured=True, protocol='standard_8_bit_address_NEC',
                address=f'{values[0][0]:02X}', **{k:f'{v[1]:02X}' for k,v in zip(KEYS,values)},
                status='Compiled from actual captured remote codes; no runtime learning required.')
    if extra_codes is not None:
        extra_values = [parse_code(extra_codes[n]) for n in EXTRAS]
        if any(a != values[0][0] for a,c in extra_values):
            raise ValueError('Extra keys must use the same NEC address')
        if len({c for a,c in values+extra_values}) != 8:
            raise ValueError('Eight different commands are required for navigation and 3D')
        profile.update(schema_version=2, extras={k:f'{v[1]:02X}' for k,v in zip(EXTRAS,extra_values)})
    if direction_codes is not None:
        direction_values = [parse_code(direction_codes[n]) for n in DIRECTIONS]
        if any(a != values[0][0] for a,c in direction_values):
            raise ValueError('Direction keys must use the same NEC address')
        previous = values + (extra_values if extra_codes is not None else [])
        if len({c for a,c in previous+direction_values}) != len(previous)+2:
            raise ValueError('Direction keys must have different commands from navigation and 3D')
        profile.update(schema_version=3, directions={k:f'{v[1]:02X}' for k,v in zip(DIRECTIONS,direction_values)})
    return profile


def packed(profile):
    return ''.join(profile[n] for n in ('address', *KEYS)).lower()


def apply_profile(root, profile):
    path = root/'rtl/hdmi_media_board_top.v'
    source = path.read_text(encoding='utf-8-sig')
    source, count = re.subn(r'parameter IR_FIXED_ENABLE=\d', 'parameter IR_FIXED_ENABLE=1', source)
    if count != 1:
        raise ValueError('Cannot locate the unique IR_FIXED_ENABLE parameter')
    source, count = re.subn(r"parameter \[47:0\] IR_FIXED_KEYS=48'h[0-9a-fA-F]{12}",
                           "parameter [47:0] IR_FIXED_KEYS=48'h"+packed(profile), source)
    if count != 1:
        raise ValueError('Cannot locate the unique IR_FIXED_KEYS parameter')
    extras = profile.get('extras',{})
    source, count = re.subn(r'parameter IR_EXTRA_ENABLE=\d',
                           'parameter IR_EXTRA_ENABLE='+str(int(bool(extras))),source)
    if count != 1:
        raise ValueError('Cannot locate the unique IR_EXTRA_ENABLE parameter')
    extra_word = ''.join(extras[n] for n in EXTRAS).lower() if extras else '000000'
    source, count = re.subn(r"parameter \[23:0\] IR_EXTRA_KEYS=24'h[0-9a-fA-F]{6}",
                           "parameter [23:0] IR_EXTRA_KEYS=24'h"+extra_word,source)
    if count != 1:
        raise ValueError('Cannot locate the unique IR_EXTRA_KEYS parameter')
    directions = profile.get('directions',{})
    source, count = re.subn(r'parameter IR_DIRECTION_ENABLE=\d',
                           'parameter IR_DIRECTION_ENABLE='+str(int(bool(directions))),source)
    if count != 1:
        raise ValueError('Cannot locate the unique IR_DIRECTION_ENABLE parameter')
    direction_word = ''.join(directions[n] for n in DIRECTIONS).lower() if directions else '0000'
    source, count = re.subn(r"parameter \[15:0\] IR_DIRECTION_KEYS=16'h[0-9a-fA-F]{4}",
                           "parameter [15:0] IR_DIRECTION_KEYS=16'h"+direction_word,source)
    if count != 1:
        raise ValueError('Cannot locate the unique IR_DIRECTION_KEYS parameter')
    path.write_text(source, encoding='utf-8')
    (root/'interfaces/infrared_fixed_keys.json').write_text(
        json.dumps(profile,ensure_ascii=False,indent=2)+'\n', encoding='utf-8')


def check_profile(root):
    profile = json.loads((root/'interfaces/infrared_fixed_keys.json').read_text(encoding='utf-8'))
    source = (root/'rtl/hdmi_media_board_top.v').read_text(encoding='utf-8-sig')
    enabled = int(re.search(r'parameter IR_FIXED_ENABLE=(\d)',source)[1])
    word = re.search(r"parameter \[47:0\] IR_FIXED_KEYS=48'h([0-9a-fA-F]{12})",source)[1].lower()
    if not profile['configured']:
        if enabled:
            raise ValueError('Uncaptured keys must not be presented as a configured fixed remote')
        return dict(status='awaiting_physical_key_capture', fixed_remote_ready=False)
    extras = profile.get('extras',{})
    directions = profile.get('directions',{})
    validated = build_profile({k:profile['address']+profile[k] for k in KEYS},
                             {k:profile['address']+extras[k] for k in EXTRAS} if extras else None,
                             {k:profile['address']+directions[k] for k in DIRECTIONS} if directions else None)
    if not enabled or word != packed(validated):
        raise ValueError('RTL reset defaults do not match the captured key manifest')
    extra_enabled = int(re.search(r'parameter IR_EXTRA_ENABLE=(\d)',source)[1])
    extra_word = re.search(r"IR_EXTRA_KEYS=24'h([0-9a-fA-F]{6})",source)[1].lower()
    expected_extra = ''.join(extras[n] for n in EXTRAS).lower() if extras else '000000'
    if extra_enabled != bool(extras) or extra_word != expected_extra:
        raise ValueError('RTL extra keys do not match the captured key manifest')
    direction_enabled = int(re.search(r'parameter IR_DIRECTION_ENABLE=(\d)',source)[1])
    direction_word = re.search(r"IR_DIRECTION_KEYS=16'h([0-9a-fA-F]{4})",source)[1].lower()
    expected_direction = ''.join(directions[n] for n in DIRECTIONS).lower() if directions else '0000'
    if direction_enabled != bool(directions) or direction_word != expected_direction:
        raise ValueError('RTL direction keys do not match the captured key manifest')
    return dict(status='passed',fixed_remote_ready=True,address=profile['address'],
                commands={k:profile[k] for k in KEYS}, extras=extras, directions=directions)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root',type=Path,default=ROOT)
    parser.add_argument('--check',action='store_true')
    for key in KEYS:
        parser.add_argument('--'+key)
    for key in EXTRAS:
        parser.add_argument('--'+key.replace('_','-'))
    for key in DIRECTIONS:
        parser.add_argument('--'+key)
    args = parser.parse_args()
    try:
        if not args.check:
            values = {k:getattr(args,k) for k in KEYS}
            if not all(values.values()):
                parser.error('Provide --right, --ok, --left, --settings and --home, or use --check')
            extras = {k:getattr(args,k) for k in EXTRAS}
            if any(extras.values()) and not all(extras.values()):
                parser.error('Provide all three of --back, --zoom and --model')
            directions = {k:getattr(args,k) for k in DIRECTIONS}
            if any(directions.values()) and not all(directions.values()):
                parser.error('Provide both --up and --down')
            apply_profile(args.root,build_profile(values,extras if all(extras.values()) else None,
                                                 directions if all(directions.values()) else None))
        print(json.dumps(check_profile(args.root),ensure_ascii=False,indent=2))
    except (OSError,ValueError,KeyError) as exc:
        parser.exit(1,str(exc)+'\n')


if __name__ == '__main__':
    main()
