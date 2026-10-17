// Embedded verbatim by the Python page producer. No network/storage/host authority.
const $ = id => document.getElementById(id);
const clone = value => JSON.parse(JSON.stringify(value));
const base = clone(input.form), fields = ['outcome', 'rationale', 'receipt_id', 'decided_at', 'evidence_refs'];
let current = clone(base), previewed = null, pending = null, version = 0, readToken = 0, dirty = false;
const MAX = 2 * 1024 * 1024;
function require(value, message) { if (!value) throw Error(message); }
function canonical(value) {
  if (Array.isArray(value)) return '[' + value.map(canonical).join(',') + ']';
  if (value && typeof value === 'object') return '{' + Object.keys(value).sort().map(k => JSON.stringify(k) + ':' + canonical(value[k])).join(',') + '}';
  return JSON.stringify(value);
}
function scalar(text) { return typeof text === 'string' && !/[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(?<![\uD800-\uDBFF])[\uDC00-\uDFFF]/.test(text); }
function keys(value, expected) {
  return value && !Array.isArray(value) && typeof value === 'object' &&
    canonical(Object.keys(value).sort()) === canonical(expected.slice().sort());
}
// Reject duplicate keys and deep input before JSON.parse can silently discard
// conflicting scope/choice values. This parses syntax only; JSON.parse owns values.
function strictParse(text) {
  require(new TextEncoder().encode(text).length <= MAX, 'Draft exceeds 2 MiB.');
  let p = 0;
  function ws() { while (/\s/.test(text[p] || '') && p < text.length) p++; }
  function string() {
    const start = p++; let escaped = false;
    while (p < text.length) { const c = text[p++]; if (c === '"' && !escaped) return JSON.parse(text.slice(start, p)); if (c === '\\' && !escaped) escaped = true; else escaped = false; }
    throw Error('Unterminated JSON string.');
  }
  function value(depth) {
    require(depth <= 40, 'Draft nesting exceeds 40 levels.'); ws();
    if (text[p] === '"') { string(); return; }
    if (text[p] === '{') {
      p++; ws(); const seen = new Set(); if (text[p] === '}') { p++; return; }
      while (p < text.length) {
        ws(); require(text[p] === '"', 'Invalid JSON object.'); const key = string();
        require(!seen.has(key), 'Duplicate JSON key: ' + key); seen.add(key); ws(); require(text[p++] === ':', 'Invalid JSON object separator.'); value(depth + 1); ws();
        if (text[p] === '}') { p++; return; } require(text[p++] === ',', 'Invalid JSON object separator.');
      }
    } else if (text[p] === '[') {
      p++; ws(); if (text[p] === ']') { p++; return; }
      while (p < text.length) { value(depth + 1); ws(); if (text[p] === ']') { p++; return; } require(text[p++] === ',', 'Invalid JSON array separator.'); }
    } else {
      const match = text.slice(p).match(/^(?:true|false|null|-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?)/);
      require(match, 'Invalid JSON value.'); p += match[0].length; return;
    }
    throw Error('Incomplete JSON.');
  }
  value(0); ws(); require(p === text.length, 'Trailing JSON content.'); return JSON.parse(text);
}
function checkShape(form) {
  require(keys(form, Object.keys(base)), 'Draft form fields changed.');
  for (const key of Object.keys(base).filter(k => k !== 'choices'))
    require(canonical(form[key]) === canonical(base[key]), 'Protected scope or discussion changed; reopen the exact current review.');
  require(Array.isArray(form.choices) && form.choices.length === base.choices.length, 'Outstanding decision list changed.');
  form.choices.forEach((choice, i) => {
    require(keys(choice, Object.keys(base.choices[i])), 'Decision choice fields changed.');
    for (const key of Object.keys(choice).filter(k => !fields.includes(k)))
      require(choice[key] === base.choices[i][key], 'Decision ownership, order, subject or prompt changed.');
    for (const key of fields.filter(k => k !== 'evidence_refs')) require(scalar(choice[key]), 'Choice text must contain valid Unicode.');
    require(['', 'approve', 'reject', 'defer'].includes(choice.outcome), 'Select approve, reject or defer explicitly.');
    require(Array.isArray(choice.evidence_refs) && choice.evidence_refs.every(scalar), 'Evidence references must be text.');
  });
  require(new TextEncoder().encode(JSON.stringify({format: 'moonchat.unverified-decision-draft.v1', form}, null, 2) + '\n').length <= MAX, 'Draft exceeds 2 MiB.');
  return form;
}
function complete(form) {
  checkShape(form); let selected = 0; const receipts = new Set(input.prior_receipt_ids);
  for (const choice of form.choices) {
    const name = choice.decision_id + ': ';
    if (!choice.outcome) {
      require(!choice.rationale && !choice.receipt_id && !choice.decided_at && !choice.evidence_refs.length,
        name + 'Incomplete choice. Select an outcome or clear all fields to leave it undecided.'); continue;
    }
    selected++;
    require(choice.rationale.trim(), name + 'Rationale is required.');
    require(/^[A-Za-z0-9_.-]+$/.test(choice.receipt_id) && !['.', '..'].includes(choice.receipt_id), name + 'Use a safe unique proposed receipt ID.');
    require(!receipts.has(choice.receipt_id), name + 'Receipt ID already exists or is repeated. Never copy a prior receipt as a new one.'); receipts.add(choice.receipt_id);
    require(/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$/.test(choice.decided_at) &&
      Number.isFinite(Date.parse(choice.decided_at)) && new Date(choice.decided_at).toISOString() === choice.decided_at.replace('Z', '.000Z'), name + 'Enter a real UTC timestamp: YYYY-MM-DDTHH:mm:ssZ.');
    for (const ref of choice.evidence_refs) require(ref && ref === ref.trim() && !/[\\:\x00-\x1f\x7f]/.test(ref) && !ref.startsWith('/') &&
      ref.split('/').every(part => part && part !== '.' && part !== '..'), name + 'Evidence must be a workspace-relative slash path, one nonblank path per line.');
  }
  require(selected, 'No explicit choices. Select approve, reject or defer before preview/export.');
}
function status(message) { $('status').textContent = message; }
function cancelPending() {
  readToken++; pending = null; $('pending').hidden = true;
  $('replace').disabled = true; $('merge').disabled = true;
  $('reopen').value = ''; $('merge-file').value = ''; $('conflicts').replaceChildren();
}
function changed() { version++; dirty = true; previewed = null; $('export').disabled = true; $('preview-text').textContent = ''; cancelPending(); status('Unverified edits are unsaved. Preview again before exporting.'); }
function label(parent, title, control) { const node = document.createElement('label'); node.textContent = title; node.append(control); parent.append(node); }
function occupied(choice) { return fields.some(key => key === 'evidence_refs' ? choice[key].length : choice[key] !== ''); }
function stageMerge(form, token, atVersion) {
  const staged = {mode: 'merge', form: clone(current), conflicts: [], token, atVersion};
  form.choices.forEach((incoming, i) => {
    const local = current.choices[i];
    if (!occupied(local)) staged.form.choices[i] = clone(incoming);
    else if (occupied(incoming) && canonical(local) !== canonical(incoming))
      staged.conflicts.push({index: i, local: clone(local), incoming: clone(incoming), selected: ''});
  });
  pending = staged;
  function refresh() {
    const display = clone(staged.form.choices);
    for (const conflict of staged.conflicts) if (!conflict.selected)
      display[conflict.index] = {decision_id: conflict.local.decision_id, unresolved_conflict: true};
    $('pending-text').textContent = JSON.stringify(display, null, 2);
    $('merge').disabled = staged.conflicts.some(conflict => !conflict.selected);
  }
  for (const conflict of staged.conflicts) {
    const box = document.createElement('fieldset'), legend = document.createElement('legend');
    legend.textContent = 'Resolve whole choice: ' + conflict.local.decision_id; box.append(legend);
    for (const [title, choice] of [['Current choice', conflict.local], ['Imported choice', conflict.incoming]]) {
      const heading = document.createElement('h4'), text = document.createElement('pre');
      heading.textContent = title; text.textContent = JSON.stringify(choice, null, 2); box.append(heading, text);
    }
    const control = document.createElement('select'); control.id = 'resolve-' + conflict.index;
    for (const [value, title] of [['', 'Choose explicitly; no default'], ['local', 'Keep the whole current choice'], ['incoming', 'Use the whole imported choice']]) {
      const option = document.createElement('option'); option.value = value; option.textContent = title; control.append(option);
    }
    control.value = '';
    control.addEventListener('change', () => {
      if (pending !== staged || token !== readToken || atVersion !== version) return;
      conflict.selected = ['local', 'incoming'].includes(control.value) ? control.value : '';
      if (conflict.selected) staged.form.choices[conflict.index] = clone(conflict[conflict.selected]);
      refresh();
    });
    label(box, 'Resolve outcome, rationale, proposed receipt ID, timestamp and evidence together', control);
    $('conflicts').append(box);
  }
  refresh();
  status('Staged exact-scope merge with ' + staged.conflicts.length + ' conflicting choice(s). Current choices are unchanged. Resolve every conflict, then merge or cancel.');
}
function uniqueMergeReceipts(form) {
  const receipts = new Set(input.prior_receipt_ids);
  for (const choice of form.choices) if (choice.receipt_id) {
    require(!receipts.has(choice.receipt_id), 'Merge blocked: proposed receipt ID ' + choice.receipt_id + ' already exists or is repeated. Resolve differently or cancel and edit the draft. Current choices are unchanged.');
    receipts.add(choice.receipt_id);
  }
}
function render() {
  $('choice-list').replaceChildren();
  current.choices.forEach((choice, i) => {
    const box = document.createElement('fieldset'), legend = document.createElement('legend');
    legend.textContent = choice.decision_id + ' · ' + choice.prompt; box.append(legend);
    const subject = document.createElement('a'); subject.textContent = 'Read subject: ' + choice.subject_entry_id;
    subject.href = '#entry-' + base.entries.findIndex(e => e.entry_id === choice.subject_entry_id); box.append(subject);
    for (const key of fields) {
      const control = document.createElement(key === 'outcome' ? 'select' : ['rationale', 'evidence_refs'].includes(key) ? 'textarea' : 'input');
      control.id = 'choice-' + i + '-' + key;
      if (key === 'outcome') for (const value of ['', 'approve', 'reject', 'defer']) {
        const option = document.createElement('option'); option.value = value; option.textContent = value || 'Undecided (no default approval)'; control.append(option);
      }
      if (key === 'decided_at') control.placeholder = 'YYYY-MM-DDTHH:mm:ssZ';
      control.value = key === 'evidence_refs' ? choice[key].join('\n') : choice[key];
      control.addEventListener(key === 'outcome' ? 'change' : 'input', () => {
        current.choices[i][key] = key === 'evidence_refs' ? (control.value === '' ? [] : control.value.split('\n')) : control.value;
        changed();
      });
      label(box, {outcome: 'Explicit outcome', rationale: 'Rationale', receipt_id: 'Proposed receipt ID (not an authenticated receipt)', decided_at: 'Decision time (declared UTC)', evidence_refs: 'Evidence references (one workspace-relative path per line)'}[key], control);
    }
    const clear = document.createElement('button'); clear.type = 'button'; clear.id = 'clear-' + i; clear.textContent = 'Clear this choice to undecided';
    clear.addEventListener('click', () => { current.choices[i] = clone(base.choices[i]); changed(); render(); $('choice-' + i + '-outcome').focus(); });
    box.append(clear); $('choice-list').append(box);
  });
}
function attempt(fn) { try { fn(); } catch (error) { status(error.message); } }
function download(text, name) {
  let url = null, link = null;
  try {
    url = URL.createObjectURL(new Blob([text], {type: 'application/json;charset=utf-8'}));
    link = document.createElement('a'); link.href = url; link.download = name; document.body.append(link); link.click();
  } finally { if (link) link.remove(); if (url) setTimeout(() => URL.revokeObjectURL(url), 1000); }
  status('Download requested: ' + name + '. Verify the saved file. This remains an unverified draft; nothing was applied.');
}
$('preview').addEventListener('click', () => attempt(() => {
  previewed = null; $('export').disabled = true; $('preview-text').textContent = ''; complete(current);
  previewed = JSON.stringify(current, null, 2) + '\n'; $('preview-text').textContent = 'UNVERIFIED DECISION SUBMISSION — not a review receipt\n' + previewed;
  $('export').disabled = false; status('Local checks passed. Inspect the exact form below. Export then run the unchanged native preview against the retained bundle and source.');
}));
$('export').addEventListener('click', () => attempt(() => {
  require(previewed && previewed === JSON.stringify(current, null, 2) + '\n', 'Preview the current choices first.'); complete(current); download(previewed, 'form.json');
}));
$('save').addEventListener('click', () => attempt(() => {
  checkShape(current); download(JSON.stringify({format: 'moonchat.unverified-decision-draft.v1', form: current}, null, 2) + '\n', 'unverified-draft.json');
}));
async function readDraft(controlID, mode) {
  const file = $(controlID).files && $(controlID).files[0]; cancelPending();
  if (!file) return;
  const token = readToken, atVersion = version;
  $('pending-title').textContent = mode === 'merge' ? 'Merge another partial draft?' : 'Replace current draft?';
  $('pending-details').textContent = mode === 'merge'
    ? 'Only this exact native review form and named reviewer are accepted. Blank choices never erase work. Conflicts require one whole choice; individual fields are never spliced. Nothing changes until you click Merge resolved draft.'
    : 'This will discard current page edits. Cancel to keep them. Imported names are still unverified.';
  $('replace').hidden = mode !== 'replace'; $('merge').hidden = mode !== 'merge';
  $('pending').hidden = false; $('pending-text').textContent = 'Reading selected local draft…'; status('Reading draft. Current choices are unchanged.');
  try {
    require(file.size > 0 && file.size <= MAX, 'Draft must contain 1 byte through 2 MiB.');
    const raw = await file.arrayBuffer();
    if (token !== readToken || version !== atVersion) return;
    require(raw.byteLength > 0 && raw.byteLength <= MAX, 'Draft must contain 1 byte through 2 MiB.');
    let text;
    try { text = new TextDecoder('utf-8', {fatal: true}).decode(raw); }
    catch (_) { throw Error('Draft must contain valid UTF-8; invalid encoding was not repaired.'); }
    const draft = strictParse(text); require(keys(draft, ['format', 'form']) && draft.format === 'moonchat.unverified-decision-draft.v1', 'Select an unverified draft file, not a receipt or bundle.');
    checkShape(draft.form);
    if (mode === 'merge') stageMerge(draft.form, token, atVersion);
    else {
      pending = {mode, form: clone(draft.form), token, atVersion};
      $('pending-text').textContent = JSON.stringify(pending.form.choices, null, 2); $('replace').disabled = false;
      status('Loaded exact-scope unverified draft. Review its choices, then replace or cancel.');
    }
  } catch (error) { if (token === readToken && version === atVersion) { cancelPending(); status(error.message); } }
}
$('reopen').addEventListener('change', () => readDraft('reopen', 'replace'));
$('merge-file').addEventListener('change', () => readDraft('merge-file', 'merge'));
$('replace').addEventListener('click', () => attempt(() => {
  require(pending && pending.mode === 'replace' && pending.token === readToken && pending.atVersion === version, 'No loaded draft is ready.');
  current = clone(pending.form); changed(); dirty = false; render();
  status('Saved draft reopened. Identity remains unverified. Preview again before exporting.'); $('preview').focus();
}));
$('merge').addEventListener('click', () => attempt(() => {
  require(pending && pending.mode === 'merge' && pending.token === readToken && pending.atVersion === version, 'No staged merge is ready.');
  require(pending.conflicts.every(conflict => conflict.selected), 'Resolve every conflicting choice before merging.');
  const merged = checkShape(clone(pending.form)); uniqueMergeReceipts(merged);
  current = merged; changed(); render();
  status('Drafts merged locally. Choices remain unverified and unsaved. Preview again before exporting; native preview is still required.'); $('preview').focus();
}));
$('cancel').addEventListener('click', () => {
  const control = $('merge').hidden ? 'reopen' : 'merge-file';
  cancelPending(); status('Draft import canceled. Current choices are unchanged.'); $(control).focus();
});
window.addEventListener('beforeunload', event => { if (dirty) { event.preventDefault(); event.returnValue = ''; } });
render();
