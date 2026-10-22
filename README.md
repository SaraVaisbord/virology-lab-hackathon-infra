# AWS Infrastructure — Commitment Form Validation

Terraform for the AWS environment that runs
[virology-lab-hackathon-app](https://github.com/SaraVaisbord/virology-lab-hackathon-app).
The application itself is deployed by [virology-lab-hackathon-k8s](https://github.com/SaraVaisbord/virology-lab-hackathon-k8s).

## What it provisions

| Component | Details | File |
|---|---|---|
| Network | VPC with public subnets for the cluster (tagged `kubernetes.io/role/elb` so the ALB can be placed on them) and **private subnets with no internet route** for the database | `modules/network` |
| Kubernetes | Amazon EKS 1.31, managed node group of `m7i-flex.large` instances (AWS Free Tier eligible) | `MAIN.tf` |
| Cluster add-ons | EBS CSI driver (encrypted volumes), AWS Load Balancer Controller, External Secrets Operator | `MAIN.tf` |
| Database | **Amazon RDS for PostgreSQL 16** in the private subnets, reachable only from the cluster, encrypted at rest. Automated backups with point-in-time recovery, a final snapshot on deletion, and deletion protection. Optional Multi-AZ standby (`db_multi_az`) | `app.tf` |
| File storage | **Private S3 bucket** for uploads and page images — public access blocked, encrypted, versioned, HTTPS-only | `app.tf` |
| Access | IAM role for the backend's service account (IRSA), scoped to that bucket only | `app.tf` |
| Container images | Two ECR repositories (backend, frontend) with scan-on-push | `app.tf` |
| Secrets | AWS Secrets Manager: the database connection (generated) and the application keys (set manually, never through Terraform or Git) | `app.tf` |
| Domain & TLS | Route 53 hosted zone for `domain_name` (registered elsewhere; its NS records point here) and a free ACM certificate for the domain and `www`, DNS-validated and renewed automatically | `dns.tf` |
| Backups | AWS Backup daily plan with 7-day retention for all tagged resources | `backup.tf` |
| Terraform state | Dedicated S3 key with native S3 state locking (`use_lockfile`, no DynamoDB table) | `backend.hcl` |

## Usage

```bash
aws sso login
terraform init -backend-config=backend.hcl
terraform plan -out tfplan
terraform apply tfplan          # ~20–25 minutes (cluster and database)
```

`terraform.tfvars` (not committed):

```hcl
common_tags = {
  owner     = "virology-lab"
  managedBy = "terraform"
  usage     = "hackathon"
  app_name  = "forms-validation"
}
region          = "us-east-1"
vpc_cidrs       = "10.0.0.0/16"
ha              = 2
cluster_version = "1.31"
node_type       = "m7i-flex.large"
domain_name     = "virolab.site"
```

### After the first apply

1. **Domain** — set the four `name_servers` from `terraform output` as the domain's nameservers at the registrar.
   The certificate is issued once the change propagates.
2. **Application keys** — store them in the `<prefix>/gemini` secret. Every key in it becomes an environment variable
   of the backend (External Secrets), so it holds all AI and login secrets:

   ```bash
   aws secretsmanager put-secret-value --secret-id virology-lab-forms-validation/gemini \
     --secret-string file://secret.json        # a temporary file — keys never go on the command line
   ```

   ```json
   {
     "ANTHROPIC_API_KEY": "…", "ANTHROPIC_API_KEY_2": "…",
     "GEMINI_API_KEY": "…", "GEMINI_API_KEY_2": "…",
     "AUTH_EMAIL": "…", "SMTP_HOST": "…", "SMTP_USERNAME": "…", "SMTP_PASSWORD": "…", "AUTH_SECRET": "…"
   }
   ```

3. **Deploy the application** — `deploy.ps1` in [virology-lab-hackathon-k8s](https://github.com/SaraVaisbord/virology-lab-hackathon-k8s).

## Outputs

`cluster_connect`, `ecr_repositories`, `files_bucket`, `secret_names`, `name_servers`, `hosted_zone_id`,
`certificate_arn` and `domain_name` — read by the deployment script, so no value is copied by hand.

## Teardown

The database is deletion-protected and the bucket is not destroyed while it holds files. To remove everything:

1. **Remove the application first:** `kubectl delete namespace virology-lab`. The ALB is created by Kubernetes, not
   by Terraform — left behind, it blocks the VPC from being deleted.
2. In `terraform.tfvars` set `db_deletion_protection = false` and `files_bucket_force_destroy = true`, then
   `terraform apply`.
3. `terraform destroy`.

A final database snapshot (`virology-lab-forms-validation-db-final`) is kept. The Terraform state bucket
(`backend.hcl`) is not managed by this configuration and is not deleted.

## Estimated cost (us-east-1)

EKS control plane, two nodes, an ALB and a small RDS instance: about **$0.35/hour (~$8–9/day)**, plus AI usage.
