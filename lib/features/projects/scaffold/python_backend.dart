import 'dart:convert';

import 'resource_spec.dart';

/// Writes a runnable FastAPI + SQLAlchemy + SQLite backend for [resources].
///
/// Everything here is deterministic text. `tools/verify_scaffolds.ps1`
/// installs the generated `requirements.txt` and runs the generated pytest
/// suite against sample projects — run it whenever this file changes.
///
/// Returned paths are relative to the project root (`backend/...`).
Map<String, String> buildPythonBackend({
  required String title,
  required List<ResourceSpec> resources,
  Map<String, Object?> siteContent = const {},
  bool publicSubmissions = false,
}) {
  // Websites: visitors may submit (POST) without a key; reading, changing
  // and deleting what they sent needs ADMIN_TOKEN. Apps: every data call
  // needs API_KEY. With the variable unset only this computer is allowed,
  // so a deploy is never accidentally open.
  final guard = publicSubmissions ? 'require_admin' : 'require_api_key';
  final files = <String, String>{
    'backend/requirements.txt': _requirements,
    'backend/pytest.ini': _pytestIni,
    'backend/.env.example': _envExample,
    'backend/app/__init__.py': '',
    'backend/app/database.py': _database,
    'backend/app/security.py': _security,
    'backend/app/models.py': _models(resources),
    'backend/app/schemas.py': _schemas(resources),
    'backend/app/routes/__init__.py': '',
    'backend/app/main.py': _main(title, resources, withSite: siteContent.isNotEmpty),
    'backend/tests/__init__.py': '',
    'backend/tests/conftest.py': _conftest,
    'backend/tests/test_api.py': _tests(resources,
        withSite: siteContent.isNotEmpty, publicSubmissions: publicSubmissions),
  };
  for (final r in resources) {
    files['backend/app/routes/${r.route}.py'] =
        _routes(r, guard: guard, publicCreate: publicSubmissions);
  }
  if (siteContent.isNotEmpty) {
    files['backend/app/site.json'] =
        const JsonEncoder.withIndent('  ').convert(siteContent);
  }
  return files;
}

const _requirements = '''
fastapi>=0.110,<1.0
uvicorn[standard]>=0.29,<1.0
sqlalchemy>=2.0,<3.0
pydantic>=2.6,<3.0
python-dotenv>=1.0,<2.0
# Testing
pytest>=8.0,<9.0
httpx>=0.27,<1.0
''';

const _pytestIni = '''
[pytest]
pythonpath = .
testpaths = tests
''';

const _envExample = '''
# Copy this file to .env and change what you need.
# SQLite file in the backend folder by default. On a host with a managed
# PostgreSQL, set e.g. postgresql+psycopg://user:pass@host/db and add
# psycopg[binary] to requirements.txt.
DATABASE_URL=sqlite:///./app.db

# Keys that protect the data. With a key unset, only requests from this
# same computer are allowed (handy while building). ALWAYS set them on a
# real server - render.yaml generates them for you on Render.
#   API_KEY      - needed to read or change the app's data (apps)
#   ADMIN_TOKEN  - needed to read contact-form messages (websites)
# Make one with:  python -c "import secrets; print(secrets.token_urlsafe(24))"
API_KEY=
ADMIN_TOKEN=

# Comma-separated list of sites allowed to call this API from a browser.
# "*" allows any site - fine while learning, narrow it before going live,
# e.g. https://yourname.github.io
CORS_ORIGINS=*
''';

const _database = '''
"""Database connection shared by every route."""
import os

from dotenv import load_dotenv
from sqlalchemy import create_engine
from sqlalchemy.orm import DeclarativeBase, sessionmaker

load_dotenv()

DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///./app.db")

# SQLite needs this flag so FastAPI's worker threads can share a connection.
_connect_args = {"check_same_thread": False} if DATABASE_URL.startswith("sqlite") else {}

engine = create_engine(DATABASE_URL, connect_args=_connect_args)
SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False)


class Base(DeclarativeBase):
    pass


def get_db():
    """Yields one database session per request and always closes it."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
''';

