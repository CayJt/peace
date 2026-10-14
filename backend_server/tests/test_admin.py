import jwt
import pytest
from fastapi.testclient import TestClient

from main import app
from routes import admin_config, auth as user_auth, public
from services import admin_security as sec, db as dbmod

client = TestClient(app)
PW = "SuperSecret123"


@pytest.fixture(autouse=True)
def seeded(monkeypatch):
    monkeypatch.setenv("INITIAL_ADMIN_PASSWORD", PW)
    sec._fails.clear()
    public._feedback_hits.clear()
    sec.seed_initial_admin()


def login(username="admin", password=PW):
    return client.post("/api/v1/admin/auth/login", json={"username": username, "password": password})


def hdr(username="admin", password=PW):
    r = login(username, password)
    assert r.status_code == 200, r.text
    return {"Authorization": f"Bearer {r.json()['token']}"}


def make_admin(h, username, role="custom", perms=None, password="Passw0rd!x"):
    body = {"username": username, "email": f"{username}@x.co", "full_name": username.title(),
            "password": password, "role": role}
    if perms is not None:
        body["permissions"] = perms
    r = client.post("/api/v1/admin/administrators", json=body, headers=h)
    assert r.status_code == 201, r.text
    return r.json()


# ---------------------------------------------------------------- seeding & login

def test_seed_creates_super_admin_with_all_permissions_once():
    with dbmod.db() as con:
        rows = con.execute("SELECT * FROM admin_users").fetchall()
        assert len(rows) == 1 and rows[0]["username"] == "admin" and rows[0]["role"] == "super_admin"
        assert con.execute("SELECT COUNT(*) c FROM admin_permissions").fetchone()["c"] == len(sec.PERMISSIONS)
        assert con.execute("SELECT value FROM system_configs WHERE key='quran_data_provider'").fetchone()[0] == "quran.com"
    assert sec.seed_initial_admin() is None  # idempotent


def test_seed_generates_and_prints_password_when_env_missing(monkeypatch, capsys, tmp_path):
    monkeypatch.delenv("INITIAL_ADMIN_PASSWORD")
    monkeypatch.setattr(dbmod, "DB_PATH", str(tmp_path / "fresh.db"))
    pw = sec.seed_initial_admin()
    assert pw and len(pw) >= 12 and pw in capsys.readouterr().out
    assert login("admin", pw).status_code == 200


def test_password_is_bcrypt_hashed():
    with dbmod.db() as con:
        h = con.execute("SELECT password_hash FROM admin_users").fetchone()[0]
    assert h.startswith("$2") and PW not in h


def test_login_success_returns_token_and_permissions():
    r = login()
    assert r.status_code == 200
    j = r.json()
    assert j["token_type"] == "bearer" and j["token"]
    assert set(j["permissions"]) == set(sec.PERMISSIONS)
    assert j["admin"]["role"] == "super_admin" and "password" not in str(j["admin"])


def test_login_wrong_password_and_unknown_user_look_identical():
    a, b = login(password="nope"), login("ghost", "nope")
    assert a.status_code == b.status_code == 401
    assert a.json() == b.json()


def test_login_is_throttled_after_repeated_failures():
    for _ in range(5):
        assert login(password="bad").status_code == 401
    assert login(password="bad").status_code == 429
    assert login().status_code == 429  # even the right password is blocked while throttled


def test_inactive_admin_cannot_login_or_use_existing_token():
    h = hdr()
    a = make_admin(h, "temp", "auditor")
    th = hdr("temp", "Passw0rd!x")
    client.put(f"/api/v1/admin/administrators/{a['id']}", json={"is_active": False}, headers=h)
    assert login("temp", "Passw0rd!x").status_code == 401
    assert client.get("/api/v1/admin/auth/me", headers=th).status_code == 401


def test_me_and_permissions_list():
    h = hdr()
    assert client.get("/api/v1/admin/auth/me", headers=h).json()["username"] == "admin"
    keys = {p["key"] for p in client.get("/api/v1/admin/permissions-list", headers=h).json()["permissions"]}
    assert keys == set(sec.PERMISSIONS)


