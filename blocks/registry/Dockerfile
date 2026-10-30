FROM python:3.12-slim
WORKDIR /app
COPY pyproject.toml ./
COPY starsi_registry ./starsi_registry
RUN pip install --no-cache-dir .
VOLUME /var/lib/starsi/registry
EXPOSE 8080
CMD ["uvicorn", "--factory", "starsi_registry.server:create_app", \
     "--host", "0.0.0.0", "--port", "8080"]
