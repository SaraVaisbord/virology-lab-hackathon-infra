# תשתית AWS – מערכת אימות טפסי התחייבות (המעבדה המרכזית לנגיפים)

Terraform שמקים את כל התשתית להרצת [virology-lab-hackathon-app](https://github.com/SaraVaisbord/virology-lab-hackathon-app) על AWS. הפריסה של האפליקציה עצמה נמצאת ב-[virology-lab-hackathon-k8s](https://github.com/SaraVaisbord/virology-lab-hackathon-k8s).

## מה מוקם

| רכיב | פירוט | קובץ |
|---|---|---|
| רשת (VPC) | תתי-רשת ציבוריות לאשכול, ותתי-רשת **פרטיות בלי גישה לאינטרנט** למסד הנתונים | `modules/network` |
| אשכול EKS | Kubernetes 1.31, 2 שרתים (`t3a.large`, אפשר 1–3) | `MAIN.tf` |
| תוספים | EBS CSI (דיסקים מוצפנים), Load Balancer Controller, External Secrets | `MAIN.tf` |
| **מסד נתונים** | **RDS PostgreSQL 16 – שרת נפרד**, בתת-רשת פרטית, נגיש רק מהאשכול, מוצפן. גיבוי אוטומטי יומי ל-7 ימים + שחזור לכל רגע בתקופה, snapshot סופי במחיקה, הגנה ממחיקה. אופציה: שרת גיבוי חם באזור אחר (`db_multi_az`) | `app.tf` |
| **קבצים ותמונות** | **באקט S3 פרטי** – חסום לגישה ציבורית, מוצפן, גרסאות (אפשר לשחזר קובץ שנמחק), רק HTTPS | `app.tf` |
| הרשאות | ל-backend יש IAM role (IRSA) שמורשה **רק** לבאקט הזה | `app.tf` |
| תמונות האפליקציה | שני מאגרי ECR (backend, frontend), סריקת אבטחה בכל דחיפה | `app.tf` |
| סודות | Secrets Manager: חיבור למסד (נוצר אוטומטית) ומפתחות Gemini (מוכנסים ידנית) | `app.tf` |
| גיבוי נוסף | AWS Backup – גיבוי יומי ל-7 ימים של כל המשאבים המתויגים | `backup.tf` |
| מצב Terraform | S3 + נעילה ב-DynamoDB, במפתח נפרד מכל תשתית אחרת | `backend.hcl` |

## הרצה

```bash
aws sso login
terraform init -backend-config=backend.hcl
terraform plan -out tfplan
terraform apply tfplan      # ~20-25 דקות (האשכול והמסד)
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
node_type       = "t3a.large"
```

אחרי ההקמה – מפתחות Gemini לסוד (הערכים לא עוברים דרך Terraform או Git):

```bash
aws secretsmanager put-secret-value --secret-id virology-lab-forms-validation/gemini \
  --secret-string '{"GEMINI_API_KEY":"...","GEMINI_API_KEY_2":"..."}'
```

ואז הפריסה: `deploy.ps1` ב-[virology-lab-hackathon-k8s](https://github.com/SaraVaisbord/virology-lab-hackathon-k8s).

## פירוק

המסד מוגן ממחיקה והבאקט לא נמחק כשיש בו קבצים. כדי לפרק הכול: `db_deletion_protection = false` ו-`files_bucket_force_destroy = true`, `terraform apply`, ואז `terraform destroy`. במחיקה נשמר snapshot סופי של המסד.

## עלות משוערת (us-east-1)

אשכול EKS + 2 שרתים + ALB + RDS קטן: כ-0.35$ לשעה (בערך 8$ ליום).