@pytest.mark.parametrize("token", ["", "garbage", "Bearer x.y.z"])
def test_bad_tokens_rejected(token):
    r = client.get("/api/v1/admin/auth/me", headers={"Authorization": token} if token else {})
    assert r.status_code == 401


def test_expired_and_wrong_type_and_forged_tokens_rejected():
    with dbmod.db() as con:
        pwv = sec.pw_version(con.execute("SELECT password_changed_at FROM admin_users").fetchone()[0])
    secret = sec.jwt_secret()
    expired = jwt.encode({"sub": "1", "typ": "admin", "pwv": pwv, "exp": 1}, secret, algorithm="HS256")
    wrong_type = jwt.encode({"sub": "1", "typ": "user", "pwv": pwv, "exp": 9999999999}, secret, algorithm="HS256")
    forged = jwt.encode({"sub": "1", "typ": "admin", "pwv": pwv, "exp": 9999999999}, "x" * 40, algorithm="HS256")
    none_alg = jwt.encode({"sub": "1", "typ": "admin", "pwv": pwv, "exp": 9999999999}, None, algorithm="none")
    for t in (expired, wrong_type, forged, none_alg):
        assert client.get("/api/v1/admin/auth/me", headers={"Authorization": f"Bearer {t}"}).status_code == 401


def test_end_user_token_is_not_an_admin_token():
    u = client.post("/api/v1/auth/register", json={"email": "u@x.co", "full_name": "U", "password": "password123"})
    r = client.get("/api/v1/admin/auth/me", headers={"Authorization": f"Bearer {u.json()['token']}"})
    assert r.status_code == 401


# ---------------------------------------------------------------- RBAC guards

GUARDED = [
    ("GET", "/api/v1/admin/analytics/realtime", "analytics.view"),
    ("GET", "/api/v1/admin/users/stats", "users.view"),
    ("GET", "/api/v1/admin/analytics/leaderboard", "users.view"),
    ("GET", "/api/v1/admin/config/quran-provider", "config.manage"),
    ("POST", "/api/v1/admin/config/cache/clear", "config.manage"),
    ("GET", "/api/v1/admin/chats/history", "chats.view"),
    ("GET", "/api/v1/admin/murajaah/sessions", "murajaah.view"),
    ("GET", "/api/v1/admin/feedback", "feedback.manage"),
    ("GET", "/api/v1/admin/administrators", "admins.manage"),
]


@pytest.mark.parametrize("method,path,perm", GUARDED)
def test_each_endpoint_demands_its_permission(method, path, perm):
    sh = hdr()
    others = [p for p in sec.PERMISSIONS if p != perm]
    make_admin(sh, "without", "custom", others)
    make_admin(sh, "withonly", "custom", [perm])
    assert client.request(method, path, headers=hdr("without", "Passw0rd!x")).status_code == 403
    assert client.request(method, path, headers=hdr("withonly", "Passw0rd!x")).status_code == 200
    assert client.request(method, path).status_code == 401  # no token at all


def test_super_admin_passes_every_guard():
    h = hdr()
    for method, path, _ in GUARDED:
        assert client.request(method, path, headers=h).status_code == 200, path


def test_role_presets_apply_when_no_explicit_permissions():
    h = hdr()
    assert set(make_admin(h, "aud", "auditor")["permissions"]) == set(sec.ROLE_PRESETS["auditor"])
    assert set(make_admin(h, "edi", "editor")["permissions"]) == set(sec.ROLE_PRESETS["editor"])
    assert make_admin(h, "cus", "custom")["permissions"] == []


def test_permission_changes_apply_to_existing_token_immediately():
    sh = hdr()
    a = make_admin(sh, "edx", "custom", ["analytics.view"])
    h = hdr("edx", "Passw0rd!x")
    assert client.get("/api/v1/admin/analytics/realtime", headers=h).status_code == 200
    client.put(f"/api/v1/admin/administrators/{a['id']}", json={"permissions": ["users.view"]}, headers=sh)
    assert client.get("/api/v1/admin/analytics/realtime", headers=h).status_code == 403
    assert client.get("/api/v1/admin/users/stats", headers=h).status_code == 200


# ---------------------------------------------------------------- admin CRUD

