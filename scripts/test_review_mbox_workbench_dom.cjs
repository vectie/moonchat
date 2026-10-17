/* Minimal DOM test double, production controller, real HTTP/native backend.
   This is not a browser rendering/accessibility test. No dependency install. */
const assert = require('node:assert/strict');
const {mount} = require('./review_mbox_workbench/app.js');
class Element {
  constructor(tag) { this.tagName=tag;this.children=[];this.listeners={};this.value='';this.textContent='';this.hidden=false;this.disabled=false; }
  append(...children) { this.children.push(...children); }
  replaceChildren(...children) { this.children=children;this.textContent=''; }
  removeAttribute(name) { delete this[name]; }
  addEventListener(name,fn) { this.listeners[name]=fn; }
  async fire(name) { if (!this.disabled && this.listeners[name]) await this.listeners[name]({target:this}); }
  set innerHTML(_) { throw new Error('Untrusted HTML assignment'); }
}
const ids=['snapshot','participants','agenda','catalog','selections','attachments','preview','status','download','result','save-draft','draft-download','draft-file','open-draft'];
let elements=Object.fromEntries(ids.map(x=>[x,new Element(x)]));
function makeDocument(nodes) { return {getElementById:id=>nodes[id],createElement:tag=>new Element(tag)}; }
let document=makeDocument(elements);
const walk=node=>[node,...node.children.flatMap(walk)];
const button=(parent,text)=>{const found=walk(parent).find(n=>n.tagName==='button'&&n.textContent===text);assert.ok(found,'button '+text);return found;};
const field=(parent,text)=>{const label=walk(parent).find(n=>n.tagName==='label'&&n.textContent===text);assert.ok(label,'field '+text);return label.children[0];};
async function input(node,value) {node.value=value;await node.fire('input');}
async function fill(card,key) {
  await input(field(card,'Item key'),key);await input(field(card,'Review kind'),'objection');
  await input(field(card,'Curator note'),'Explicit curator note for '+key);
  await button(card,'Add pending decision request').fire('click');
  card=elements.selections.children.find(c=>field(c,'Item key').value===key);
  await input(field(card,'Named human reviewer'),'ops');await input(field(card,'Pending decision prompt'),'Is this evidence sufficient?');
}
(async()=>{
  const base=process.argv[2]; let delay=false,release;
  const fetcher=async(path,options)=>{const response=await fetch(new URL(path,base),options);if(path==='preview'&&delay)await new Promise(resolve=>{release=resolve;});return response;};
  await mount(document,fetcher).ready;
  assert.equal(elements.participants.children.length,3);
  assert.ok(!walk(elements.catalog).some(n=>n.textContent.startsWith('Add attachment')));
  await button(elements.catalog,'Add message body 1/1.1').fire('click');
  await fill(elements.selections.children[0],'body');
  await elements.attachments.fire('click');
  assert.ok(walk(elements.catalog).some(n=>n.tagName==='pre'&&n.textContent.includes('<script>never()</script>')));
  await button(elements.catalog,'Add attachment 1/1.2').fire('click');
  await fill(elements.selections.children[1],'attachment');
  await button(elements.selections.children[1],'Up').fire('click');
  assert.equal(field(elements.selections.children[0],'Item key').value,'attachment');
  await button(elements.catalog,'Add attachment 1/1.2').fire('click');assert.equal(elements.selections.children.length,2);
  if (process.argv[3]) {
    // Save unfinished, ordered objection/question cards through actual HTTP.
    await input(field(elements.selections.children[0],'Item key'),'');
    await input(field(elements.selections.children[0],'Pending decision prompt'),'');
    await input(field(elements.selections.children[1],'Review kind'),'question');
    await input(field(elements.selections.children[1],'Curator note'),'');
    await elements['save-draft'].fire('click');assert.equal(elements['draft-download'].hidden,false);
    const saved=await(await fetch(new URL(elements['draft-download'].href,base))).text();
    const snapshot=JSON.parse(saved);assert.equal(snapshot.selections[0].key,'');assert.equal(snapshot.selections[0].decisions[0].prompt,'');
    assert.equal(snapshot.selections[1].kind,'question');assert.equal(snapshot.selections[1].note,'');
    // Entirely new production controller and server, no shared session state.
    const freshBase=process.argv[3]; let hold=false,releaseOpen,holdSave=false,releaseSave;
    const freshFetch=async(path,options)=>{const response=await fetch(new URL(path,freshBase),options);if(path==='draft/open'&&hold)await new Promise(resolve=>{releaseOpen=resolve;});if(path==='draft/save'&&holdSave)await new Promise(resolve=>{releaseSave=resolve;});return response;};
    elements=Object.fromEntries(ids.map(x=>[x,new Element(x)]));document=makeDocument(elements);
    await mount(document,freshFetch).ready;
    const file=(text,size=Buffer.byteLength(text))=>{elements['draft-file'].files=[{size,text:async()=>text}];};
    file(saved);await elements['open-draft'].fire('click');assert.equal(elements.selections.children.length,2);
    assert.equal(field(elements.selections.children[0],'Item key').value,'');
    assert.equal(field(elements.selections.children[0],'Pending decision prompt').value,'');
    assert.equal(field(elements.selections.children[0],'Named human reviewer').value,'ops');
    assert.equal(field(elements.selections.children[1],'Review kind').value,'question');
    assert.equal(field(elements.selections.children[1],'Curator note').value,'');
    assert.equal(elements.attachments.disabled,false);assert.equal(elements.download.hidden,true);
    assert.ok(!walk(elements.catalog).some(n=>n.textContent.includes('Rollback')));
    await input(field(elements.selections.children[0],'Item key'),'attachment');
    await input(field(elements.selections.children[0],'Pending decision prompt'),'Confirm rollback?');
    await input(field(elements.selections.children[1],'Curator note'),'Finished after reopening');
    await elements.preview.fire('click');assert.equal(elements.download.hidden,true);assert.match(elements.status.textContent,/inspect text attachments explicitly/);
    await elements.attachments.fire('click');await elements.preview.fire('click');assert.equal(elements.download.hidden,false);
    const oldHref=elements.download.href;
    let bundle=await(await fetch(new URL(oldHref,freshBase))).json();assert.equal(bundle.decision_receipts.length,0);
    assert.match(bundle.entries.at(-2).body,/Rollback/);assert.match(bundle.entries.at(-1).body,/UNSELECTED BODY/);
    // Rejected imports preserve editable work and revoke both browser/server links.
    for (const bad of ['{',JSON.stringify({...snapshot,agenda_digest:'sha256:other'}),'{}']) {
      file(bad);await elements['open-draft'].fire('click');assert.equal(field(elements.selections.children[0],'Item key').value,'attachment');
      assert.match(elements.status.textContent,/current edits kept/);assert.equal(elements.download.hidden,true);
    }
    assert.equal((await fetch(new URL(oldHref,freshBase))).status,404);
    file(saved,1024*1024+1);await elements['open-draft'].fire('click');assert.match(elements.status.textContent,/1 MiB/);
    // An older reopen response cannot overwrite edits made while it was pending.
    hold=true;file(saved);const opening=elements['open-draft'].fire('click');while(!releaseOpen)await new Promise(r=>setTimeout(r,5));
    await input(field(elements.selections.children[0],'Curator note'),'Newer edit must survive');releaseOpen();await opening;hold=false;
    assert.equal(field(elements.selections.children[0],'Curator note').value,'Newer edit must survive');
    assert.equal(field(elements.selections.children[0],'Item key').value,'attachment');assert.equal(elements.download.hidden,true);
    await elements['save-draft'].fire('click');assert.equal(elements['draft-download'].hidden,false);
    const second=await(await fetch(new URL(elements['draft-download'].href,freshBase))).json();assert.equal(second.selections[0].note,'Newer edit must survive');
    holdSave=true;const saving=elements['save-draft'].fire('click');while(!releaseSave)await new Promise(r=>setTimeout(r,5));
    await input(field(elements.selections.children[0],'Curator note'),'Changed while saving');releaseSave();await saving;
    assert.equal(elements['draft-download'].hidden,true);assert.equal(field(elements.selections.children[0],'Curator note').value,'Changed while saving');
    // Repeated compatible open restores the same ordered cards, never appends.
    holdSave=false;file(saved);await elements['open-draft'].fire('click');file(saved);await elements['open-draft'].fire('click');
    assert.equal(elements.selections.children.length,2);assert.equal(field(elements.selections.children[0],'Item key').value,'');
    console.log('PASS production DOM fresh controller draft save/download/reopen, blank edits, identity failures, fresh consent, native pending bundle, failed and racing opens');
    return;
  }
  await elements.preview.fire('click');assert.equal(elements.download.hidden,false);assert.match(elements.status.textContent,/pending/);
  let downloaded=await (await fetch(new URL(elements.download.href,base))).json();
  assert.equal(downloaded.decision_receipts.length,0);assert.match(downloaded.entries.at(-2).body,/Rollback/);assert.match(downloaded.entries.at(-1).body,/UNSELECTED BODY/);
  await input(field(elements.selections.children[0],'Curator note'),'Changed note');assert.equal(elements.download.hidden,true);
  await button(elements.selections.children[0],'Remove decision request').fire('click');
  await elements.preview.fire('click');assert.equal(elements.download.hidden,true);assert.match(elements.status.textContent,/objection requires/);
  await fill(elements.selections.children[0],'attachment');
  delay=true;const pending=elements.preview.fire('click');while(!release)await new Promise(r=>setTimeout(r,5));
  await input(field(elements.selections.children[0],'Curator note'),'Changed while composing');release();await pending;assert.equal(elements.download.hidden,true);
  delay=false;await button(elements.selections.children[0],'Remove item').fire('click');assert.equal(elements.selections.children.length,1);
  await elements.preview.fire('click');assert.equal(elements.download.hidden,false);
  downloaded=await(await fetch(new URL(elements.download.href,base))).json();assert.equal(downloaded.entries.length,2);
  console.log('PASS production DOM add/edit/reorder/remove, named requests, mixed selection, exact native download, errors and stale-response invalidation');
})().catch(error=>{console.error(error);process.exitCode=1;});
