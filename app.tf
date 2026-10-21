# Everything the forms-validation app needs besides the cluster:
#   ECR      images of the backend and the frontend
#   S3       private, encrypted bucket for uploaded files and page images (never in the database)
#   RDS      PostgreSQL on its own server, private subnets only, daily backups + point-in-time restore
#   Secrets  database connection and Gemini keys in Secrets Manager (read by External Secrets)
#   IRSA     an IAM role for the backend pod: this bucket only

locals {
  app_service_account = "backend"
  files_bucket_name   = "${local.name_prefix}-files-${data.aws_caller_identity.current.account_id}"
}

####### ECR #######

resource "aws_ecr_repository" "app" {
  for_each             = toset(["backend", "frontend"])
  name                 = "${local.name_prefix}-${each.key}"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

####### S3 — files #######

resource "aws_s3_bucket" "files" {
  bucket        = local.files_bucket_name
  force_destroy = var.files_bucket_force_destroy
}

resource "aws_s3_bucket_public_access_block" "files" {
  bucket                  = aws_s3_bucket.files.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "files" {
  bucket = aws_s3_bucket.files.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "files" {
  bucket = aws_s3_bucket.files.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# A deleted or overwritten page image can be recovered.
resource "aws_s3_bucket_versioning" "files" {
  bucket = aws_s3_bucket.files.id
  versioning_configuration {
    status = "Enabled"
  }
}

data "aws_iam_policy_document" "files_tls_only" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.files.arn, "${aws_s3_bucket.files.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "files" {
  bucket     = aws_s3_bucket.files.id
  policy     = data.aws_iam_policy_document.files_tls_only.json
  depends_on = [aws_s3_bucket_public_access_block.files]
}

####### IRSA — the backend pod may use this bucket, nothing else #######

resource "aws_iam_policy" "backend_files" {
  name = "${local.name_prefix}-backend-files"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = "${aws_s3_bucket.files.arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = aws_s3_bucket.files.arn
      }
    ]
  })
}

module "backend_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.30.0"

  role_name        = "${local.name_prefix}-backend"
  role_policy_arns = { files = aws_iam_policy.backend_files.arn }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["${var.app_namespace}:${local.app_service_account}"]
    }
  }
}

####### RDS PostgreSQL — a separate database server #######

resource "random_password" "db" {
  length  = 32
  special = false # goes into a connection URL
}

resource "aws_db_subnet_group" "app" {
  name       = "${local.name_prefix}-db"
  subnet_ids = module.network.private_subnet_ids
}

resource "aws_security_group" "db" {
  name        = "${local.name_prefix}-db"
  description = "PostgreSQL - reachable only from the EKS nodes"
  vpc_id      = module.network.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "db_from_nodes" {
  for_each = {
    nodes   = module.eks.node_security_group_id
    cluster = module.eks.cluster_primary_security_group_id
  }
  security_group_id            = aws_security_group.db.id
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  description                  = "PostgreSQL from EKS (${each.key})"
}

resource "aws_db_instance" "app" {
  identifier     = "${local.name_prefix}-db"
  engine         = "postgres"
  engine_version = "16"
  instance_class = var.db_instance_class

  allocated_storage     = 20
  max_allocated_storage = 100
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = "forms"
  username = "lab"
  password = random_password.db.result

  db_subnet_group_name   = aws_db_subnet_group.app.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false
  multi_az               = var.db_multi_az # true = a standby server takes over automatically if the main one fails

  # Daily automatic backups kept 7 days, and restore to any second in that window.
  backup_retention_period   = 7
  backup_window             = "00:00-01:00"
  maintenance_window        = "sun:01:30-sun:02:30"
  copy_tags_to_snapshot     = true
  skip_final_snapshot       = false
  final_snapshot_identifier = "${local.name_prefix}-db-final"
  deletion_protection       = var.db_deletion_protection
  apply_immediately         = true
}

####### Secrets Manager (names under "<prefix>/" — the only ones External Secrets may read) #######

resource "aws_secretsmanager_secret" "db" {
  name                    = "${local.name_prefix}/db"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    DATABASE_URL = "postgresql+psycopg://${aws_db_instance.app.username}:${random_password.db.result}@${aws_db_instance.app.address}:${aws_db_instance.app.port}/${aws_db_instance.app.db_name}"
  })
}

# Created empty: the keys are put in with the AWS CLI, so they never appear in Terraform state or in Git.
resource "aws_secretsmanager_secret" "gemini" {
  name                    = "${local.name_prefix}/gemini"
  recovery_window_in_days = 0
}
