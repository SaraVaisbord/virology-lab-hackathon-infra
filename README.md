# 🚀 Infra-People-Management

> **Production-ready AWS EKS infrastructure** for the PeopleManagement application — fully automated with Terraform, featuring high availability, automated backups, and enterprise-grade security.

---

## 📐 Architecture

![Architecture Diagram](./architecture-diagram.png)

### Infrastructure Components

| Component | Description | Features |
|-----------|-------------|----------|
| **🌐 VPC** | Custom Virtual Private Cloud | Multi-AZ subnets, Internet Gateway, public routing |
| **☸️ EKS Cluster** | Managed Kubernetes (v1.31) | Auto-scaling node groups, API access control, RBAC |
| **💾 Storage** | EBS CSI Driver | GP3 volumes (default), encryption at rest, dynamic provisioning |
| **⚖️ Load Balancing** | AWS Load Balancer Controller | ALB/NLB integration, automatic ingress management |
| **🔐 Secrets Management** | External Secrets Operator | AWS Secrets Manager sync, IRSA authentication |
| **💼 Backup & Recovery** | AWS Backup | Daily snapshots, 7-day retention, tag-based selection |
| **🔒 State Management** | S3 + DynamoDB | Remote state, locking, versioning, team collaboration |

---

## ✨ Key Features

- ✅ **High Availability** — Multi-AZ deployment with configurable redundancy
- ✅ **Security First** — IRSA for pod-level IAM, encrypted storage, network policies
- ✅ **GitOps Ready** — GitHub Actions integration with cluster admin access
- ✅ **Auto-Scaling** — Managed node groups (1-3 nodes) with on-demand capacity
- ✅ **Disaster Recovery** — Automated daily backups with 7-day retention
- ✅ **Production Addons** — CoreDNS, VPC-CNI, Kube-proxy, EBS CSI, ALB Controller
- ✅ **Team Collaboration** — Remote state with locking prevents conflicts

---

## 🏗️ Project Structure

```
.
├── MAIN.tf                          # Main infrastructure orchestration
├── providers.tf                     # AWS, Kubernetes, Helm providers + S3 backend
├── variables.tf                     # Input variables
├── outputs.tf                       # Cluster connection info & security groups
├── backup.tf                        # AWS Backup configuration
├── backend.hcl.example              # Backend configuration template
├── terraform.tfvars                 # Variable values (not in Git)
└── modules/
    ├── network/                     # VPC, subnets, IGW, route tables
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    └── ebs-csi-storageclass/        # GP3 StorageClass configuration
        ├── main.tf
        ├── provider.tf
        ├── variables.tf
        └── outputs.tf
```

---

## 🛠️ Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| **Terraform** | `>= 1.0` | Infrastructure provisioning |
| **AWS CLI** | `>= 2.0` | AWS authentication & EKS access |
| **kubectl** | `>= 1.28` | Kubernetes cluster management |

### AWS Resources (Pre-deployment)

1. **S3 Bucket** — for Terraform state storage
   ```bash
   aws s3 mb s3://people-mgnt-tf-state-<YOUR_ACCOUNT_ID> --region us-east-1
   aws s3api put-bucket-versioning --bucket people-mgnt-tf-state-<YOUR_ACCOUNT_ID> --versioning-configuration Status=Enabled
   ```

2. **DynamoDB Table** — for state locking
   ```bash
   aws dynamodb create-table \
     --table-name people-mgnt-terraform-lock \
     --attribute-definitions AttributeName=LockID,AttributeType=S \
     --key-schema AttributeName=LockID,KeyType=HASH \
     --billing-mode PAY_PER_REQUEST \
     --region us-east-1
   ```

3. **IAM Role** — GitHub Actions role (if using CI/CD)
   - Role name: `GitHubActions-CICD-Role`
   - Trust policy: GitHub OIDC provider

---

## 🚀 Quick Start

### 1️⃣ Configure Backend

