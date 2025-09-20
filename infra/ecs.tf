locals {
  # Allow passing either a bare repository name (default) or a fully-qualified
  # ECR repository URI via var.ecr_repo. The Terraform logic normalises this
  # to an absolute URI before appending the tag supplied via var.image_tag.
  ecr_repository_uri = can(regex(".amazonaws.com/", var.ecr_repo)) ? var.ecr_repo : "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com/${var.ecr_repo}"
  image_uri = "${local.ecr_repository_uri}:${var.image_tag}"
}

resource "aws_ecs_cluster" "this" {
  name = "mlops-api-cluster"
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
  tags = { Project = "mlops-sklearn-portfolio" }
}

resource "aws_ecs_task_definition" "api" {
  family                   = "mlops-api-task"
  cpu                      = "256"   # Fargate最小
  memory                   = "512"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      "name": "api",
      "image": local.image_uri,
      "essential": true,
      "portMappings": [
        { 
          "containerPort": var.container_port, 
          "hostPort": var.container_port, 
          "protocol": "tcp" 
        }
      ],
      "environment": [
        { "name": "MODEL_PATH",        "value": "/app/models/model_openml_adult.joblib" },
        { "name": "LOG_JSON",          "value": "1" },
        # /metrics で使う予定のダミー環境変数（後で値をCIから注入）
        { "name": "METRICS_VERSION",   "value": "vLOCAL" },
        { "name": "METRICS_GIT_SHA",   "value": "unknown" }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group":  "/mlops/api",
          "awslogs-region": var.region,
          "awslogs-stream-prefix": "ecs"
        }
      }
    }
  ])

  tags = { Project = "mlops-sklearn-portfolio" }
}

resource "aws_ecs_service" "api" {
  name            = "mlops-api-svc"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.api.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = data.aws_subnets.default.ids
    security_groups = [aws_security_group.tasks.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.api.arn
    container_name   = "api"
    container_port   = var.container_port
  }

  health_check_grace_period_seconds = 30
  propagate_tags = "SERVICE"

  lifecycle {
    ignore_changes = [desired_count] # 将来的にオートスケールと共存しやすく
  }

  depends_on = [
    aws_lb_listener.http,
    aws_security_group_rule.alb_to_tasks_8000
  ]

  tags = { Project = "mlops-sklearn-portfolio" }
}
