# ── Etapa 1: builder ──────────────────────────────────
FROM python:3.12-slim AS builder
WORKDIR /build
COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir --prefix=/install -r requirements.txt

# ── Etapa 2: runtime ──────────────────────────────────
FROM python:3.12-slim AS runtime
WORKDIR /app

RUN useradd --no-create-home --shell /bin/false appuser
USER appuser

COPY --from=builder /install /usr/local
COPY app.py .

EXPOSE 8080
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "app:app"]
