data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_security_group" "alb" {
  name        = "mlops-alb-sg"
  description = "ALB inbound 80/443"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.x/0"]
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.x/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.x/0"]
  }

  tags = { Project = "mlops-sklearn-portfolio" }
}

resource "aws_security_group" "tasks" {
  name        = "mlops-ecs-sg"
  description = "ECS tasks egress only"
  vpc_id      = data.aws_vpc.default.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.x/0"]
  }

  tags = { Project = "mlops-sklearn-portfolio" }
}

# ALBのSG -> ECSタスクのSG へ 8000/TCP を許可
resource "aws_security_group_rule" "alb_to_tasks_8000" {
  type                     = "ingress"
  from_port                = var.container_port
  to_port                  = var.container_port
  protocol                 = "tcp"
  security_group_id        = aws_security_group.tasks.id
  source_security_group_id = aws_security_group.alb.id
}
