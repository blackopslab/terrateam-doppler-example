# Install the Doppler and AWS providers
terraform {
  required_providers {
    doppler = {
      source = "DopplerHQ/doppler"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source = "hashicorp/random"
    }
  }

  backend "s3" {
    bucket = "terrateam-doppler"
    key    = "terraform.tfstate"
    region = "eu-west-1"
  }
}

# AWS provider configuration
provider "aws" {
  region = "eu-west-1"
}

# Doppler provider configuration
variable "doppler_token" {
  type        = string
  description = "Token to access Doppler"
  sensitive   = true
}

provider "doppler" {
  doppler_token = var.doppler_token
}

# Generate a random password for the API key
resource "random_password" "demo_password" {
  length  = 32
  special = true
}

# Save the random password to Doppler as the API key
resource "doppler_secret" "demo_password" {
  project = "example-project"
  config  = "dev"
  name    = "DEMO_PASSWORD"
  value   = random_password.demo_password.result
}

# IAM role for Lambda execution
resource "aws_iam_role" "lambda_role" {
  name = "lambda-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# Attach basic execution policy to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_policy" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Lambda function to call the mock API
resource "aws_lambda_function" "mock_api_lambda" {
  function_name = "mock-api-test-function"
  role          = aws_iam_role.lambda_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.9"

  filename         = "lambda_function.zip"
  source_code_hash = filebase64sha256("lambda_function.zip")

  environment {
    variables = {
      MOCK_API_KEY = doppler_secret.demo_password.value
      MOCK_API_URL = "${aws_api_gateway_stage.test_stage.invoke_url}/weather"
    }
  }

  description = "Lambda to call mock API with Doppler secret"
  timeout     = 10
  memory_size = 128

  depends_on = [
    aws_iam_role_policy_attachment.lambda_policy,
    aws_api_gateway_stage.test_stage
  ]
}

# API Gateway REST API for mock endpoint
resource "aws_api_gateway_rest_api" "mock_api" {
  name        = "MockWeatherAPI"
  description = "Mock API for testing Lambda with Doppler secret"
}

# Resource for /weather endpoint
resource "aws_api_gateway_resource" "weather_resource" {
  rest_api_id = aws_api_gateway_rest_api.mock_api.id
  parent_id   = aws_api_gateway_rest_api.mock_api.root_resource_id
  path_part   = "weather"
}

# GET method for /weather
resource "aws_api_gateway_method" "weather_get" {
  rest_api_id      = aws_api_gateway_rest_api.mock_api.id
  resource_id      = aws_api_gateway_resource.weather_resource.id
  http_method      = "GET"
  authorization    = "NONE"
  api_key_required = true # Require API key

  request_parameters = {
    "method.request.header.X-Api-Key" = true
  }
}

# Mock integration for GET /weather
resource "aws_api_gateway_integration" "weather_integration" {
  rest_api_id = aws_api_gateway_rest_api.mock_api.id
  resource_id = aws_api_gateway_resource.weather_resource.id
  http_method = aws_api_gateway_method.weather_get.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

# Mock response configuration
resource "aws_api_gateway_method_response" "weather_response" {
  rest_api_id = aws_api_gateway_rest_api.mock_api.id
  resource_id = aws_api_gateway_resource.weather_resource.id
  http_method = aws_api_gateway_method.weather_get.http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }
}

# Integration response for mock API
resource "aws_api_gateway_integration_response" "weather_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.mock_api.id
  resource_id = aws_api_gateway_resource.weather_resource.id
  http_method = aws_api_gateway_method.weather_get.http_method
  status_code = aws_api_gateway_method_response.weather_response.status_code

  response_templates = {
    "application/json" = jsonencode({
      "forecast" : "Sunny",
      "temperature" : "22C",
      "mock_message" : "Mock API response for testing"
    })
  }

  depends_on = [
    aws_api_gateway_method.weather_get,
    aws_api_gateway_integration.weather_integration
  ]
}

# API key using Doppler secret
resource "aws_api_gateway_api_key" "mock_api_key" {
  name  = "mock-api-key"
  value = doppler_secret.demo_password.value # Set API key to Doppler secret
}

# API Gateway deployment
resource "aws_api_gateway_deployment" "mock_api" {
  rest_api_id = aws_api_gateway_rest_api.mock_api.id

  depends_on = [
    aws_api_gateway_integration.weather_integration,
    aws_api_gateway_integration_response.weather_integration_response
  ]

  lifecycle {
    create_before_destroy = true
  }
}

# API Gateway stage
resource "aws_api_gateway_stage" "test_stage" {
  rest_api_id   = aws_api_gateway_rest_api.mock_api.id
  deployment_id = aws_api_gateway_deployment.mock_api.id
  stage_name    = "test"
}

# Usage plan for API key
resource "aws_api_gateway_usage_plan" "mock_api_usage_plan" {
  name = "mock-api-usage-plan"

  api_stages {
    api_id = aws_api_gateway_rest_api.mock_api.id
    stage  = aws_api_gateway_stage.test_stage.stage_name
  }
}

# Link API key to usage plan
resource "aws_api_gateway_usage_plan_key" "mock_api_usage_plan_key" {
  key_id        = aws_api_gateway_api_key.mock_api_key.id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.mock_api_usage_plan.id
}

# Outputs
output "resource_value" {
  value       = nonsensitive(doppler_secret.demo_password.value)
  description = "Value of the Doppler secret (nonsensitive for demo)"
}

output "lambda_function_arn" {
  value       = aws_lambda_function.mock_api_lambda.arn
  description = "ARN of the Lambda function"
}

output "mock_api_url" {
  value       = "${aws_api_gateway_stage.test_stage.invoke_url}/weather"
  description = "URL of the mock API endpoint"
}