import json

import pytest
from starsi_pipeline.pipeline import ALL_STAGES, Pipeline


class FakeRunner:
    def __init__(self, train_polls=2):
        self.commands = []
        self.train_polls = train_polls
        self._status_calls = 0

    def run(self, args):
        cmd = " ".join(args)
        self.commands.append(cmd)
        if "starsi-train status" in cmd:
            self._status_calls += 1
            status = "succeeded" if self._status_calls >= self.train_polls else "running"
            return json.dumps({"status": status})
        if "starsi-train lora" in cmd:
            return json.dumps({"run_id": "r1", "pid": 123})
        return ""

    def sleep(self, seconds):
        pass


ENV = {
    "MAC_SSH": "user@mac",
    "AWS_SSH": "admin@aws",
    "HF_REPO": "org/base-model",
    "RUN_ID": "r1",
    "VERSION": "v7",
    "MODEL_NAME": "starsi",
}


def test_stage_order_and_ssh_targets():
    runner = FakeRunner()
    p = Pipeline(env=ENV, runner=runner)
    p.run(["fetch", "dataset", "train", "fuse"])
    joined = "\n".join(runner.commands)
    assert joined.index("starsi-train fetch org/base-model") < joined.index("dataset-prep")
    assert joined.index("dataset-prep") < joined.index("starsi-train lora")
    assert joined.index("starsi-train lora") < joined.index("starsi-train fuse --run-id r1")
    assert all(cmd.startswith("ssh ") and "user@mac" in cmd for cmd in runner.commands)


def test_train_polls_until_succeeded():
    runner = FakeRunner(train_polls=3)
    Pipeline(env=ENV, runner=runner).train()
    polls = [c for c in runner.commands if "starsi-train status r1" in c]
    assert len(polls) == 3


def test_train_raises_on_failure():
    class FailRunner(FakeRunner):
        def run(self, args):
            cmd = " ".join(args)
            self.commands.append(cmd)
            if "status" in cmd:
                return json.dumps({"status": "failed"})
            return ""

    with pytest.raises(RuntimeError, match="training failed"):
        Pipeline(env=ENV, runner=FailRunner()).train()


def test_all_stages_exist_as_methods():
    p = Pipeline(env=ENV, runner=FakeRunner())
    for stage in ALL_STAGES:
        assert callable(getattr(p, stage))
