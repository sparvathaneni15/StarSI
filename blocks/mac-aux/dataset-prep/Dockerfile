FROM python:3.12-slim
RUN pip install --no-cache-dir httpx
COPY prepare.py /prepare.py
ENTRYPOINT ["python", "/prepare.py"]