```bash
cp backend.hcl.example backend.hcl
```

Edit `backend.hcl`:
```hcl
bucket         = "people-mgnt-tf-state-123456789012"  # Your account ID
key            = "eks/terraform.tfstate"
region         = "us-east-1"
encrypt        = true
dynamodb_table = "people-mgnt-terraform-lock"
```

### 2️⃣ Set Variables

Create or edit `terraform.tfvars`:
```hcl
# General
common_tags = {
  owner    = "your-team"
  managedBy = "terraform"
  usage    = "production"
  app_name = "PeopleManagement"
}
region = "us-east-1"

# Network
vpc_cidrs = "10.0.0.0/16"
ha        = 3  # Number of availability zones

# EKS
cluster_version = "1.31"
node_type       = "t3a.medium"

# Security
allowed_cidr_blocks = ["0.0.0.0/0"]  # Restrict in production!
```

### 3️⃣ Initialize Terraform

```bash
terraform init -backend-config=backend.hcl
```

### 4️⃣ Plan & Apply

```bash
terraform plan -out=tfplan
terraform apply tfplan
```

⏱️ **Deployment time:** ~15-20 minutes

### 5️⃣ Connect to Cluster

```bash
# Get the connection command from outputs
terraform output cluster_connect

# Or manually:
aws eks update-kubeconfig --region <region> --name <owner>-cluster
kubectl get nodes
```

---

## 📋 Configuration Reference

### Input Variables

| Variable | Type | Required | Default | Description |
|----------|------|----------|---------|-------------|
| `vpc_cidrs` | `string` | ✅ | — | VPC CIDR block (e.g., `10.0.0.0/16`) |
| `cluster_version` | `string` | ✅ | — | EKS Kubernetes version (e.g., `1.31`) |
| `node_type` | `string` | ✅ | — | EC2 instance type for worker nodes |
| `allowed_cidr_blocks` | `list(string)` | ✅ | — | CIDRs allowed to access EKS API server |
| `region` | `string` | ❌ | `us-east-1` | AWS region for deployment |
| `ha` | `number` | ❌ | `3` | Number of availability zones / subnets |
| `github_actions_role_name` | `string` | ❌ | `GitHubActions-CICD-Role` | IAM role for GitHub Actions |
| `common_tags` | `map(string)` | ❌ | See below | Resource tags |

**Default Tags:**
```hcl
{
  owner     = "terraform-eks"
  managedBy = "terraform"
  usage     = "training"
  app_name  = "PeopleManagement"
}
```

### Outputs

| Output | Description | Example |
|--------|-------------|---------|
| `cluster_endpoint` | EKS API server endpoint | `https://ABC123.gr7.us-east-1.eks.amazonaws.com` |
| `SG.cluster_primary_security_group_id` | Primary cluster security group | `sg-0123456789abcdef0` |
| `SG.cluster_security_group_id` | Additional cluster security group | `sg-0123456789abcdef1` |
| `SG.node_security_group_id` | Node security group | `sg-0123456789abcdef2` |
| `cluster_connect` | Ready-to-run kubectl config command | `aws eks update-kubeconfig ...` |

---

## 🔐 Security Features

### IAM Roles for Service Accounts (IRSA)

| Service Account | Namespace | IAM Role | Permissions |
|-----------------|-----------|----------|-------------|
| `ebs-csi-controller-sa` | `kube-system` | `<prefix>-ebs-csi` | EBS volume management |
| `aws-load-balancer-controller` | `kube-system` | `<prefix>-lb-controller` | ALB/NLB provisioning |
| `external-secrets` | `external-secrets` | `<prefix>-external-secrets` | Secrets Manager read access |

### Network Security

- **API Server Access:** Configurable CIDR whitelist
- **Node Security Groups:** Managed by EKS with minimal required rules
- **Subnet Tagging:** Automatic ELB discovery (`kubernetes.io/role/elb`)

