terraform {
  required_version = ">= 1.6"
  required_providers {
    aws  = { source = "hashicorp/aws", version = "~> 5.50" }
    null = { source = "hashicorp/null", version = ">= 3.2.0" }
  }
}

# Idempotent secret CREATION via the AWS CLI (per project convention:
# "use the aws cli with null provider to create secrets, then reference
# those in terraform"). The VALUE is set out-of-band by
# `scripts/bootstrap-secrets.sh` so it never enters Terraform state.
resource "null_resource" "ensure_secret" {
  for_each = toset(var.secret_names)

  triggers = {
    secret_name = each.value
    region      = var.region
    aws_profile = var.aws_profile
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      PROFILE_FLAG=""
      if [ -n "${var.aws_profile}" ]; then
        PROFILE_FLAG="--profile ${var.aws_profile}"
      fi

      if aws $PROFILE_FLAG --region "${var.region}" \
           secretsmanager describe-secret --secret-id "${each.value}" \
           > /dev/null 2>&1; then
        echo "[aws-secrets] secret '${each.value}' already exists — leaving as-is"
      else
        echo "[aws-secrets] creating secret '${each.value}'"
        aws $PROFILE_FLAG --region "${var.region}" \
          secretsmanager create-secret \
          --name "${each.value}" \
          --description "Managed by cdktf-demo (value set out-of-band)" \
          --tags Key=Project,Value=cdktf-demo Key=Env,Value=${var.env}
      fi
    EOT
  }
}
