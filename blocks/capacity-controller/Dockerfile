FROM python:3.12-slim
WORKDIR /app
COPY pyproject.toml ./
COPY starsi_capacity ./starsi_capacity
RUN pip install --no-cache-dir .
EXPOSE 8080
CMD ["uvicorn", "--factory", "starsi_capacity.server:create_app", \
     "--host", "0.0.0.0", "--port", "8080"]
