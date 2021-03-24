/**
 * Amazon API Gateway as a REST API for HTTP throttling proxy to Elasticsearch endpoint
 * per https://docs.aws.amazon.com/apigateway/latest/developerguide/how-to-deploy-api.html
 */

## Prerequisites

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.27"
    }
  }
}

provider "aws" {
  profile = var.aws_profile
  region  = var.aws_region
}

## per https://medium.com/onfido-tech/aws-api-gateway-with-terraform-7a2bebe8b68f

resource "aws_api_gateway_rest_api" "my_es_api_gw" {
  name = "my_es_api_gw"
  description = "REST API throttling HTTP proxy to ES"
  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_resource" "my_proxy_resource" {
  rest_api_id = aws_api_gateway_rest_api.my_es_api_gw.id
  parent_id   = aws_api_gateway_rest_api.my_es_api_gw.root_resource_id
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "all_es_http" {
  rest_api_id   = aws_api_gateway_rest_api.my_es_api_gw.id
  resource_id   = aws_api_gateway_resource.my_proxy_resource.id
  http_method   = "ANY"
  authorization = "NONE"
  request_parameters = {
    "method.request.path.proxy" = true
  }
}

resource "aws_api_gateway_integration" "my_es_integration" {
  rest_api_id = aws_api_gateway_rest_api.my_es_api_gw.id
  resource_id = aws_api_gateway_resource.my_proxy_resource.id
  http_method = aws_api_gateway_method.all_es_http.http_method
  integration_http_method = "ANY"
  type                    = "HTTP_PROXY"
  uri                     = "https://search-<your_aes_domain_endpoint>.<region>.es.amazonaws.com/{proxy}"
  request_parameters =  {
    "integration.request.path.proxy" = "method.request.path.proxy"
  }
}

resource "aws_api_gateway_stage" "my_es_stage" {
  deployment_id = aws_api_gateway_deployment.my_es_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.my_es_api_gw.id
  stage_name    = "t1r1"
}

## per https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_method_settings

resource "aws_api_gateway_method_settings" "all" {
  rest_api_id = aws_api_gateway_rest_api.my_es_api_gw.id
  stage_name  = aws_api_gateway_stage.my_es_stage.stage_name
  method_path = "*/*"
  settings {
    throttling_burst_limit = 1000
    throttling_rate_limit = 1000
    metrics_enabled = true
    logging_level   = "OFF"
  }
}

## per https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_deployment

resource "aws_api_gateway_deployment" "my_es_deployment" {
  rest_api_id = aws_api_gateway_rest_api.my_es_api_gw.id
  stage_name  = "t10r5"
  variables = {
    deployed_at = timestamp()
  }
  triggers = {
    redeployment = sha1(jsonencode(aws_api_gateway_rest_api.my_es_api_gw.body))
  }
  lifecycle { create_before_destroy = true }
  depends_on = [ aws_api_gateway_method.all_es_http ]  # https://github.com/hashicorp/terraform/issues/7588#issuecomment-232427478
}

