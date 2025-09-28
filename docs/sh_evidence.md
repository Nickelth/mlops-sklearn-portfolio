## ALB DNS

```bash
evo alb-dns bash -lc 'ALB_ARN=$(aws elbv2 describe-target-groups --names mlops-api-tg \
  --query "TargetGroups[0].LoadBalancerArns[0]" -o text); \
  aws elbv2 describe-load-balancers --load-balancer-arns "$ALB_ARN" \
  --query "LoadBalancers[0].DNSName" -o text'
  ```

## /healthz

```bash
evo healthz curl -i "http://$DNS/healthz"
```

## Target Health

```bash
evo tg-health aws elbv2 describe-target-health --target-group-arn "$TG_ARN" \
  --query 'TargetHealthDescriptions[].{State:TargetHealth.State,Reason:TargetHealth.Reason,Port:Target.Port}' \
  --output table --region "$AWS_REGION"
```

## ECS events

```bash
evo ecs-events aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" \
  --query 'services[0].events[0:10]' --output table --region "$AWS_REGION"
```

## CloudWatch Logs tail

```bash
evo cwlogs bash -lc 'STREAM=$(aws logs describe-log-streams --log-group-name /mlops/api \
  --order-by LastEventTime --descending --limit 1 --query "logStreams[0].logStreamName" -o text); \
  aws logs get-log-events --log-group-name /mlops/api --log-stream-name "$STREAM" --limit 100'
```