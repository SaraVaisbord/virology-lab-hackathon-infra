bucket       = "virology-lab-tf-state-475568920419"
key          = "virology-lab-hackathon/eks/terraform.tfstate"
region       = "us-east-1"
encrypt      = true
use_lockfile = true # state locking inside S3 (no DynamoDB table needed)
