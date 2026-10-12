#!/usr/bin/env python3
"""Prepare selected JUnit test evidence for the existing MoonChat agenda editor."""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

from review_docx import IntakeError, load_json
from review_docx_plan import check_shape

LIMIT = 2 * 1024 * 1024


def require(ok, message):
    if not ok:
        raise IntakeError(message)


def digest(raw):
    return 'sha256:' + hashlib.sha256(raw).hexdigest()


def catalog(raw):
    require(len(raw) <= LIMIT, 'JUnit report exceeds 2 MiB')
    text = raw.decode('utf-8-sig')
    require('<!DOCTYPE' not in text.upper() and '<!ENTITY' not in text.upper(), 'DTD and entities are unsupported')
    root = ET.fromstring(text)
    require(root.tag in ('testsuites', 'testsuite'), 'expected unnamespaced testsuites or testsuite')
    cases = []
    def visit(element, suites, depth=0):
        require(depth <= 32, 'JUnit nesting exceeds 32')
        if element.tag == 'testsuite':
            suites = suites + [element.get('name', '')]
        for child in element:
            if child.tag in ('testsuites', 'testsuite'):
                visit(child, suites, depth + 1)
            elif child.tag == 'testcase':
                require(len(cases) < 5000, 'JUnit report exceeds 5000 test cases')
                signals = []
                for node in child:
                    if node.tag in ('failure', 'error', 'skipped'):
                        signals.append({'kind': node.tag, 'type': node.get('type', ''),
                                        'message': node.get('message', ''), 'text': ''.join(node.itertext())})
                kinds = {signal['kind'] for signal in signals}
                status = 'error' if 'error' in kinds else 'failure' if 'failure' in kinds else 'skipped' if 'skipped' in kinds else 'no-failure-reported'
                cases.append({'index': len(cases), 'suites': suites, 'name': child.get('name', ''),
                              'classname': child.get('classname', ''), 'file': child.get('file', ''),
                              'line': child.get('line', ''), 'time_reported': child.get('time', ''),
                              'status': status, 'signals': signals,
                              'system_out': [ ''.join(n.itertext()) for n in child if n.tag == 'system-out'],
                              'system_err': [ ''.join(n.itertext()) for n in child if n.tag == 'system-err']})
    visit(root, [])
    return {'contract_id': 'moonchat.junit-catalog.v1', 'report_digest': digest(raw), 'cases': cases}


def reference(value):
    require(isinstance(value, str) and value.strip() and not value.startswith(('/', '\\'))
            and '\\' not in value and ':' not in value
            and all(part not in ('', '.', '..') for part in value.split('/')),
            'report_ref must be a workspace-relative retained file reference')
    return value


def draft(agenda_raw, source_raw, report_raw, plan_raw):
    agenda, plan = load_json(agenda_raw), load_json(plan_raw)
    check_shape(agenda)
    require(isinstance(plan, dict) and plan.get('contract_id') == 'moonchat.junit-selection.v1', 'expected junit-selection.v1')
    require(plan.get('source_digest') == digest(source_raw), 'source digest changed; select exact source bytes')
    report = catalog(report_raw)
    require(plan.get('report_digest') == report['report_digest'], 'JUnit report digest changed; recatalog')
    report_ref = reference(plan.get('report_ref'))
    choices = plan.get('cases')
    require(isinstance(choices, list) and 1 <= len(choices) <= 100, 'select 1..100 cases')
    candidate = copy.deepcopy(agenda)
    seen = set()
    for choice in choices:
        require(isinstance(choice, dict) and set(choice) == {'index', 'key', 'kind', 'author', 'note', 'decisions'}, 'each selection needs index/key/kind/author/note/decisions')
        index = choice['index']
        require(type(index) is int and 0 <= index < len(report['cases']) and index not in seen, 'case index missing or repeated')
        seen.add(index)
        require(isinstance(choice['note'], str) and choice['note'].strip(), 'selection needs curator note')
        evidence = {'source_artifact_ref': agenda['source_artifact_ref'],
                    'source_revision_id': agenda['source_revision_id'], 'source_digest': digest(source_raw),
                    'report_ref': report_ref, 'report_digest': report['report_digest'],
                    'case': report['cases'][index]}
        body = choice['note'] + '\n\nJUnit report evidence (unverified test-run claims, not a human decision):\n' + json.dumps(evidence, ensure_ascii=False, indent=2)
        candidate['items'].append({'key': choice['key'], 'kind': choice['kind'], 'author': choice['author'],
                                   'body': body, 'evidence_refs': [report_ref], 'decisions': copy.deepcopy(choice['decisions'])})
    check_shape(candidate)
    encoded = json.dumps(candidate, ensure_ascii=False, indent=2).encode('utf-8')
    require(len(encoded) <= 8 * 1024 * 1024, 'draft exceeds 8 MiB; select fewer cases')
    return candidate


def read(path, limit=LIMIT):
    with Path(path).open('rb') as stream:
        raw = stream.read(limit + 1)
    require(len(raw) <= limit, 'input exceeds byte limit')
    return raw


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='mode', required=True)
    inspect = commands.add_parser('catalog'); inspect.add_argument('report')
    prepare = commands.add_parser('draft')
    for name in ('agenda', 'source', 'report', 'plan'):
        prepare.add_argument(name)
    compare = commands.add_parser('compare', help='compare two retained reports without inferring passes')
    compare.add_argument('before'); compare.add_argument('after')
    prepare_comparison = commands.add_parser('comparison-draft', help='append selected report changes to an agenda')
    for name in ('agenda', 'source', 'before', 'after', 'plan'):
        prepare_comparison.add_argument(name)
    parser.add_argument('--output', required=True, help='new JSON file; never overwrites')
    args = parser.parse_args()
    try:
        if args.mode == 'catalog':
            result = catalog(read(args.report))
        elif args.mode == 'draft':
            result = draft(read(args.agenda), read(args.source, 8 * 1024 * 1024), read(args.report), read(args.plan))
        else:
            from review_junit_compare import compare_reports, comparison_draft
            if args.mode == 'compare':
                result = compare_reports(read(args.before), read(args.after))
            else:
                result = comparison_draft(read(args.agenda), read(args.source, 8 * 1024 * 1024),
                                          read(args.before), read(args.after), read(args.plan))
        output = (json.dumps(result, ensure_ascii=False, indent=2) + '\n').encode('utf-8')
        with Path(args.output).open('xb') as stream:
            stream.write(output)
        print(json.dumps({'output_sha256': digest(output), 'kind': args.mode, 'receipts_created': 0}))
    except (IntakeError, ValueError, UnicodeError, OSError, ET.ParseError, RecursionError) as error:
        print(str(error), file=sys.stderr); return 2
    return 0

if __name__ == '__main__':
    sys.exit(main())
