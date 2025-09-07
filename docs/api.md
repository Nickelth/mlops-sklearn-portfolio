## API

- ベース: FastAPI（`api/app.py`）
- モデル: 起動時 `MODEL_PATH` をロード、`/reload?path=...` で切替可
- ログ: 1行JSONを `logs/api-YYYYMMDD.log`

### Endpoints
- `GET /health` → `{status, model, ts}`
- `GET /schema` → `{required_columns[], numeric_columns[]}`
- `POST /predict` → `{"features": {...}}` → `{pred} or {pred_proba}`
- `POST /predict_batch` → `{"rows": [{...}, ...]}` → 配列結果
- `POST /reload?path=/app/models/model_xxx.joblib`

### 最小例
```bash
curl -s -X POST localhost:8000/predict -H 'content-type: application/json' \
  -d '{"features":{"age":39,"education":"Bachelors","hours-per-week":40}}'