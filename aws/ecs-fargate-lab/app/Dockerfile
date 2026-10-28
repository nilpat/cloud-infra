FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=8080

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

# Run as a non-root user. ECS will not complain if you skip this, but every
# image review you ever sit through will.
RUN useradd --create-home --uid 10001 appuser
USER appuser

EXPOSE 8080

# 2 workers so a single /crash does not always take the whole task down --
# useful when you want to see the difference between a container dying and a
# worker dying.
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "--access-logfile", "-", "app:app"]
