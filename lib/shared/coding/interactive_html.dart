/// Ensures generated HTML is a complete, clickable offline document.
///
/// When the 1.5B coder truncates mid-`<script>` or omits handlers, we close
/// tags and merge a self-contained interactive runtime so buttons/tabs/forms
/// still work inside the in-app WebView.
String ensureInteractiveHtmlDocument(String raw) {
  var html = _stripFences(raw).trim();
  if (html.isEmpty) {
    return kInteractiveBaseTemplate
        .replaceAll('{{TITLE}}', 'Interactive Preview')
        .replaceAll(
          '{{BODY}}',
          '<section class="card"><h2>Offline preview</h2>'
          '<p>Build again or edit Source, then Apply Changes &amp; Preview.</p></section>',
        );
  }

  final wasTruncated = _scriptLooksTruncated(html);
  html = _repairTruncatedDocument(html);

  final hasStyle = RegExp(r'<style[\s>]', caseSensitive: false).hasMatch(html);
  final hasScript =
      RegExp(r'<script[\s>]', caseSensitive: false).hasMatch(html);
  final interactiveSignals = RegExp(
    r'addEventListener|onclick\s*=|onchange\s*=|localStorage|querySelector|'
    r'getElementById\s*\(|OTIC_INTERACTIVE_RUNTIME',
    caseSensitive: false,
  ).hasMatch(html);

  if (!hasStyle || !hasScript || !interactiveSignals || wasTruncated) {
    html = _mergeIntoInteractiveShell(html);
  }

  if (!RegExp(r'</html\s*>', caseSensitive: false).hasMatch(html)) {
    html = '$html\n</html>';
  }
  return html;
}

String _stripFences(String raw) {
  var s = raw.trim();
  final fenced = RegExp(
    r'```(?:html|HTML|htm)?\s*([\s\S]*?)```',
    multiLine: true,
  ).firstMatch(s);
  if (fenced != null) s = (fenced.group(1) ?? '').trim();
  s = s.replaceAll(
    RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false),
    '',
  );
  return s.trim();
}

bool htmlLooksInteractive(String html) {
  return RegExp(
    r'addEventListener|onclick\s*=|localStorage|OTIC_INTERACTIVE_RUNTIME',
    caseSensitive: false,
  ).hasMatch(html);
}

bool _scriptLooksTruncated(String html) {
  final opens =
      RegExp(r'<script\b', caseSensitive: false).allMatches(html).length;
  final closes =
      RegExp(r'</script\s*>', caseSensitive: false).allMatches(html).length;
  if (opens > closes) return true;
  // Open brace imbalance inside the last script is a common truncate symptom.
  final lastOpen = html.toLowerCase().lastIndexOf('<script');
  if (lastOpen < 0) return false;
  final slice = html.substring(lastOpen);
  if (!RegExp(r'</script\s*>', caseSensitive: false).hasMatch(slice)) {
    return true;
  }
  final body = RegExp(
    r'<script[^>]*>([\s\S]*?)</script\s*>',
    caseSensitive: false,
  ).allMatches(html);
  if (body.isEmpty) return opens > 0;
  final last = body.last.group(1) ?? '';
  final opensBrace = '{'.allMatches(last).length;
  final closesBrace = '}'.allMatches(last).length;
  return opensBrace > closesBrace + 1;
}

