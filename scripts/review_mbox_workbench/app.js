/* Production DOM controller. No mail content is interpreted as markup. */
(function (root) {
  'use strict';
  function mount(document, fetcher) {
    const byId = id => document.getElementById(id);
    let state, selections = [], revision = 0, busy = false;
    function el(tag, text) { const node = document.createElement(tag); if (text !== undefined) node.textContent = text; return node; }
    function clear(node) { node.replaceChildren(); }
    function status(text) { byId('status').textContent = text; }
    function invalidate() { revision++; for (const id of ['download','draft-download']) { byId(id).hidden = true; byId(id).removeAttribute('href'); } byId('result').textContent = ''; status('Changes need a new preview.'); }
    async function api(path, value) {
      const response = await fetcher(path, value === undefined ? {cache: 'no-store'} : {method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify(value)});
      const result = await response.json(); if (!response.ok) throw new Error(result.error || 'Request failed'); return result;
    }
    function button(text, fn) { const node = el('button', text); node.type = 'button'; node.addEventListener('click', fn); return node; }
    function field(parent, title, value, changed, options) {
      const label = el('label', title), input = el(options ? 'select' : title.includes('note') || title.includes('prompt') ? 'textarea' : 'input');
      if (options) for (const [id, name] of options) { const option = el('option', name); option.value = id; input.append(option); }
      input.value = value; input.addEventListener('input', () => { changed(input.value); invalidate(); }); label.append(input); parent.append(label); return input;
    }
    function renderSelections() {
      clear(byId('selections'));
      selections.forEach((choice, index) => {
        const card = el('section'); const locator = choice.attachment || choice.body;
        card.append(el('h3', (index + 1) + '. Message ' + choice.ordinal + ', MIME ' + locator.part + ' (' + locator.mode + ')'));
        field(card, 'Item key', choice.key, value => { choice.key = value; });
        field(card, 'Review kind', choice.kind, value => { choice.kind = value; }, ['question','objection','proposal'].map(x => [x,x]));
        field(card, 'Curator author', choice.author, value => { choice.author = value; }, [['','Choose a curator'],...state.agenda.participants.map(p => [p.participant_id, p.display_name + ' (' + p.participant_id + ', ' + p.participant_kind + ')'])]);
        field(card, 'Curator note', choice.note, value => { choice.note = value; });
        const humans = state.agenda.participants.filter(p => p.participant_kind === 'human').map(p => [p.participant_id,p.display_name + ' (' + p.participant_id + ')']);
        choice.decisions.forEach((decision, d) => {
          const row = el('article'); field(row, 'Named human reviewer', decision.reviewer, value => { decision.reviewer = value; }, [['','Choose a human reviewer'],...humans]);
          field(row, 'Pending decision prompt', decision.prompt, value => { decision.prompt = value; });
          row.append(button('Remove decision request', () => { choice.decisions.splice(d,1); invalidate(); renderSelections(); })); card.append(row);
        });
        const add = button('Add pending decision request', () => { choice.decisions.push({reviewer:humans[0][0],prompt:''}); invalidate(); renderSelections(); }); add.disabled = !humans.length; card.append(add);
        for (const [title, delta] of [['Up', -1], ['Down', 1]]) { const move = button(title, () => { const other = index + delta; [selections[index],selections[other]] = [selections[other],selections[index]]; invalidate(); renderSelections(); }); move.disabled = index + delta < 0 || index + delta >= selections.length; card.append(move); }
        card.append(button('Remove item', () => { selections.splice(index,1); invalidate(); renderSelections(); })); byId('selections').append(card);
      });
    }
    function addChoice(message, part, attachment) {
      const name = attachment ? 'attachment' : 'body';
      if (selections.some(s => s.ordinal === message.ordinal && s[name] && s[name].part === part.part)) { status('That exact message/part is already selected.'); return; }
      selections.push({ordinal:message.ordinal, key:'',kind:'question',author:state.agenda.participants[0].participant_id,note:'',decisions:[],[name]:{part:part.part,mode:attachment?'plain-text-attachment':'plain-text'}});
      invalidate(); renderSelections();
    }
    function renderCatalog() {
      clear(byId('catalog'));
      for (const message of state.catalog.messages) {
        const card = el('article'); card.append(el('h3','Message ' + message.ordinal),el('p',message.message_digest + ' • bytes ' + message.source_start_byte + '–' + message.source_end_byte));
        card.append(el('pre',message.headers.map(h => h.name + ': ' + h.decoded_value).join('\n')));
        for (const part of message.parts) {
          const detail = el('details'); detail.append(el('summary','MIME ' + part.part + ' • ' + part.content_type + (part.filename ? ' • ' + part.filename : '')));
          detail.append(el('pre',part.text === undefined ? part.omission || 'Opaque part' : part.text));
          if (part.body_available && part.content_type === 'text/plain') detail.append(button('Add message body ' + message.ordinal + '/' + part.part, () => addChoice(message,part,false)));
          if (part.attachment_available) detail.append(button('Add attachment ' + message.ordinal + '/' + part.part, () => addChoice(message,part,true)));
          card.append(detail);
        }
        byId('catalog').append(card);
      }
    }
    byId('attachments').addEventListener('click', async () => {
      try { state = await api('attachments',{inspect:true}); renderCatalog(); byId('attachments').disabled = true; status('Supported text attachments inspected. Nothing has been selected automatically.'); }
      catch (error) { status(error.message); }
    });
    byId('preview').addEventListener('click', async () => {
      if (busy || !state) return; busy = true; invalidate(); const requested = revision; byId('preview').disabled = true; status('Validating with the existing native composer…');
      try {
        const result = await api('preview',{mailbox_digest:state.catalog.mailbox_digest,selections});
        if (revision === requested) { byId('result').textContent = result.preview; byId('download').href = 'bundle/' + result.bundle_digest; byId('download').hidden = false; status(result.status); }
      } catch (error) { if (revision === requested) status(error.message); }
      finally { busy = false; byId('preview').disabled = false; }
    });
    byId('save-draft').addEventListener('click', async () => {
      if (busy || !state) return; busy = true; invalidate(); const requested = revision;
      try {
        const result = await api('draft/save',{format:'moonchat.mailbox-review-draft.v1',agenda_digest:state.agenda_digest,mailbox_digest:state.catalog.mailbox_digest,selections});
        if (revision === requested) { byId('draft-download').href = 'draft/' + result.draft_digest; byId('draft-download').hidden = false; status(result.status); }
      } catch (error) { if (revision === requested) status(error.message); }
      finally { busy = false; }
    });
    byId('open-draft').addEventListener('click', async () => {
      if (busy || !state) return;
      const file = byId('draft-file').files && byId('draft-file').files[0];
      if (!file) { status('Choose a saved draft file first.'); return; }
      busy = true; invalidate(); const requested = revision;
      try {
        // Revoke prior links even if reading/parsing this file fails locally.
        await api('invalidate',{});
        if (file.size > 1024 * 1024) throw new Error('Draft exceeds 1 MiB.');
        const text = await file.text();
        // JSON parsing happens on the server: duplicate keys and unsupported
        // semantics are rejected by the existing strict JSON loader.
        const response = await fetcher('draft/open',{method:'POST',headers:{'Content-Type':'application/json'},body:text});
        const result = await response.json();
        if (!response.ok) throw new Error(result.error || 'Draft could not be reopened.');
        if (revision === requested) { selections = result.selections; renderSelections(); status(result.status); }
      } catch (error) { if (revision === requested) status('Draft not opened; current edits kept. ' + error.message); }
      finally { busy = false; byId('draft-file').value = ''; }
    });
    const ready = api('catalog').then(value => {
      state = value; byId('snapshot').textContent = 'Mailbox ' + state.catalog.mailbox_digest + ' • Agenda ' + state.agenda_digest + ' • ' + state.catalog.message_count + ' messages • frozen at launch';
      for (const p of state.agenda.participants) byId('participants').append(el('li',p.display_name + ' (' + p.participant_id + ', ' + p.participant_kind + ')'));
      byId('agenda').textContent = JSON.stringify(state.agenda.items,null,2); renderCatalog(); status('Choose exact evidence to begin.');
    }).catch(error => { status(error.message); });
    return {ready};
  }
  if (typeof module !== 'undefined' && module.exports) module.exports = {mount};
  if (root.document) mount(root.document,root.fetch.bind(root));
})(typeof window === 'undefined' ? globalThis : window);
