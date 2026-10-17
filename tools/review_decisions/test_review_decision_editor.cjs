// Executes the real Python-emitted controller against its actual controls.
// This small DOM model does not qualify browser rendering, CSP or accessibility.
'use strict';
const assert = require('node:assert/strict'), fs = require('node:fs'), vm = require('node:vm'), cp = require('node:child_process'), path = require('node:path');
const [htmlPath, decider, bundle, source, out] = process.argv.slice(2);
const html = fs.readFileSync(htmlPath, 'utf8');
let checks = 0;
function decode(value) { return value.replace(/&(#x[0-9a-f]+|#\d+|amp|lt|gt|quot|apos);/gi, (_, entity) => entity[0] === '#' ? String.fromCodePoint(entity[1].toLowerCase() === 'x' ? parseInt(entity.slice(2), 16) : +entity.slice(1)) : ({amp:'&',lt:'<',gt:'>',quot:'"',apos:"'"})[entity]); }
function harness(markup = html) {
  const all = [], events = new Map(), urls = new Map(), requested = [], timers = [];
  let failure = '';
  class Element {
    constructor(tag) { this.tagName = tag.toUpperCase(); this.children = []; this.parentNode = null; this.attributes = {}; this.listeners = {}; this._value = ''; this.files = []; this.disabled = false; this.hidden = false; this._text = ''; all.push(this); }
    set value(value) { this._value = String(value); if (this.type === 'file' && value === '') this.files = []; }
    get value() { return this._value; }
    set textContent(value) { this._text = String(value); this.children.forEach(c => c.parentNode = null); this.children = []; }
    get textContent() { return this._text + this.children.map(c => c.textContent).join(''); }
    append(...nodes) { for (const node of nodes) { node.remove(); node.parentNode = this; this.children.push(node); } }
    replaceChildren(...nodes) { this.textContent = ''; this.append(...nodes); }
    remove() { if (this.parentNode) { this.parentNode.children.splice(this.parentNode.children.indexOf(this), 1); this.parentNode = null; } }
    addEventListener(type, fn) { (this.listeners[type] ||= []).push(fn); }
    async fire(type) { for (const fn of this.listeners[type] || []) await fn({target: this, preventDefault() {}}); }
    click() { if (this.disabled) return; if (this.tagName === 'A' && this.download) { if (failure === 'click') throw Error('download interrupted'); requested.push({name:this.download, text:urls.get(this.href)}); } else for (const fn of this.listeners.click || []) fn({target:this}); }
    focus() { document.activeElement = this; }
    setAttribute(key, value) { this.attributes[key] = value; if (['id','href','type','value'].includes(key)) this[key] = value; if (key === 'hidden') this.hidden = true; if (key === 'disabled') this.disabled = true; }
    connected() { return this === document.body || !!(this.parentNode && this.parentNode.connected()); }
  }
  const document = {createElement: tag => new Element(tag), getElementById: id => all.find(n => n.id === id && n.connected()), activeElement: null};
  const script = markup.match(/<script>([\s\S]*)<\/script>/)[1], shell = markup.replace(/<script>[\s\S]*<\/script>/, '');
  const stack = [];
  for (const token of shell.match(/<![^>]*>|<[^>]+>|[^<]+/g)) {
    if (token.startsWith('<!')) continue;
    if (token.startsWith('</')) { stack.pop(); continue; }
    if (token.startsWith('<')) {
      const tag = token.match(/^<([\w-]+)/)[1], node = new Element(tag);
      for (const [, name, value] of token.slice(tag.length + 1, -1).matchAll(/([\w-]+)(?:="([^"]*)")?/g)) node.setAttribute(name, decode(value || ''));
      if (stack.length) stack.at(-1).append(node);
      if (tag === 'body') document.body = node;
      if (!['meta','input','br','hr'].includes(tag)) stack.push(node);
    } else if (stack.length) stack.at(-1)._text += decode(token);
  }
  const context = vm.createContext({document, window:{addEventListener:(type,fn)=>events.set(type,fn)}, TextEncoder, TextDecoder,
    setTimeout:fn=>timers.push(fn), Blob:class {constructor(parts) {if (failure === 'blob') throw Error('Blob unavailable'); this.text = parts.join('');}},
    URL:{createObjectURL(blob) {if (failure === 'url') throw Error('URL unavailable'); const id='blob:'+urls.size; urls.set(id,blob.text); return id;}, revokeObjectURL:id=>urls.delete(id)}});
  vm.runInContext(script,context,{timeout:1000});
  const $ = document.getElementById;
  const click = id => $(id).click();
  const set = async (i,key,value) => { const n=$('choice-'+i+'-'+key); n.value=value; await n.fire(key === 'outcome' ? 'change' : 'input'); };
  async function fill(i=0,outcome='defer') { await set(i,'outcome',outcome); await set(i,'rationale','  Retain rollback objection.\nCafé ✓  '); await set(i,'receipt_id','draft-'+i); await set(i,'decided_at','2026-10-12T17:00:00Z'); await set(i,'evidence_refs','release/checks.txt\nnotes/café.md'); }
  function save() { click('save'); return requested.at(-1).text; }
  async function load(text, control='reopen') { $(control).files=[new File([text], 'draft.json', {type:'application/json'})]; await $(control).fire('change'); }
  function deferred(control='reopen') { let resolve, reject; const promise=new Promise((r,j)=>{resolve=r;reject=j;}); $(control).files=[{size:10,arrayBuffer:async()=>Buffer.from(await promise)}]; const finished=$(control).fire('change'); return {resolve,reject,finished}; }
  async function resolveChoice(i, value) { const n=$('resolve-'+i); n.value=value; await n.fire('change'); }
  function preview() {click('preview'); if ($('export').disabled) return null; return JSON.parse($('preview-text').textContent.split('\n').slice(1).join('\n'));}
  return {$,click,set,fill,save,load,deferred,resolveChoice,preview,requested,urls,timers,document, failure:value=>failure=value,
    unload() {let prevented=false; events.get('beforeunload')({preventDefault(){prevented=true;}}); return prevented;}};
}
async function check(name,fn) { await fn(); checks++; console.log('PASS '+name); }
(async () => {
  const h=harness(); let saved, form;
  await check('blank choices, protected context, native request links and no default approval', async()=>{
    assert.equal(h.$('choice-list').children.length,2); assert.equal(h.$('choice-0-outcome').value,'');
    assert.equal(h.$('export').disabled,true); assert.equal(h.unload(),false); assert.equal(h.preview(),null);
    assert.match(h.$('status').textContent,/No explicit choices/); assert.ok(h.$('entry-1')); assert.ok(h.$('source'));
    const link=h.$('choice-list').children[0].children[1]; assert.equal(link.href,'#entry-0'); assert.match(h.$('discussion').textContent,/rollback owner/);
  });
  await check('unfinished choices save losslessly and cannot preview or export',async()=>{
    await h.set(0,'rationale','  unfinished\nCafé  '); assert.equal(h.unload(),true); assert.equal(h.preview(),null);
    saved=h.save(); const draft=JSON.parse(saved); assert.equal(draft.format,'moonchat.unverified-decision-draft.v1');
    assert.equal(draft.form.choices[0].rationale,'  unfinished\nCafé  '); assert.equal(draft.form.choices[0].outcome,'');
    assert.match(h.$('status').textContent,/Download requested/); assert.equal(h.unload(),true);
  });
  await check('reopen requires explicit replacement, cancel preserves current fields, incomplete text returns',async()=>{
    await h.set(0,'rationale','newer'); await h.load(saved); assert.equal(h.$('pending').hidden,false); assert.equal(h.$('choice-0-rationale').value,'newer');
    h.click('cancel'); assert.equal(h.$('pending').hidden,true); assert.equal(h.$('choice-0-rationale').value,'newer');
    await h.load(saved); h.click('replace'); assert.equal(h.$('choice-0-rationale').value,'  unfinished\nCafé  '); assert.equal(h.$('export').disabled,true); assert.equal(h.unload(),false);
  });
  await check('approve reject and defer use explicit inputs with unchanged native form schema',async()=>{
    for (const outcome of ['approve','reject','defer']) {
      await h.fill(0,outcome); form=h.preview(); assert.ok(form); assert.equal(form.choices[0].outcome,outcome); assert.equal(form.choices[1].outcome,'');
      assert.equal(form.choices[0].rationale,'  Retain rollback objection.\nCafé ✓  '); h.click('export');
      const target=path.join(out,outcome+'-form.json'); fs.writeFileSync(target,h.requested.at(-1).text);
      const result=cp.spawnSync(decider,['preview',target,bundle,source],{encoding:'utf8'}); assert.equal(result.status,0,result.stderr);
      assert.match(result.stdout,/UNVERIFIED DECISION SUBMISSION/); assert.match(result.stdout,/not a review receipt/); assert.match(result.stdout,/rollback owner/);
      fs.writeFileSync(path.join(out,outcome+'-native-preview.txt'),result.stdout);
    }
  });
  await check('any field edit invalidates previously previewed export; repeat preview/export is stable',async()=>{
    const old=h.requested.length; await h.set(0,'rationale','Changed reason'); h.click('export'); assert.equal(h.requested.length,old); assert.equal(h.$('preview-text').textContent,'');
    h.preview(); h.click('export'); const once=h.requested.at(-1).text; h.preview(); h.click('export'); assert.equal(h.requested.at(-1).text,once);
  });
  await check('validation blocks missing text, unsafe IDs, impossible dates, invalid outcomes and evidence paths',async()=>{
    const cases=[['rationale','   '],['receipt_id','../evil'],['decided_at','2026-02-30T12:00:00Z'],['decided_at','2026-10-12T17:00:00+00:00'],['outcome','accepted'],['evidence_refs','../secret'],['evidence_refs','https://host/a'],['evidence_refs','a\n'],['evidence_refs','C:\\secret']];
    for (const [key,value] of cases) {await h.fill(); await h.set(0,key,value); assert.equal(h.preview(),null,key+' '+value); assert.equal(h.$('export').disabled,true);}
    await h.fill(); await h.fill(1,'reject'); await h.set(1,'receipt_id','draft-0'); assert.equal(h.preview(),null); assert.match(h.$('status').textContent,/already exists/);
    h.click('clear-1'); assert.ok(h.preview()); assert.equal(h.$('choice-1-outcome').value,'');
  });
  await check('saved draft roundtrip keeps all protected context and requires fresh preview',async()=>{
    saved=h.save(); const fresh=harness(); await fresh.load(saved); fresh.click('replace'); assert.equal(fresh.$('export').disabled,true);
    assert.deepEqual(fresh.preview(),JSON.parse(saved).form); assert.equal(fresh.unload(),false);
    fresh.click('clear-0'); assert.equal(fresh.$('choice-0-outcome').value,''); assert.equal(fresh.preview(),null); assert.equal(fresh.document.activeElement,fresh.$('choice-0-outcome'));
  });
  await check('scope ownership discussion order receipt-envelope and extra field tampering rejected atomically',async()=>{
    const mutations=[d=>d.form.entries.splice(1,1),d=>d.form.reviewer_name='Impersonator',d=>d.form.reviewer_participant_id='editor',d=>d.form.base_bundle_digest='sha256:'+'0'.repeat(64),d=>d.form.choices.reverse(),d=>d.form.choices[0].prompt='changed',d=>d.form.choices[0].decision_id='other',d=>d.form.choices.pop(),d=>d.form.authenticated=true,d=>d.format='moonchat.receipt.v1',d=>d.form.choices[0].evidence_refs='bad',d=>d.form.choices[0].rationale='\ud800'];
    for (const mutate of mutations) {const bad=JSON.parse(saved); mutate(bad); await h.load(JSON.stringify(bad)); assert.equal(h.$('pending').hidden,true); assert.equal(h.$('choice-0-outcome').value,'defer');}
  });
  await check('duplicate keys, malformed trailing/deep/oversized input and failed reads are rejected',async()=>{
    for (const bad of ['{"format":"x","format":"x"}',saved+'{}','{"x":NaN}', '['.repeat(42)+'0'+']'.repeat(42),'{"x":"'+'a'.repeat(2*1024*1024)+'"}']) {await h.load(bad); assert.equal(h.$('pending').hidden,true);}
    h.$('reopen').files=[{size:10,arrayBuffer:async()=>{throw Error('read interrupted');}}]; await h.$('reopen').fire('change'); assert.match(h.$('status').textContent,/read interrupted/);
  });
  await check('actual File/Blob invalid UTF-8 cannot silently repair rationale or stage replacement',async()=>{
    await h.fill(); const text=h.save();
    for (const bytes of [Buffer.from([0xff]),Buffer.from([0xc0,0xaf]),Buffer.from([0xed,0xa0,0x80]),Buffer.from([0xf0,0x9f])]) {
      const raw=Buffer.from(text), at=raw.indexOf(Buffer.from('Retain rollback'));
      const invalid=Buffer.concat([raw.subarray(0,at),bytes,raw.subarray(at+1)]);
      h.$('reopen').files=[new File([new Blob([invalid])],'broken.json',{type:'application/json'})];
      await h.$('reopen').fire('change'); assert.equal(h.$('pending').hidden,true); assert.equal(h.$('replace').disabled,true);
      assert.match(h.$('status').textContent,/valid UTF-8/); assert.equal(h.$('choice-0-rationale').value,'  Retain rollback objection.\nCafé ✓  ');
    }
    await h.load(text); assert.equal(h.$('pending').hidden,false); h.click('cancel');
    // A returned byte buffer must itself satisfy limits even if a custom file
    // source reports an inaccurate size. No truncation or replacement fallback.
    h.$('reopen').files=[{size:1,arrayBuffer:async()=>new Uint8Array(2*1024*1024+1).buffer}];
    await h.$('reopen').fire('change'); assert.equal(h.$('pending').hidden,true); assert.match(h.$('status').textContent,/2 MiB/);
  });
  await check('cancel and local edits invalidate asynchronous late file reads',async()=>{
    let slow=h.deferred(); h.click('cancel'); slow.resolve(saved); await slow.finished; assert.equal(h.$('pending').hidden,true);
    slow=h.deferred(); await h.set(0,'rationale','newest local edit'); slow.resolve(saved); await slow.finished; assert.equal(h.$('pending').hidden,true); assert.equal(h.$('choice-0-rationale').value,'newest local edit');
    slow=h.deferred(); await h.load(saved); const ready=h.$('pending-text').textContent; slow.resolve('invalid'); await slow.finished; assert.equal(h.$('pending-text').textContent,ready); h.click('cancel');
  });
  await check('edits invalidate a staged reopen and replacement clicks cannot repeat it',async()=>{
    await h.load(saved); await h.set(0,'rationale','keep local'); h.click('replace'); assert.equal(h.$('choice-0-rationale').value,'keep local');
    await h.load(saved); h.click('replace'); h.click('replace'); assert.equal(h.$('choice-0-rationale').value,JSON.parse(saved).form.choices[0].rationale);
  });
  await check('download errors preserve current choices and successful URLs are revoked',async()=>{
    await h.fill(); for (const kind of ['blob','url','click']) {h.failure(kind); const before=h.requested.length; h.click('save'); assert.equal(h.requested.length,before); assert.equal(h.$('choice-0-outcome').value,'defer');}
    h.failure(''); h.click('save'); for (const fn of h.timers) fn(); assert.equal(h.urls.size,0); assert.equal(h.unload(),true);
  });
  await check('prior receipt IDs cannot be reused and prior decisions never become initial outcomes',async()=>{
    const prior=harness(html.replace('"prior_receipt_ids": []','"prior_receipt_ids": ["draft-0"]')); await prior.fill(); assert.equal(prior.preview(),null); assert.match(prior.$('status').textContent,/already exists/);
  });
  const left=harness(), right=harness(); await left.fill(0,'defer'); await right.fill(1,'reject');
  const leftDraft=left.save(), rightDraft=right.save();
  const leftForm=JSON.parse(leftDraft).form, rightForm=JSON.parse(rightDraft).form;
  const currentForm=host=>JSON.parse(host.save()).form;
  async function firstDraft() {const host=harness(); await host.load(leftDraft); host.click('replace'); return host;}
  await check('two saved partial drafts merge disjoint choices only after explicit confirmation, preserving native form and dissent',async()=>{
    const host=await firstDraft(); assert.ok(host.preview());
    await host.load(rightDraft,'merge-file'); assert.deepEqual(currentForm(host),leftForm);
    assert.equal(host.$('replace').disabled,true); assert.equal(host.$('merge').disabled,false);
    assert.equal(host.$('conflicts').children.length,0); host.click('replace'); assert.deepEqual(currentForm(host),leftForm);
    host.click('merge'); assert.equal(host.$('pending').hidden,true); assert.equal(host.$('export').disabled,true); assert.equal(host.$('preview-text').textContent,'');
    assert.equal(host.unload(),true); const merged=host.preview(); assert.ok(merged);
    assert.deepEqual(merged,{...leftForm,choices:[leftForm.choices[0],rightForm.choices[1]]});
    host.click('export'); const bytes=host.requested.at(-1).text;
    const target=path.join(out,'merged-native-form.json'); fs.writeFileSync(target,bytes);
    const result=cp.spawnSync(decider,['preview',target,bundle,source],{encoding:'utf8'}); assert.equal(result.status,0,result.stderr);
    assert.match(result.stdout,/UNVERIFIED DECISION SUBMISSION/); assert.match(result.stdout,/not a review receipt/);
    assert.match(result.stdout,/rollback owner/); assert.match(result.stdout,/defer/); assert.match(result.stdout,/reject/); assert.doesNotMatch(result.stdout,/accepted-knowledge/);
    fs.writeFileSync(path.join(out,'merged-native-preview.txt'),result.stdout);
    host.click('merge'); assert.deepEqual(currentForm(host),merged);
    const fresh=harness(); await fresh.load(host.save()); fresh.click('replace'); assert.deepEqual(fresh.preview(),merged);
    host.click('export'); assert.equal(host.requested.at(-1).text,bytes);
  });
  await check('blank and identical incoming choices are nonconflicting and never erase current work',async()=>{
    const host=await firstDraft(), blank=harness().save();
    for (const incoming of [blank,leftDraft]) {
      await host.load(incoming,'merge-file'); assert.equal(host.$('conflicts').children.length,0);
      assert.deepEqual(currentForm(host),leftForm); host.click('merge'); assert.deepEqual(currentForm(host),leftForm);
    }
    const fresh=harness(); await fresh.load(leftDraft,'merge-file'); assert.equal(fresh.$('choice-0-outcome').value,'');
    fresh.click('merge'); assert.deepEqual(currentForm(fresh),leftForm);
  });
  await check('conflicting same-outcome rationale and receipt IDs require whole-object selection with no default',async()=>{
    const host=await firstDraft(), incoming=JSON.parse(leftDraft);
    Object.assign(incoming.form.choices[0],{rationale:'Different reason <img src=x onerror=alert(1)>',receipt_id:'incoming-0',decided_at:'2026-10-12T18:00:00Z',evidence_refs:['different/proof.txt']});
    await host.load(JSON.stringify(incoming),'merge-file'); assert.equal(host.$('merge').disabled,true);
    assert.equal(host.$('resolve-0').value,''); assert.match(host.$('pending-text').textContent,/unresolved_conflict/);
    assert.match(host.$('conflicts').textContent,/Different reason <img/); assert.deepEqual(currentForm(host),leftForm);
    host.click('merge'); assert.deepEqual(currentForm(host),leftForm);
    await host.resolveChoice(0,'incoming'); assert.equal(host.$('merge').disabled,false); assert.deepEqual(currentForm(host),leftForm);
    await host.resolveChoice(0,''); assert.equal(host.$('merge').disabled,true);
    await host.resolveChoice(0,'local'); host.click('merge'); assert.deepEqual(currentForm(host),leftForm);
    await host.load(JSON.stringify(incoming),'merge-file'); await host.resolveChoice(0,'incoming'); host.click('merge');
    assert.deepEqual(currentForm(host),incoming.form); assert.ok(host.preview());
    host.click('export'); const target=path.join(out,'resolved-native-form.json'); fs.writeFileSync(target,host.requested.at(-1).text);
    const result=cp.spawnSync(decider,['preview',target,bundle,source],{encoding:'utf8'}); assert.equal(result.status,0,result.stderr);
    assert.match(result.stdout,/UNVERIFIED DECISION SUBMISSION/); assert.match(result.stdout,/Different reason/);
    fs.writeFileSync(path.join(out,'resolved-native-preview.txt'),result.stdout);
  });
  await check('each outcome rationale receipt timestamp and evidence difference independently conflicts atomically',async()=>{
    for (const [field,value] of [['outcome','approve'],['rationale','alternate'],['receipt_id','alternate-0'],['decided_at','2026-10-12T18:00:00Z'],['evidence_refs',['other.txt']]]) {
      const host=await firstDraft(), incoming=JSON.parse(leftDraft); incoming.form.choices[0][field]=value;
      await host.load(JSON.stringify(incoming),'merge-file'); assert.equal(host.$('merge').disabled,true,field);
      await host.resolveChoice(0,'incoming'); host.click('merge'); assert.deepEqual(currentForm(host),incoming.form,field);
    }
  });
  await check('multiple conflicts must all resolve and conflicting choices can choose different sides',async()=>{
    const host=harness(), remote=harness(); await host.fill(0,'approve'); await host.fill(1,'reject');
    await remote.fill(0,'reject'); await remote.fill(1,'defer');
    const local=currentForm(host), incoming=currentForm(remote); await host.load(remote.save(),'merge-file');
    await host.resolveChoice(0,'incoming'); assert.equal(host.$('merge').disabled,true); host.click('merge'); assert.deepEqual(currentForm(host),local);
    await host.resolveChoice(1,'local'); host.click('merge'); assert.deepEqual(currentForm(host),{...local,choices:[incoming.choices[0],local.choices[1]]});
  });
  await check('unfinished text is merged as one object, never completed by splicing fields from two drafts',async()=>{
    const host=harness(), remote=harness(); await host.set(0,'rationale','unfinished current'); await remote.set(0,'receipt_id','partial-remote');
    await remote.set(1,'rationale','second unfinished'); const before=currentForm(host), incoming=currentForm(remote);
    await host.load(remote.save(),'merge-file'); assert.equal(host.$('merge').disabled,true);
    await host.resolveChoice(0,'incoming'); host.click('merge'); const merged=currentForm(host);
    assert.equal(merged.choices[0].rationale,''); assert.deepEqual(merged.choices[0],incoming.choices[0]);
    assert.deepEqual(merged.choices[1],incoming.choices[1]); assert.equal(host.preview(),null);
    assert.match(host.$('status').textContent,/Incomplete choice/); assert.notDeepEqual(merged,before);
  });
  await check('duplicate proposed receipt IDs across disjoint drafts block the whole merge without mutation',async()=>{
    const host=await firstDraft(), incoming=JSON.parse(rightDraft); incoming.form.choices[1].receipt_id='draft-0';
    await host.load(JSON.stringify(incoming),'merge-file'); host.click('merge');
    assert.match(host.$('status').textContent,/Merge blocked/); assert.equal(host.$('pending').hidden,false); assert.deepEqual(currentForm(host),leftForm);
    const prior=harness(html.replace('"prior_receipt_ids": []','"prior_receipt_ids": ["draft-1"]'));
    await prior.load(rightDraft,'merge-file'); prior.click('merge'); assert.match(prior.$('status').textContent,/already exists/);
    assert.equal(prior.$('choice-1-outcome').value,'');
  });
  await check('wrong reviewer exact source revision base discussion ownership order and draft envelope cannot merge',async()=>{
    const host=await firstDraft();
    const mutations=[d=>d.form.reviewer_participant_id='editor',d=>d.form.reviewer_name='Other',d=>d.form.source_revision_id='other',d=>d.form.source_digest='sha256:'+'0'.repeat(64),d=>d.form.base_bundle_digest='sha256:'+'0'.repeat(64),d=>d.form.entries.pop(),d=>d.form.choices.reverse(),d=>d.form.choices.pop(),d=>d.form.choices[0].prompt='different',d=>d.form.choices[0].reviewer_participant_id='other',d=>d.form.choices[0].subject_entry_id='other',d=>d.form.choices[0].extra='x',d=>d.format='receipt',d=>d.form.extra=true];
    for (const mutate of mutations) {
      const bad=JSON.parse(rightDraft); mutate(bad); await host.load(JSON.stringify(bad),'merge-file');
      assert.equal(host.$('pending').hidden,true); assert.equal(host.$('merge').disabled,true); assert.deepEqual(currentForm(host),leftForm);
    }
  });
  await check('two individually bounded drafts whose merged envelope exceeds 2 MiB are refused atomically',async()=>{
    const host=harness(), local=JSON.parse(leftDraft), incoming=JSON.parse(rightDraft);
    local.form.choices[0].rationale='l'.repeat(1100000); incoming.form.choices[1].rationale='r'.repeat(1100000);
    await host.load(JSON.stringify(local)); host.click('replace'); await host.load(JSON.stringify(incoming),'merge-file');
    assert.equal(host.$('merge').disabled,false); host.click('merge'); assert.match(host.$('status').textContent,/Draft exceeds 2 MiB/);
    assert.deepEqual(currentForm(host),local.form); assert.equal(host.$('choice-1-outcome').value,'');
  });
  await check('merge rejects malformed duplicate-key oversized invalid UTF-8 and interrupted reads without mutation',async()=>{
    const host=await firstDraft();
    for (const bad of ['{"format":"a","format":"b"}',rightDraft+'{}','{"x":NaN}','['.repeat(42)+'0'+']'.repeat(42),'x'.repeat(2*1024*1024+1),'']) {
      await host.load(bad,'merge-file'); assert.equal(host.$('pending').hidden,true); assert.deepEqual(currentForm(host),leftForm);
    }
    host.$('merge-file').files=[new File([Buffer.from([0xff])],'invalid.json')]; await host.$('merge-file').fire('change');
    assert.match(host.$('status').textContent,/valid UTF-8/); assert.deepEqual(currentForm(host),leftForm);
    host.$('merge-file').files=[{size:1,arrayBuffer:async()=>new Uint8Array(2*1024*1024+1).buffer}]; await host.$('merge-file').fire('change');
    assert.match(host.$('status').textContent,/2 MiB/); assert.equal(host.$('pending').hidden,true);
    const slow=host.deferred('merge-file'); slow.reject(Error('merge read interrupted')); await slow.finished;
    assert.match(host.$('status').textContent,/merge read interrupted/); assert.deepEqual(currentForm(host),leftForm);
  });
  await check('merge cancel before and after conflict selection preserves existing preview edits and unsaved state',async()=>{
    const host=await firstDraft(); await host.fill(0,'approve'); const before=currentForm(host); assert.ok(host.preview());
    const preview=host.$('preview-text').textContent;
    await host.load(leftDraft,'merge-file'); await host.resolveChoice(0,'incoming'); host.click('cancel'); host.click('merge');
    assert.deepEqual(currentForm(host),before); assert.equal(host.$('preview-text').textContent,preview); assert.equal(host.$('export').disabled,false); assert.equal(host.unload(),true);
    assert.equal(host.document.activeElement,host.$('merge-file'));
    const slow=host.deferred('merge-file'); host.click('cancel'); slow.resolve(rightDraft); await slow.finished;
    assert.equal(host.$('pending').hidden,true); assert.deepEqual(currentForm(host),before);
  });
  await check('local edits clear staged merge resolutions and late reads cannot overwrite newer work',async()=>{
    const host=await firstDraft(); await host.load(rightDraft,'merge-file'); await host.set(0,'rationale','new local'); host.click('merge');
    assert.equal(host.$('choice-0-rationale').value,'new local'); assert.equal(host.$('choice-1-outcome').value,'');
    const slow=host.deferred('merge-file'); await host.set(0,'rationale','newest'); slow.resolve(rightDraft); await slow.finished;
    assert.equal(host.$('pending').hidden,true); assert.equal(host.$('choice-0-rationale').value,'newest');
    await host.load(leftDraft,'merge-file'); const detached=host.$('resolve-0'); await host.set(0,'rationale','after stage');
    detached.value='incoming'; await detached.fire('change'); assert.equal(host.$('pending').hidden,true); assert.equal(host.$('merge').disabled,true);
    assert.equal(host.$('conflicts').children.length,0); host.click('merge'); assert.equal(host.$('choice-0-rationale').value,'after stage');
  });
  await check('new file selection across merge and replacement invalidates all earlier successes and failures',async()=>{
    const host=await firstDraft();
    for (const [oldMode,newMode] of [['merge-file','merge-file'],['merge-file','reopen'],['reopen','merge-file']]) {
      for (const fail of [false,true]) {
        const slow=host.deferred(oldMode); await host.load(rightDraft,newMode); const ready=host.$('pending-text').textContent;
        if (fail) slow.reject(Error('stale failure')); else slow.resolve(leftDraft); await slow.finished;
        assert.equal(host.$('pending-text').textContent,ready); assert.equal(host.$(newMode==='reopen'?'replace':'merge').disabled,false);
        assert.deepEqual(currentForm(host),leftForm); host.click('cancel');
      }
    }
    const slow=host.deferred('merge-file'); host.$('merge-file').files=[]; await host.$('merge-file').fire('change');
    slow.resolve(rightDraft); await slow.finished; assert.equal(host.$('pending').hidden,true); assert.deepEqual(currentForm(host),leftForm);
  });
  fs.writeFileSync(path.join(out,'saved-unverified-draft.json'),saved);
  console.log('PASS '+checks+' emitted-controller scenarios; native approve/reject/defer and merged previews consumed exact exports. Browser/CSP/layout/accessibility not run.');
})().catch(error=>{console.error(error);process.exitCode=1;});
