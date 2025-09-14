# infra/ecs.tf  —— 重複ナシ版（既存 network.tf / log.tf を参照）

# 既存: data.aws_vpc.default, data.aws_subnets.default（network.tf）
# 既存: aws_security_group.alb, aws_security_group.tasks（network.tf）
# 既存: aws_cloudwatch_log_group.api（log.tf）
# 既存: aws_lb_target_group.api / aws_lb (alb.tf 相当) を想定

variable "ecr_repo"        { type = string }                 # 例: 1234....dkr.ecr.us-west-2.amazonaws.com/mlops-sklearn-portfolio
variable "image_tag"       { 
    type = string  
    default = "latest"
}
variable "container_port"  { 
    type = number  
    default = 8000
}

# タスク実行ロール（ECR pull / CloudWatch Logs）
resource "aws_iam_role" "exec" {
  name               = "${var.project}-ecs-exec"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{ 
        Effect="Allow", 
        Principal={ Service="ecs-tasks.amazonaws.com" }, 
        Action="sts:AssumeRole" 
    }]
  })
}
resource "aws_iam_role_policy_attachment" "exec_ecr_logs" {
  role       = aws_iam_role.exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# タスクロール（必要に応じて SSM/Secrets ポリシーを別途付与）
resource "aws_iam_role" "task" {
  name               = "${var.project}-ecs-task"
  assume_role_policy = aws_iam_role.exec.assume_role_policy
}

# ALB からタスク:8000 への INGRESS を追加（tasks SG は network.tf の既存）
resource "aws_security_group_rule" "alb_to_tasks_8000" {
  type                     = "ingress"
  from_port                = var.container_port
  to_port                  = var.container_port
  protocol                 = "tcp"
  security_group_id        = aws_security_group.tasks.id
  source_security_group_id = aws_security_group.alb.id
  description              = "Allow ALB to tasks on ${var.container_port}/tcp"
}

# ECS Cluster
resource "aws_ecs_cluster" "api" {
  name = "${var.project}-cluster"
}

# Task Definition（Fargate）
resource "aws_ecs_task_definition" "api" {
  family                   = "${var.project}-task"
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
      portMappings = [{ 
        containerPort = var.container_port, 
        hostPort = var.container_port, 
        protocol = "tcp"
        }]
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
      command = ["uvicorn","api.app:app","--host","0.0.0.x","--port", tostring(var.container_port)]
      logConfiguration = {
        logDriver = "awslogs",
        options = {
          awslogs-group         = aws_cloudwatch_log_group.api.name,
          awslogs-region        = var.region,            # ← providers.tf/variables.tf の既存 var.region を利用
          awslogs-stream-prefix = "api"
        }
      }
    }
  ])
}

# Service（ALB TG にぶら下げる / まずは Public IP で起動確認）
resource "aws_ecs_service" "api" {
  name            = "${var.project}-svc"
  cluster         = aws_ecs_cluster.api.id
  task_definition = aws_ecs_task_definition.api.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.tasks.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.api.arn
    container_name   = "api"
    container_port   = var.container_port
  }

  depends_on = [aws_security_group_rule.alb_to_tasks_8000]
}
