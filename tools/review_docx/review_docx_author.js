// Embedded by the Python producer with a hash-only CSP; no network or persistence.
const $ = id => document.getElementById(id);
const clone = value => JSON.parse(JSON.stringify(value));
const bytes = value => new TextEncoder().encode(value).length;
const roster = new Map(input.agenda.participants.map(person => [person.participant_id, person]));
const humans = input.agenda.participants.filter(person => person.participant_kind === 'human');
const comments = new Map(input.comments.map(comment => [comment.comment_id, comment]));
const originalKeys = new Set(input.agenda.items.map(item => item.key));
let choices = clone(input.plan.comments), editing = null, preview = null, dirty = false;
const status = message => { $('author-status').textContent = message; };
function invalidate() {
  preview = null;
  $('author-preview-text').textContent = '';
  $('author-download').disabled = true;
}
function changed() { dirty = true; invalidate(); }
function text(value, field) {
  if (typeof value !== 'string' || !value.trim()) throw Error(field + ' is required.');
  for (const char of value) {
    if (char.length === 1 && char.charCodeAt(0) >= 0xd800 && char.charCodeAt(0) <= 0xdfff) throw Error(field + ' requires valid Unicode text.');
  }
}
function validate(choice, others) {
  if (!comments.has(choice.comment_id)) throw Error('Unknown Word comment.');
  text(choice.key, 'Item key');
  if (!/^[A-Za-z0-9_.-]+$/.test(choice.key)) throw Error('Use letters, numbers, underscores, dots or hyphens in the item key.');
  if (originalKeys.has(choice.key) || others.some(item => item.key === choice.key)) throw Error('Item key already exists; choose a unique key.');
  if (others.some(item => item.comment_id === choice.comment_id)) throw Error('Word comment is already selected.');
  if (!['question', 'objection', 'proposal'].includes(choice.kind)) throw Error('Choose a discussion kind.');
  if (!roster.has(choice.author)) throw Error('Choose an existing agenda author.');
  text(choice.note, 'Curator note');
  if (choice.kind === 'objection' && !choice.decisions.length) throw Error('An objection needs an explicit human decision request.');
  const assigned = new Set();
  for (const decision of choice.decisions) {
    if (!roster.has(decision.reviewer) || roster.get(decision.reviewer).participant_kind !== 'human') throw Error('Choose an existing human reviewer.');
    if (assigned.has(decision.reviewer)) throw Error('Each reviewer can have one request per item.');
    assigned.add(decision.reviewer);
    text(decision.prompt, 'Decision prompt');
  }
}
function recipe(rows) {
  if (rows.length < 1 || rows.length > 100) throw Error('Select 1–100 comments.');
  let cost = 0;
  rows.forEach((choice, index) => {
    validate(choice, rows.filter((_, other) => other !== index));
    cost += bytes(choice.note) + comments.get(choice.comment_id).evidence_bytes;
  });
  if (cost > 16 * 1024 * 1024) throw Error('Selected comment evidence exceeds 16 MiB; select fewer ranges.');
  const result = JSON.stringify({format: 'moonchat.docx-review.v1', document_digest: input.plan.document_digest, comments: rows}, null, 2) + '\n';
  if (bytes(result) > 4 * 1024 * 1024) throw Error('Selection recipe exceeds 4 MiB. Shorten notes or prompts.');
  return result;
}
function element(tag, value) {
  const node = document.createElement(tag);
  if (value !== undefined) node.textContent = value;
  return node;
}
function button(label, action) {
  const node = element('button', label); node.type = 'button';
  node.addEventListener('click', action); return node;
}
function selectPeople(select, people, value) {
  select.replaceChildren();
  const empty = element('option', 'Choose a person'); empty.value = ''; select.append(empty);
  for (const person of people) {
    const option = element('option', person.display_name + ' (' + person.participant_id + ', ' + person.participant_kind + ')');
    option.value = person.participant_id; select.append(option);
  }
  select.value = value;
}
function noEdit() {
  if (editing) { status('Apply or cancel the open item edit first. Your text is retained.'); return false; }
  return true;
}
function renderList() {
  const list = $('author-items'); list.replaceChildren();
  choices.forEach((choice, index) => {
    const row = element('li');
    row.append(element('span', choice.key + ' · ' + choice.kind + ' · Word comment ' + choice.comment_id));
    row.append(button('Edit ' + choice.key, () => begin(choice.comment_id)));
    const up = button('Move ' + choice.key + ' up', () => move(index, -1));
    const down = button('Move ' + choice.key + ' down', () => move(index, 1));
    up.disabled = index === 0; down.disabled = index === choices.length - 1;
    row.append(up, down, button('Remove ' + choice.key, () => {
      if (!noEdit()) return;
      choices.splice(index, 1); changed(); renderList();
      status('Selection removed. Original comment and source are still retained.');
    }));
    list.append(row);
  });
  for (const id of comments.keys()) $('author-select-' + id).textContent = choices.some(choice => choice.comment_id === id) ? 'Edit selected item' : 'Select for review';
}
function move(index, delta) {
  if (!noEdit() || index + delta < 0 || index + delta >= choices.length) return;
  [choices[index], choices[index + delta]] = [choices[index + delta], choices[index]];
  changed(); renderList(); status('Selection order changed. Preview again before downloading.');
}
function addDecision(decision = {reviewer: '', prompt: ''}) {
  const row = element('fieldset');
  const legend = element('legend', 'Proposed human request');
  const label = element('label', 'Reviewer '), select = element('select');
  selectPeople(select, humans, decision.reviewer); label.append(select);
  const promptLabel = element('label', 'Decision prompt'), prompt = element('textarea');
  prompt.rows = 3; prompt.value = decision.prompt; promptLabel.append(prompt);
  select.addEventListener('change', changed); prompt.addEventListener('input', changed);
  row.append(legend, label, promptLabel, button('Remove request', () => { row.remove(); changed(); }));
  $('author-decisions').append(row);
}
function begin(id) {
  if (editing) {
    if (editing.comment_id !== id) status('Apply or cancel the open item edit before selecting another comment. Your text is retained.');
    $('author-key').focus(); return;
  }
  const saved = choices.find(choice => choice.comment_id === id);
  if (!saved && choices.length === 100) { status('Select at most 100 comments.'); return; }
  if (!comments.has(id)) { status('Unknown comment.'); return; }
  let key = 'word-comment-' + id;
  while (originalKeys.has(key) || choices.some(choice => choice.key === key)) key += '-new';
  editing = saved ? clone(saved) : {comment_id: id, key, kind: 'question', author: '', note: '', decisions: []};
  invalidate();
  $('author-editor').hidden = false;
  $('author-heading').textContent = 'Author Word comment ' + id;
  $('author-source').href = '#source-' + id;
  $('author-comment').href = '#comment-' + id;
  const source = comments.get(id);
  $('author-original').textContent = $('author-original-text-' + id).textContent;
  const quote = $('author-quote-text-' + id);
  $('author-quote').textContent = quote ? quote.textContent : 'No text selected; nearby words are context only.';
  $('author-anchor').textContent = source.anchor_kind + ' · [' + source.start_offset + ', ' + source.end_offset + ') Unicode code points. ' + (source.end_offset - source.start_offset > 2000 ? 'Excerpt limited to 2,000 characters; use the full source link above.' : 'Exact anchored passage.');
  $('author-key').value = editing.key;
  $('author-kind').value = editing.kind;
  selectPeople($('author-person'), input.agenda.participants, editing.author);
  $('author-note').value = editing.note;
  $('author-decisions').replaceChildren();
  editing.decisions.forEach(addDecision);
  status('Edit the discussion and requests, then apply or cancel. Source and comments remain unchanged.');
  $('author-key').focus();
}
function readEdit() {
  return {comment_id: editing.comment_id, key: $('author-key').value, kind: $('author-kind').value,
    author: $('author-person').value, note: $('author-note').value,
    decisions: Array.from($('author-decisions').children, row => ({reviewer: row.querySelector('select').value, prompt: row.querySelector('textarea').value}))};
}
$('author-apply').addEventListener('click', () => {
  if (!editing) return;
  try {
    const choice = readEdit();
    const next = choices.filter(item => item.comment_id !== choice.comment_id);
    validate(choice, next);
    const index = choices.findIndex(item => item.comment_id === choice.comment_id);
    if (index < 0) next.push(choice); else next.splice(index, 0, choice);
    recipe(next); // Validate bounds atomically before changing applied selections.
    choices = next; editing = null; $('author-editor').hidden = true;
    changed(); renderList(); status('Selection applied locally. Preview the complete recipe next.');
  } catch (error) { status(error.message); }
});
$('author-cancel').addEventListener('click', () => {
  if (!editing) return;
  editing = null; $('author-editor').hidden = true; invalidate();
  status('Item edit cancelled. Previously applied selections are unchanged.');
});
$('author-add-decision').addEventListener('click', () => {
  if (!editing) return;
  if ($('author-decisions').children.length >= humans.length) { status('There can be one request per existing human reviewer on an item.'); return; }
  addDecision(); changed();
});
for (const id of ['author-key', 'author-note']) $(id).addEventListener('input', changed);
for (const id of ['author-kind', 'author-person']) $(id).addEventListener('change', changed);
for (const id of comments.keys()) $('author-select-' + id).addEventListener('click', () => begin(id));
$('author-preview').addEventListener('click', () => {
  if (!noEdit()) return;
  invalidate();
  try {
    preview = recipe(choices); $('author-preview-text').textContent = preview;
    $('author-download').disabled = false;
    status('Exact recipe preview ready. This is preparation; the native composer still validates the agenda and exact DOCX.');
  } catch (error) { status(error.message); }
});
$('author-download').addEventListener('click', () => {
  if (!noEdit() || preview === null) { status('Preview the current selections before downloading.'); return; }
  let url, anchor;
  try {
    if (preview !== recipe(choices)) { invalidate(); throw Error('Selections changed. Preview again.'); }
    url = URL.createObjectURL(new Blob([preview], {type: 'application/json;charset=utf-8'}));
    anchor = element('a'); anchor.href = url; anchor.download = 'selections.json';
    document.body.append(anchor); anchor.click();
    status('Download requested. Confirm selections.json was saved, and keep the original agenda and exact DOCX. No save acknowledgement is available here.');
  } catch (error) { status('Could not request download. Your selections and preview remain available. ' + error.message); }
  finally {
    if (anchor) anchor.remove();
    if (url) setTimeout(() => URL.revokeObjectURL(url), 1000);
  }
});
window.addEventListener('beforeunload', event => {
  if (dirty || editing) { event.preventDefault(); event.returnValue = ''; }
});
renderList();
status(choices.length ? 'Initial recipe loaded. Select an item to edit or preview the current selections.' : 'Select an original comment below to author its review item.');
