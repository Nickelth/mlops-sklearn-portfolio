# ====== 既存の default VPC / Subnets / TG を前提 ======
data "aws_vpc" "default" { default = true }
data "aws_subnets" "all_in_default" {
  filter { 
    name = "vpc-id" 
    values = [data.aws_vpc.default.id] 
  }
}

# すでに作成済みの ALB/TG を参照（リソース名が違う場合は修正）
data "aws_lb_target_group" "api" {
  arn = aws_lb_target_group.api.arn
}

# アプリ用 CloudWatch Logs グループ（作成済みなら data に置き換え可）
resource "aws_cloudwatch_log_group" "api" {
  name              = "/mlops/api"
  retention_in_days = 30
}

# タスク実行ロール（ECR Pull / Logs 出力に必要）
resource "aws_iam_role" "exec" {
  name               = "mlops-ecs-exec"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
        { 
            Effect="Allow", 
            Principal={ Service="ecs-tasks.amazonaws.com" }, 
            Action="sts:AssumeRole" 
        }
    ]
  })
}
resource "aws_iam_role_policy_attachment" "exec_ecr_logs" {
  role       = aws_iam_role.exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# アプリ用タスクロール（必要最小＝空。SSM/Secrets を読むなら別途付与）
resource "aws_iam_role" "task" {
  name               = "mlops-ecs-task"
  assume_role_policy = aws_iam_role.exec.assume_role_policy
}

# タスクが入る SG（まずは 8000 を全許可→後で ALB SG に絞る）
resource "aws_security_group" "tasks" {
  name        = "mlops-ecs-tasks"
  description = "Allow HTTP(8000) to tasks; tighten to ALB SG later"
  vpc_id      = data.aws_vpc.default.id
  ingress { 
        from_port=8000 
        to_port=8000 
        rotocol="tcp" 
        cidr_blocks=["0.0.0.x/0"]
    }
  egress  { 
        from_port=0    
        to_port=0    
        protocol="-1"  
        cidr_blocks=["0.0.0.x/0"]
    }
}

# ECS Cluster
resource "aws_ecs_cluster" "api" {
  name = "mlops-api-cluster"
}

# 画像タグは vars から。例: ecr_repo="4383....dkr.ecr.us-west-2.amazonaws.com/mlops-sklearn-portfolio", image_tag="latest"
variable "ecr_repo"   { type = string }
variable "image_tag"  { 
    type = string  
    default = "latest"
    }
variable "container_port" { 
    type = number 
    default = 8000 
    }

# Task Definition
resource "aws_ecs_task_definition" "api" {
  family                   = "mlops-api"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.exec.arn
  task_role_arn            = aws_iam_role.task.arn
  container_definitions = jsonencode([
    {
      name      = "api"
      image     = "${var.ecr_repo}:${var.image_tag}"
      essential = true
      portMappings = [
        { 
            containerPort = var.container_port, 
            hostPort = var.container_port, 
            protocol = "tcp" 
        }
      ]
      environment = [
        { 
            name = "MODEL_PATH", 
            value = "/app/models/model_openml_adult.joblib" 
        },
        { 
            name = "LOG_JSON",   
            value = "1" 
        }
      ]
      logConfiguration = {
        logDriver = "awslogs",
        options = {
          awslogs-group         = aws_cloudwatch_log_group.api.name,
          awslogs-region        = var.region,
          awslogs-stream-prefix = "api"
        }
      }
      command = ["uvicorn","api.app:app","--host","0.0.0.x","--port", tostring(var.container_port)]
    }
  ])
}

# 必要なら region 変数（outputs にも使う）
variable "aws_region" { type=string default="us-west-2" }

# Service（ALB の TG にぶら下げる / パブリックIPを付与してまずは動かす）
resource "aws_ecs_service" "api" {
  name            = "mlops-api-svc"
  cluster         = aws_ecs_cluster.api.id
  task_definition = aws_ecs_task_definition.api.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = data.aws_subnets.all_in_default.ids
    security_groups = [aws_security_group.tasks.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = data.aws_lb_target_group.api.arn
    container_name   = "api"
    container_port   = var.container_port
  }

  depends_on = [aws_cloudwatch_log_group.api]
}