def test_create_list_update_delete_admin():
    h = hdr()
    a = make_admin(h, "ali", "custom", ["feedback.manage"])
    assert a["permissions"] == ["feedback.manage"] and a["is_primary"] is False
    names = [x["username"] for x in client.get("/api/v1/admin/administrators", headers=h).json()["administrators"]]
    assert names == ["admin", "ali"]

    r = client.put(f"/api/v1/admin/administrators/{a['id']}", headers=h,
                   json={"full_name": "Ali B", "email": "ALI2@x.co", "permissions": ["chats.view", "murajaah.view"]})
    assert r.status_code == 200
    assert r.json()["full_name"] == "Ali B" and r.json()["email"] == "ali2@x.co"
    assert r.json()["permissions"] == ["chats.view", "murajaah.view"]

    assert client.delete(f"/api/v1/admin/administrators/{a['id']}", headers=h).status_code == 204
    with dbmod.db() as con:  # permissions cascade
        assert con.execute("SELECT COUNT(*) c FROM admin_permissions WHERE admin_id=?", (a["id"],)).fetchone()["c"] == 0
    assert client.delete(f"/api/v1/admin/administrators/{a['id']}", headers=h).status_code == 404


def test_validation_and_uniqueness():
    h = hdr()
    base = {"username": "dup", "email": "dup@x.co", "full_name": "D", "password": "Passw0rd!x"}
    assert client.post("/api/v1/admin/administrators", json=base, headers=h).status_code == 201
    assert client.post("/api/v1/admin/administrators", json=base, headers=h).status_code == 409
    assert client.post("/api/v1/admin/administrators", json={**base, "username": "DUP", "email": "o@x.co"}, headers=h).status_code == 409
    for bad in ({"username": "a"}, {"email": "no"}, {"password": "short"}, {"password": "x" * 80},
                {"role": "root"}, {"permissions": ["nope.key"]}, {"username": "bad name!"}):
        r = client.post("/api/v1/admin/administrators", json={**base, "username": "n1", "email": "n1@x.co", **bad}, headers=h)
        assert r.status_code == 422, bad


def test_primary_super_admin_is_protected():
    h = hdr()
    sa2 = make_admin(h, "boss2", "super_admin")
    h2 = hdr("boss2", "Passw0rd!x")
    pid = client.get("/api/v1/admin/auth/me", headers=h).json()["id"]
    assert client.delete(f"/api/v1/admin/administrators/{pid}", headers=h2).status_code == 403
    assert client.put(f"/api/v1/admin/administrators/{pid}", json={"is_active": False}, headers=h2).status_code == 403
    assert client.put(f"/api/v1/admin/administrators/{pid}", json={"role": "custom"}, headers=h2).status_code == 403
    assert client.delete(f"/api/v1/admin/administrators/{pid}", headers=h).status_code == 403  # not even by itself
    # a secondary super admin is deletable by the primary
    assert client.delete(f"/api/v1/admin/administrators/{sa2['id']}", headers=h).status_code == 204


def test_cannot_lock_yourself_out():
    h = hdr()
    sa2 = make_admin(h, "boss2", "super_admin")
    h2 = hdr("boss2", "Passw0rd!x")
    assert client.delete(f"/api/v1/admin/administrators/{sa2['id']}", headers=h2).status_code == 400
    assert client.put(f"/api/v1/admin/administrators/{sa2['id']}", json={"is_active": False}, headers=h2).status_code == 400
    assert client.put(f"/api/v1/admin/administrators/{sa2['id']}", json={"role": "auditor"}, headers=h2).status_code == 400


