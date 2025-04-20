markdown

# Terrateam-Doppler GitOps Secrets Management

This repository demonstrates a GitOps workflow for secure secret management using [Terrateam](https://terrateam.io) and [Doppler](https://doppler.com). It provisions a secure API endpoint with a randomized secret, stored in Doppler, and includes a test function to verify it, all managed through Terraform and GitHub pull requests (PRs).

## Features

- **Secure Secret Management**: Secrets are stored in Doppler, never exposed in the Git repository.
- **GitOps Workflow**: Infrastructure and secrets are managed via Terraform, with changes reviewed and applied through PRs.
- **Automation**: Terrateam automates `terraform plan` and `apply` on PR creation and merge.
- **Seamless Updates & Rollbacks**: Doppler propagates randomized secrets instantly across services, ensuring consistency.
- **Auditability**: All changes are version-controlled in Git for full transparency.

## Prerequisites

- [Terrateam](https://terrateam.io) account and GitHub App installed.
- [Doppler](https://doppler.com) account with a project and config set up.
- AWS account with permissions for API Gateway, Lambda, and S3.
- Terraform installed locally or configured in your CI/CD environment.
- GitHub repository with Actions enabled.

## Setup

### 1. Install Terrateam
1. Sign up at [terrateam.io](https://terrateam.io).
2. Install the Terrateam GitHub App for your repository.
3. Commit `.github/workflows/terrateam.yml` to enable Terraform jobs.
4. Configure `.terrateam/config.yml` for PR handling and S3 backend:

```yaml
when_modified:
  autoapply: true
cost_estimation:
  enabled: false
hooks:
  all:
    pre:
      - type: oidc
        provider: aws
        role_arn: "arn:aws:iam::YOUR_AWS_ACCOUNT_ID:role/terrateam"
terraform:
  backend:
    s3:
      bucket: "terrateam-doppler"
      key: "terraform.tfstate"
      region: "eu-west-1"
      encrypt: true
workflows:
  - tag_query: ""
    plan:
      - type: init
      - type: plan
    apply:
      - type: init
      - type: apply
```

    Grant Terrateam AWS access via OIDC. See Cloud Provider Setup.

### 2. Configure Doppler Token
In Doppler, create a project (e.g., example-project) and config (e.g., dev).
Generate a personal Doppler token.
In your GitHub repository, add the token as a secret named DOPPLER_TOKEN under Settings > Secrets and Variables > Actions.

### 3. Define Terraform Configuration
Create a main.tf file to provision an API endpoint, generate a random secret, and store it in Doppler. Example:

```hcl
terraform {
  required_providers {
    doppler = { source = "DopplerHQ/doppler" }
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
    random = { source = "hashicorp/random" }
  }
  backend "s3" {
    bucket = "terrateam-doppler"
    key    = "terraform.tfstate"
    region = "eu-west-1"
  }
}

provider "aws" { region = "eu-west-1" }
provider "doppler" { doppler_token = var.doppler_token }

variable "doppler_token" { type = string, sensitive = true }

resource "random_password" "api_secret" { length = 32, special = true }
resource "doppler_secret" "api_secret" {
  project = "example-project"
  config  = "dev"
  name    = "API_SECRET"
  value   = random_password.api_secret.result
}

resource "aws_api_gateway_rest_api" "secure_api" {
  name = "SecureAPI"
  description = "API protected by Doppler secret"
}
```

See main.tf for the full configuration and lambda_function.py for the test function.

### 4. Open a Pull Request
Push changes to a feature branch and open a PR.
Terrateam runs terraform plan and posts the output to the PR.
Review the plan, approve, and merge.
Terrateam runs terraform apply to provision resources and store the secret in Doppler.

### 5. Test the API Endpoint
Run the Lambda test function (mock-api-test-function) in the AWS console with an empty payload to verify the endpoint returns a 200 response.

### 6. Roll Back Changes
To revert, open a PR with the previous Terraform state. Terrateam applies it, and Doppler propagates the new secret to all services, ensuring seamless rollbacks.

## Use Cases

- Secret Rotation: Rotate API keys securely with Git-tracked changes.
- Secure Provisioning: Deploy endpoints with secrets managed outside the repository.
- Team Collaboration: Enable developers and DevOps to review secrets and infrastructure in PRs.

License
MIT License. See LICENSE for details.