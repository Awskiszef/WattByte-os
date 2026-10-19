#!/usr/bin/env python3
"""Adds keys to BOTH ARB files atomically (several people/agents may edit them).

Usage:  python3 tool/arb_add.py <<'JSON'
  {"en": {"key": "English text", "@key": {...optional metadata...}},
   "pl": {"key": "Polski tekst"}}
JSON

* Both locales must define the same non-metadata keys (the tool refuses otherwise).
* An existing key is only replaced when --replace is given.
* Runs `flutter gen-l10n` afterwards unless --no-gen is given.
"""
import collections
import fcntl
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
EN = os.path.join(ROOT, 'lib/l10n/app_en.arb')
PL = os.path.join(ROOT, 'lib/l10n/app_pl.arb')


def load(path):
    with open(path, encoding='utf-8') as f:
        return json.load(f, object_pairs_hook=collections.OrderedDict)


def dump(path, data):
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write('\n')


def main():
    replace = '--replace' in sys.argv
    gen = '--no-gen' not in sys.argv
    payload = json.load(sys.stdin)
    en_new, pl_new = payload.get('en', {}), payload.get('pl', {})
    plain_en = {k for k in en_new if not k.startswith('@')}
    plain_pl = {k for k in pl_new if not k.startswith('@')}
    if plain_en != plain_pl:
        sys.exit(f'en/pl keys differ: only en={sorted(plain_en - plain_pl)} only pl={sorted(plain_pl - plain_en)}')
    with open(os.path.join(HERE, '.arb.lock'), 'w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        en, pl = load(EN), load(PL)
        clashes = [k for k in plain_en if k in en and not replace]
        if clashes:
            sys.exit(f'keys already exist (use --replace): {clashes}')
        en.update(en_new)
        # Metadata (@key) belongs to the template (en) only; pl gets plain strings.
        pl.update({k: v for k, v in pl_new.items() if not k.startswith('@')})
        dump(EN, en)
        dump(PL, pl)
    print(f'added/updated {len(plain_en)} key(s)')
    if gen:
        subprocess.run(['flutter', 'gen-l10n'], cwd=ROOT, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


if __name__ == '__main__':
    main()
