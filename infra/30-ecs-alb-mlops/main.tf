variable "region"     { type = string }
variable "image_tag"  { 
    type = string  
    default = "latest" 
    }
variable "ecr_repo"   { 
    type = string  
    default = "mlops-sklearn-portfolio" 
    }
variable "container_port" { 
    type = number 
    default = 8000 
    }

# 既存の default VPC / サブネットを name/タグではなく "default" で拾う薄切り
data "aws_vpc" "default" { default = true }
data "aws_subnets" "default" {
  filter { 
    name = "vpc-id" 
    values = [data.aws_vpc.default.id] 
    }
}

# 既存の SG/TG/LogGroup は “名前” で引く
data "aws_security_group" "tasks" { 
    filter { 
        name="group-name" 
        values=["mlops-ecs-tasks"] 
    } 
}
data "aws_security_group" "alb"   { 
    filter { 
        name="group-name" 
        values=["mlops-alb"] 
    } 
}

data "aws_lb_target_group" "api" { name = "mlops-api-tg" }
data "aws_cloudwatch_log_group" "api" { name = "/mlops/api" }

# ECR リポジトリURIを region / account から補完（完全URIが var.ecr_repo に来てもOK）
data "aws_caller_identity" "me" {}
locals {
  ecr_repo_uri = can(regex(".amazonaws.com/", var.ecr_repo)) ? var.ecr_repo : "${data.aws_caller_identity.me.account_id}.dkr.ecr.${var.region}.amazonaws.com/${var.ecr_repo}"
  image_uri = "${local.ecr_repo_uri}:${var.image_tag}"
}

# IAM ロールは既存名前でdata参照（作成は 9/15 で済んでいる想定）
data "aws_iam_role" "task_execution" { name = "mlops-ecsTaskExecutionRole" }
data "aws_iam_role" "task_role"      { name = "mlops-ecsTaskRole" }

resource "aws_ecs_cluster" "this" {
  name = "mlops-api-cluster"
  setting { 
    name="containerInsights" 
    value="enabled" 
    }
  tags = { Project = "mlops-sklearn-portfolio" }
}

resource "aws_ecs_task_definition" "api" {
  family                   = "mlops-api-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = data.aws_iam_role.task_execution.arn
  task_role_arn            = data.aws_iam_role.task_role.arn

  container_definitions = jsonencode([{
    name         = "api"
    image        = local.image_uri
    essential    = true
    portMappings = [{ containerPort = var.container_port, hostPort = var.container_port, protocol = "tcp" }]
    environment  = [
      { name = "MODEL_PATH",   value = "/app/models/model_openml_adult.joblib" },
      { name = "MODEL_S3_URI", value = "s3://nickelth-mlops-artifacts/mlops-sklearn-portfolio/models/latest/model_openml_adult.joblib" },
      { name = "LOG_JSON",     value = "1" }
    ]
    logConfiguration = {
      logDriver = "awslogs",
      options = {
        awslogs-group         = data.aws_cloudwatch_log_group.api.name,
        awslogs-region        = var.region,
        awslogs-stream-prefix = "api"
      }
    }
  }])
}

resource "aws_ecs_service" "api" {
  name            = "mlops-api-svc"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.api.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    assign_public_ip = true
    subnets          = data.aws_subnets.default.ids
    security_groups  = [data.aws_security_group.tasks.id]
  }

  load_balancer {
    target_group_arn = data.aws_lb_target_group.api.arn
    container_name   = "api"
    container_port   = var.container_port
  }

  health_check_grace_period_seconds = 60
  propagate_tags = "SERVICE"

  deployment_circuit_breaker { 
    enable = true
    rollback = true 
  }

  depends_on = [] # ネットワークは data 参照なので module 間の明示依存は不要
  tags = { Project = "mlops-sklearn-portfolio" }
}
