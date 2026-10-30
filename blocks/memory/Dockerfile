FROM python:3.12-slim
WORKDIR /app
COPY pyproject.toml ./
COPY starsi_memory ./starsi_memory
RUN pip install --no-cache-dir .
VOLUME /var/lib/starsi/memory
EXPOSE 8080
CMD ["uvicorn", "--factory", "starsi_memory.server:create_app", \
     "--host", "0.0.0.0", "--port", "8080"]
