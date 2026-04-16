variable "secret_names" {
  type        = list(string)
  description = "Secret names to ensure exist in AWS Secrets Manager."
  default = [
    "cdktf-demo/devnet/cachix-radupopa2010-token"
  ]
}

variable "region" {
  type        = string
  description = "AWS region for secrets."
}

variable "env" {
  type        = string
  description = "Environment tag value (devnet/testnet/mainnet)."
}

variable "aws_profile" {
  type        = string
  default     = ""
  description = "AWS CLI profile (empty in CI where OIDC supplies creds)."
}
