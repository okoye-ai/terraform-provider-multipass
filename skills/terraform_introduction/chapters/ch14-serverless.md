# Chapter 14: Terraform for Serverless Architecture

## Core Idea
Serverless resources are declared exactly like servers: provider block → resource blocks (function + IAM role) per cloud.

## Frameworks Introduced
- **Function + role pairing (AWS)**: an `aws_lambda_function` requires an IAM `role` — define both, reference the role's ARN
  - How: `role = aws_iam_role.example.arn` wires the Lambda to its execution role via a `assume_role_policy` letting `lambda.amazonaws.com` assume it

## Key Concepts
- **AWS Lambda**: runs code without managing servers; code stored in S3 (`s3_bucket` + `s3_key`), triggered via `handler`/`runtime`
- **Google Cloud Functions**: lightweight event-based functions (`trigger_http`, `source_archive_bucket`)
- **Azure Functions**: needs resource group + storage account + app service plan (`sku tier Dynamic, size Y1`) before the function app itself

## Mental Models
- **Function code lives in object storage**: on every provider, Terraform points at a zip in a bucket — the function resource is a pointer, not the code.

## Code Examples *(technical)*
```hcl
resource "aws_lambda_function" "example" {
  function_name = "lambda_example"
  s3_bucket     = "lambda-functions"
  s3_key        = "example.zip"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.example.arn
}

resource "aws_iam_role" "example" {
  name = "lambda_example_role"
  assume_role_policy = <<-EOF
  {
    "Version": "2012-10-17",
    "Statement": [{ "Action": "sts:AssumeRole",
      "Principal": { "Service": "lambda.amazonaws.com" },
      "Effect": "Allow", "Sid": "" }]
  }
  EOF
}
```
- **What it demonstrates**: the Lambda + IAM role pairing — the extra dependency people usually forget on AWS.

## Key Takeaways
1. AWS Lambda needs the IAM role with a proper assume policy — build it in the same config.
2. On GCP the function is a bucket + `entry_point`; on Azure it's resource group + storage + service plan + function app.
3. Serverless = just more resource types; the Terraform workflow is unchanged.

## Connects To
- **Ch 15**: the same pattern — provider + resource blocks — continues with Kubernetes
- **Ch 5**: the `<<-EOF` heredoc is part of the expression/hcl toolbox