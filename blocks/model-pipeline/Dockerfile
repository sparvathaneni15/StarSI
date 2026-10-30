FROM python:3.12-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
    openssh-client rsync && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY pyproject.toml ./
COPY starsi_pipeline ./starsi_pipeline
RUN pip install --no-cache-dir .
# SSH key + pinned known_hosts arrive as a mounted Secret (see chart)
ENTRYPOINT ["starsi-pipeline"]
