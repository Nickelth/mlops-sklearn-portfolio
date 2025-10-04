# 実行ロール（ログ/ECR Pull 用）
resource "aws_iam_role" "ecs_task_execution" {
  name               = "mlops-ecsTaskExecutionRole"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume.json
}

data "aws_iam_policy_document" "ecs_task_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals { 
      type = "Service" 
      identifiers = ["ecs-tasks.amazonaws.com"] 
    }
  }
}

resource "aws_iam_role_policy_attachment" "ecs_task_exec_attach" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# アプリ用タスクロール（今は最小。後でS3やSSM読むなら権限追加）
resource "aws_iam_role" "ecs_task_role" {
  name               = "mlops-ecsTaskRole"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume.json
}

# --- モデル取得専用の最小権限（S3:GetObject） ---
resource "aws_iam_policy" "s3_get_model" {
name = "${var.project}-ecs-s3-get-model"
policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
    Sid      = "GetModelObject",
    Effect   = "Allow",
    Action   = ["s3:GetObject"],
    Resource = "arn:aws:s3:::nickelth-mlops-artifacts/mlops-sklearn-portfolio/models/latest/*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "task_s3_attach" {
role       = aws_iam_role.ecs_task_role.name
policy_arn = aws_iam_policy.s3_get_model.arn
}