def test_no_privilege_escalation_by_delegated_admins():
    sh = hdr()
    make_admin(sh, "mgr", "custom", ["admins.manage", "chats.view"])
    mh = hdr("mgr", "Passw0rd!x")
    body = {"username": "xtra1", "email": "xtra1@x.co", "full_name": "X", "password": "Passw0rd!x"}
    assert client.post("/api/v1/admin/administrators", json={**body, "role": "super_admin"}, headers=mh).status_code == 403
    assert client.post("/api/v1/admin/administrators", json={**body, "permissions": ["config.manage"]}, headers=mh).status_code == 403
    ok = client.post("/api/v1/admin/administrators", json={**body, "permissions": ["chats.view"]}, headers=mh)
    assert ok.status_code == 201
    pid = client.get("/api/v1/admin/auth/me", headers=sh).json()["id"]
    assert client.put(f"/api/v1/admin/administrators/{pid}", json={"full_name": "Hacked"}, headers=mh).status_code == 403
    assert client.delete(f"/api/v1/admin/administrators/{pid}", headers=mh).status_code == 403
    me = client.get("/api/v1/admin/auth/me", headers=mh).json()["id"]
    r = client.put(f"/api/v1/admin/administrators/{me}", json={"permissions": ["admins.manage", "config.manage"]}, headers=mh)
    assert r.status_code == 403


def test_super_admin_promotion_sets_all_permissions():
    h = hdr()
    a = make_admin(h, "upx", "auditor")
    r = client.put(f"/api/v1/admin/administrators/{a['id']}", json={"role": "super_admin"}, headers=h)
    assert set(r.json()["permissions"]) == set(sec.PERMISSIONS)


# ---------------------------------------------------------------- passwords

def test_super_admin_resets_other_password_and_old_token_dies():
    sh = hdr()
    a = make_admin(sh, "victim", "auditor")
    old = hdr("victim", "Passw0rd!x")
    r = client.put(f"/api/v1/admin/administrators/{a['id']}/password", json={"new_password": "BrandNew#123"}, headers=sh)
    assert r.status_code == 204
    assert login("victim", "Passw0rd!x").status_code == 401
    assert login("victim", "BrandNew#123").status_code == 200
    assert client.get("/api/v1/admin/auth/me", headers=old).status_code == 401  # old session revoked


def test_owner_changes_own_password_only_with_current_password():
    sh = hdr()
    a = make_admin(sh, "own", "custom")
    oh = hdr("own", "Passw0rd!x")
    url = f"/api/v1/admin/administrators/{a['id']}/password"
    assert client.put(url, json={"new_password": "Another#12345"}, headers=oh).status_code == 403
    assert client.put(url, json={"new_password": "Another#12345", "current_password": "wrong"}, headers=oh).status_code == 403
    assert client.put(url, json={"new_password": "short", "current_password": "Passw0rd!x"}, headers=oh).status_code == 422
    assert client.put(url, json={"new_password": "Another#12345", "current_password": "Passw0rd!x"}, headers=oh).status_code == 204
    assert login("own", "Another#12345").status_code == 200


def test_non_super_cannot_reset_someone_elses_password():
    sh = hdr()
    make_admin(sh, "mgr1", "custom", ["admins.manage"])
    other = make_admin(sh, "mgr2", "custom")
    r = client.put(f"/api/v1/admin/administrators/{other['id']}/password", json={"new_password": "Whatever#123"}, headers=hdr("mgr1", "Passw0rd!x"))
    assert r.status_code == 403


# ---------------------------------------------------------------- provider & cache

def test_provider_switch_persists_in_database():
    h = hdr()
    r = client.get("/api/v1/admin/config/quran-provider", headers=h).json()
    assert r["provider"] == "quran.com" and r["available"] == ["quran.com", "kemenag"]
    assert r["adapter_implemented"] == {"quran.com": True, "kemenag": False}
    out = client.put("/api/v1/admin/config/quran-provider", json={"provider": "kemenag"}, headers=h).json()
    assert out["provider"] == "kemenag" and out["updated_by"] == 1
    with dbmod.db() as con:
        assert con.execute("SELECT value,updated_by FROM system_configs WHERE key='quran_data_provider'").fetchone()[:] == ("kemenag", 1)
    assert client.get("/api/v1/admin/config/quran-provider", headers=h).json()["provider"] == "kemenag"
    assert client.get("/api/v1/config/public").json() == {"quran_data_provider": "kemenag"}
    assert client.put("/api/v1/admin/config/quran-provider", json={"provider": "bogus"}, headers=h).status_code == 422