String _repairTruncatedDocument(String html) {
  var out = html;

  // Close dangling style / script before inventing outer wrappers.
  final styleOpen =
      RegExp(r'<style\b', caseSensitive: false).allMatches(out).length;
  final styleClose =
      RegExp(r'</style\s*>', caseSensitive: false).allMatches(out).length;
  if (styleOpen > styleClose) {
    out = '$out\n</style>';
  }

  final scriptOpen =
      RegExp(r'<script\b', caseSensitive: false).allMatches(out).length;
  final scriptClose =
      RegExp(r'</script\s*>', caseSensitive: false).allMatches(out).length;
  if (scriptOpen > scriptClose) {
    // Soft-close truncated JS so the browser can still parse the DOM.
    out = '$out\n}catch(e){}\n</script>';
  }

  if (!RegExp(r'<!DOCTYPE', caseSensitive: false).hasMatch(out) &&
      RegExp(r'<html', caseSensitive: false).hasMatch(out)) {
    out = '<!DOCTYPE html>\n$out';
  }

  if (RegExp(r'<body[\s>]', caseSensitive: false).hasMatch(out) &&
      !RegExp(r'</body\s*>', caseSensitive: false).hasMatch(out)) {
    out = '$out\n</body>';
  }
  if (RegExp(r'<html', caseSensitive: false).hasMatch(out) &&
      !RegExp(r'</html\s*>', caseSensitive: false).hasMatch(out)) {
    out = '$out\n</html>';
  }
  return out;
}

String _extractBodyInner(String html) {
  final m = RegExp(
    r'<body[^>]*>([\s\S]*?)</body>',
    caseSensitive: false,
  ).firstMatch(html);
  if (m != null) return m.group(1)!.trim();
  // No body — drop head-ish tags and keep remainder as content.
  return html
      .replaceAll(
        RegExp(r'<!DOCTYPE[^>]*>', caseSensitive: false),
        '',
      )
      .replaceAll(
        RegExp(r'</?html[^>]*>', caseSensitive: false),
        '',
      )
      .replaceAll(
        RegExp(r'<head[\s\S]*?</head>', caseSensitive: false),
        '',
      )
      .replaceAll(
        RegExp(r'<script[\s\S]*?</script>', caseSensitive: false),
        '',
      )
      .trim();
}

String _mergeIntoInteractiveShell(String partial) {
  final body = _extractBodyInner(partial);
  final titleMatch = RegExp(
    r'<title[^>]*>([\s\S]*?)</title>',
    caseSensitive: false,
  ).firstMatch(partial);
  final title = (titleMatch?.group(1) ?? 'Interactive Preview').trim();
  final safeBody = body.isEmpty
      ? '<section class="bento"><h2>Your build</h2>'
          '<p>Partial output recovered — try the interactive controls below.</p>'
          '</section>'
      : body;

  return kInteractiveBaseTemplate
      .replaceAll('{{TITLE}}', _escapeHtml(title))
      .replaceAll('{{BODY}}', safeBody);
}

