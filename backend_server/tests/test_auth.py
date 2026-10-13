from fastapi.testclient import TestClient

from main import app

c = TestClient(app)
U = {"email": "a@b.co", "full_name": "Ali", "password": "password123"}


def test_register_login_me_logout():
    r = c.post("/api/v1/auth/register", json=U)
    assert r.status_code == 201
    r = c.post("/api/v1/auth/login", json={"username": "A@B.co", "password": U["password"]})
    assert r.status_code == 200
    tok = r.json()["token"]
    h = {"Authorization": f"Bearer {tok}"}
    assert c.get("/api/v1/auth/me", headers=h).json()["full_name"] == "Ali"
    assert c.post("/api/v1/auth/logout", headers=h).status_code == 204
    assert c.get("/api/v1/auth/me", headers=h).status_code == 401


def test_bad_credentials_and_duplicates():
    c.post("/api/v1/auth/register", json=U)
    assert c.post("/api/v1/auth/register", json=U).status_code == 409
    assert c.post("/api/v1/auth/login", json={"username": U["email"], "password": "wrong"}).status_code == 401
    assert c.post("/api/v1/auth/login", json={"username": "no@x.co", "password": "x"}).status_code == 401


def test_validation():
    assert c.post("/api/v1/auth/register", json={**U, "email": "bad"}).status_code == 422
    assert c.post("/api/v1/auth/register", json={**U, "password": "short"}).status_code == 422
