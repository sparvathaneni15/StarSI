from fastapi.testclient import TestClient
from starsi_memory.server import create_app

AUTH = {"Authorization": "Bearer t"}


def make_client(tmp_path):
    return TestClient(create_app(store_path=tmp_path / "store", token="t"))


def test_sync_is_idempotent(tmp_path):
    client = make_client(tmp_path)
    turns = [{"turn_id": "a", "content": "x"}, {"turn_id": "b", "content": "y"}]
    assert client.post("/v1/sync", headers=AUTH, json={"turns": turns}).json() == {"accepted": 2}
    assert client.post("/v1/sync", headers=AUTH, json={"turns": turns}).json() == {"accepted": 0}
    assert client.get("/health").json()["turns"] == 2


def test_turns_paged_read(tmp_path):
    client = make_client(tmp_path)
    turns = [{"turn_id": str(i)} for i in range(5)]
    client.post("/v1/sync", headers=AUTH, json={"turns": turns})
    page = client.get("/v1/turns?since=0&limit=3", headers=AUTH).json()
    assert [t["turn_id"] for t in page["turns"]] == ["0", "1", "2"]
    page2 = client.get(f"/v1/turns?since={page['next']}", headers=AUTH).json()
    assert [t["turn_id"] for t in page2["turns"]] == ["3", "4"]


def test_auth_required(tmp_path):
    client = make_client(tmp_path)
    assert client.post("/v1/sync", json={"turns": []}).status_code == 401
    assert client.get("/v1/turns").status_code == 401


def test_survives_restart(tmp_path):
    client = make_client(tmp_path)
    client.post("/v1/sync", headers=AUTH, json={"turns": [{"turn_id": "a"}]})
    reopened = make_client(tmp_path)
    assert reopened.post(
        "/v1/sync", headers=AUTH, json={"turns": [{"turn_id": "a"}]}
    ).json() == {"accepted": 0}
