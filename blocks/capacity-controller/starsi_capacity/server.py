"""StarSI capacity controller.

Scale-to-zero for the GPU tier = stopping/starting its EC2 instance. The k3s
agent on it rejoins on boot and the vLLM pod reschedules; nothing else needed.

    GET  /health                       controller + instance state, no auth
    POST /capacity/gpu/touch           "someone wants the GPU": start if
                                       stopped, record activity (gateway calls
                                       this on every GPU-tier request)
    POST /capacity/gpu/start           explicit start
    POST /capacity/gpu/stop            explicit stop

A watcher loop stops the instance after `idle_minutes` without a touch.
Credentials come from the node's instance profile (IAM limited to instances
tagged starsi-role=gpu).
"""

from __future__ import annotations

import asyncio
import os
import time
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Request


class GpuInstance:
    """boto3 wrapper, isolated so tests can stub it."""

    def __init__(self, instance_id: str, region: str):
        import boto3

        self.instance_id = instance_id
        self.ec2 = boto3.client("ec2", region_name=region)

    def state(self) -> str:
        r = self.ec2.describe_instances(InstanceIds=[self.instance_id])
        return r["Reservations"][0]["Instances"][0]["State"]["Name"]

    def start(self) -> None:
        self.ec2.start_instances(InstanceIds=[self.instance_id])

    def stop(self) -> None:
        self.ec2.stop_instances(InstanceIds=[self.instance_id])


def create_app(instance: GpuInstance | None = None) -> FastAPI:
    token = os.environ.get("STARSI_AUTH_TOKEN", "")
    idle_minutes = float(os.environ.get("STARSI_GPU_IDLE_MINUTES", "15"))
    if instance is None:
        instance = GpuInstance(
            os.environ["GPU_INSTANCE_ID"],
            os.environ.get("AWS_REGION", "us-west-2"),
        )

    last_touch = {"at": 0.0}

    async def idle_watcher():
        while True:
            await asyncio.sleep(60)
            if last_touch["at"] == 0.0:
                continue
            idle_s = time.time() - last_touch["at"]
            if idle_s > idle_minutes * 60:
                state = await asyncio.to_thread(instance.state)
                if state == "running":
                    await asyncio.to_thread(instance.stop)
                last_touch["at"] = 0.0

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        watcher = asyncio.create_task(idle_watcher())
        try:
            yield
        finally:
            watcher.cancel()

    app = FastAPI(title="starsi-capacity", lifespan=lifespan)

    def check_auth(request: Request) -> None:
        if request.headers.get("authorization") != f"Bearer {token}":
            raise HTTPException(status_code=401, detail="bad or missing token")

    @app.get("/health")
    async def health():
        return {
            "status": "ok",
            "gpu_state": await asyncio.to_thread(instance.state),
            "idle_minutes": idle_minutes,
            "last_touch_s_ago": (
                round(time.time() - last_touch["at"], 1) if last_touch["at"] else None
            ),
        }

    @app.post("/capacity/gpu/touch")
    async def touch(request: Request):
        check_auth(request)
        last_touch["at"] = time.time()
        state = await asyncio.to_thread(instance.state)
        if state in ("stopped", "stopping"):
            await asyncio.to_thread(instance.start)
            state = "pending"
        return {"gpu_state": state}

    @app.post("/capacity/gpu/start")
    async def start(request: Request):
        check_auth(request)
        last_touch["at"] = time.time()
        await asyncio.to_thread(instance.start)
        return {"gpu_state": "pending"}

    @app.post("/capacity/gpu/stop")
    async def stop(request: Request):
        check_auth(request)
        last_touch["at"] = 0.0
        await asyncio.to_thread(instance.stop)
        return {"gpu_state": "stopping"}

    return app
