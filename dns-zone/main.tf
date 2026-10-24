# The Route 53 hosted zone of the domain — created once and kept across environment teardowns.
# Its four nameservers are set at the outside registrar; a zone recreated by every apply/destroy would get
# new ones each time and the domain would stop resolving until the registrar is updated again.
# The main configuration (../dns.tf) only reads this zone; its own state is separate so `terraform destroy`
# there never touches it.
#
#   terraform init && terraform apply      (once)
#   terraform output name_servers          → the registrar

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket       = "virology-lab-tf-state-475568920419"
    key          = "virology-lab-hackathon/dns-zone/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      owner     = "virology-lab"
      managedBy = "terraform"
      usage     = "hackathon"
      app_name  = "forms-validation"
    }
  }
}

variable "domain_name" {
  type    = string
  default = "virolab.site"
}

resource "aws_route53_zone" "main" {
  name = var.domain_name

  lifecycle {
    prevent_destroy = true
  }
}

output "name_servers" {
  description = "Put these four as the domain's nameservers at the registrar"
  value       = aws_route53_zone.main.name_servers
}

output "hosted_zone_id" {
  value = aws_route53_zone.main.zone_id
}
