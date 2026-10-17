#!/usr/bin/env python3
"""Catalog original SubRip cues and curate source-bound native review bundles."""
from __future__ import annotations
import argparse
import copy
from pathlib import Path
import re
import subprocess
import sys
import review_mbox as common

MAX_BYTES = 2 * 1024 * 1024
MAX_CUES = 10000
MAX_SELECTED = 100
MAX_IMPORTED = 8 * 1024 * 1024
STAMP = r'([0-9]{2,}):([0-5][0-9]):([0-5][0-9]),([0-9]{3})'
TIMING = re.compile('^' + STAMP + r' --> ' + STAMP + '$')


def parse_srt(raw):
    common.require(0 < len(raw) <= MAX_BYTES, 'SRT must contain 1 byte through 2 MiB')
    common.require(b'\x00' not in raw, 'NUL is unsupported')
    common.require(b'\r' not in raw.replace(b'\r\n', b''), 'bare CR line endings are unsupported')
    raw.decode('utf-8-sig', errors='strict')
    offset = 3 if raw.startswith(b'\xef\xbb\xbf') else 0
    # Byte spans exclude separator blank lines, preserving original cue bytes.
    chunks = []
    start = offset
    for separator in re.finditer(rb'\r?\n[ \t]*\r?\n(?:[ \t]*\r?\n)*', raw[offset:]):
        end = offset + separator.start()
        chunks.append((start, end))
        start = offset + separator.end()
    if start < len(raw):
        chunks.append((start, len(raw)))
    cues = []
    for start, end in chunks:
        block = raw[start:end]
        if not block.strip():
            continue
        lines = block.decode('utf-8').splitlines()
        common.require(len(lines) >= 3 and re.fullmatch(r'[0-9]{1,12}', lines[0]) is not None,
                       'each SRT cue needs a numeric identifier, timing line and text')
        match = TIMING.fullmatch(lines[1])
        common.require(match is not None, 'expected HH:MM:SS,mmm --> HH:MM:SS,mmm without settings')
        values = [int(x) for x in match.groups()]
        begin, finish = [((v[0]*60+v[1])*60+v[2])*1000+v[3] for v in (values[:4], values[4:])]
        common.require(finish > begin, 'cue end must follow start')
        common.require(not cues or begin >= cues[-1]['start_ms'], 'cue starts must be nondecreasing')
        text = '\n'.join(lines[2:])
        common.require(bool(text.strip()), 'cue text is empty')
        ordinal = len(cues) + 1
        cues.append({'ordinal': ordinal, 'identifier': lines[0], 'cue_locator': 'srt/cue/' + str(ordinal),
                     'source_start_byte': start, 'source_end_byte': end, 'cue_digest': common.digest(block),
                     'start_ms': begin, 'end_ms': finish, 'timing': lines[1], 'text': text})
        common.require(len(cues) <= MAX_CUES, 'SRT exceeds 10000 cues')
    common.require(bool(cues), 'SRT has no cues')
    return {'format': 'moonchat.srt-catalog.v1', 'source_digest': common.digest(raw),
            'media_type': 'application/x-subrip', 'byte_count': len(raw), 'cue_count': len(cues), 'cues': cues,
            'interpretation': 'Original UTF-8 SubRip snapshot; ordinal locators disambiguate supplied identifiers. Text and markup are quoted evidence, not verified speaker identity or approval.'}


def search_cues(catalog, query='', start_ms=None, end_ms=None, context=0):
    """Discover original cues; neighbors are context, never implicit selections."""
    common.require(isinstance(query, str) and len(query) <= 1000, 'query must be at most 1000 characters')
    common.require(type(context) is int and 0 <= context <= 5, 'context must be 0..5 cues')
    for value in (start_ms, end_ms):
        common.require(value is None or (type(value) is int and value >= 0), 'time bounds must be nonnegative milliseconds')
    common.require(bool(query) or start_ms is not None or end_ms is not None, 'supply text or a time bound')
    common.require(start_ms is None or end_ms is None or start_ms < end_ms, 'time window must have positive duration')
    needle = query.casefold()
    matches = [cue for cue in catalog['cues'] if needle in cue['text'].casefold()
               and (start_ms is None or cue['end_ms'] > start_ms)
               and (end_ms is None or cue['start_ms'] < end_ms)]
    visible = set()
    for cue in matches:
        visible.update(range(max(1, cue['ordinal']-context), min(catalog['cue_count'], cue['ordinal']+context)+1))
    return {'format': 'moonchat.srt-search.v1', 'source_digest': catalog['source_digest'],
            'query': query, 'start_ms': start_ms, 'end_ms': end_ms, 'context': context,
            'matched_ordinals': [cue['ordinal'] for cue in matches], 'match_count': len(matches),
            'cues': [cue for cue in catalog['cues'] if cue['ordinal'] in visible],
            'meaning': 'Casefolded literal text AND half-open time overlap. Neighbor cues are context only; explicitly select ordinals for review.'}


