import 'dart:convert';

import 'resource_spec.dart';

/// README.md for a full-stack (frontend + FastAPI backend) project.
String fullStackReadme({
  required String title,
  required String kindLabel,
  required List<ResourceSpec> resources,
  String? description,
}) {
  final endpoints = StringBuffer();
  for (final r in resources) {
    endpoints
      ..writeln('| `GET` | `/api/${r.route}` | List ${r.label.toLowerCase()} |')
      ..writeln('| `POST` | `/api/${r.route}` | Add one |')
      ..writeln('| `GET` | `/api/${r.route}/{id}` | Get one |')
      ..writeln('| `PATCH` | `/api/${r.route}/{id}` | Change some fields |')
      ..writeln('| `DELETE` | `/api/${r.route}/{id}` | Delete one |');
  }
  final first = resources.first;
  final curlBody = jsonEncode(first.samplePayload);
  return '''
# $title

$kindLabel built with **AI Connect Africa**.${description == null || description.isEmpty ? '' : '\n\n$description'}

| Part | What it is |
|------|------------|
| `frontend/` | The pages people see: HTML, CSS and JavaScript. No framework, no build step. |
| `backend/` | A Python API (FastAPI) that stores data in a SQLite database file. |
| `DEPLOY.md` | How to put it online for free. |

## Open it in VS Code

1. Copy this whole folder to your computer (from the app: **Projects → ⋮ → Export**).
2. In VS Code: **File → Open Folder…** and pick this folder.
3. Install the recommended **Python** extension when VS Code asks.

## Run it on your computer

You need [Python 3.10 or newer](https://www.python.org/downloads/).

```bash
cd backend
python -m venv .venv
# Windows:            .venv\\Scripts\\activate
# macOS / Linux:      source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload
```

Now open:

- <http://127.0.0.1:8000> — the $kindLabel
- <http://127.0.0.1:8000/docs> — every API endpoint, which you can try in the browser

In VS Code you can also press **F5** and choose **Run backend**.

Just want to look at the pages? Open `frontend/index.html` in a browser. It runs in
*offline mode*: data is saved in that browser only, until the backend is running.

## API

| Method | Path | What it does |
|--------|------|--------------|
| `GET` | `/api/health` | Is the server up? |
$endpoints
On your own computer the API needs no key. On a server it asks for one
(`X-API-Key`, or `X-Admin-Token` for contact messages) — see **Your keys**
in `DEPLOY.md`.

Try it:

```bash
curl -X POST http://127.0.0.1:8000/api/${first.route} -H "Content-Type: application/json" -d '$curlBody'
```

## Test it

```bash
cd backend
pytest
```

## Change it

| To change… | Edit |
|------------|------|
| Text, pictures, layout | `frontend/index.html` |
| Colours and fonts | `frontend/css/styles.css` |
| What the buttons do | `frontend/js/main.js` |
| What data is stored | `backend/app/models.py` and `backend/app/schemas.py` |
| The API | `backend/app/routes/` |

After changing `models.py`, delete `backend/app.db` so the tables are made again
(or learn [Alembic](https://alembic.sqlalchemy.org) for real migrations).
''';
}

/// DEPLOY.md — free / open hosting options, written to be read offline.
String deployGuide({required String title, required String slug}) => '''
# Put "$title" online

Your project has two parts. You can put them online **together** (one server
runs both) or **separately** (pages on a static host, API on a server host).
All the services below have a free plan. Sign-up needs internet, so do this
part at a school lab, cyber café or anywhere you have a connection.

---

## Step 0 — Put the code on GitHub (needed by most hosts)

1. Make a free account at <https://github.com>.
2. In VS Code open this folder, then open the **Source Control** panel
   (the branch icon on the left) and click **Publish to GitHub**.
   Choose *public* if you want GitHub Pages for free.

   Or from a terminal inside this folder:

   ```bash
   git init
   git add .
   git commit -m "First version of $title"
   git branch -M main
   git remote add origin https://github.com/YOUR-NAME/$slug.git
   git push -u origin main
   ```

---

## Your keys (keep your data private)

The API refuses anyone without a key, so strangers cannot read or delete
your data:

| Key | Protects | Who needs it |
|-----|----------|--------------|
| `API_KEY` | An app's data (`/api/...`) | You and anyone you let use the app — the app asks for it once |
| `ADMIN_TOKEN` | Messages sent through a website's contact form | Only you (visitors can still *send* messages) |

- On your own computer no key is needed.
- On **Render** they are made for you: open your service → **Environment**
  to see them.
- Anywhere else, make one with
  `python -c "import secrets; print(secrets.token_urlsafe(24))"` and set it
  as an environment variable.
- To read contact messages, open `/docs` on your live site, pick
  `GET /api/contact`, **Try it out**, and paste your `ADMIN_TOKEN` into
  `x-admin-token`.

---

## Option A — Everything on one server (easiest)

### Render (render.com)

This folder already has a `render.yaml`.

1. Sign in to <https://render.com> with GitHub.
2. **New → Blueprint** → pick your repository → **Apply**.
3. Wait for the build, then open the `.onrender.com` link. The site and the
   API are both there (`/docs` shows the API).

> The free plan sleeps after 15 minutes without visitors; the first visit
> after that takes about a minute. The SQLite file is reset when the server
> restarts — for data that must last, add a Render PostgreSQL database and
> set `DATABASE_URL` (see `backend/.env.example`).

### Railway (railway.app)

1. **New Project → Deploy from GitHub repo** → pick your repository.
2. It finds the `Dockerfile` and builds it. Under **Settings → Networking**
   click **Generate Domain**.

### Any server with Docker (Fly.io, a school server, a VPS)

```bash
docker build -t $slug .
docker run -p 8000:8000 $slug
```

On Fly.io: install `flyctl`, then `fly launch` in this folder and accept the
Dockerfile it finds.

### PythonAnywhere (pythonanywhere.com)

1. Upload the folder (or `git clone` it in a Bash console).
2. In a console: `cd $slug/backend && pip install --user -r requirements.txt`.
3. **Web → Add a new web app → Manual configuration**, then follow their
   "Deploying FastAPI / ASGI" help page, pointing it at `app.main:app`.

---

## Option B — Pages and API on different hosts

Use this when you only need the pages online (the data then stays in each
visitor's browser), or when you want a fast static host for the pages.

### 1. Put the pages online

Any of these serve the `frontend/` folder:

- **GitHub Pages** — repository **Settings → Pages → Deploy from a branch**,
  branch `main`, folder `/` … then open
  `https://YOUR-NAME.github.io/$slug/frontend/`.
  (Or copy the contents of `frontend/` into a `docs/` folder and pick `/docs`.)
- **Netlify Drop** — open <https://app.netlify.com/drop> and drag the
  `frontend` folder onto the page. Done — no account needed to try it.
- **Cloudflare Pages** — **Create → Pages → Connect to Git**, set the build
  output directory to `frontend`, no build command.
- **Vercel** — **Add New → Project**, import the repository, set the root
  directory to `frontend`, framework *Other*.

### 2. Put the API online

Deploy the backend with Render, Railway or PythonAnywhere as in Option A.

### 3. Connect them

1. Open `frontend/js/config.js` and set your API address:

   ```js
   window.OTIC_API_BASE = "https://$slug.onrender.com";
   ```

2. On the API host, set the environment variable `CORS_ORIGINS` to your pages
   address (for example `https://YOUR-NAME.github.io`) so browsers are allowed
   to call it.
3. Push the change; the static host updates by itself.

---

## Before you share it

- [ ] `pytest` passes in `backend/`.
- [ ] `API_KEY` and `ADMIN_TOKEN` are set on the server (never written in the code).
- [ ] `CORS_ORIGINS` lists only your own site.
- [ ] No passwords or keys are written in the code (use environment variables).
- [ ] You tested adding, changing and deleting data on the live site.
''';

