#!/usr/bin/env python3
"""Turn selected local WebVTT cues into the existing MoonChat agenda/composer flow."""
import argparse
import hashlib
import html
import json
from pathlib import Path
import re
import subprocess
import sys

MAX_BYTES = 2 * 1024 * 1024
STAMP = re.compile(r'(?:(\d{2,}):)?([0-5]\d):([0-5]\d)\.(\d{3})\Z')

def timestamp(value):
    match = STAMP.fullmatch(value)
    if not match:
        raise ValueError('Invalid WebVTT timestamp: ' + value)
    h, m, s, ms = match.groups()
    return ((int(h or 0) * 60 + int(m)) * 60 + int(s)) * 1000 + int(ms)

def parse_vtt(raw):
    if len(raw) > MAX_BYTES:
        raise ValueError('Transcript exceeds 2 MiB')
    text = raw.decode('utf-8-sig', errors='strict').replace('\r\n', '\n').replace('\r', '\n')
    if '\x00' in text:
        raise ValueError('NUL is not transcript text')
    blocks = re.split(r'\n[ \t]*\n', text.rstrip('\n'))
    header = blocks.pop(0).splitlines() if blocks else []
    if not header or not re.fullmatch(r'WEBVTT(?:[ \t].*)?', header[0]) or '-->' in header[0]:
        raise ValueError('Expected a WEBVTT header followed by a blank line')
    if any('-->' in line for line in header[1:]):
        raise ValueError('Separate the WEBVTT header from cues with a blank line')
    cues = []
    for block in blocks:
        lines = block.splitlines()
        if not lines:
            continue
        if re.match(r'^NOTE(?:[ \t]|$)', lines[0]) or lines[0] in ('STYLE', 'REGION'):
            continue
        cue_id = ''
        if '-->' not in lines[0]:
            cue_id = lines.pop(0)
        if not lines or '-->' not in lines[0]:
            raise ValueError('Cue has no timing line')
        parts = lines.pop(0).split()
        if len(parts) < 3 or parts[1] != '-->':
            raise ValueError('Malformed cue timing')
        start, end = timestamp(parts[0]), timestamp(parts[2])
        if end <= start:
            raise ValueError('Cue end must follow its start')
        if cues and start < cues[-1]['start_ms']:
            raise ValueError('Cue start times must be nondecreasing')
        if not lines or not '\n'.join(lines).strip():
            raise ValueError('Cue text is empty')
        cues.append(dict(cue=len(cues) + 1, identifier=cue_id, start=parts[0], end=parts[2],
                         start_ms=start, end_ms=end, text='\n'.join(lines)))
        if len(cues) > 10000:
            raise ValueError('Transcript exceeds 10000 cues')
    if not cues:
        raise ValueError('Transcript has no cues')
    return cues

def make_agenda(selection, cues):
    if not isinstance(selection, dict):
        raise ValueError('Selection must be an object')
    fields = ('review_id', 'conversation_id', 'source_artifact_ref', 'source_revision_id', 'recorded_at', 'participants')
    if any(k not in selection for k in fields):
        raise ValueError('Selection is missing agenda metadata or participants')
    agenda = {key: selection[key] for key in fields}
    items = selection.get('items')
    if not isinstance(items, list) or not 1 <= len(items) <= 256:
        raise ValueError('Select between 1 and 256 review items')
    agenda['items'] = []
    keys = set()
    for item in items:
        if not isinstance(item, dict) or not all(k in item for k in ('key','kind','author','body','decisions','cues')):
            raise ValueError('Each item needs key, kind, author, body, decisions and cues')
        if not isinstance(item['key'], str) or not re.fullmatch(r'[A-Za-z0-9_.-]+', item['key']) or item['key'] in keys:
            raise ValueError('Item keys must be unique safe identifiers')
        keys.add(item['key'])
        if item['kind'] not in ('proposal','question','objection') or not isinstance(item['body'],str) or not item['body'].strip():
            raise ValueError('Write an explicit review kind and body')
        indexes = item['cues']
        if not isinstance(indexes,list) or not 1 <= len(indexes) <= 256 or any(type(i) is not int or not 1 <= i <= len(cues) for i in indexes):
            raise ValueError('Cue selections must name existing one-based cue numbers')
        if len(indexes) != len(set(indexes)):
            raise ValueError('Duplicate selected cue')
        excerpts = []
        for i in sorted(indexes):
            cue = cues[i - 1]
            excerpts.append(f"Cue {i} [{cue['start']} --> {cue['end']}]\n{cue['text']}")
        entry = {key:item[key] for key in ('key','kind','author','decisions')}
        entry['body'] = item['body'] + '\n\nSelected transcript evidence (recorded text; no speaker identity verification):\n' + '\n\n'.join(excerpts)
        entry['evidence_refs'] = [selection['source_artifact_ref']]
        agenda['items'].append(entry)
    return agenda

