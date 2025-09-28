## 付録：証跡用打鍵コマンド (2025-09-28)

```bash
# 作業前の現状確認
TS=$(date +%Y%m%d_%H%M%S)
curl -si "http://$DNS/health"  | tee "docs/evidence/${TS}_health_200.txt"
curl -si "http://$DNS/healthz" | tee "docs/evidence/${TS}_healthz_404.txt"

# release-ecr.yml 後にECS更新　:latest前提
aws ecs update-service \
  --cluster mlops-api-cluster \
  --service mlops-api-svc \
  --force-new-deployment \
  --region "$AWS_REGION" | tee "docs/evidence/${TS}_ecs_update_force_new.txt"

# 起動ログをエビデンス保存
STREAM=$(aws logs describe-log-streams --log-group-name /mlops/api \
  --order-by LastEventTime --descending --limit 1 \
  --query 'logStreams[0].logStreamName' -o text --region "$AWS_REGION")
aws logs get-log-events --log-group-name /mlops/api --log-stream-name "$STREAM" \
  --limit 150 --region "$AWS_REGION" \
  | tee "docs/evidence/${TS}_cwlogs_boot.txt"

# ALB 経由で /healthz が 200 になることを先に確認
TS=$(date +%Y%m%d_%H%M%S)
curl -si "http://$DNS/healthz" | tee "docs/evidence/${TS}_healthz_200_pre_switch.txt"

# 上で200確認後
# TG のヘルスチェックパスを /healthz に切り替え
TS=$(date +%Y%m%d_%H%M%S)

TG_ARN=$(aws elbv2 describe-target-groups \
  --names "$TG_NAME" \
  --query 'TargetGroups[0].TargetGroupArn' \
  --output text --region "$AWS_REGION")

aws elbv2 modify-target-group \
  --target-group-arn "$TG_ARN" \
  --health-check-path /healthz \
  --matcher HttpCode=200-399 \
  --health-check-interval-seconds 10 \
  --healthy-threshold-count 2 \
  --region "$AWS_REGION" \
  | tee "docs/evidence/${TS}_tg_hc_switch_to_healthz.txt"

# ヘルスが healthy になるまで監視（証跡としても保存）
aws elbv2 describe-target-health --target-group-arn "$TG_ARN" \
  --query 'TargetHealthDescriptions[].{State:TargetHealth.State,Reason:TargetHealth.Reason,Port:Target.Port}' \
  --output table --region "$AWS_REGION" \
  | tee "docs/evidence/${TS}_tg_health_after_switch.txt"

# /healthz と /metrics の両方、証跡保存
TS=$(date +%Y%m%d_%H%M%S)
curl -si "http://$DNS/healthz" | tee "docs/evidence/${TS}_healthz_200_final.txt"
curl -si "http://$DNS/metrics" | tee "docs/evidence/${TS}_metrics_200.txt"

# ECS サービスイベントを保存（デプロイ経緯の監査用）
aws ecs describe-services --cluster mlops-api-cluster --services mlops-api-svc \
  --query 'services[0].events[0:10]' --output table --region "$AWS_REGION" \
  | tee "docs/evidence/${TS}_ecs_events.txt"
```