/// DEPLOY.md for a frontend-only project (Web Dev Lab).
String staticDeployGuide({required String title, required String slug}) => '''
# Put "$title" online

These are plain HTML, CSS and JavaScript files, so any static host works.
All have a free plan; signing up needs internet.

- **Netlify Drop** — open <https://app.netlify.com/drop> and drag this
  folder onto the page.
- **GitHub Pages** — push the folder to a public GitHub repository
  (VS Code: **Source Control → Publish to GitHub**), then **Settings → Pages
  → Deploy from a branch → main / (root)**. Your site appears at
  `https://YOUR-NAME.github.io/$slug/`.
- **Cloudflare Pages** / **Vercel** — import the repository; no build
  command, output directory `/`.
''';

/// README.md for a Python Lab project.
String pythonReadme({required String title, required String mainFile}) => '''
# $title

A Python program made in the AI Connect Africa **Python Lab**.

## Run it

You need [Python 3.10 or newer](https://www.python.org/downloads/).

```bash
python $mainFile
```

In VS Code: open this folder, open `$mainFile` and press **F5** (or the ▶ button).

## Share it

- Put it on GitHub (VS Code: **Source Control → Publish to GitHub**).
- Run it online for free at <https://www.pythonanywhere.com> (upload the file,
  open a Bash console, `python $mainFile`) or on <https://replit.com>.
''';

const kPythonGitignore = '''
__pycache__/
*.pyc
.venv/
venv/
.env
*.db
.pytest_cache/
''';

const kFullStackGitignore = '''
# Python
__pycache__/
*.pyc
.venv/
venv/
.pytest_cache/

# Local settings and data - never commit these
.env
backend/app.db
*.db

# Editors / OS
.DS_Store
Thumbs.db
''';

const kDockerfile = '''
# One container serves the API and the frontend together.
FROM python:3.12-slim

WORKDIR /srv
COPY backend/requirements.txt backend/requirements.txt
RUN pip install --no-cache-dir -r backend/requirements.txt

COPY . .
WORKDIR /srv/backend

ENV PORT=8000
EXPOSE 8000
CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port \${PORT}"]
''';

const kDockerignore = '''
.git
.venv
**/__pycache__
**/.pytest_cache
backend/app.db
.env
''';

String renderYaml(String slug) => '''
# Render Blueprint - render.com → New → Blueprint → pick this repository.
services:
  - type: web
    name: $slug
    runtime: python
    rootDir: backend
    buildCommand: pip install -r requirements.txt
    startCommand: uvicorn app.main:app --host 0.0.0.0 --port \$PORT
    healthCheckPath: /api/health
    envVars:
      - key: PYTHON_VERSION
        value: 3.12.4
      - key: CORS_ORIGINS
        value: "*"
      # Random secret keys, made by Render. Find them under
      # Environment in the dashboard (see DEPLOY.md, "Your keys").
      - key: API_KEY
        generateValue: true
      - key: ADMIN_TOKEN
        generateValue: true
''';

const kVsCodeExtensions = '''
{
  "recommendations": ["ms-python.python", "ms-python.vscode-pylance"]
}
''';

const kVsCodeLaunch = '''
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Run backend",
      "type": "debugpy",
      "request": "launch",
      "module": "uvicorn",
      "args": ["app.main:app", "--reload"],
      "cwd": "\${workspaceFolder}/backend",
      "jinja": true
    }
  ]
}
''';

const kVsCodePythonLaunch = '''
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Run main.py",
      "type": "debugpy",
      "request": "launch",
      "program": "\${workspaceFolder}/main.py",
      "console": "integratedTerminal"
    }
  ]
}
''';
