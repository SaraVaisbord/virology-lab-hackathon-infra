variable "ha" {
  type        = number
  default     = "3"
  description = "High Availabilty Redundancy"
}


variable "vpc_cidrs" {
  description = "vpc cidrs"
  type        = string
}

variable "common_tags" {
  default = {
    owner     = "virology-lab"
    managedBy = "terraform"
    usage     = "hackathon"
    app_name  = "forms-validation"
  }
}

variable "region" {
  type    = string
  default = "us-east-1"
}

# ── the forms-validation app (app.tf) ──

variable "app_namespace" {
  description = "Kubernetes namespace of the app (the backend's IAM role is bound to its service account there)"
  type        = string
  default     = "virology-lab"
}

variable "db_instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "db_backup_retention_days" {
  description = "RDS automatic backups (point-in-time restore window). AWS free-plan accounts allow only 1 day; 7 on a paid plan."
  type        = number
  default     = 1
}

variable "db_multi_az" {
  description = "A standby database server in another zone that takes over automatically (doubles the DB cost)"
  type        = bool
  default     = false
}

variable "db_deletion_protection" {
  description = "Refuse to delete the database (set false only to tear the environment down)"
  type        = bool
  default     = true
}

variable "files_bucket_force_destroy" {
  description = "Allow 'terraform destroy' to delete the files bucket even when it still holds files"
  type        = bool
  default     = false
}

variable "enable_github_actions_access" {
  description = "Give the GitHub Actions role cluster-admin access (the role must already exist)"
  type        = bool
  default     = false
}

variable "cluster_version" {
  type = string
}

variable "node_type" {
  type = string
}

variable "node_count" {
  description = "Worker nodes (also the maximum). node_count x vCPUs of node_type must fit the account's EC2 vCPU quota."
  type        = number
  default     = 2
}

variable "github_actions_role_name" {
  type    = string
  default = "GitHubActions-CICD-Role"
}

variable "allowed_cidr_blocks" {
  type    = list(string)
  default = ["0.0.0.0/0"]
}