def search_cues(raw, query='', voice=None, start_ms=None, end_ms=None, context=0):
    """Discover cues by quoted voice label, words and time; never select context."""
    if not isinstance(query, str) or len(query) > 1000:
        raise ValueError('Text query must have at most 1000 characters')
    if voice is not None and (not isinstance(voice, str) or not voice or len(voice) > 1000):
        raise ValueError('Voice must be a nonempty label of at most 1000 characters')
    if type(context) is not int or not 0 <= context <= 5:
        raise ValueError('Context must be 0..5 cues')
    for value in (start_ms, end_ms):
        if value is not None and (type(value) is not int or value < 0):
            raise ValueError('Time bounds must be nonnegative milliseconds')
    if start_ms is not None and end_ms is not None and start_ms >= end_ms:
        raise ValueError('Time window must have positive duration')
    if not query and voice is None and start_ms is None and end_ms is None:
        raise ValueError('Supply text, voice or a time bound')
    cues = parse_vtt(raw)
    matches, visible, labels = [], set(), {}
    for cue in cues:
        # Voice annotations are supplied transcript labels, never authenticated people.
        voices = sorted(set(html.unescape(v.strip()) for v in
                     re.findall(r'<v(?:\.[^\s>]+)*[ \t]+([^>]+)>', cue['text'])))
        labels[cue['cue']] = voices
        plain = html.unescape(re.sub(r'<[^>]*>', '', cue['text']))
        if (query.casefold() in plain.casefold() and (voice is None or voice in voices)
                and (start_ms is None or cue['end_ms'] > start_ms)
                and (end_ms is None or cue['start_ms'] < end_ms)):
            matches.append(cue['cue'])
            visible.update(range(max(1, cue['cue']-context), min(len(cues), cue['cue']+context)+1))
    return {'format': 'moonchat.vtt-search.v1', 'source_digest': 'sha256:'+hashlib.sha256(raw).hexdigest(),
            'query': query, 'voice': voice, 'start_ms': start_ms, 'end_ms': end_ms,
            'context': context, 'matched_cues': matches, 'match_count': len(matches),
            'cues': [cue | {'voice_labels': labels[cue['cue']], 'matched': cue['cue'] in matches}
                     for cue in cues if cue['cue'] in visible],
            'meaning': 'Literal decoded text and exact declared voice labels; labels are unverified. Only matched_cues are matches; neighbors require explicit selection.'}

def read_bounded(path):
    if path.stat().st_size > MAX_BYTES:
        raise ValueError('Input exceeds 2 MiB')
    with path.open('rb') as stream:
        raw = stream.read(MAX_BYTES + 1)
    if len(raw) > MAX_BYTES:
        raise ValueError('Input grew beyond 2 MiB')
    return raw

def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=('cues','search','agenda','bundle','preview'))
    parser.add_argument('transcript')
    parser.add_argument('selection', nargs='?')
    parser.add_argument('--composer', help='Path to existing native review_compose executable; required for bundle/preview')
    parser.add_argument('--text', default='')
    parser.add_argument('--voice', help='Exact declared WebVTT voice label, not verified identity')
    parser.add_argument('--start-ms', type=int)
    parser.add_argument('--end-ms', type=int)
    parser.add_argument('--context', type=int, default=0)
    args = parser.parse_args(argv)
    transcript = Path(args.transcript).resolve()
    raw = read_bounded(transcript)
    if args.mode == 'search':
        print(json.dumps(search_cues(raw, args.text, args.voice, args.start_ms, args.end_ms, args.context), ensure_ascii=False, indent=2)); return
    cues = parse_vtt(raw)
    if args.mode == 'cues':
        print(json.dumps(cues,ensure_ascii=False,indent=2)); return
    if not args.selection:
        parser.error('Selection JSON is required')
    selection_path = Path(args.selection)
    agenda = make_agenda(json.loads(read_bounded(selection_path).decode('utf-8')), cues)
    if args.mode == 'agenda':
        print(json.dumps(agenda,ensure_ascii=False,indent=2)); return
    if not args.composer:
        parser.error('--composer is required; build cmd/review_compose with the project toolchain')
    # Temporary agenda is local authoring only; composer receives exact original VTT bytes.
    import tempfile
    with tempfile.TemporaryDirectory(prefix='moonchat-vtt-') as directory:
        agenda_path = Path(directory)/'agenda.json'
        agenda_path.write_text(json.dumps(agenda,ensure_ascii=False),encoding='utf-8')
        source_path = Path(directory)/'source.vtt'
        source_path.write_bytes(raw)
        result = subprocess.run([str(Path(args.composer).resolve()),args.mode,str(agenda_path),str(source_path)],
                                capture_output=True,check=False)
        if result.returncode:
            raise ValueError('Composer rejected review: '+ result.stderr.decode('utf-8',errors='replace').strip())
        sys.stdout.buffer.write(result.stdout)

if __name__ == '__main__':
    try:
        main()
    except (ValueError,OSError,UnicodeError) as error:
        print('review-vtt: '+str(error),file=sys.stderr)
        sys.exit(2)
