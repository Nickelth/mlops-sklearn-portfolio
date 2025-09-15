############################
# ECS Cluster
############################
resource "aws_ecs_cluster" "this" {
  name = "mlops-ecs"
  setting { name = "containerInsights" value = "enabled" }
  tags = { Project = "mlops-sklearn-portfolio" }
}

############################
# IAM (Execution / Task)
############################
data "aws_iam_policy_document" "ecs_tasks_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals { 
      type = "Service" 
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "task_execution" {
  name               = "mlops-ecsTaskExecutionRole"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_trust.json
  tags = { Project = "mlops-sklearn-portfolio" }
}

resource "aws_iam_role_policy_attachment" "exec_managed" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# アプリ用（必要最小。今は空でOK）
resource "aws_iam_role" "task_role" {
  name               = "mlops-ecsTaskRole"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_trust.json
  tags = { Project = "mlops-sklearn-portfolio" }
}

############################
# ECR image (:latest)
############################
variable "ecr_repo" { type = string, default = "mlops-sklearn-portfolio" }
data "aws_ecr_repository" "repo" { name = var.ecr_repo }
locals {
  image_uri = "${data.aws_ecr_repository.repo.repository_url}:latest"
}

############################
# セキュリティグループ（ALB→タスク）
############################
# network.tfで作ったSGに“ALBから8000/TCPだけ開ける”を追加
resource "aws_security_group_rule" "tasks_from_alb_8000" {
  type                     = "ingress"
  security_group_id        = aws_security_group.tasks.id
  from_port                = 8000
  to_port                  = 8000
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
}

############################
# Task Definition
############################
resource "aws_cloudwatch_log_group" "api_ref" {
  # 既存 /mlops/api を参照したいが module間依存回避で同名作成OK（同名既存ならno-op）
  name              = "/mlops/api"
  retention_in_days = 30
}

locals {
  container_name = "api"
  container_port = 8000
  env_base = [
    { name = "MODEL_PATH", value = "/app/models/model_openml_adult.joblib" },
    { name = "LOG_JSON",   value = "1" },
    # /metrics で使う予定のダミー
    { name = "APP_VERSION", value = "v0-dev" },
    { name = "GIT_SHA",     value = "TBD" },
  ]
}

resource "aws_ecs_task_definition" "api" {
  family                   = "mlops-api"
  cpu                      = "256"
  memory                   = "512"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task_role.arn

  container_definitions = jsonencode([
    {
      name  = local.container_name
      image = local.image_uri
      portMappings = [{ 
        ontainerPort = local.container_port, 
        hostPort = local.container_port, 
        protocol = "tcp" 
      }]
      essential = true
      environment = local.env_base
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.api_ref.name
          awslogs-region        = var.region
          awslogs-stream-prefix = "api"
        }
      }
    }
  ])

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  tags = { Project = "mlops-sklearn-portfolio" }
}

############################
# Service (Fargate 1タスク / ALB配下)
############################
resource "aws_ecs_service" "api" {
  name            = "mlops-api-svc"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.api.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  load_balancer {
    target_group_arn = aws_lb_target_group.api.arn
    container_name   = local.container_name
    container_port   = local.container_port
  }

  network_configuration {
    assign_public_ip = true
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.tasks.id]
  }

  lifecycle {
    ignore_changes = [task_definition] # 後日のローリング更新時に便利
  }

  depends_on = [aws_lb_listener.http, aws_security_group_rule.tasks_from_alb_8000]
  tags = { Project = "mlops-sklearn-portfolio" }
}
