FROM python:3.12-alpine

WORKDIR /app

COPY requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt

COPY app.py /app/app.py
COPY wearable_ingestion_api /app/wearable_ingestion_api

CMD ["python3", "/app/app.py"]
