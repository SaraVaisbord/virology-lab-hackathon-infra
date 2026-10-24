output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "SG" {
  value = {
    "cluster_primary_security_group_id" = module.eks.cluster_primary_security_group_id
    "cluster_security_group_id"         = module.eks.cluster_security_group_id
    "node_security_group_id"            = module.eks.node_security_group_id
  }
}


output "cluster_connect" {
  value = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}

# ── for the Kubernetes manifests (virology-lab-hackathon-k8s) ──

output "ecr_repositories" {
  value = { for name, repo in aws_ecr_repository.app : name => repo.repository_url }
}

output "files_bucket" {
  value = aws_s3_bucket.files.bucket
}

output "backend_role_arn" {
  description = "IAM role of the backend service account (eks.amazonaws.com/role-arn annotation)"
  value       = module.backend_irsa_role.iam_role_arn
}

output "db_endpoint" {
  value = aws_db_instance.app.address
}

output "secret_names" {
  value = {
    db     = aws_secretsmanager_secret.db.name
    gemini = aws_secretsmanager_secret.gemini.name
  }
}

# ── the public address (dns.tf) ──

output "domain_name" {
  value = var.domain_name
}

output "name_servers" {
  description = "Put these four as the domain's nameservers at the registrar"
  value       = data.aws_route53_zone.main.name_servers
}

output "hosted_zone_id" {
  value = data.aws_route53_zone.main.zone_id
}

output "certificate_arn" {
  value = aws_acm_certificate_validation.main.certificate_arn
}