def test_provider_health_reports_latency_without_network(monkeypatch):
    import httpx

    class R:
        status_code = 200

    def fake_get(url, **kw):
        if "kemenag" in url or "qurankemenag" in url:
            raise httpx.ConnectError("down")
        return R()

    monkeypatch.setattr(admin_config.httpx, "get", fake_get)
    out = client.get("/api/v1/admin/config/quran-provider/health", headers=hdr()).json()["providers"]
    assert out["quran.com"]["ok"] is True and isinstance(out["quran.com"]["latency_ms"], int)
    assert out["kemenag"] == {"ok": False, "status_code": None, "latency_ms": None, "error": "ConnectError"}


def test_cache_clear_empties_verse_cache():
    from services import verse_provider
    p = verse_provider.get_verse_provider()
    p._cache["1:1"] = [{"uthmani": "x", "imlaei": "x"}]
    assert client.post("/api/v1/admin/config/cache/clear", headers=hdr()).json() == {"cleared_entries": 1}
    assert p._cache == {}


# ---------------------------------------------------------------- feedback

def test_public_feedback_then_admin_triages_it():
    r = client.post("/api/v1/feedback", json={"category": "bug", "message": "Tombol mic tidak bekerja", "app_version": "1.0.0"})
    assert r.status_code == 201
    fid = r.json()["id"]
    h = hdr()
    listing = client.get("/api/v1/admin/feedback", headers=h).json()
    assert listing["counts"]["open"] == 1 and listing["items"][0]["user_id"] == "anonymous"
    assert client.get("/api/v1/admin/analytics/realtime", headers=h).json()["pending_feedback"] == 1

    p = client.patch(f"/api/v1/admin/feedback/{fid}", json={"status": "in_progress", "admin_notes": "Diperiksa"}, headers=h)
    assert p.status_code == 200 and p.json()["status"] == "in_progress" and p.json()["admin_notes"] == "Diperiksa"
    assert client.get("/api/v1/admin/feedback?status=open", headers=h).json()["items"] == []
    assert client.get("/api/v1/admin/feedback?status=in_progress", headers=h).json()["counts"]["in_progress"] == 1
    assert client.patch(f"/api/v1/admin/feedback/{fid}", json={"status": "resolved"}, headers=h).json()["status"] == "resolved"
    assert client.patch(f"/api/v1/admin/feedback/{fid}", json={"status": "weird"}, headers=h).status_code == 422
    assert client.patch(f"/api/v1/admin/feedback/{fid}", json={}, headers=h).status_code == 422
    assert client.patch("/api/v1/admin/feedback/999", json={"status": "open"}, headers=h).status_code == 404


def test_feedback_validation_rate_limit_and_user_attribution():
    assert client.post("/api/v1/feedback", json={"category": "x", "message": "halo dunia"}).status_code == 422
    assert client.post("/api/v1/feedback", json={"category": "bug", "message": "a"}).status_code == 422
    assert client.post("/api/v1/feedback", json={"category": "bug", "message": "x" * 2001}).status_code == 422
    u = client.post("/api/v1/auth/register", json={"email": "f@x.co", "full_name": "F", "password": "password123"}).json()
    client.post("/api/v1/feedback", json={"category": "suggestion", "message": "Tambah fitur"},
                headers={"Authorization": f"Bearer {u['token']}"})
    assert client.get("/api/v1/admin/feedback", headers=hdr()).json()["items"][0]["user_id"] == "1"
    for _ in range(4):
        client.post("/api/v1/feedback", json={"category": "bug", "message": "spam spam"})
    assert client.post("/api/v1/feedback", json={"category": "bug", "message": "spam spam"}).status_code == 429


def test_feedback_markup_is_stored_verbatim_as_data():
    client.post("/api/v1/feedback", json={"category": "bug", "message": "<script>alert(1)</script>"})
    assert client.get("/api/v1/admin/feedback", headers=hdr()).json()["items"][0]["message"] == "<script>alert(1)</script>"


# ---------------------------------------------------------------- analytics & logs

def register(i):
    r = client.post("/api/v1/auth/register", json={"email": f"u{i}@x.co", "full_name": f"User {i}", "password": "password123"})
    return {"Authorization": f"Bearer {r.json()['token']}"}


