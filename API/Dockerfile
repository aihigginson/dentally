FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY mock_api.py .
COPY data/ data/
EXPOSE 5000
CMD ["python", "mock_api.py"]
