"""Actual CLI fixture checks; no network, authentication or receipt delivery."""
import copy
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile

exe, source = map(Path, sys.argv[1:])
bundle = source / 'examples/review-agenda/review.json'
artifact = source / 'examples/review-agenda/source.md'
before = [hashlib.sha256(p.read_bytes()).hexdigest() for p in (bundle, artifact)]

def run(*args, ok=True):
    result = subprocess.run([str(exe), *map(str, args)], capture_output=True, text=True)
    assert (result.returncode == 0) == ok, (args, result.stdout, result.stderr)
    return result.stdout

with tempfile.TemporaryDirectory() as directory:
    work = Path(directory)
    form = json.loads(run('prepare', bundle, artifact, 'ops'))
    assert form['choices'] and all(c['outcome'] == '' for c in form['choices'])
    assert any(e['entry_kind'] == 'objection' for e in form['entries'])
    path = work / 'form.json'
    path.write_text(json.dumps(form))
    run('preview', path, bundle, artifact, ok=False)
    for outcome in ('approve', 'reject', 'defer'):
        submitted = copy.deepcopy(form)
        for choice in submitted['choices']:
            choice.update(outcome=outcome, rationale='Fixture human choice; keep dissent visible.',
                          receipt_id='choice-' + choice['decision_id'], decided_at='2026-10-12T12:00:00Z')
        path.write_text(json.dumps(submitted))
        preview = run('preview', path, bundle, artifact)
        assert 'UNVERIFIED DECISION SUBMISSION' in preview
        assert 'not a review receipt' in preview
        assert outcome in preview
        for entry in form['entries']:
            assert entry['body'] in preview
        assert 'accepted-knowledge' not in preview
        assert run('preview', path, bundle, artifact) == preview
    run('apply', path, bundle, artifact, ok=False)
    run('prepare', bundle, artifact, 'assistant', ok=False)
    changed_source = work / 'changed.md'
    changed_source.write_text('replacement bytes')
    run('preview', path, bundle, changed_source, ok=False)
    changed_bundle = work / 'changed.json'
    changed_bundle.write_text(bundle.read_text() + ' ')
    run('preview', path, changed_bundle, artifact, ok=False)
    submitted['entries'] = []
    path.write_text(json.dumps(submitted))
    run('preview', path, bundle, artifact, ok=False)
assert [hashlib.sha256(p.read_bytes()).hexdigest() for p in (bundle, artifact)] == before
print('PASS: actual CLI prepare, approve/reject/defer preview, repeated preview, no apply authority, blank/agent/stale-source/stale-bundle/hidden-dissent rejection, unchanged inputs')
