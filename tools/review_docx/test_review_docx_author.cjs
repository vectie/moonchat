// Executes the actual Python-emitted inline authoring script against its HTML
// controls. A deliberately small DOM model, not a browser/CSP/layout claim.
'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const cp = require('node:child_process');
const root = path.resolve(__dirname, '../..');
const cli = path.join(__dirname, 'review_docx.py');
const agenda = path.join(root, 'examples/review-docx-plan/agenda.json');
const docx = path.join(root, 'examples/review-docx/launch.docx');
const seed = path.join(root, 'examples/review-docx-plan/selections.json');
let checks = 0;
function check(name, fn) { fn(); checks++; console.log('PASS ' + name); }
function generate(extra = []) {
  const result = cp.spawnSync('python3', ['-B', cli, 'plan-packet', agenda, docx, ...extra, '--authoring'], {encoding: 'utf8'});
  assert.equal(result.status, 0, result.stderr); return result.stdout;
}
function decode(value) {
  return value.replace(/&(#x[0-9a-f]+|#\d+|amp|lt|gt|quot|apos);/gi, (_, entity) => entity[0] === '#' ? String.fromCodePoint(entity[1].toLowerCase() === 'x' ? parseInt(entity.slice(2), 16) : +entity.slice(1)) : ({amp:'&',lt:'<',gt:'>',quot:'"',apos:"'"})[entity]);
}
function harness(html) {
  const all = [], events = new Map(), urls = new Map(), requested = [], timers = [];
  let failBlob = false, failURL = false, failClick = false;
  class Element {
    constructor(tag) { this.tagName = tag.toUpperCase(); this.children = []; this.parentNode = null; this.attributes = {}; this.listeners = {}; this.value = ''; this.disabled = false; this.hidden = false; this._text = ''; all.push(this); }
    set textContent(value) { this._text = String(value); this.children.forEach(child => { child.parentNode = null; }); this.children = []; }
    get textContent() { return this._text + this.children.map(child => child.textContent).join(''); }
    append(...nodes) { for (const node of nodes) { node.remove(); node.parentNode = this; this.children.push(node); } }
    replaceChildren(...nodes) { this.textContent = ''; this.append(...nodes); }
    remove() { if (this.parentNode) { this.parentNode.children.splice(this.parentNode.children.indexOf(this), 1); this.parentNode = null; } }
    addEventListener(type, listener) { (this.listeners[type] ||= []).push(listener); }
    fire(type) { for (const listener of this.listeners[type] || []) listener({target: this, preventDefault() {}}); }
    click() { if (this.disabled) return; if (this.tagName === 'A' && this.download) { if (failClick) throw Error('download interrupted'); requested.push({href: this.href, download: this.download, data: urls.get(this.href)}); } else this.fire('click'); }
    focus() { document.activeElement = this; }
    querySelector(tag) { return this.children.find(child => child.tagName.toLowerCase() === tag) || this.children.map(child => child.querySelector(tag)).find(Boolean) || null; }
    setAttribute(key, value) { this.attributes[key] = value; if (key === 'id') this.id = value; if (['href', 'type', 'value'].includes(key)) this[key] = value; if (key === 'hidden') this.hidden = true; if (key === 'disabled') this.disabled = true; }
  }
  const document = {createElement: tag => new Element(tag), getElementById: id => all.find(node => node.id === id), activeElement: null};
  const script = html.match(/<script>([\s\S]*)<\/script>/)[1];
  const shell = html.replace(/<script>[\s\S]*<\/script>/, '');
  const stack = [];
  for (const token of shell.match(/<![^>]*>|<[^>]+>|[^<]+/g)) {
    if (token.startsWith('<!')) continue;
    if (token.startsWith('</')) { stack.pop(); continue; }
    if (token.startsWith('<')) {
      const tag = token.match(/^<([\w-]+)/)[1], node = new Element(tag);
      for (const [, name, value] of token.slice(tag.length + 1, -1).matchAll(/([\w-]+)(?:="([^"]*)")?/g)) node.setAttribute(name, decode(value || ''));
      if (stack.length) stack.at(-1).append(node);
      if (tag === 'body') document.body = node;
      if (!['meta', 'input', 'br', 'hr'].includes(tag)) stack.push(node);
    } else if (stack.length) stack.at(-1)._text += decode(token);
  }
  const window = {addEventListener(type, fn) { events.set(type, fn); }};
  const context = vm.createContext({document, window, TextEncoder, setTimeout: fn => timers.push(fn),
    Blob: class { constructor(parts) { if (failBlob) throw Error('Blob unavailable'); this.text = parts.join(''); } },
    URL: {createObjectURL(blob) { if (failURL) throw Error('URL unavailable'); const id = 'blob:local-' + (urls.size + 1); urls.set(id, blob.text); return id; }, revokeObjectURL(id) { urls.delete(id); }}});
  vm.runInContext(script, context, {timeout: 1000});
  const $ = document.getElementById;
  function click(id) { $(id).click(); }
  function set(id, value, event = 'input') { $(id).value = value; $(id).fire(event); }
  function fill(note, kind = 'question', author = 'curator', key) {
    set('author-note', note); set('author-kind', kind, 'change'); set('author-person', author, 'change');
    if (key) set('author-key', key);
  }
  function decision(reviewer, prompt) {
    click('author-add-decision'); const row = $('author-decisions').children.at(-1);
    row.querySelector('select').value = reviewer; row.querySelector('select').fire('change');
    row.querySelector('textarea').value = prompt; row.querySelector('textarea').fire('input');
    return row;
  }
  function listButton(index, text) { const node = $('author-items').children[index].children.find(child => child.tagName === 'BUTTON' && child.textContent.startsWith(text)); assert.ok(node, text); node.click(); }
  function preview() { click('author-preview'); return JSON.parse($('author-preview-text').textContent); }
  return {$, click, set, fill, decision, listButton, preview, document, requested, timers, urls,
    unload() { let prevented = false; const event = {preventDefault() { prevented = true; }}; events.get('beforeunload')(event); return prevented; },
    failures(blob, url, link) { failBlob = blob; failURL = url; failClick = link; }};
}
const html = generate();
const h = harness(html);
let finalRecipe;
check('actual empty page, source anchors and no hidden implicit choice', () => {
  assert.equal(h.$('author-items').children.length, 0); assert.equal(h.$('author-download').disabled, true);
  assert.equal(h.$('author-editor').hidden, true); assert.equal(h.unload(), false);
  h.click('author-preview'); assert.match(h.$('author-status').textContent, /1–100/);
  h.click('author-select-7'); assert.equal(h.$('author-source').href, '#source-7'); assert.equal(h.$('author-comment').href, '#comment-7');
  assert.ok(h.$('source-7')); assert.ok(h.$('comment-7'));
  assert.equal(h.$('author-original').textContent, h.$('author-original-text-7').textContent);
  assert.equal(h.$('author-quote').textContent, h.$('author-quote-text-7').textContent);
  assert.match(h.$('author-anchor').textContent, /Unicode code points/);
});
check('unfinished text survives repeated selection, navigation and blocked preview', () => {
  h.fill('Retain rollback dissent.', 'objection'); h.click('author-select-7'); h.click('author-select-2');
  assert.equal(h.$('author-note').value, 'Retain rollback dissent.'); assert.equal(h.$('author-heading').textContent, 'Author Word comment 7');
  h.click('author-preview'); assert.match(h.$('author-status').textContent, /Apply or cancel/); assert.equal(h.$('author-download').disabled, true);
  assert.equal(h.unload(), true); h.click('author-apply'); assert.match(h.$('author-status').textContent, /objection needs/);
});
check('named humans only, complete prompt editing and atomic invalid-reviewer rejection', () => {
  const row = h.decision('notes', 'Not allowed');
  assert.equal(row.querySelector('select').children.some(option => option.value === 'notes'), false);
  h.click('author-apply'); assert.match(h.$('author-status').textContent, /existing human reviewer/); assert.equal(h.$('author-items').children.length, 0);
  row.querySelector('select').value = 'ops'; row.querySelector('select').fire('change');
  row.querySelector('textarea').value = ''; h.click('author-apply'); assert.match(h.$('author-status').textContent, /Decision prompt is required/);
  row.querySelector('textarea').value = 'Can rollback be rehearsed before rollout?';
  h.decision('support', 'Can support witness the rollback?');
  h.click('author-apply'); assert.equal(h.$('author-editor').hidden, true); assert.equal(h.$('author-items').children.length, 1);
  h.click('author-apply'); assert.equal(h.$('author-items').children.length, 1);
});
check('all kinds, existing-author validation, unique safe keys and exact whitespace', () => {
  h.click('author-select-2'); h.fill('  Confirm support coverage.\nSecond line.  ', 'question', 'missing');
  h.click('author-apply'); assert.match(h.$('author-status').textContent, /existing agenda author/);
  h.set('author-person', 'curator', 'change'); h.set('author-key', 'rollout'); h.click('author-apply'); assert.match(h.$('author-status').textContent, /already exists/);
  h.set('author-key', 'bad key'); h.click('author-apply'); assert.match(h.$('author-status').textContent, /Use letters/);
  h.set('author-key', 'word-comment-7'); h.click('author-apply'); assert.match(h.$('author-status').textContent, /already exists/);
  h.set('author-key', 'support-new'); h.decision('support', 'Who covers support?'); h.click('author-apply');
  h.click('author-select-11'); h.fill('A proposal to retain the automated note as unverified metadata.', 'proposal', 'notes'); h.click('author-apply');
  const p = h.preview(); assert.deepEqual(p.comments.map(c => c.kind), ['objection', 'question', 'proposal']);
  assert.equal(p.comments[1].note, '  Confirm support coverage.\nSecond line.  ');
});
check('editing, cancelling, duplicate reviewer and preview invalidation', () => {
  const before = h.preview(); h.click('author-select-7'); assert.equal(h.$('author-download').disabled, true); assert.equal(h.$('author-preview-text').textContent, '');
  h.fill('Uncommitted changed note.', 'objection'); h.decision('ops', 'Duplicate human'); h.click('author-apply'); assert.match(h.$('author-status').textContent, /one request per item/);
  h.click('author-cancel'); assert.deepEqual(h.preview(), before);
  h.click('author-select-7'); h.set('author-note', '   '); h.click('author-apply'); assert.match(h.$('author-status').textContent, /Curator note is required/); h.click('author-cancel');
});
check('reordering/removing applied rows changes only selection recipe and cancels dirty moves', () => {
  const source = h.$('document-text').textContent, original = h.$('comment-7').textContent;
  h.listButton(1, 'Move'); assert.equal(h.$('author-download').disabled, true); assert.equal(h.preview().comments[0].comment_id, '2');
  h.listButton(1, 'Move'); assert.equal(h.preview().comments[0].comment_id, '7');
  h.click('author-select-2'); h.set('author-note', 'Keep this unfinished edit.'); h.listButton(0, 'Remove'); assert.match(h.$('author-status').textContent, /Apply or cancel/); h.click('author-cancel');
  h.listButton(2, 'Remove'); assert.equal(h.preview().comments.length, 2); assert.equal(h.$('document-text').textContent, source); assert.equal(h.$('comment-7').textContent, original);
});
check('failed download retains exact preview, repeated downloads and URL cleanup', () => {
  const expected = h.$('author-preview-text').textContent;
  for (const failure of [[true,false,false], [false,true,false], [false,false,true]]) {
    h.failures(...failure); h.click('author-download'); assert.match(h.$('author-status').textContent, /Could not request download/); assert.equal(h.$('author-preview-text').textContent, expected);
  }
  h.failures(false,false,false); h.click('author-download'); h.click('author-download');
  assert.equal(h.requested.length, 2); assert.equal(h.requested[0].data, expected); assert.equal(h.requested[1].data, expected);
  assert.equal(h.requested[0].download, 'selections.json'); assert.match(h.$('author-status').textContent, /Confirm selections.json was saved/);
  h.timers.forEach(fn => fn()); assert.equal(h.urls.size, 0); finalRecipe = expected;
});
check('seeded recipe restores exact choices without hand editing and allows new cancel', () => {
  const seeded = harness(generate([seed])); assert.deepEqual(seeded.preview(), JSON.parse(fs.readFileSync(seed)));
  seeded.click('author-select-11'); seeded.fill('Discard this new item.'); seeded.click('author-cancel');
  assert.deepEqual(seeded.preview(), JSON.parse(fs.readFileSync(seed)));
});
check('malicious authored text stays literal in preview, author names and option labels', () => {
  const attack = '</script><img src="https://example.invalid" onerror="throw 1">&\u2028';
  const malicious = harness(html.replace('"display_name": "Jules"', '"display_name": "\\u003c/script\\u003e"'));
  malicious.click('author-select-7'); assert.match(malicious.$('author-person').children[1].textContent, /<\/script>/); malicious.fill(attack, 'proposal'); malicious.decision('ops', attack); malicious.click('author-apply');
  const value = malicious.preview(); assert.equal(value.comments[0].note, attack); assert.equal(value.comments[0].decisions[0].prompt, attack);
  assert.equal(malicious.document.body.querySelector('img'), null);
});
check('16 MiB imported evidence and 4 MiB UTF-8 recipe limits are atomic', () => {
  const limit = harness(html);
  limit.click('author-select-7'); limit.fill('\ud800'); limit.click('author-apply');
  assert.match(limit.$('author-status').textContent, /valid Unicode text/); assert.equal(limit.$('author-items').children.length, 0);
  limit.fill('界'.repeat(1500000)); limit.click('author-apply');
  assert.match(limit.$('author-status').textContent, /recipe exceeds 4 MiB/); assert.equal(limit.$('author-items').children.length, 0);
  limit.fill('x'.repeat(16 * 1024 * 1024)); limit.click('author-apply');
  assert.match(limit.$('author-status').textContent, /evidence exceeds 16 MiB/); assert.equal(limit.$('author-items').children.length, 0);
  limit.click('author-cancel'); assert.equal(limit.$('author-editor').hidden, true);
});
check('101 source comments enforce the 100-selection boundary without dropping draft text', () => {
  const code = `import sys,json; sys.path.insert(0,${JSON.stringify(__dirname)})
from review_docx_author import authoring_packet
from test_review_docx import agenda,archive,parts,W
comments='<w:comments xmlns:w="'+W+'">'+''.join('<w:comment w:id="'+str(i)+'"><w:p><w:r><w:t>Original '+str(i)+'</w:t></w:r></w:p></w:comment>' for i in range(101))+'</w:comments>'
document='<w:document xmlns:w="'+W+'"><w:body><w:p><w:r><w:t>All point anchors.</w:t>'+''.join('<w:commentReference w:id="'+str(i)+'"/>' for i in range(101))+'</w:r></w:p></w:body></w:document>'
print(authoring_packet(json.dumps(agenda()).encode(),archive(parts(document=document,comments=comments))))`;
  const generated = cp.spawnSync('python3', ['-B', '-c', code], {encoding: 'utf8'}); assert.equal(generated.status, 0, generated.stderr);
  const large = harness(generated.stdout);
  for (let i = 0; i < 100; i++) { large.click('author-select-' + i); large.fill('Question ' + i); large.click('author-apply'); }
  assert.equal(large.preview().comments.length, 100); large.click('author-select-100');
  assert.match(large.$('author-status').textContent, /at most 100/); assert.equal(large.$('author-editor').hidden, true);
  large.listButton(0, 'Remove'); large.click('author-select-100'); large.fill('Replacement'); large.click('author-apply');
  assert.equal(large.preview().comments.length, 100); assert.equal(large.preview().comments.at(-1).comment_id, '100');
});
if (process.argv[2]) fs.writeFileSync(path.resolve(process.argv[2]), finalRecipe);
console.log(JSON.stringify({passed: checks, failed: 0, inline_script: true, actual_cli: true, browser: false}));