const _security = '''
"""Keys that protect the API's data.

X-API-Key must match API_KEY to use the app's data endpoints, and
X-Admin-Token must match ADMIN_TOKEN to read contact-form messages.
When a key is not set, only requests from this computer are allowed, so a
server deployed without keys refuses everyone instead of exposing data.
"""
import os
import secrets
from typing import Optional

from fastapi import Header, HTTPException, Request, status

_LOCAL_HOSTS = {"127.0.0.1", "::1", "localhost"}


def _check(request: Request, sent: Optional[str], env_name: str) -> None:
    expected = os.getenv(env_name, "")
    if expected:
        if sent and secrets.compare_digest(sent, expected):
            return
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"Missing or wrong key. Send the {env_name} value in the request header.",
        )
    host = request.client.host if request.client else ""
    if host in _LOCAL_HOSTS:
        return
    raise HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail=f"Set {env_name} on the server to allow access from other computers.",
    )


def require_api_key(request: Request, x_api_key: Optional[str] = Header(default=None)) -> None:
    _check(request, x_api_key, "API_KEY")


def require_admin(request: Request, x_admin_token: Optional[str] = Header(default=None)) -> None:
    _check(request, x_admin_token, "ADMIN_TOKEN")
''';

String _sqlType(FieldType t) => switch (t) {
      FieldType.string => 'String(200)',
      FieldType.text => 'Text',
      FieldType.integer => 'Integer',
      FieldType.decimal => 'Float',
      FieldType.boolean => 'Boolean',
    };

String _pyType(FieldType t) => switch (t) {
      FieldType.string || FieldType.text => 'str',
      FieldType.integer => 'int',
      FieldType.decimal => 'float',
      FieldType.boolean => 'bool',
    };

String _pyDefault(FieldType t) => switch (t) {
      FieldType.string || FieldType.text => '""',
      FieldType.integer => '0',
      FieldType.decimal => '0.0',
      FieldType.boolean => 'False',
    };

String _models(List<ResourceSpec> resources) {
  final buf = StringBuffer()
    ..writeln('"""Database tables."""')
    ..writeln('from datetime import datetime')
    ..writeln()
    ..writeln(
        'from sqlalchemy import Boolean, DateTime, Float, Integer, String, Text, func')
    ..writeln('from sqlalchemy.orm import Mapped, mapped_column')
    ..writeln()
    ..writeln('from .database import Base');
  for (final r in resources) {
    buf
      ..writeln()
      ..writeln()
      ..writeln('class ${r.className}(Base):')
      ..writeln('    __tablename__ = "${r.route}"')
      ..writeln()
      ..writeln(
          '    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)');
    for (final f in r.fields) {
      buf.writeln('    ${f.name}: Mapped[${_pyType(f.type)}] = '
          'mapped_column(${_sqlType(f.type)}, default=${_pyDefault(f.type)})');
    }
    buf
      ..writeln('    created_at: Mapped[datetime] = mapped_column(')
      ..writeln('        DateTime, server_default=func.now()')
      ..writeln('    )');
  }
  return buf.toString();
}

String _schemas(List<ResourceSpec> resources) {
  final buf = StringBuffer()
    ..writeln('"""Request and response shapes (validated by Pydantic)."""')
    ..writeln('from datetime import datetime')
    ..writeln('from typing import Optional')
    ..writeln()
    ..writeln('from pydantic import BaseModel, ConfigDict, Field');
  for (final r in resources) {
    final c = r.className;
    buf
      ..writeln()
      ..writeln()
      ..writeln('class ${c}Base(BaseModel):');
    for (final f in r.fields) {
      final t = _pyType(f.type);
      final isText = f.type == FieldType.string || f.type == FieldType.text;
      final maxLen = f.type == FieldType.string ? ', max_length=200' : '';
      if (f.required) {
        final min = isText ? 'min_length=1$maxLen' : '';
        buf.writeln('    ${f.name}: $t = Field(${min.isEmpty ? '...' : '..., $min'})');
      } else {
        buf.writeln(
            '    ${f.name}: $t = Field(default=${_pyDefault(f.type)}$maxLen)');
      }
    }
    buf
      ..writeln()
      ..writeln()
      ..writeln('class ${c}Create(${c}Base):')
      ..writeln('    pass')
      ..writeln()
      ..writeln()
      ..writeln('class ${c}Update(BaseModel):')
      ..writeln('    """Every field optional: send only what changes."""')
      ..writeln();
    for (final f in r.fields) {
      final maxLen = f.type == FieldType.string ? ', max_length=200' : '';
      buf.writeln('    ${f.name}: Optional[${_pyType(f.type)}] = '
          'Field(default=None$maxLen)');
    }
    buf
      ..writeln()
      ..writeln()
      ..writeln('class ${c}Read(${c}Base):')
      ..writeln('    model_config = ConfigDict(from_attributes=True)')
      ..writeln()
      ..writeln('    id: int')
      ..writeln('    created_at: Optional[datetime] = None');
  }
  return buf.toString();
}

