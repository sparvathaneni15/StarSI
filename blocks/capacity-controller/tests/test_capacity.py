import os

from fastapi.testclient import TestClient
from starsi_capacity.server import create_app

AUTH = {"Authorization": "Bearer t"}


class FakeInstance:
    def __init__(self, state="stopped"):
        self._state = state
        self.calls = []

    def state(self):
        return self._state

    def start(self):
        self.calls.append("start")
        self._state = "pending"

    def stop(self):
        self.calls.append("stop")
        self._state = "stopping"


def make_client(instance):
    os.environ["STARSI_AUTH_TOKEN"] = "t"
    return TestClient(create_app(instance=instance))


def test_touch_starts_stopped_instance():
    inst = FakeInstance("stopped")
    with make_client(inst) as client:
        r = client.post("/capacity/gpu/touch", headers=AUTH)
        assert r.json() == {"gpu_state": "pending"}
        assert inst.calls == ["start"]


def test_touch_noop_when_running():
    inst = FakeInstance("running")
    with make_client(inst) as client:
        r = client.post("/capacity/gpu/touch", headers=AUTH)
        assert r.json() == {"gpu_state": "running"}
        assert inst.calls == []


def test_explicit_stop_and_auth():
    inst = FakeInstance("running")
    with make_client(inst) as client:
        assert client.post("/capacity/gpu/stop").status_code == 401
        assert client.post("/capacity/gpu/stop", headers=AUTH).json() == {
            "gpu_state": "stopping"
        }
        assert inst.calls == ["stop"]