def import_cues(agenda, plan, catalog):
    common.require(isinstance(agenda, dict), 'agenda must be an object')
    common.check_shape({k: v for k, v in agenda.items() if k != 'source_digest_constraint'})
    common.require(isinstance(plan, dict) and set(plan) == {'format', 'source_digest', 'items'} and
                   plan['format'] == 'moonchat.srt-review.v1', 'selection requires exact moonchat.srt-review.v1 fields')
    common.require(plan['source_digest'] == catalog['source_digest'], 'SRT source digest differs; recatalog original bytes')
    common.require(agenda.get('source_digest_constraint', '') in ('', catalog['source_digest']), 'agenda source digest differs')
    items = plan['items']
    common.require(isinstance(items, list) and 1 <= len(items) <= MAX_SELECTED, 'select 1–100 review items')
    candidate = copy.deepcopy(agenda)
    candidate['source_digest_constraint'] = catalog['source_digest']
    total = 0
    for item in items:
        common.require(isinstance(item, dict) and set(item) == {'cues', 'key', 'kind', 'author', 'note', 'decisions'},
                       'each item needs cues, key, kind, author, note and decisions')
        ordinals = item['cues']
        common.require(isinstance(ordinals, list) and 1 <= len(ordinals) <= MAX_SELECTED and
                       all(type(i) is int and 1 <= i <= len(catalog['cues']) for i in ordinals), 'select 1–100 existing cue ordinals')
        common.require(len(ordinals) == len(set(ordinals)), 'duplicate selected cue')
        common.require(isinstance(item['note'], str) and bool(item['note'].strip()), 'write an explicit curator note')
        evidence = {'source_ref': agenda['source_artifact_ref'], 'source_digest': catalog['source_digest'],
                    'media_type': catalog['media_type'], 'cues': [catalog['cues'][i-1] for i in sorted(ordinals)]}
        body = item['note'] + '\n\nSelected original SRT evidence (quoted text; no speaker identity or approval verification):\n' + common.json_text(evidence)
        total += len(body.encode('utf-8'))
        common.require(total <= MAX_IMPORTED, 'selected SRT evidence exceeds 8 MiB')
        candidate['items'].append({'key': item['key'], 'kind': item['kind'], 'author': item['author'],
                                   'body': body, 'evidence_refs': [agenda['source_artifact_ref']],
                                   'decisions': copy.deepcopy(item['decisions'])})
    common.check_shape({k: v for k, v in candidate.items() if k != 'source_digest_constraint'})
    return candidate


def read_bounded(path):
    with Path(path).open('rb') as stream:
        raw = stream.read(MAX_BYTES + 1)
    common.require(len(raw) <= MAX_BYTES, 'input exceeds 2 MiB')
    return raw


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='mode', required=True)
    command = sub.add_parser('catalog')
    command.add_argument('transcript', type=Path)
    command = sub.add_parser('search', help='find original cues by literal text and/or time overlap')
    command.add_argument('transcript', type=Path)
    command.add_argument('--text', default='')
    command.add_argument('--start-ms', type=int)
    command.add_argument('--end-ms', type=int)
    command.add_argument('--context', type=int, default=0)
    for mode in ('agenda', 'preview', 'bundle'):
        command = sub.add_parser(mode)
        command.add_argument('agenda', type=Path)
        command.add_argument('transcript', type=Path)
        command.add_argument('selection', type=Path)
        command.add_argument('--composer', type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        raw = read_bounded(args.transcript)
        catalog = parse_srt(raw)
        if args.mode == 'catalog':
            output = common.json_text(catalog)
        elif args.mode == 'search':
            output = common.json_text(search_cues(catalog, args.text, args.start_ms, args.end_ms, args.context))
        else:
            candidate = import_cues(common.load_json(read_bounded(args.agenda)),
                                    common.load_json(read_bounded(args.selection)), catalog)
            # Shared native composer reads these exact original bytes, not a converted VTT.
            output = common.compile_candidate(candidate, raw, args.composer, args.mode)
        sys.stdout.write(output)
        return 0
    except (common.IntakeError, OSError, UnicodeError, RecursionError, subprocess.TimeoutExpired, ValueError) as error:
        print('review-srt: ' + str(error), file=sys.stderr)
        return 2


if __name__ == '__main__':
    raise SystemExit(main())
