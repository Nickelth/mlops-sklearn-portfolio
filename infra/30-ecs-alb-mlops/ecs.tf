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