###############################################################################
# ACM certificate for the ALB (requested automatically when possible)
###############################################################################
locals {
  # Request a public ACM certificate for <record_name>.<hosted_zone_name> when Route53 is used with a public
  # ALB and no certificate was supplied. DNS validation records are created in the hosted zone. Not applicable
  # with CloudFront (its certificate must live in us-east-1) or with a private hosted zone (no public validation).
  create_acm_certificate      = var.use_route53 && var.public_load_balancer && !var.use_cloudfront && var.certificate_arn == ""
  use_self_signed_certificate = var.certificate_arn == "" && !local.create_acm_certificate
  alb_certificate_arn = var.certificate_arn != "" ? var.certificate_arn : (
    local.create_acm_certificate ? aws_acm_certificate_validation.alb[0].certificate_arn : aws_acm_certificate.self_signed[0].arn
  )
}

resource "aws_acm_certificate" "alb" {
  count             = local.create_acm_certificate ? 1 : 0
  domain_name       = "${var.record_name}.${var.hosted_zone_name}"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "acm_validation" {
  for_each = local.create_acm_certificate ? {
    for dvo in aws_acm_certificate.alb[0].domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  } : {}

  allow_overwrite = true
  zone_id         = data.aws_route53_zone.this[0].zone_id
  name            = each.value.name
  type            = each.value.type
  ttl             = 60
  records         = [each.value.record]
}

resource "aws_acm_certificate_validation" "alb" {
  count                   = local.create_acm_certificate ? 1 : 0
  certificate_arn         = aws_acm_certificate.alb[0].arn
  validation_record_fqdns = [for record in aws_route53_record.acm_validation : record.fqdn]
}
