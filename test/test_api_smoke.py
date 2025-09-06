# tests/test_api_smoke.py
import json, httpx
def test_schema():
    r = httpx.get("http://localhost:8000/schema", timeout=5)
    j = r.json()
    assert r.status_code == 200 and len(j["required_columns"]) >= 10
