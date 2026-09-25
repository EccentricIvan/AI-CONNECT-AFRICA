import 'dart:convert';

import 'resource_spec.dart';

/// Result of moving a single-file HTML page's inline CSS/JS into files.
class SplitHtml {
  const SplitHtml({required this.html, required this.css, required this.js});
  final String html;
  final String css;
  final String js;
}

final _styleRe = RegExp(r'<style\b[^>]*>([\s\S]*?)</style>', caseSensitive: false);
final _scriptRe = RegExp(
  r'<script\b([^>]*)>([\s\S]*?)</script>',
  caseSensitive: false,
);

/// Moves inline `<style>` blocks to `css/styles.css` and inline classic
/// `<script>` blocks to `js/main.js`, so the project reads like a real
/// codebase in VS Code.
///
/// Scripts with a `src`, JSON-LD / templates (non-JS `type`) and modules are
/// left in place. The combined script is loaded with `defer` at the end of
/// `<body>`: deferred scripts run after parsing and before
/// `DOMContentLoaded`, so both "run at end of body" and "wait for
/// DOMContentLoaded" scripts keep working.
SplitHtml splitInlineAssets(String html) {
  final css = StringBuffer();
  final js = StringBuffer();

  var firstStyle = true;
  var out = html.replaceAllMapped(_styleRe, (m) {
    final body = m.group(1)!.trim();
    if (body.isNotEmpty) css.writeln(body);
    if (!firstStyle) return '';
    firstStyle = false;
    return '<link rel="stylesheet" href="css/styles.css">';
  });

  out = out.replaceAllMapped(_scriptRe, (m) {
    final attrs = m.group(1)!;
    final body = m.group(2)!;
    final lower = attrs.toLowerCase();
    if (lower.contains('src=')) return m.group(0)!;
    final type = RegExp(r'''type\s*=\s*["']?([^"'\s>]+)''').firstMatch(lower)?.group(1);
    final isClassicJs =
        type == null || type == 'text/javascript' || type == 'application/javascript';
    if (!isClassicJs) return m.group(0)!;
    if (body.trim().isNotEmpty) {
      js
        ..writeln(body.trim())
        ..writeln();
    }
    return '';
  });

  return SplitHtml(html: out, css: css.toString(), js: js.toString());
}

/// Inserts [snippet] just before `</head>` (or at the top when missing).
String injectIntoHead(String html, String snippet) {
  final i = html.toLowerCase().lastIndexOf('</head>');
  if (i < 0) return '$snippet\n$html';
  return '${html.substring(0, i)}$snippet\n${html.substring(i)}';
}

/// Inserts [snippet] just before `</body>` (or at the end when missing).
String injectBeforeBodyEnd(String html, String snippet) {
  final i = html.toLowerCase().lastIndexOf('</body>');
  if (i < 0) return '$html\n$snippet';
  return '${html.substring(0, i)}$snippet\n${html.substring(i)}';
}

const kConfigJs = '''
// Where the backend API lives.
//
// Leave this empty when the backend serves this folder
// (cd backend && uvicorn app.main:app) - the usual setup.
//
// If you host the frontend on its own (GitHub Pages, Netlify, Cloudflare
// Pages) and the backend somewhere else (Render, Railway...), put the
// backend's address here, e.g. "https://my-app-api.onrender.com".
window.OTIC_API_BASE = window.OTIC_API_BASE || "";
''';

