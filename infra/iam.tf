# 後日：必要なら S3 専用ポリシーをこのロールに付与する
# data "aws_iam_role" "github_oidc" { name = var.github_oidc_role_name }
# resource "aws_iam_role_policy" "s3_write" {
#   name   = "${var.project}-s3-write"
#   role   = data.aws_iam_role.github_oidc.name
#   policy = data.aws_iam_policy_document.s3_write.json
# }