def test_realtime_counts_only_recent_heartbeats():
    h1, h2 = register(1), register(2)
    client.post("/api/v1/heartbeat", headers=h1)
    client.post("/api/v1/heartbeat", headers=h2)
    with dbmod.db() as con:
        con.execute("UPDATE user_heartbeats SET last_seen = last_seen - 600 WHERE user_id = 2")
    j = client.get("/api/v1/admin/analytics/realtime", headers=hdr()).json()
    assert j["active_users"] == 1 and j["window_seconds"] == 300
    assert client.post("/api/v1/heartbeat").status_code == 401


def test_user_stats_trend():
    for i in range(3):
        register(i)
    j = client.get("/api/v1/admin/users/stats?days=14", headers=hdr()).json()
    assert j["total_users"] == 3 and j["new_last_7d"] == 3 and len(j["trend"]) == 14
    assert j["trend"][-1]["count"] == 3 and sum(t["count"] for t in j["trend"]) == 3


def test_leaderboard_weights_by_letters_and_ranks():
    a, b = register(1), register(2)
    s = lambda h, letters, score, k=0: client.post("/api/v1/murajaah/sessions", headers=h, json={
        "page": 1, "duration_sec": 40, "letters_evaluated": letters, "score": score, "khatam_count": k})
    assert s(a, 100, 0.9).status_code == 201
    s(a, 100, 0.7, 2)
    s(b, 50, 0.95, 1)
    assert client.post("/api/v1/murajaah/sessions", json={}).status_code == 401
    assert client.post("/api/v1/murajaah/sessions", headers=a, json={
        "page": 700, "duration_sec": 1, "letters_evaluated": 1, "score": 0.5}).status_code == 422
    e = client.get("/api/v1/admin/analytics/leaderboard", headers=hdr()).json()["entries"]
    assert [x["name"] for x in e] == ["User 2", "User 1"]
    assert e[1]["avg_score"] == pytest.approx(0.8) and e[1]["letters_evaluated"] == 200 and e[1]["khatam_count"] == 2
    assert "@" in e[0]["email"] and "u2@" not in e[0]["email"]  # masked
    k = client.get("/api/v1/admin/analytics/leaderboard?sort=khatam", headers=hdr()).json()["entries"]
    assert k[0]["name"] == "User 1"
    sess = client.get("/api/v1/admin/murajaah/sessions", headers=hdr()).json()
    assert sess["total"] == 3 and sess["items"][0]["name"] == "User 2"


def test_chat_questions_are_logged_with_guardrail_flag():
    from routes import quran_ai

    class A:
        def answer(self, q, ctx):
            return {"answer": "Jawaban.", "verse_keys": []}

    app.dependency_overrides[quran_ai.get_answerer] = lambda: A()
    app.dependency_overrides[quran_ai.get_verse_lookup] = lambda: (lambda k: None)
    try:
        h = register(1)
        client.post("/api/v1/quran-chat", json={"text": "Apa makna surah Al-Fatihah?"}, headers=h)
        client.post("/api/v1/quran-chat", json={"text": "Harga bitcoin?"})
    finally:
        app.dependency_overrides.clear()
    j = client.get("/api/v1/admin/chats/history", headers=hdr()).json()
    assert j["total"] == 2 and j["guardrail_total"] == 1
    assert [i["is_guardrail_triggered"] for i in j["items"]] == [True, False]
    assert j["items"][1]["user_id"] == "1" and j["items"][0]["user_id"] == "anonymous"
    only = client.get("/api/v1/admin/chats/history?guardrail_only=true", headers=hdr()).json()
    assert only["total"] == 1 and only["items"][0]["question"] == "Harga bitcoin?"
    assert client.get("/api/v1/admin/chats/history?q=Fatihah", headers=hdr()).json()["total"] == 1
    assert client.get("/api/v1/admin/chats/history?q=%25", headers=hdr()).json()["total"] == 0  # % is literal


def test_sql_injection_attempts_are_inert():
    assert login("admin' OR '1'='1", "x").status_code == 401
    r = client.get("/api/v1/admin/chats/history?q=' OR 1=1 --", headers=hdr())
    assert r.status_code == 200 and r.json()["total"] == 0