/// Tiny fetch client with an offline fallback.
///
/// When no server answers (the page opened straight from disk, or the
/// backend is down) the same calls read and write `localStorage`, so the
/// page still works as a demo. `OticApi.online` tells the UI which mode it
/// is in.
const kApiJs = r'''
(function () {
  "use strict";
  var base = (window.OTIC_API_BASE || "").replace(/\/$/, "");
  var mayHaveServer = base !== "" || /^https?:$/.test(location.protocol);

  function localKey(resource) { return "otic-data:" + resource; }
  function readLocal(resource) {
    try { return JSON.parse(localStorage.getItem(localKey(resource)) || "[]"); }
    catch (e) { return []; }
  }
  function writeLocal(resource, items) {
    try { localStorage.setItem(localKey(resource), JSON.stringify(items)); }
    catch (e) { /* storage full or blocked: keep going in memory */ }
  }

  // The server may be protected with an API_KEY (see backend/.env.example).
  // The key is asked for once and kept in this browser only.
  var KEY_STORE = "otic-api-key";
  function savedKey() {
    try { return window.OTIC_API_KEY || localStorage.getItem(KEY_STORE) || ""; }
    catch (e) { return window.OTIC_API_KEY || ""; }
  }

  function request(method, path, body, retried) {
    var options = { method: method, headers: {} };
    var key = savedKey();
    if (key) options.headers["X-API-Key"] = key;
    if (body !== undefined) {
      options.headers["Content-Type"] = "application/json";
      options.body = JSON.stringify(body);
    }
    return fetch(base + path, options).then(function (res) {
      if (res.status === 401 && !retried && !path.startsWith("/api/contact")) {
        var entered = window.prompt("This app's data is protected. Enter its access key (API_KEY):", "");
        if (entered) {
          try { localStorage.setItem(KEY_STORE, entered.trim()); } catch (e) { window.OTIC_API_KEY = entered.trim(); }
          return request(method, path, body, true);
        }
      }
      if (!res.ok) {
        return res.text().then(function (text) {
          var err = new Error(method + " " + path + " failed (" + res.status + ")");
          err.status = res.status;
          err.detail = text;
          throw err;
        });
      }
      return res.status === 204 ? null : res.json();
    });
  }

  // A TypeError from fetch means "no server reachable" - fall back to local
  // storage. An HTTP error (validation, 404) is a real answer: rethrow it.
  function withFallback(remote, local) {
    if (!mayHaveServer) { api.online = false; return Promise.resolve(local()); }
    return remote().then(function (value) {
      api.online = true;
      return value;
    }, function (err) {
      if (err instanceof TypeError) { api.online = false; return local(); }
      throw err;
    });
  }

  var api = {
    online: mayHaveServer,
    list: function (resource) {
      return withFallback(
        function () { return request("GET", "/api/" + resource); },
        function () { return readLocal(resource); }
      );
    },
    create: function (resource, data) {
      return withFallback(
        function () { return request("POST", "/api/" + resource, data); },
        function () {
          var items = readLocal(resource);
          var item = Object.assign({}, data, { id: Date.now(), created_at: new Date().toISOString() });
          items.unshift(item);
          writeLocal(resource, items);
          return item;
        }
      );
    },
    update: function (resource, id, changes) {
      return withFallback(
        function () { return request("PATCH", "/api/" + resource + "/" + id, changes); },
        function () {
          var items = readLocal(resource);
          var updated = null;
          items = items.map(function (it) {
            if (it.id !== id) return it;
            updated = Object.assign({}, it, changes);
            return updated;
          });
          writeLocal(resource, items);
          return updated;
        }
      );
    },
    remove: function (resource, id) {
      return withFallback(
        function () { return request("DELETE", "/api/" + resource + "/" + id); },
        function () {
          writeLocal(resource, readLocal(resource).filter(function (it) { return it.id !== id; }));
          return null;
        }
      );
    }
  };

  window.OticApi = api;
})();
''';

