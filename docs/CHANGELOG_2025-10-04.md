## 付録：証跡用打鍵コマンド (2025-10-04)

### 1. メインの証跡取得

**目標**

- `terraform plan -target=module.ecs` が通る

- `outputs.tf` から `ALB DNS` が取得可能

```bash
cd ~/mlops-sklearn-portfolio/infra
export TF_DATA_DIR=/tmp/tfdata
export TF_PLUGIN_CACHE_DIR=/tmp/tfplugin

TS=$(date +%Y%m%d_%H%M%S)
terraform init -upgrade | tee "../docs/evidence/${TS}_tf_init_refactor.txt"

# まず network だけ plan/apply（出力を生やす）
TS=$(date +%Y%m%d_%H%M%S)
terraform plan  -var="region=us-west-2" -target=module.network \
  | tee "../docs/evidence/${TS}_tf_plan_target_network.txt"
terraform apply -auto-approve -var="region=us-west-2" -target=module.network \
  | tee "../docs/evidence/${TS}_tf_apply_target_network.txt"

# outputs 確認（unsupported attribute の原因を潰す）
terraform output -json | tee "../docs/evidence/${TS}_tf_outputs_after_network.json"

# ecs だけ plan/apply（module.network の outputs を入力に使う）
TS=$(date +%Y%m%d_%H%M%S)
terraform plan  -var="region=us-west-2" -target=module.ecs \
  | tee "../docs/evidence/${TS}_tf_plan_target_ecs.txt"
terraform apply -auto-approve -var="region=us-west-2" -target=module.ecs \
  | tee "../docs/evidence/${TS}_tf_apply_target_ecs.txt"

# ALB DNS を証跡保存
TS=$(date +%Y%m%d_%H%M%S)
terraform output -raw alb_dns | tee "../docs/evidence/${TS}_alb_dns.txt"
```

### 2. 最終チェック

```bash
# 1) ALB DNS を証跡保存
TS=$(date +%Y%m%d_%H%M%S)
terraform output -raw alb_dns | tee "../docs/evidence/${TS}_alb_dns.txt"

# 2) “-target無し”の差分確認（未反映が無いか）
terraform plan | tee "../docs/evidence/${TS}_tf_plan_full.txt"

# 3) ECS サービス安定化＆イベント抜粋（任意だが残すと吉）
CLUSTER=mlops-api-cluster
SVC=mlops-api-svc
aws ecs wait services-stable --cluster "$CLUSTER" --services "$SVC"
aws ecs describe-services --cluster "$CLUSTER" --services "$SVC" \
  --query 'services[0].events[0:10].[createdAt,message]' --output table \
  | tee "../docs/evidence/${TS}_ecs_events.txt"

```

### 3. ソース更新に伴い再取得する証跡

```bash
TS=$(date +%Y%m%d_%H%M%S)
DNS=$(terraform output -raw alb_dns)
curl -i "http://$DNS/healthz" \
  | tee "../docs/evidence/${TS}_healthz_200_final.txt"

TS=$(date +%Y%m%d_%H%M%S)
CLUSTER=$(terraform output -raw cluster_name)
SVC=$(terraform output -raw ecs_service_name)

# 直前のTaskDef（復旧用）を控える
PREV_TD=$(aws ecs describe-services --cluster "$CLUSTER" --services "$SVC" \
  --query 'services[0].taskDefinition' --output text)
echo "$PREV_TD" | tee "../docs/evidence/${TS}_prev_taskdef.txt"

# 成功デプロイ（force new）
aws ecs update-service --cluster "$CLUSTER" --service "$SVC" \
  --force-new-deployment \
  | tee "../docs/evidence/${TS}_ecs_force_new_success.txt"
aws ecs wait services-stable --cluster "$CLUSTER" --services "$SVC"

# 意図的失敗デプロイ（存在しないタグを指定して失敗させる例）
BAD_TD="${PREV_TD%:*}:999999"
aws ecs update-service --cluster "$CLUSTER" --service "$SVC" \
  --task-definition "$BAD_TD" \
  | tee "../docs/evidence/${TS}_ecs_set_bad_td.txt" || true

# CircuitBreaker/デプロイ失敗を待たずに即ロールバック（復旧）
aws ecs update-service --cluster "$CLUSTER" --service "$SVC" \
  --task-definition "$PREV_TD" \
  | tee "../docs/evidence/${TS}_ecs_rollback_to_prev.txt"
aws ecs wait services-stable --cluster "$CLUSTER" --services "$SVC"

# イベント抜粋
aws ecs describe-services --cluster "$CLUSTER" --services "$SVC" \
  --query 'services[0].events[0:20].[createdAt,message]' --output table \
  | tee "../docs/evidence/${TS}_ecs_events_rollback_demo.txt"

TS=$(date +%Y%m%d_%H%M%S)
LOG_GROUP=$(terraform output -raw log_group_name)
# 直近100行から {" を含む行を抽出（簡易）
aws logs filter-log-events --log-group-name "$LOG_GROUP" \
  --limit 100 \
  --query 'events[].message' --output text \
  | grep -m1 '{' \
  | tee "../docs/evidence/${TS}_cwlogs_json_line.txt"

TS=$(date +%Y%m%d_%H%M%S)
ALB_ARN=$(terraform output -raw alb_arn)
aws cloudwatch put-metric-alarm \
  --alarm-name "mlops-api-alb-5xx-rate-gt1pct" \
  --metric-name HTTPCode_ELB_5XX_Count \
  --namespace AWS/ApplicationELB \
  --statistic Sum --period 300 --evaluation-periods 2 \
  --threshold 1 --comparison-operator GreaterThanOrEqualToThreshold \
  --dimensions Name=LoadBalancer,Value=$(echo "$ALB_ARN" | awk -F/ '{print $2"/"$3"/"$4}') \
  --treat-missing-data notBreaching \
  | tee "../docs/evidence/${TS}_cw_alarm_put_5xx.txt"

# 作成確認（証跡）
aws cloudwatch describe-alarms --alarm-names mlops-api-alb-5xx-rate-gt1pct \
  | tee "../docs/evidence/${TS}_cw_alarm_describe_5xx.txt"

TS=$(date +%Y%m%d_%H%M%S)
export PS4='+ $(date -Is) ${BASH_SOURCE##*/}:${LINENO}: '
set -x
# ここに本命コマンド群（例：curl/ecs/alarmコマンドなど）をまとめて実行
set +x 2> "../docs/evidence/${TS}_bash_trace.txt"

# 直近の UpdateService をCloudTrailで1件拾う例（証跡として抜粋）
aws cloudtrail lookup-events --lookup-attributes AttributeKey=EventName,AttributeValue=UpdateService \
  --max-results 1 \
  | tee "../docs/evidence/${TS}_cloudtrail_lookup_updateservice.txt"
```