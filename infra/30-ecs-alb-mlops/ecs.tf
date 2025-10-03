locals { name = "${var.project}-ecs" }

# ========== Task Role（アプリ用の実行ロール） ==========
resource "aws_iam_role" "task_role" {
  name = "${local.name}-task-role"
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
  name = "${local.name}-s3-get-model"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Sid      = "GetModelObject"
      Effect   = "Allow"
      Action   = ["s3:GetObject"]
      Resource = "arn:aws:s3:::nickelth-mlops-artifacts/mlops-sklearn-portfolio/models/latest/*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "task_s3_attach" {
  role       = aws_iam_role.task_role.name
  policy_arn = aws_iam_policy.s3_get_model.arn
}