/// Renders a working create / list / edit / delete panel for every resource
/// in `window.OTIC_RESOURCES`, wired to [kApiJs].
const kDataPanelJs = r'''
(function () {
  "use strict";
  var resources = window.OTIC_RESOURCES || [];
  if (!resources.length || !window.OticApi) return;

  function el(tag, attrs, children) {
    var node = document.createElement(tag);
    Object.keys(attrs || {}).forEach(function (k) {
      if (k === "text") node.textContent = attrs[k];
      else if (k === "className") node.className = attrs[k];
      else node.setAttribute(k, attrs[k]);
    });
    (children || []).forEach(function (c) { node.appendChild(c); });
    return node;
  }

  function inputFor(field) {
    var id = "otic-" + field.resource + "-" + field.name;
    var input;
    if (field.type === "text") input = el("textarea", { id: id, rows: "2" });
    else if (field.type === "boolean") input = el("input", { id: id, type: "checkbox" });
    else if (field.type === "integer") input = el("input", { id: id, type: "number", step: "1" });
    else if (field.type === "decimal") input = el("input", { id: id, type: "number", step: "any" });
    else input = el("input", { id: id, type: "text", maxlength: "200" });
    if (field.required && field.type !== "boolean") input.required = true;
    input.name = field.name;
    var label = el("label", { "for": id, text: field.label });
    return { wrap: el("div", { className: "otic-field otic-field-" + field.type }, [label, input]), input: input };
  }

  function valueOf(field, input) {
    if (field.type === "boolean") return input.checked;
    if (field.type === "integer") return input.value === "" ? 0 : parseInt(input.value, 10);
    if (field.type === "decimal") return input.value === "" ? 0 : parseFloat(input.value);
    return input.value.trim();
  }

  function describe(resource, item) {
    var title = resource.fields[0];
    var rest = resource.fields.slice(1).filter(function (f) { return f.type !== "boolean"; });
    var parts = rest.map(function (f) {
      var v = item[f.name];
      return v === undefined || v === null || v === "" ? null : f.label + ": " + v;
    }).filter(Boolean);
    return { title: String(item[title.name] == null ? "" : item[title.name]), detail: parts.join(" · ") };
  }

  function mountResource(container, resource) {
    var status = el("p", { className: "otic-status", role: "status" });
    var list = el("ul", { className: "otic-list" });
    var form = el("form", { className: "otic-form", novalidate: "" });
    var inputs = resource.fields.map(function (f) {
      var made = inputFor(Object.assign({ resource: resource.route }, f));
      form.appendChild(made.wrap);
      return made.input;
    });
    form.appendChild(el("button", { type: "submit", className: "otic-btn", text: "Add" }));

    function setStatus(text, isError) {
      status.textContent = text;
      status.className = "otic-status" + (isError ? " otic-status-error" : "");
    }

    function render(items) {
      list.innerHTML = "";
      if (!items.length) {
        list.appendChild(el("li", { className: "otic-empty", text: "Nothing here yet - add the first one above." }));
      }
      items.forEach(function (item) {
        var info = describe(resource, item);
        var row = el("li", { className: "otic-row" });
        resource.fields.filter(function (f) { return f.type === "boolean"; }).forEach(function (f) {
          var box = el("input", { type: "checkbox", title: f.label, "aria-label": f.label });
          box.checked = !!item[f.name];
          box.addEventListener("change", function () {
            var change = {}; change[f.name] = box.checked;
            OticApi.update(resource.route, item.id, change).then(refresh, showError);
          });
          row.appendChild(box);
        });
        var text = el("div", { className: "otic-row-text" }, [
          el("strong", { text: info.title }),
          el("span", { text: info.detail })
        ]);
        row.appendChild(text);
        var del = el("button", { type: "button", className: "otic-btn otic-btn-ghost", text: "Delete", "aria-label": "Delete " + info.title });
        del.addEventListener("click", function () {
          OticApi.remove(resource.route, item.id).then(refresh, showError);
        });
        row.appendChild(del);
        list.appendChild(row);
      });
      setStatus(OticApi.online ? "Saved on the server." : "Offline mode - saved on this device only.");
    }

    function showError(err) {
      setStatus(err && err.status === 422 ? "Please fill in the required fields." : "Something went wrong: " + (err && err.message), true);
    }

    function refresh() { return OticApi.list(resource.route).then(render, showError); }

    form.addEventListener("submit", function (ev) {
      ev.preventDefault();
      var data = {};
      var missing = false;
      resource.fields.forEach(function (f, i) {
        data[f.name] = valueOf(f, inputs[i]);
        if (f.required && f.type !== "boolean" && (data[f.name] === "" || Number.isNaN(data[f.name]))) missing = true;
      });
      if (missing) { setStatus("Please fill in the required fields.", true); return; }
      OticApi.create(resource.route, data).then(function () { form.reset(); return refresh(); }, showError);
    });

    container.appendChild(el("section", { className: "otic-resource", "aria-label": resource.label }, [
      el("h2", { text: resource.label }), form, status, list
    ]));
    refresh();
  }

  function start() {
    var host = document.getElementById("otic-data");
    if (!host) {
      host = el("section", { id: "otic-data", className: "otic-data" });
      document.body.appendChild(host);
    }
    host.appendChild(el("p", { className: "otic-data-title", text: "App data · saved by the backend" }));
    resources.forEach(function (r) { mountResource(host, r); });
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", start);
  else start();
})();
''';

