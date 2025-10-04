locals { name = "${var.project}-ecs" }

// infra/30-ecs-alb-mlops/ecs.tf  （ecs_cluster / taskdef / service の例）

resource "aws_ecs_cluster" "this" {
  name = "mlops-api-cluster"
  setting { 
    name = "containerInsights"
    value = "enabled" 
  }
  tags = { Project = var.project }
}

resource "aws_ecs_task_definition" "api" {
  family                   = "mlops-sklearn-portfolio-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu    = "256"
  memory = "512"

  execution_role_arn = aws_iam_role.ecs_task_execution.arn
  task_role_arn      = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([{
    name  = "api"
    image = var.image
    essential = true
    portMappings = [{ containerPort = var.container_port, hostPort = var.container_port, protocol = "tcp" }]
    environment = [
      { name = "LOG_JSON",   value = "1" },
      { name = "MODEL_PATH", value = "/app/models/model_openml_adult.joblib" },
      { name = "MODEL_S3_URI", value = "s3://<BUCKET>/mlops-sklearn-portfolio/models/latest/model_openml_adult.joblib" },
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = var.log_group_name
        awslogs-region        = var.region
        awslogs-stream-prefix = "api"
      }
    }
  }])

  tags_all = { Env="dev", Managed="terraform", Project=var.project }
}

resource "aws_ecs_service" "api" {
  name            = "mlops-api-svc"
  cluster         = aws_ecs_cluster.this.arn
  task_definition = aws_ecs_task_definition.api.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"
  propagate_tags  = "SERVICE"
  health_check_grace_period_seconds = 60
  deployment_circuit_breaker { 
    enable = true
    rollback = true 
  }

  load_balancer {
    target_group_arn = var.tg_arn
    container_name   = "api"
    container_port   = var.container_port
  }

  network_configuration {
    assign_public_ip = true
    security_groups  = [var.tasks_sg_id]
    subnets          = var.subnet_ids
  }

  tags = { Project = var.project }
}
