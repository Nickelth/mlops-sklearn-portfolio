## Docker

```bash
make docker-build IMAGE=mlops-sklearn-portfolio:local
make docker-run   IMAGE=mlops-sklearn-portfolio:local PORT=8000
# health
curl -s localhost:8000/health | jq .
````

* モデル/ログはボリュームで渡す（`models/`, `logs/` を -v マウント）
* ARM→amd64 ビルド: `docker build --platform linux/amd64 -t <image> .`