const kDataPanelCss = '''
/* Data panel added by the project scaffold - talks to the backend API. */
/* Many app screens centre a phone frame with a flex row on <body>; wrapping
   lets the panel sit on its own full-width row underneath instead. */
body { flex-wrap: wrap; }
.otic-data { flex: 0 0 100%; width: 100%; max-width: 960px; margin: 32px auto; padding: 0 16px; box-sizing: border-box; font-family: Inter, system-ui, sans-serif; color: #111827; }
.otic-data-title { font-size: .8rem; letter-spacing: .08em; text-transform: uppercase; color: #6b7280; margin: 0 0 12px; }
.otic-resource { background: #fff; border: 1px solid #e5e7eb; border-radius: 16px; padding: 20px; margin-bottom: 20px; box-shadow: 0 4px 16px rgba(15, 23, 42, .06); }
.otic-resource h2 { margin: 0 0 12px; font-size: 1.25rem; }
.otic-form { display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); gap: 12px; align-items: end; }
.otic-field { display: flex; flex-direction: column; gap: 4px; font-size: .875rem; }
.otic-field input, .otic-field textarea { padding: 10px 12px; border: 1px solid #d1d5db; border-radius: 10px; font: inherit; }
.otic-field-boolean { flex-direction: row; align-items: center; gap: 8px; }
.otic-btn { padding: 10px 16px; border: 0; border-radius: 10px; background: var(--primary, #2563eb); color: #fff; font-weight: 600; cursor: pointer; transition: opacity .15s; }
.otic-btn:hover { opacity: .9; }
.otic-btn-ghost { background: transparent; color: #b91c1c; }
.otic-status { font-size: .8rem; color: #6b7280; margin: 10px 0; }
.otic-status-error { color: #b91c1c; }
.otic-list { list-style: none; margin: 0; padding: 0; }
.otic-row { display: flex; align-items: center; gap: 12px; padding: 10px 0; border-top: 1px solid #f3f4f6; }
.otic-row-text { flex: 1; display: flex; flex-direction: column; }
.otic-row-text span { color: #6b7280; font-size: .8rem; }
.otic-empty { color: #9ca3af; padding: 10px 0; }
''';

