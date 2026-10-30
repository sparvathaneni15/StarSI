from fastapi.testclient import TestClient
from starsi_registry.server import create_app

AUTH = {"Authorization": "Bearer t"}


def make_client(tmp_path):
    return TestClient(create_app(state_path=tmp_path / "state.json", token="t"))


def test_model_version_roundtrip(tmp_path):
    client = make_client(tmp_path)
    r = client.put(
        "/v1/models/starsi-cpu",
        headers=AUTH,
        json={"version": "v3", "artifact": "s3://starsi-artifacts/m/v3/model.gguf"},
    )
    assert r.status_code == 200
    assert client.get("/v1/models").json()["tiers"]["starsi-cpu"]["version"] == "v3"
    # survives restart
    assert make_client(tmp_path).get("/v1/models").json()["tiers"]["starsi-cpu"]["version"] == "v3"


def test_health_report(tmp_path):
    client = make_client(tmp_path)
    client.post(
        "/v1/health-report",
        headers=AUTH,
        json={"source": "aws", "payload": {"tiers": {"starsi-cpu": {"up": True}}}},
    )
    reports = client.get("/v1/status", headers=AUTH).json()["reports"]
    assert reports["aws"]["payload"]["tiers"]["starsi-cpu"]["up"] is True


def test_auth_required(tmp_path):
    client = make_client(tmp_path)
    assert client.put("/v1/models/x", json={"version": "v"}).status_code == 401
    assert client.get("/v1/status").status_code == 401
