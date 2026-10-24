# The public address: https://<domain_name> (and www.)
#   Route 53  hosted zone for the domain — created once by dns-zone/ and kept across teardowns, so the
#             nameservers set at the outside registrar never change. Here it is only read.
#   ACM       free public certificate for the ALB, validated through this zone and renewed by AWS automatically
# The ALIAS records to the ALB are written by deploy.ps1 in the k8s repo: the ALB is created by the
# Load Balancer Controller, not by Terraform.

data "aws_route53_zone" "main" {
  name = var.domain_name
}

resource "aws_acm_certificate" "main" {
  domain_name               = var.domain_name
  subject_alternative_names = ["www.${var.domain_name}"]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for o in aws_acm_certificate.main.domain_validation_options : o.domain_name => {
      name   = o.resource_record_name
      type   = o.resource_record_type
      record = o.resource_record_value
    }
  }
  zone_id         = data.aws_route53_zone.main.zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 300
  allow_overwrite = true
}

# Waits until the registrar points at this zone and ACM sees the records (minutes once the NS change is live).
resource "aws_acm_certificate_validation" "main" {
  certificate_arn         = aws_acm_certificate.main.arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]
}