/// Sends every contact-style form on the page to `POST /api/contact`.
const kContactJs = r'''
(function () {
  "use strict";
  function pick(form, names) {
    for (var i = 0; i < names.length; i++) {
      var f = form.querySelector('[name="' + names[i] + '"], #' + names[i]);
      if (f && f.value) return f.value.trim();
    }
    return "";
  }

  function wire(form) {
    if (form.dataset.oticSkip !== undefined) return;
    form.addEventListener("submit", function (ev) {
      ev.preventDefault();
      var emailInput = form.querySelector('input[type="email"]');
      var text = form.querySelector("textarea");
      var payload = {
        name: pick(form, ["name", "fullname", "full_name"]) || (form.querySelector('input[type="text"]') || {}).value || "",
        email: pick(form, ["email"]) || (emailInput ? emailInput.value.trim() : ""),
        phone: pick(form, ["phone", "tel"]),
        message: pick(form, ["message", "msg"]) || (text ? text.value.trim() : "")
      };
      var note = form.querySelector(".otic-form-note");
      if (!note) {
        note = document.createElement("p");
        note.className = "otic-form-note";
        note.setAttribute("role", "status");
        form.appendChild(note);
      }
      if (!payload.name || !payload.message) {
        note.textContent = "Please add your name and a message.";
        return;
      }
      window.OticApi.create("contact", payload).then(function () {
        form.reset();
        note.textContent = window.OticApi.online
          ? "Thank you! Your message was sent."
          : "Saved on this device - it will not reach us until the site runs with its backend.";
      }, function () {
        note.textContent = "Sorry, the message could not be sent. Please try again.";
      });
    });
  }

  function start() {
    Array.prototype.forEach.call(document.querySelectorAll("form"), function (form) {
      if (form.querySelector("textarea") || form.querySelector('input[type="email"]')) wire(form);
    });
  }
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", start);
  else start();
})();
''';

/// `window.OTIC_RESOURCES = [...]` for the data panel.
String resourcesJs(List<ResourceSpec> resources) {
  final list = [
    for (final r in resources)
      {
        'route': r.route,
        'label': r.label,
        'fields': [
          for (final f in r.fields)
            {
              'name': f.name,
              'label': f.displayLabel,
              'type': f.type.name,
              'required': f.required,
            },
        ],
      },
  ];
  return '// The backend resources this page manages (see backend/app/models.py).\n'
      'window.OTIC_RESOURCES = ${const JsonEncoder.withIndent('  ').convert(list)};\n';
}

/// Web app manifest so the app can be installed to a phone's home screen.
String webManifest({required String title, required String themeColor}) =>
    const JsonEncoder.withIndent('  ').convert({
      'name': title,
      'short_name': title.length > 12 ? title.substring(0, 12) : title,
      'start_url': './index.html',
      'display': 'standalone',
      'background_color': '#ffffff',
      'theme_color': themeColor,
      'icons': [
        {'src': 'icon.svg', 'sizes': 'any', 'type': 'image/svg+xml'},
      ],
    });

String appIconSvg(String themeColor, String title) {
  final letter = title.trim().isEmpty ? 'A' : title.trim()[0].toUpperCase();
  final safe = const HtmlEscape().convert(letter);
  return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">'
      '<rect width="512" height="512" rx="112" fill="$themeColor"/>'
      '<text x="50%" y="54%" font-family="system-ui, sans-serif" font-size="280" '
      'font-weight="700" fill="#fff" text-anchor="middle" dominant-baseline="middle">$safe</text>'
      '</svg>\n';
}

/// Service worker: caches the app shell so it opens without a connection.
/// API calls always go to the network (the data panel falls back itself).
const kServiceWorkerJs = r'''
const CACHE = "app-shell-v1";
const SHELL = ["./", "./index.html", "./css/styles.css", "./css/data.css",
  "./js/config.js", "./js/api.js", "./js/resources.js", "./js/data.js", "./js/main.js",
  "./manifest.webmanifest", "./icon.svg"];

self.addEventListener("install", (event) => {
  event.waitUntil(caches.open(CACHE).then((c) => c.addAll(SHELL)).then(() => self.skipWaiting()));
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", (event) => {
  const url = new URL(event.request.url);
  if (event.request.method !== "GET" || url.pathname.startsWith("/api/")) return;
  event.respondWith(caches.match(event.request).then((hit) => hit || fetch(event.request)));
});
''';

const kRegisterServiceWorker = '''
<script>
  if ("serviceWorker" in navigator && /^https?:\$/.test(location.protocol)) {
    window.addEventListener("load", function () { navigator.serviceWorker.register("sw.js"); });
  }
</script>''';
