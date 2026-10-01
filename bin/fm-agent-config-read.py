#!/usr/bin/env python3
"""Parse config/agent.md's YAML frontmatter.

config/agent.md's frontmatter is small and fixed-shape (flat scalar keys plus
one two-level `vault:` map, written by the onboarding skill from
templates/agent.md), so this is a bounded regex scan rather than a real YAML
parser or a new dependency - python3 is already used elsewhere in bin/.

Usage: fm-agent-config-read.py <path-to-agent.md>

Prints one "key<TAB>value" line per recognized field actually present in the
frontmatter: name, user_name, address, vault_root, vault_entry, vault_queue.
A field absent from the file is omitted entirely (never printed with an empty
value), so a caller can tell "not set" apart from "set to an empty string".
Quoted values keep embedded spaces (e.g. a vault root under "My Vault").

Exits 0 with no output when the file is absent, unreadable, or its
frontmatter can't be located - absence is meaningful upstream (AGENTS.md: load
onboarding) and is the caller's to report, not this script's to fail on.
Exits 1 only for a real argument-count error.
"""
import re
import sys

_KEY_RE = re.compile(r'^([A-Za-z_][A-Za-z0-9_]*):\s*(.*)$')
_TOP_FIELDS = ('name', 'user_name', 'address')
_VAULT_FIELDS = ('root', 'entry', 'queue')


def _unquote(raw):
    v = raw.strip()
    if v and v[0] in ('"', "'"):
        end = v.find(v[0], 1)
        if end != -1:
            return v[1:end]
    # An unquoted scalar may carry a trailing "# comment".
    return re.split(r'\s+#', v, 1)[0].strip()


def _parse_frontmatter(text):
    lines = text.splitlines()
    if not lines or lines[0].strip() != '---':
        return {}
    end = None
    for i in range(1, len(lines)):
        if lines[i].strip() == '---':
            end = i
            break
    if end is None:
        return {}

    out = {}
    in_vault = False
    for raw in lines[1:end]:
        if not raw.strip() or raw.lstrip().startswith('#'):
            continue
        indent = len(raw) - len(raw.lstrip(' '))
        m = _KEY_RE.match(raw.strip())
        if not m:
            continue
        key, val = m.group(1), m.group(2)
        if indent == 0:
            if key == 'vault':
                in_vault = True
                continue
            in_vault = False
            if key in _TOP_FIELDS:
                out[key] = _unquote(val)
        elif in_vault and key in _VAULT_FIELDS:
            out['vault_' + key] = _unquote(val)
    return out


def main(argv):
    if len(argv) != 2:
        print('usage: fm-agent-config-read.py <path>', file=sys.stderr)
        return 1
    try:
        with open(argv[1], 'r', encoding='utf-8') as f:
            text = f.read()
    except OSError:
        return 0

    fields = _parse_frontmatter(text)
    for key in ('name', 'user_name', 'address', 'vault_root', 'vault_entry', 'vault_queue'):
        if key in fields:
            print('{}\t{}'.format(key, fields[key]))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
