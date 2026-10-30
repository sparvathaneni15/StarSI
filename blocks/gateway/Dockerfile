FROM python:3.12-slim
WORKDIR /app
COPY pyproject.toml ./
COPY starsi_gateway ./starsi_gateway
RUN pip install --no-cache-dir .
VOLUME /var/lib/starsi/spool
EXPOSE 8484
CMD ["uvicorn", "--factory", "starsi_gateway.server:create_app", \
     "--host", "0.0.0.0", "--port", "8484"]
