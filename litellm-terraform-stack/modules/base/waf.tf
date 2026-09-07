###############################################################################
# WAFv2 Web ACL
###############################################################################

# Optional client IP allow-list (defence in depth on top of the ALB security group)
resource "aws_wafv2_ip_set" "allowed_clients" {
  count              = length(var.waf_allowed_cidrs) > 0 ? 1 : 0
  name               = "${var.name}-allowed-clients"
  description        = "Client IP ranges allowed to reach the LiteLLM ALB"
  scope              = "REGIONAL"
  ip_address_version = "IPV4"
  addresses          = var.waf_allowed_cidrs
}

resource "aws_wafv2_web_acl" "litellm_waf" {
  name        = "LiteLLMWAF"
  description = "WAF for LiteLLM"
  scope       = "REGIONAL" # or CLOUDFRONT

  default_action {
    allow {}
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "LiteLLMWebAcl"
    sampled_requests_enabled   = true
  }

  # Evaluated first: block any client outside the allow-list (only when an allow-list is configured)
  dynamic "rule" {
    for_each = length(var.waf_allowed_cidrs) > 0 ? [1] : []
    content {
      name     = "BlockClientsOutsideAllowList"
      priority = 0

      action {
        block {}
      }

      statement {
        not_statement {
          statement {
            ip_set_reference_statement {
              arn = aws_wafv2_ip_set.allowed_clients[0].arn
            }
          }
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "LiteLLMClientAllowList"
        sampled_requests_enabled   = true
      }
    }
  }

  rule {
    name     = "AWSManagedRulesCommonRuleSet-Exclusions"
    priority = 1

    # override_action is required if referencing a rule group
    # - use 'none' if you want to keep the group’s default action 
    # - or 'count' to effectively “disable” or “exclude” from blocking
    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"

        # This is the Terraform equivalent to the "excludedRules" from CloudFormation/CDK:
        # We override the action of these specific sub-rules to avoid them blocking requests.
        rule_action_override {
          name = "NoUserAgent_HEADER"
          action_to_use {
            count {}
          }
        }

        rule_action_override {
          name = "SizeRestrictions_BODY"
          action_to_use {
            count {}
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "LiteLLMCommonRuleSet"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWS-AWSManagedRulesKnownBadInputsRuleSet"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "LiteLLMCommonRuleSet"
      sampled_requests_enabled   = true
    }
  }

}
