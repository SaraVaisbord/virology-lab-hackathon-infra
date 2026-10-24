data "aws_caller_identity" "current" {}
terraform {
  backend "s3" {}
}
locals {
  name_prefix = "${var.common_tags.owner}-${var.common_tags.app_name}"
}

module "network" {
  source      = "./modules/network"
  name_prefix = local.name_prefix
  vpc_cidrs   = var.vpc_cidrs
  ha          = var.ha
  # common_tags        = var.common_tags
}

module "eks" {
  source                                   = "terraform-aws-modules/eks/aws"
  version                                  = "20.37.2" # pinned: the version this setup was proven with
  cluster_name                             = "${var.common_tags.owner}-cluster"
  cluster_version                          = var.cluster_version
  subnet_ids                               = module.network.subnet_ids
  vpc_id                                   = module.network.vpc_id
  cluster_endpoint_public_access           = true
  enable_cluster_creator_admin_permissions = true
  authentication_mode                      = "API_AND_CONFIG_MAP"
  tags                                     = var.common_tags
  access_entries = var.enable_github_actions_access ? {
    github_actions = {
      principal_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.github_actions_role_name}"
      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  } : {}
  cluster_security_group_additional_rules = {
    ingress_github_actions = {
      description = "Allow GitHub Actions to reach API Server"
      protocol    = "tcp"
      from_port   = 443
      to_port     = 443
      type        = "ingress"
      cidr_blocks = var.allowed_cidr_blocks
    }
  }

  eks_managed_node_groups = {
    main = {
      name           = "${var.common_tags.owner}-eks-node"
      capacity_type  = "ON_DEMAND"
      desired_size   = var.node_count
      max_size       = var.node_count # a new account allows only 5 vCPUs: never more than this many nodes
      min_size       = 1
      instance_types = [var.node_type]
      update_config = {
        max_unavailable = 1 # replace nodes one by one instead of adding extra ones during updates
      }
    }
  }
}


module "eks_blueprints_addons" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "1.23.0" # pinned: newer 1.x needs Helm provider 3

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn

  eks_addons = {
    aws-ebs-csi-driver = {
      most_recent              = true
      service_account_role_arn = module.ebs_csi_irsa_role.iam_role_arn
    }
    coredns = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
  }

  enable_aws_load_balancer_controller = true
  enable_external_secrets             = true
  external_secrets = {
    service_account_role_arn = module.external_secrets_irsa_role.iam_role_arn
    # The chart's CRDs make Helm download the whole cluster OpenAPI schema first, which times out on a slow
    # connection ("failed to download openapi"). The API server still validates every object on create.
    disable_openapi_validation = true
  }
}

module "ebs_csi_irsa_role" {
  source                = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version               = "5.30.0"
  role_name             = "${local.name_prefix}-ebs-csi"
  attach_ebs_csi_policy = true
  tags                  = var.common_tags

  oidc_providers = {
    ex = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
}
module "lb_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.30.0"

  role_name                              = "${local.name_prefix}-lb-controller"
  attach_load_balancer_controller_policy = true
  tags                                   = var.common_tags

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}

module "external_secrets_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.30.0"

  role_name = "${local.name_prefix}-external-secrets"
  tags      = var.common_tags

  role_policy_arns = {
    policy = aws_iam_policy.external_secrets.arn
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["external-secrets:external-secrets"]
    }
  }
}

resource "aws_iam_policy" "external_secrets" {
  name        = "${local.name_prefix}-external-secrets-policy"
  description = "Minimal permissions for External Secrets Operator"
  tags        = var.common_tags

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [
          "arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:${local.name_prefix}/*"
        ]
      }
    ]
  })
}

data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

module "ebs_csi_storageclass" {
  source                 = "./modules/ebs-csi-storageclass"
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this.token
}
