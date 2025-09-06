FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 NUMEXPR_NUM_THREADS=1

# scikit-learn 実行時に必要
RUN apt-get update && apt-get install -y --no-install-recommends libgomp1 && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# 依存はキャッシュ効くように先に
COPY pyproject.toml README.md ./

# アプリ本体
COPY src ./src
COPY api ./api
# モデルは基本ボリュームで渡す想定（焼きたいなら models を COPY して .dockerignore を調整）

RUN python -m pip install -U pip setuptools wheel && \
    pip install .

# 実行ユーザー
RUN useradd -m appuser && mkdir -p /app/logs /app/models && chown -R appuser:appuser /app
USER appuser

EXPOSE 8000
CMD ["uvicorn","api.app:app","--host","0.0.0.x","--port","8000"]