String _escapeHtml(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

/// Premium interactive offline shell used when the model truncates or omits JS.
const kInteractiveBaseTemplate = '''
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>{{TITLE}}</title>
<style>
:root{
  --bg:#0b1220;--surface:rgba(255,255,255,.08);--card:rgba(255,255,255,.1);
  --text:#e2e8f0;--muted:#94a3b8;--primary:#38bdf8;--accent:#a78bfa;
  --ok:#34d399;--radius:18px;--shadow:0 18px 50px rgba(0,0,0,.35);
  --font:Inter,system-ui,-apple-system,Segoe UI,Roboto,Arial,sans-serif;
}
*{box-sizing:border-box}
html,body{margin:0;min-height:100%;font-family:var(--font);background:
  radial-gradient(1200px 600px at 10% -10%,#1e3a5f 0%,transparent 55%),
  radial-gradient(900px 500px at 100% 0%,#3b0764 0%,transparent 50%),
  var(--bg);color:var(--text)}
a{color:var(--primary)}
.wrap{max-width:1100px;margin:0 auto;padding:24px}
.nav{display:flex;gap:10px;flex-wrap:wrap;align-items:center;justify-content:space-between;
  padding:14px 18px;border:1px solid rgba(255,255,255,.12);border-radius:999px;
  background:var(--surface);backdrop-filter:blur(14px);box-shadow:var(--shadow);margin-bottom:22px}
.brand{font-weight:800;letter-spacing:.2px}
.tabs{display:flex;gap:8px;flex-wrap:wrap}
.tab,.btn{border:0;cursor:pointer;border-radius:999px;padding:10px 16px;font-weight:700;
  transition:transform .15s ease,background .2s ease,box-shadow .2s ease;color:#0b1220;background:var(--primary)}
.tab{background:rgba(255,255,255,.12);color:var(--text)}
.tab.active,.btn:hover,.tab:hover{transform:translateY(-1px);box-shadow:0 8px 24px rgba(56,189,248,.35)}
.tab.active{background:linear-gradient(135deg,var(--primary),var(--accent));color:#0b1220}
.hero{padding:28px;border-radius:var(--radius);background:linear-gradient(135deg,rgba(56,189,248,.18),rgba(167,139,250,.16));
  border:1px solid rgba(255,255,255,.14);box-shadow:var(--shadow);margin-bottom:18px}
.hero h1{margin:0 0 8px;font-size:clamp(28px,4vw,42px)}
.hero p{margin:0;color:var(--muted);line-height:1.55}
.bento{display:grid;grid-template-columns:repeat(12,1fr);gap:14px;margin:18px 0}
.card{grid-column:span 12;padding:18px;border-radius:var(--radius);background:var(--card);
  border:1px solid rgba(255,255,255,.12);backdrop-filter:blur(12px);box-shadow:var(--shadow)}
@media(min-width:720px){.card.span-6{grid-column:span 6}.card.span-4{grid-column:span 4}.card.span-8{grid-column:span 8}}
.card h2,.card h3{margin:0 0 10px}
label{display:block;font-size:12px;color:var(--muted);margin:10px 0 6px}
input,select,textarea{width:100%;padding:12px 14px;border-radius:12px;border:1px solid rgba(255,255,255,.16);
  background:rgba(15,23,42,.55);color:var(--text);outline:none}
input:focus,select:focus,textarea:focus{border-color:var(--primary);box-shadow:0 0 0 3px rgba(56,189,248,.2)}
.row{display:flex;gap:10px;flex-wrap:wrap;align-items:center}
.pill{display:inline-flex;align-items:center;gap:6px;padding:6px 10px;border-radius:999px;
  background:rgba(52,211,153,.15);color:var(--ok);font-size:12px;font-weight:700}
.panel{display:none}.panel.active{display:block}
.muted{color:var(--muted)}
.total{font-size:28px;font-weight:800}
.list{list-style:none;padding:0;margin:0}.list li{padding:10px 0;border-bottom:1px solid rgba(255,255,255,.08);
  display:flex;justify-content:space-between;gap:12px}
footer{margin-top:28px;color:var(--muted);font-size:13px;text-align:center}
#student-content img{max-width:100%;border-radius:12px}
</style>
</head>
<body>
<div class="wrap">
  <nav class="nav">
    <div class="brand">{{TITLE}}</div>
    <div class="tabs" id="main-tabs">
      <button class="tab active" data-tab="home" type="button">Home</button>
      <button class="tab" data-tab="studio" type="button">Studio</button>
      <button class="tab" data-tab="checkout" type="button">Checkout</button>
      <button class="tab" data-tab="quiz" type="button">Quiz</button>
    </div>
  </nav>

  <section class="panel active" id="panel-home">
    <div class="hero">
      <h1>Interactive offline preview</h1>
      <p>Buttons, tabs, forms, and totals below are wired with vanilla JavaScript — no CDN. Tap around to test.</p>
      <div class="row" style="margin-top:16px">
        <button class="btn" id="cta-go" type="button">Open Studio</button>
        <span class="pill" id="live-pill">Ready</span>
      </div>
    </div>
    <div id="student-content" class="bento">
      <article class="card span-8">{{BODY}}</article>
      <article class="card span-4">
        <h3>Quick actions</h3>
        <p class="muted">These controls always work, even if the model cut off early.</p>
        <div class="row" style="margin-top:12px">
          <button class="btn" id="btn-like" type="button">Like +1</button>
          <span class="pill">Likes: <strong id="like-count">0</strong></span>
        </div>
      </article>
    </div>
  </section>

  <section class="panel" id="panel-studio">
    <div class="bento">
      <article class="card span-6">
        <h2>Notes</h2>
        <label for="note">Add a note</label>
        <input id="note" placeholder="Type and save…"/>
        <div class="row" style="margin-top:12px">
          <button class="btn" id="btn-save" type="button">Save note</button>
          <button class="tab" id="btn-clear" type="button">Clear</button>
        </div>
        <ul class="list" id="note-list"></ul>
      </article>
      <article class="card span-6">
        <h2>Theme lab</h2>
        <p class="muted">Toggle accent glow stored in localStorage.</p>
        <button class="btn" id="btn-theme" type="button">Toggle accent</button>
        <p class="muted" id="theme-status" style="margin-top:12px"></p>
      </article>
    </div>
  </section>

  <section class="panel" id="panel-checkout">
    <div class="bento">
      <article class="card span-8">
        <h2>Checkout calculator</h2>
        <label for="qty">Quantity</label>
        <input id="qty" type="number" min="1" value="2"/>
        <label for="price">Unit price</label>
        <input id="price" type="number" min="0" step="0.01" value="15"/>
        <label for="tax">Tax %</label>
        <input id="tax" type="number" min="0" step="0.1" value="5"/>
        <p class="muted" style="margin-top:14px">Total updates as you type.</p>
      </article>
      <article class="card span-4">
        <h3>Live total</h3>
        <div class="total" id="checkout-total">0.00</div>
        <button class="btn" id="btn-checkout" type="button" style="margin-top:14px">Confirm order</button>
        <p class="muted" id="checkout-msg" style="margin-top:10px"></p>
      </article>
    </div>
  </section>

  <section class="panel" id="panel-quiz">
    <div class="card">
      <h2>Quick quiz</h2>
      <p id="quiz-q">2 + 3 = ?</p>
      <div class="row" id="quiz-options"></div>
      <p class="muted" id="quiz-score" style="margin-top:12px">Score: 0</p>
    </div>
  </section>

  <footer>OTIC interactive runtime · fully offline · localStorage enabled</footer>
</div>
<script>
/* OTIC_INTERACTIVE_RUNTIME */
(function(){
  const \$ = (s, r=document) => r.querySelector(s);
  const \$\$ = (s, r=document) => Array.from(r.querySelectorAll(s));
  const store = {
    get(k, d){ try { const v = localStorage.getItem(k); return v==null?d:JSON.parse(v);} catch(e){ return d; } },
    set(k, v){ try { localStorage.setItem(k, JSON.stringify(v)); } catch(e){} }
  };

  function showTab(id){
    \$\$('.tab').forEach(t => t.classList.toggle('active', t.dataset.tab===id));
    \$\$('.panel').forEach(p => p.classList.toggle('active', p.id==='panel-'+id));
    store.set('otic_tab', id);
    const pill = \$('#live-pill'); if(pill) pill.textContent = 'Tab: '+id;
  }

  \$\$('#main-tabs .tab').forEach(btn => btn.addEventListener('click', () => showTab(btn.dataset.tab)));
  const cta = \$('#cta-go'); if(cta) cta.addEventListener('click', () => showTab('studio'));

  let likes = store.get('otic_likes', 0);
  const likeEl = \$('#like-count');
  if(likeEl) likeEl.textContent = likes;
  const likeBtn = \$('#btn-like');
  if(likeBtn) likeBtn.addEventListener('click', () => {
    likes += 1; store.set('otic_likes', likes);
    if(likeEl) likeEl.textContent = likes;
  });

  function renderNotes(){
    const list = \$('#note-list'); if(!list) return;
    const notes = store.get('otic_notes', []);
    list.innerHTML = notes.map((n,i)=>'<li><span>'+n+'</span><button data-i="'+i+'" class="tab" type="button">Delete</button></li>').join('');
    list.querySelectorAll('button').forEach(b => b.addEventListener('click', () => {
      const notes2 = store.get('otic_notes', []);
      notes2.splice(+b.dataset.i,1); store.set('otic_notes', notes2); renderNotes();
    }));
  }
  const save = \$('#btn-save');
  if(save) save.addEventListener('click', () => {
    const input = \$('#note'); const val = (input&&input.value||'').trim(); if(!val) return;
    const notes = store.get('otic_notes', []); notes.unshift(val); store.set('otic_notes', notes);
    if(input) input.value=''; renderNotes();
  });
  const clear = \$('#btn-clear');
  if(clear) clear.addEventListener('click', () => { store.set('otic_notes', []); renderNotes(); });
  renderNotes();

  let accentOn = store.get('otic_accent', true);
  function paintTheme(){
    document.documentElement.style.setProperty('--primary', accentOn ? '#38bdf8' : '#f472b6');
    const st = \$('#theme-status'); if(st) st.textContent = accentOn ? 'Accent: sky' : 'Accent: pink';
  }
  paintTheme();
  const themeBtn = \$('#btn-theme');
  if(themeBtn) themeBtn.addEventListener('click', () => { accentOn=!accentOn; store.set('otic_accent', accentOn); paintTheme(); });

  function calc(){
    const qty = parseFloat((\$('#qty')||{}).value)||0;
    const price = parseFloat((\$('#price')||{}).value)||0;
    const tax = parseFloat((\$('#tax')||{}).value)||0;
    const total = qty*price*(1+tax/100);
    const el = \$('#checkout-total'); if(el) el.textContent = total.toFixed(2);
    return total;
  }
  ['qty','price','tax'].forEach(id => { const el=\$('#'+id); if(el) el.addEventListener('input', calc); });
  calc();
  const checkout = \$('#btn-checkout');
  if(checkout) checkout.addEventListener('click', () => {
    const msg = \$('#checkout-msg');
    if(msg) msg.textContent = 'Order confirmed for '+calc().toFixed(2)+' (saved offline).';
    store.set('otic_last_total', calc());
  });

  const quiz = [
    {q:'2 + 3 = ?', opts:['4','5','6'], a:1},
    {q:'Capital of Kenya?', opts:['Nairobi','Kampala','Kigali'], a:0}
  ];
  let qi=0, score=store.get('otic_quiz',0);
  function renderQuiz(){
    const item = quiz[qi%quiz.length];
    const q = \$('#quiz-q'); if(q) q.textContent = item.q;
    const box = \$('#quiz-options'); if(!box) return;
    box.innerHTML = item.opts.map((o,i)=>'<button class="btn" data-i="'+i+'" type="button">'+o+'</button>').join('');
    box.querySelectorAll('button').forEach(b => b.addEventListener('click', () => {
      if(+b.dataset.i===item.a) score++;
      store.set('otic_quiz', score);
      const s = \$('#quiz-score'); if(s) s.textContent = 'Score: '+score;
      qi++; renderQuiz();
    }));
    const s = \$('#quiz-score'); if(s) s.textContent = 'Score: '+score;
  }
  renderQuiz();

  // Wire common student markup if present (buttons without handlers).
  \$\$('button:not([data-tab]):not([id])').forEach((btn, idx) => {
    if(btn.onclick || btn.getAttribute('onclick')) return;
    btn.addEventListener('click', () => {
      const pill = \$('#live-pill');
      if(pill) pill.textContent = 'Clicked control #'+(idx+1);
      btn.style.transform='scale(.98)';
      setTimeout(()=>btn.style.transform='',120);
    });
  });

  showTab(store.get('otic_tab','home'));
})();
</script>
</body>
</html>
''';
