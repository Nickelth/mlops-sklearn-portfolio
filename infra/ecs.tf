locals {
  # Allow passing either a bare repository name (default) or a fully-qualified
  # ECR repository URI via var.ecr_repo. The Terraform logic normalises this
  # to an absolute URI before appending the tag supplied via var.image_tag.
  ecr_repository_uri = can(regex(".amazonaws.com/", var.ecr_repo)) ? var.ecr_repo : "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com/${var.ecr_repo}"
  image_uri = "${local.ecr_repository_uri}:${var.image_tag}"
  name = "${var.project}-ecs"
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
  family                   = "${project}-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512

  execution_role_arn = aws_iam_role.task_exec.arn
  task_role_arn      = aws_iam_role.task_role.arn

  container_definitions = jsonencode([
    {
      name      = "app",
      image     = "${var.ecr_repository_url}:latest",
      essential = true,
      portMappings = [{
        containerPort = var.container_port, hostPort = var.container_port, protocol = "tcp"
      }],
      environment = [
        { name = "MODEL_PATH",   value = "models/model_openml_adult.joblib" },
        { name = "MODEL_S3_URI", value = "s3://nickelth-mlops-artifacts/mlops-sklearn-portfolio/models/latest/model_openml_adult.joblib" },
        { name = "LOG_JSON",     value = "1" },
        { name = "VERSION",      value = "0.0.0-dev" },
        { name = "GIT_SHA",      value = "0000000" }
      ],
      logConfiguration = {
        logDriver = "awslogs",
        options = {
          awslogs-group         = aws_cloudwatch_log_group.app.name,
          awslogs-region        = var.region,
          awslogs-stream-prefix = "app"
        }
      }
      # 最初はECSのhealthCheckは外す。ALBの健康診断だけに寄せる。
      # healthCheck = { ... }  # ← 付けない
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

# ========== Task Role（アプリ用の実行ロール） ==========
resource "aws_iam_role" "task_role" {
  name = "${locals.name}-task-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Action = "sts:AssumeRole",
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

# モデル取得専用の最小権限（S3:GetObject）
resource "aws_iam_policy" "s3_get_model" {
  name = "${locals.name}-s3-get-model"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Sid: "GetModelObject",
      Effect: "Allow",
      Action: ["s3:GetObject"],
      Resource: "arn:aws:s3://nickelth-mlops-artifacts/mlops-sklearn-portfolio/models/latest/*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "task_s3_attach" {
  role       = aws_iam_role.task_role.name
  policy_arn = aws_iam_policy.s3_get_model.arn
}