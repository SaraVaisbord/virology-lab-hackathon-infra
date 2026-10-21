resource "aws_backup_vault" "eks_backup" {
  name = "${local.name_prefix}-backup-vault"
  tags = var.common_tags
}

resource "aws_backup_plan" "eks_backup" {
  name = "${local.name_prefix}-backup-plan"

  rule {
    rule_name         = "daily_backup"
    target_vault_name = aws_backup_vault.eks_backup.name
    schedule          = "cron(0 2 * * ? *)"

    lifecycle {
      delete_after = 7
    }
  }

  tags = var.common_tags
}

resource "aws_iam_role" "backup_role" {
  name = "${local.name_prefix}-backup-role"
  tags = var.common_tags

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "backup.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "backup_policy" {
  role       = aws_iam_role.backup_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_backup_selection" "eks_volumes" {
  name         = "${local.name_prefix}-ebs-selection"
  plan_id      = aws_backup_plan.eks_backup.id
  iam_role_arn = aws_iam_role.backup_role.arn

  selection_tag {
    type  = "STRINGEQUALS"
    key   = "owner"
    value = var.common_tags.owner
  }
}
