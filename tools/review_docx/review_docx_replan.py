"""Explicit editorial re-selection across DOCX revisions; never transfer decisions."""
from __future__ import annotations

import copy

from review_docx import IntakeError, MAX_IMPORTED_TEXT, digest, import_comments, load_json, required_text
from review_docx_compare import compare_docx
from review_docx_plan import check_shape

FORMAT = 'moonchat.docx-replan.v1'
EDITABLE = {'action', 'comment_id', 'reason'}


def checked_plan(agenda: dict, plan: dict, catalog: dict) -> None:
    """Reuse the importer with complete selected quotes, then check draft shape."""
    selected = plan.get('comments')
    ids = {c.get('comment_id') for c in selected
           if isinstance(c, dict) and isinstance(c.get('comment_id'), str)} if isinstance(selected, list) else set()
    source = catalog['logical_text']
    hydrated = {**catalog, 'comments': []}
    size = 0
    for item in catalog['comments']:
        current = {**item}
        if item['comment_id'] in ids:
            quote = source[item['start_offset']:item['end_offset']]
            size += len(quote.encode('utf-8'))
            if size > MAX_IMPORTED_TEXT:
                raise IntakeError('selected comment evidence exceeds 16 MiB; select fewer ranges')
            current['quote'] = quote
        hydrated['comments'].append(current)
    check_shape(import_comments(agenda, plan, hydrated))


def preparation(agenda_bytes: bytes, before: bytes, after: bytes, plan_bytes: bytes):
    agenda, plan = load_json(agenda_bytes), load_json(plan_bytes)
    check_shape(agenda)
    comparison = compare_docx(before, after)
    checked_plan(agenda, plan, comparison['before'])
    changes = {row['comment_id']: row for row in comparison['changes']}
    selections = []
    for choice in plan['comments']:
        change = changes[choice['comment_id']]
        selections.append({'key': choice['key'], 'previous_comment_id': choice['comment_id'],
                           'status': change['status'], 'changed_fields': change['changed_fields'],
                           'action': 'review', 'comment_id': None if change['status'] == 'removed' else choice['comment_id'],
                           'reason': ''})
    draft = {'format': FORMAT, 'agenda_digest': digest(agenda_bytes),
             'previous_document_digest': digest(before), 'document_digest': digest(after),
             'previous_plan_digest': digest(plan_bytes),
             'new_comment_ids': [r['comment_id'] for r in comparison['changes'] if r['status'] == 'added'],
             'selections': selections, 'additions': []}
    return agenda, plan, comparison, draft


def draft_replan(agenda_bytes: bytes, before: bytes, after: bytes, plan_bytes: bytes) -> dict:
    """Every prior selection starts unresolved, including identical archive bytes."""
    return preparation(agenda_bytes, before, after, plan_bytes)[3]


def apply_replan(agenda_bytes: bytes, before: bytes, after: bytes, plan_bytes: bytes,
                 recipe_bytes: bytes) -> dict:
    """Return only the existing intake plan format after all editorial choices exist."""
    agenda, previous, comparison, expected = preparation(agenda_bytes, before, after, plan_bytes)
    recipe = load_json(recipe_bytes)
    if set(recipe) != set(expected):
        raise IntakeError('replan recipe requires its exact draft fields')
    for field in set(expected) - {'selections', 'additions'}:
        if recipe[field] != expected[field]:
            raise IntakeError('replan recipe snapshot or comparison differs; generate a fresh draft')
    rows = recipe['selections']
    if not isinstance(rows, list) or len(rows) != len(expected['selections']):
        raise IntakeError('explicitly keep, remap or drop every previous selection')
    by_key = {row['key']: row for row in expected['selections']}
    old_choices = {choice['key']: choice for choice in previous['comments']}
    seen, choices = set(), []
    for row in rows:
        if not isinstance(row, dict) or set(row) != set(expected['selections'][0]):
            raise IntakeError('each replan selection requires its exact draft fields')
        key = required_text(row, 'key')
        if key in seen or key not in by_key:
            raise IntakeError('replan selection keys must cover the previous plan exactly once')
        seen.add(key)
        if any(row[field] != by_key[key][field] for field in set(row) - EDITABLE):
            raise IntakeError('replan comparison fields changed; edit only action, comment_id and reason')
        if row['action'] not in ('keep', 'remap', 'drop'):
            raise IntakeError('every selection needs an explicit keep, remap or drop action')
        required_text(row, 'reason')
        if row['action'] == 'drop':
            if row['comment_id'] is not None:
                raise IntakeError('a dropped selection must have null comment_id; omission is not resolution')
            continue
        identity = required_text(row, 'comment_id')
        if row['action'] == 'keep' and identity != row['previous_comment_id']:
            raise IntakeError('keep requires the same Word ID; use remap for a different ID')
        if row['action'] == 'remap' and identity == row['previous_comment_id']:
            raise IntakeError('remap requires a different Word ID; use keep for the same ID')
        choice = copy.deepcopy(old_choices[key])
        choice['comment_id'] = identity
        choices.append(choice)
    if not isinstance(recipe['additions'], list):
        raise IntakeError('replan additions must be an array of ordinary selection objects')
    # Dropped keys remain reserved: a new discussion must not silently reuse one.
    for addition in recipe['additions']:
        if (not isinstance(addition, dict) or not isinstance(addition.get('key'), str)
                or addition['key'] in old_choices):
            raise IntakeError('added selections need new item keys, distinct from all previous selections')
    choices.extend(copy.deepcopy(recipe['additions']))
    result = {'format': 'moonchat.docx-review.v1', 'document_digest': digest(after), 'comments': choices}
    checked_plan(agenda, result, comparison['after'])
    return result
