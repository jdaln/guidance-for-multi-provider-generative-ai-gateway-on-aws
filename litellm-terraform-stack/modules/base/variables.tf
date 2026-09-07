variable "name" {
  description = "Standard name to be used as prefix on all resources."
  type        = string
}

variable "vpc_id" {
  description = "ID of an existing VPC to use. If not provided, a new VPC will be created."
  type        = string
  default     = ""
}

variable "ecrLitellmRepository" {
  type        = string
  description = "Name of the LiteLLM ECR repository"
}

variable "ecrMiddlewareRepository" {
  type        = string
  description = "Name of the Middleware ECR repository"
}

variable "deployment_platform" {
  description = "Which platform to deploy (ECS or EKS)"
  type        = string
  
  validation {
    condition     = can(regex("^(ECS|EKS)$", upper(var.deployment_platform)))
    error_message = "DEPLOYMENT_PLATFORM must be either 'ECS' or 'EKS' (case insensitive)."
  }
}

variable "disable_outbound_network_access" {
    description = "Whether to disable outbound network access"
    type = bool
}

variable "create_vpc_endpoints_in_existing_vpc" {
  type    = bool
  description = "If using an existing VPC, set this to true to also create interface/gateway endpoints within it."
}

variable "hostedZoneName" {
  description = "Hosted zone name"
  type        = string
  default     = ""
}

variable "publicLoadBalancer" {
  description = "Whether the load balancer is public or private"
  type = bool
}

variable "create_private_hosted_zone_in_existing_vpc" {
  description = "In the case publicLoadBalancer=false (meaning we need a private hosted zone), and an vpc_id is provided, decides whether we create a private hosted zone, or assume one already exists and import it"
  type        = bool
}

variable "rds_instance_class" {
  type        = string
  description = "The instance class for the RDS database"
}

variable "rds_allocated_storage" {
  type        = number
  description = "The allocated storage in GB for the RDS database"
}

variable "redis_node_type" {
  type        = string
  description = "The node type for Redis clusters"
}

variable "redis_num_cache_clusters" {
  type        = number
  description = "The number of cache clusters for Redis"
}

variable "use_route53" {
  description = "Whether to use Route53 for DNS management. If false, no Route53 resources will be created."
  type        = bool
  default     = false
}

variable "create_bedrock_agent_endpoint" {
  description = "Whether to create the bedrock-agent Interface VPC endpoint (used by the middleware for Amazon Bedrock Managed Prompts). Set to false in Regions where Agents for Amazon Bedrock is not offered (for example eu-north-1); there the endpoint service lookup would fail the whole apply."
  type        = bool
  default     = true
}

variable "rds_backup_retention_days" {
  description = "Automated RDS backup retention in days (0 disables backups)."
  type        = number
  default     = 7
}

variable "rds_deletion_protection" {
  description = "Enable RDS deletion protection and a final snapshot on destroy. Set to false for disposable environments so undeploy can remove the database."
  type        = bool
  default     = false
}

variable "rds_log_statement" {
  description = "PostgreSQL log_statement parameter (none, ddl, mod, all)."
  type        = string
  default     = "ddl"
}

variable "waf_allowed_cidrs" {
  description = "When non-empty, the regional WAF blocks every request whose client IP is outside these IPv4 CIDR blocks (used for a public ALB without CloudFront)."
  type        = list(string)
  default     = []
}

variable "enable_middleware" {
  description = "Whether the middleware image/repository is part of the deployment."
  type        = bool
  default     = true
}
