FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY wearable_operator_dashboard ./wearable_operator_dashboard

EXPOSE 8501
CMD ["streamlit", "run", "wearable_operator_dashboard/app.py", "--server.port=8501", "--server.address=0.0.0.0"]