String _routes(ResourceSpec r, {required String guard, required bool publicCreate}) {
  final c = r.className;
  final one = r.singular;
  // Public create: only POST is open, every other route carries the guard.
  final routerDeps = publicCreate ? '' : ', dependencies=[Depends($guard)]';
  final perRoute = publicCreate ? ', dependencies=[Depends($guard)]' : '';
  final doc = publicCreate
      ? 'Anyone can POST; the other routes need the X-Admin-Token header.'
      : 'Every route needs the X-API-Key header.';
  return '''
"""CRUD endpoints for ${r.label.toLowerCase()} at /api/${r.route}.

$doc See app/security.py.
"""
from fastapi import APIRouter, Depends, HTTPException, Response, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from .. import models, schemas
from ..database import get_db
from ..security import $guard

router = APIRouter(prefix="/api/${r.route}", tags=["${r.route}"]$routerDeps)


def _get_or_404(db: Session, item_id: int) -> models.$c:
    item = db.get(models.$c, item_id)
    if item is None:
        raise HTTPException(status_code=404, detail="$c not found")
    return item


@router.get("", response_model=list[schemas.${c}Read]$perRoute)
def list_${r.route}(db: Session = Depends(get_db)):
    return db.scalars(select(models.$c).order_by(models.$c.id.desc())).all()


@router.post("", response_model=schemas.${c}Read, status_code=status.HTTP_201_CREATED)
def create_$one(payload: schemas.${c}Create, db: Session = Depends(get_db)):
    item = models.$c(**payload.model_dump())
    db.add(item)
    db.commit()
    db.refresh(item)
    return item


@router.get("/{item_id}", response_model=schemas.${c}Read$perRoute)
def get_$one(item_id: int, db: Session = Depends(get_db)):
    return _get_or_404(db, item_id)


@router.patch("/{item_id}", response_model=schemas.${c}Read$perRoute)
def update_$one(item_id: int, payload: schemas.${c}Update, db: Session = Depends(get_db)):
    item = _get_or_404(db, item_id)
    for key, value in payload.model_dump(exclude_unset=True).items():
        setattr(item, key, value)
    db.commit()
    db.refresh(item)
    return item


@router.delete("/{item_id}", status_code=status.HTTP_204_NO_CONTENT$perRoute)
def delete_$one(item_id: int, db: Session = Depends(get_db)):
    item = _get_or_404(db, item_id)
    db.delete(item)
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)
''';
}

String _main(String title, List<ResourceSpec> resources, {required bool withSite}) {
  final imports = resources.map((r) => r.route).join(', ');
  final includes =
      resources.map((r) => 'app.include_router(${r.route}.router)').join('\n');
  final site = withSite
      ? '''


@app.get("/api/site")
def site_content():
    """The text this website was built with (name, tagline, contact...)."""
    return json.loads((Path(__file__).parent / "site.json").read_text(encoding="utf-8"))'''
      : '';
  return '''
"""$title - API server.

Run from the backend folder:
    uvicorn app.main:app --reload
Then open http://127.0.0.1:8000 (the site) or http://127.0.0.1:8000/docs (the API).
"""
${withSite ? 'import json\n' : ''}import os
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from .database import Base, engine
from .routes import $imports

FRONTEND_DIR = Path(__file__).resolve().parents[2] / "frontend"


@asynccontextmanager
async def lifespan(_app: FastAPI):
    # Creates any missing tables on start-up. For schema changes on a live
    # database, move to Alembic migrations.
    Base.metadata.create_all(bind=engine)
    yield


app = FastAPI(title=${jsonEncode(title)}, version="1.0.0", lifespan=lifespan)

_origins = [o.strip() for o in os.getenv("CORS_ORIGINS", "*").split(",") if o.strip()]
app.add_middleware(
    CORSMiddleware,
    allow_origins=_origins,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/api/health")
def health():
    return {"status": "ok"}$site


$includes

# Serve the frontend from the same server, so one deploy runs everything.
# Mounted last: /api routes above always win.
if FRONTEND_DIR.is_dir():
    app.mount("/", StaticFiles(directory=FRONTEND_DIR, html=True), name="frontend")
''';
}

const _conftest = '''
"""Points the app at a throwaway database for every test run."""
import os
import tempfile

_tmp = tempfile.mkdtemp()
os.environ["DATABASE_URL"] = "sqlite:///" + os.path.join(_tmp, "test.db").replace("\\\\", "/")
os.environ["API_KEY"] = "test-api-key"
os.environ["ADMIN_TOKEN"] = "test-admin-token"

import pytest  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

from app.main import app  # noqa: E402


@pytest.fixture()
def client():
    with TestClient(app) as c:
        yield c
''';

