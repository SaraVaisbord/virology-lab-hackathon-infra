# תשתית AWS – מערכת אימות טפסי התחייבות (המעבדה המרכזית לנגיפים)

Terraform שמקים את התשתית להרצת [virology-lab-hackathon-app](https://github.com/SaraVaisbord/virology-lab-hackathon-app) על AWS EKS. קובצי ה-Kubernetes של האפליקציה נמצאים ב-[virology-lab-hackathon-k8s](https://github.com/SaraVaisbord/virology-lab-hackathon-k8s).

> **סטטוס:** הקוד הועתק מתשתית קיימת ועדיין **מותאם** לאפליקציה הזו – ראו "מה נשאר להתאים" למטה.

## מה מוקם

| רכיב | פירוט |
|---|---|
| רשת (VPC) | תתי-רשת ציבוריות בכמה אזורי זמינות (`ha`), Internet Gateway |
| אשכול EKS | Kubernetes 1.31, קבוצת שרתים מנוהלת (1–3, ברירת מחדל 2, `t3a.medium`) |
| אחסון | EBS CSI driver ו-StorageClass מסוג gp3 כברירת מחדל |
| כניסה מהאינטרנט | AWS Load Balancer Controller (ALB) |
| סודות | External Secrets Operator, קורא מ-AWS Secrets Manager רק סודות תחת `<owner>-<app_name>/*` |
| גיבוי | AWS Backup – גיבוי יומי ב-02:00, שמירה ל-7 ימים, לפי התגית `owner` |
| מצב Terraform | S3 + נעילה ב-DynamoDB (`backend.hcl`) |

## מבנה

```
MAIN.tf              רשת, EKS, תוספים, הרשאות IRSA
providers.tf         AWS, Kubernetes, Helm
variables.tf         משתנים
outputs.tf           כתובת האשכול ופקודת החיבור
backup.tf            AWS Backup
backend.hcl          מיקום קובץ המצב (S3)
modules/network/     VPC, תתי-רשת, ניתוב
modules/ebs-csi-storageclass/  StorageClass מסוג gp3
```

## הרצה

```bash
aws sso login
terraform init -backend-config=backend.hcl
terraform plan -out tfplan          # נדרש terraform.tfvars – ראו למטה
terraform apply tfplan
aws eks update-kubeconfig --region <region> --name <owner>-cluster
```

`terraform.tfvars` (לא נשמר ב-Git):

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
node_type       = "t3a.large"   # OCR ועיבוד תמונה צריכים יותר זיכרון
```

## מה נשאר להתאים

- [ ] **מאגרי ECR** לאימג'ים של השרת והממשק.
- [ ] **סוד ב-Secrets Manager** למפתחות Gemini, תחת `<owner>-<app_name>/`.
- [ ] **הצפנת דיסקים** – `encrypted = true` ב-`modules/ebs-csi-storageclass` (כרגע בהערה).
- [ ] **גיבוי הדיסק של האפליקציה** – לתייג את הדיסק ב-`owner`, אחרת AWS Backup לא כולל אותו.
- [ ] **הגבלת גישה** – `allowed_cidr_blocks` פתוח כרגע ל-`0.0.0.0/0`.
- [ ] בהמשך: RDS PostgreSQL למסד הנתונים ו-S3 לתמונות, במקום דיסק אחד.

קובץ המצב נשמר תחת המפתח `virology-lab-hackathon/eks/terraform.tfstate` – נפרד מכל תשתית אחרת באותו bucket.
