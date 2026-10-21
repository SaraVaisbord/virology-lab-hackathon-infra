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
    owner           = "terraform-eks"
    managedBy       = "terraform"
    usage           = "training"
    app_name        = "PeopleManagement"
  }
}

variable "region" {
  type        = string
  default     = "us-east-2"
}

variable "cluster_version" {
    type      = string
}

variable "node_type" {
  type        = string
}

variable "github_actions_role_name" {
  type    = string
  default = "GitHubActions-CICD-Role"
}

variable "allowed_cidr_blocks" {
  type    = list(string)
  default = ["0.0.0.0/0"]
}
