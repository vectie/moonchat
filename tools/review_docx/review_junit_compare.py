"""Compare retained JUnit evidence and prepare explicit review questions.

Matching is a stated name-based heuristic, not proof of test or run identity.
Neither comparison nor agenda preparation creates authoritative review evidence.
"""
import copy
import json

from review_docx import load_json
from review_docx_plan import check_shape
from review_junit import LIMIT, catalog, digest, reference, require

MAX_COMPARISON = 16 * 1024 * 1024
MAX_DRAFT = 8 * 1024 * 1024


def _identity(case):
    return (tuple(case['suites']), case['classname'], case['name'])


def _groups(cases):
    groups = {}
    for case in cases:
        groups.setdefault(_identity(case), []).append(case)
    return groups


def _outcome_change(before, after):
    old, new = before['status'], after['status']
    if old == new:
        return 'same-reported-status'
    failing = {'error', 'failure'}
    if old not in failing and new in failing:
        return 'new-failure-or-error-reported'
    if old in failing and new not in failing:
        return 'failure-or-error-no-longer-reported'
    return 'reported-status-changed'


def _bounded(result, limit, message):
    # Suite paths repeat across cases. Bound serialization incrementally so a
    # short report with long shared names cannot first allocate a huge JSON string.
    size = 1  # CLI trailing newline
    for piece in json.JSONEncoder(ensure_ascii=False, indent=2).iterencode(result):
        size += len(piece.encode('utf-8'))
        require(size <= limit, message)
    return result


def compare_reports(before_raw, after_raw):
    """Group exact suite-path/class/name tuples; never pair duplicate occurrences."""
    before, after = catalog(before_raw), catalog(after_raw)
    old, new = _groups(before['cases']), _groups(after['cases'])
    keys = list(old) + [key for key in new if key not in old]
    rows = []
    counts = {name: 0 for name in ('added', 'absent', 'changed', 'unchanged', 'ambiguous')}
    for key in keys:
        left, right = old.get(key, []), new.get(key, [])
        presence = 'both' if left and right else 'before-only' if left else 'after-only'
        fields = []
        outcome = 'not-comparable'
        if len(left) > 1 or len(right) > 1 or not key[2].strip():
            change = 'ambiguous'
        elif not left:
            change = 'added'
        elif not right:
            change = 'absent'
        else:
            # Document position is provenance, not a change to test evidence.
            fields = [field for field in left[0] if field != 'index' and left[0][field] != right[0][field]]
            change = 'changed' if fields else 'unchanged'
            outcome = _outcome_change(left[0], right[0])
        counts[change] += 1
        rows.append({'index': len(rows), 'identity': {'suites': list(key[0]), 'classname': key[1], 'name': key[2]},
                     'presence': presence, 'change': change, 'outcome_change': outcome,
                     'changed_fields': fields, 'before_cases': left, 'after_cases': right})
    result = {'contract_id': 'moonchat.junit-comparison.v1',
              'before_report_digest': before['report_digest'], 'after_report_digest': after['report_digest'],
              'matching_rule': 'exact suite path, classname and nonblank name; unique on each present side',
              'qualification': 'Unverified report claims. Before/after are caller labels, not verified execution order. '
                               'Names suggest correspondence, not test identity. Absence is not resolution; '
                               'no-failure-reported is not a proven pass. No decisions or receipts are created.',
              'before_case_count': len(before['cases']), 'after_case_count': len(after['cases']),
              'row_count': len(rows), 'counts': counts, 'rows': rows}
    return _bounded(result, MAX_COMPARISON, 'comparison exceeds 16 MiB')


def comparison_draft(agenda_raw, source_raw, before_raw, after_raw, plan_raw):
    """Append selected full comparisons to the existing editable agenda format."""
    require(len(agenda_raw) <= LIMIT and len(plan_raw) <= LIMIT, 'agenda or selection plan exceeds 2 MiB')
    require(len(source_raw) <= MAX_DRAFT, 'source exceeds 8 MiB')
    agenda, plan = load_json(agenda_raw), load_json(plan_raw)
    require(isinstance(agenda, dict), 'expected editable agenda object')
    check_shape(agenda)
    fields = {'contract_id', 'source_digest', 'before_report_digest', 'after_report_digest',
              'before_report_ref', 'after_report_ref', 'rows'}
    require(isinstance(plan, dict) and set(plan) == fields
            and plan['contract_id'] == 'moonchat.junit-comparison-selection.v1',
            'expected exact junit-comparison-selection.v1 fields')
    require(plan['source_digest'] == digest(source_raw), 'source digest changed; select exact source bytes')
    comparison = compare_reports(before_raw, after_raw)
    for side in ('before', 'after'):
        require(plan[side + '_report_digest'] == comparison[side + '_report_digest'],
                side + ' report digest changed; compare again')
    before_ref = reference(plan['before_report_ref'])
    after_ref = reference(plan['after_report_ref'])
    require(before_ref != after_ref, 'retain before and after reports under distinct references')
    choices = plan['rows']
    require(isinstance(choices, list) and 1 <= len(choices) <= 100, 'select 1..100 comparison rows')
    candidate, seen = copy.deepcopy(agenda), set()
    for choice in choices:
        require(isinstance(choice, dict) and set(choice) == {'index', 'key', 'kind', 'author', 'note', 'decisions'},
                'each row selection needs index/key/kind/author/note/decisions')
        index = choice['index']
        require(type(index) is int and 0 <= index < len(comparison['rows']) and index not in seen,
                'comparison row index missing or repeated')
        seen.add(index)
        require(isinstance(choice['note'], str) and choice['note'].strip(), 'selection needs curator note')
        evidence = {'comparison_contract_id': comparison['contract_id'],
                    'source_artifact_ref': agenda['source_artifact_ref'],
                    'source_revision_id': agenda['source_revision_id'], 'source_digest': digest(source_raw),
                    'before_report_ref': before_ref, 'before_report_digest': comparison['before_report_digest'],
                    'after_report_ref': after_ref, 'after_report_digest': comparison['after_report_digest'],
                    'matching_rule': comparison['matching_rule'], 'qualification': comparison['qualification'],
                    'row': comparison['rows'][index]}
        body = choice['note'] + '\n\nJUnit comparison evidence (report claims, not human decisions):\n' + json.dumps(evidence, ensure_ascii=False, indent=2)
        candidate['items'].append({'key': choice['key'], 'kind': choice['kind'], 'author': choice['author'],
                                   'body': body, 'evidence_refs': [before_ref, after_ref],
                                   'decisions': copy.deepcopy(choice['decisions'])})
    check_shape(candidate)
    return _bounded(candidate, MAX_DRAFT, 'draft exceeds 8 MiB; select fewer comparison rows')