String _pyLiteral(Object v) {
  if (v is bool) return v ? 'True' : 'False';
  if (v is num) return '$v';
  return jsonEncode(v);
}

String _tests(List<ResourceSpec> resources,
    {required bool withSite, required bool publicSubmissions}) {
  final header = publicSubmissions
      ? '{"X-Admin-Token": "test-admin-token"}'
      : '{"X-API-Key": "test-api-key"}';
  final createAuth = publicSubmissions ? '' : ', headers=AUTH';
  final buf = StringBuffer()
    ..writeln('"""API tests. Run from the backend folder:  pytest"""')
    ..writeln()
    ..writeln('AUTH = $header')
    ..writeln()
    ..writeln()
    ..writeln('def test_health(client):')
    ..writeln('    res = client.get("/api/health")')
    ..writeln('    assert res.status_code == 200')
    ..writeln('    assert res.json() == {"status": "ok"}');
  if (withSite) {
    buf
      ..writeln()
      ..writeln()
      ..writeln('def test_site_content(client):')
      ..writeln('    res = client.get("/api/site")')
      ..writeln('    assert res.status_code == 200')
      ..writeln('    assert isinstance(res.json(), dict)');
  }
  for (final r in resources) {
    final payload = r.samplePayload.entries
        .map((e) => '"${e.key}": ${_pyLiteral(e.value)}')
        .join(', ');
    final first = r.fields.first;
    final changed = switch (first.type) {
      FieldType.string || FieldType.text => '"Changed"',
      FieldType.integer => '42',
      FieldType.decimal => '99.5',
      FieldType.boolean => 'True',
    };
    final required = r.fields.where((f) => f.required).toList();
    buf
      ..writeln()
      ..writeln()
      ..writeln('def payload_for_${r.route}():')
      ..writeln('    return {$payload}')
      ..writeln()
      ..writeln()
      ..writeln('def test_${r.route}_crud(client):')
      ..writeln('    payload = payload_for_${r.route}()')
      ..writeln('    created = client.post("/api/${r.route}", json=payload$createAuth)')
      ..writeln('    assert created.status_code == 201, created.text')
      ..writeln('    item = created.json()')
      ..writeln('    for key, value in payload.items():')
      ..writeln('        assert item[key] == value')
      ..writeln()
      ..writeln('    listed = client.get("/api/${r.route}", headers=AUTH).json()')
      ..writeln('    assert any(row["id"] == item["id"] for row in listed)')
      ..writeln()
      ..writeln('    fetched = client.get(f"/api/${r.route}/{item[\'id\']}", headers=AUTH)')
      ..writeln('    assert fetched.status_code == 200')
      ..writeln()
      ..writeln('    updated = client.patch(')
      ..writeln('        f"/api/${r.route}/{item[\'id\']}", json={"${first.name}": $changed}, headers=AUTH')
      ..writeln('    )')
      ..writeln('    assert updated.status_code == 200, updated.text')
      ..writeln('    assert updated.json()["${first.name}"] == $changed')
      ..writeln()
      ..writeln('    deleted = client.delete(f"/api/${r.route}/{item[\'id\']}", headers=AUTH)')
      ..writeln('    assert deleted.status_code == 204')
      ..writeln('    assert client.get(f"/api/${r.route}/{item[\'id\']}", headers=AUTH).status_code == 404')
      ..writeln()
      ..writeln()
      ..writeln('def test_${r.route}_needs_a_key(client):')
      ..writeln('    assert client.get("/api/${r.route}").status_code == 401')
      ..writeln('    wrong = {k: "wrong" for k in AUTH}')
      ..writeln('    assert client.get("/api/${r.route}", headers=wrong).status_code == 401');
    if (publicSubmissions) {
      buf.writeln('    assert client.post("/api/${r.route}", json=payload_for_${r.route}()).status_code == 201');
    } else {
      buf.writeln('    assert client.post("/api/${r.route}", json=payload_for_${r.route}()).status_code == 401');
    }
    if (required.isNotEmpty) {
      buf
        ..writeln()
        ..writeln()
        ..writeln('def test_${r.route}_rejects_missing_fields(client):')
        ..writeln('    res = client.post("/api/${r.route}", json={}$createAuth)')
        ..writeln('    assert res.status_code == 422');
    }
  }
  return buf.toString();
}
