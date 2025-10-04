# 既存の default VPC / サブネットを name/タグではなく "default" で拾う薄切り
data "aws_vpc" "default" { default = true }
data "aws_subnets" "default" {
  filter { 
    name = "vpc-id" 
    values = [data.aws_vpc.default.id] 
    }
}

data "aws_lb_target_group" "api" { name = "mlops-api-tg" }
data "aws_cloudwatch_log_group" "api" { name = "/mlops/api" }

# ECR リポジトリURIを region / account から補完（完全URIが var.ecr_repo に来てもOK）
data "aws_caller_identity" "current" {}
locals {
  ecr_repo_uri = can(regex(".amazonaws.com/", var.ecr_repo)) ? var.ecr_repo : "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com/${var.ecr_repo}"
  image_uri = "${local.ecr_repo_uri}:${var.image_tag}"
}

# IAM ロールは同一モジュール内の aws_iam_role リソースで作成する
# （外部リソースへの依存を避ける）

resource "aws_ecs_task_definition" "api" {
  family                   = "${var.project}-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512

  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "api",
      image     = var.ecr_repository_url != "" ? "${var.ecr_repository_url}:${var.image_tag}" : local.image_uri,
      essential = true,
      portMappings = [{
        containerPort = var.container_port, hostPort = var.container_port, protocol = "tcp"
      }],
      environment = [
        { name = "MODEL_PATH",   value = "/app/models/model_openml_adult.joblib" },
        { name = "MODEL_S3_URI", value = "s3://<BUCKET>/mlops-sklearn-portfolio/models/latest/model_openml_adult.joblib" },
        { name = "LOG_JSON",     value = "1" }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = data.aws_cloudwatch_log_group.api.name
          awslogs-region        = var.region
          awslogs-stream-prefix = "api"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "api" {
  name            = "mlops-api-svc"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.api.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = data.aws_subnets.default.ids
    security_groups = [var.tasks_sg_id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = var.tg_arn
    container_name   = "api"
    container_port   = var.container_port
  }

  health_check_grace_period_seconds = 60
  propagate_tags = "SERVICE"

  lifecycle {
    ignore_changes = [desired_count]
  }

  tags = { Project = "mlops-sklearn-portfolio" }

  deployment_circuit_breaker { 
    enable = true
    rollback = true 
  }
}