### Data Protection

- **Encryption at Rest:** All EBS volumes encrypted by default
- **State Encryption:** S3 backend with server-side encryption
- **Backup Encryption:** AWS Backup vault encryption

---

## 💾 Backup & Recovery

### Backup Schedule

- **Frequency:** Daily at 02:00 UTC
- **Retention:** 7 days
- **Scope:** All EBS volumes tagged with `owner = <your-owner-tag>`

### Manual Backup

```bash
aws backup start-backup-job \
  --backup-vault-name <prefix>-backup-vault \
  --resource-arn <volume-arn> \
  --iam-role-arn <backup-role-arn>
```

### Restore Process

1. Navigate to AWS Backup Console
2. Select recovery point
3. Choose "Restore" and configure target
4. Update PersistentVolume references in Kubernetes

---

## 🔧 Maintenance

### Upgrade EKS Version

```bash
# Update variable
vim terraform.tfvars  # Change cluster_version

# Apply changes
terraform plan -out=tfplan
terraform apply tfplan
```

### Scale Node Group

Edit `MAIN.tf`:
```hcl
eks_managed_node_groups = {
  main = {
    desired_size = 3  # Change this
    max_size     = 5  # And this
    min_size     = 2  # And this
  }
}
```

### Add New Subnet

```bash
# Increase HA value
vim terraform.tfvars  # ha = 4

terraform apply
```

---

## 🧹 Cleanup

```bash
# Destroy all resources
terraform destroy

# Clean up backend resources (manual)
aws s3 rb s3://people-mgnt-tf-state-<ACCOUNT_ID> --force
aws dynamodb delete-table --table-name people-mgnt-terraform-lock
```

⚠️ **Warning:** This will delete the EKS cluster and all associated resources. Ensure backups are available if needed.

---

## 📚 Module Documentation

### `modules/network`

Creates VPC infrastructure with multi-AZ support.

**Inputs:**
- `vpc_cidrs` — VPC CIDR block
- `ha` — Number of availability zones
- `name_prefix` — Resource naming prefix
- `common_tags` — Resource tags

**Outputs:**
- `vpc_id` — VPC identifier
- `subnet_ids` — List of subnet IDs
- `total_ha` — Actual number of AZs used

### `modules/ebs-csi-storageclass`

Configures GP3 as the default Kubernetes StorageClass.

**Features:**
- Removes default annotation from `gp2`
- Creates `ebs-csi-gp3` StorageClass
- Enables volume expansion
- Sets `WaitForFirstConsumer` binding mode

---

## 🤝 Contributing

1. Create a feature branch
2. Make changes and test locally
3. Run `terraform fmt` and `terraform validate`
4. Submit pull request with description

---

## 📄 License

This project is licensed under the MIT License.

---

## 🆘 Troubleshooting

### Issue: "Error: error configuring Terraform AWS Provider"

**Solution:** Ensure AWS credentials are configured:
```bash
aws configure
# Or use environment variables
export AWS_ACCESS_KEY_ID="..."
export AWS_SECRET_ACCESS_KEY="..."
```

### Issue: "Error acquiring the state lock"

**Solution:** Another process is running. Wait or force-unlock:
```bash
terraform force-unlock <LOCK_ID>
```

### Issue: "Error: Kubernetes cluster unreachable"

**Solution:** Update kubeconfig:
```bash
aws eks update-kubeconfig --region <region> --name <cluster-name>
```

### Issue: Pods stuck in "Pending" state

**Solution:** Check node capacity and storage:
```bash
kubectl get nodes
kubectl describe pod <pod-name>
kubectl get pvc
```

---

## 📞 Support

For issues and questions:
- 📧 Email: infrastructure@yourcompany.com
- 💬 Slack: #infrastructure-support
- 📖 Wiki: https://wiki.yourcompany.com/eks-infrastructure

---

**Built with ❤️ using Terraform**
