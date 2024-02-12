provider "aws" {
    profile = "default"
    region  = "eu-west-2"
}

resource "aws_lambda_function" "terraform-func" {
    role = aws_iam_role.lambda_exec_role.arn
    function_name = "terraform-func"
    filename = data.archive_file.zip.output_path
    source_code_hash = data.archive_file.zip.output_base64sha256
    handler = "index.handler"
    runtime = "python3.12"
    timeout = 300
    memory_size = 128
}

resource "aws_iam_role" "lambda_exec_role" {
    name = "lambda_exec_role"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_policy" "iam_policy_for_dynamodb_role" {
  name = "iam_policy_for_dynamodb_role"
  path = "/"
  policy = jsonencode(
    {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Action" : [
                    "logs:CreateLogGroup",
                    "logs:CreateLogStream",
                    "logs:PutLogEvents"
                ],
                "Resource" : "arn:aws:logs:*:*:*",
                "Effect" : "Allow"
            },
            {
                "Effect" : "Allow",
                "Action": [
                    "dynamodb:UpdateItem",
                    "dynamodb:GetItem", 
                ],
                "Resource": "arn:aws:dynamodb:*:*:table/cloudresume"
            }
        ]
    }
  )
}

resource "aws_iam_role_policy_attachment" "attach_iam_policy_to_iam_role" {
  role = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.iam_policy_for_dynamodb_role.arn
  
}

data "archive_file" "zip" {
    type       = "zip"
    source_dir = "${path.module}/lambda/"
    output_path = "${path.module}/packedlamda.zip"
}

resource "aws_lambda_function_url" "url1" {
    function_name = aws_lambda_function.terraform-func.function_name
    authorization_type = "NONE"

    cors {
        allow_credentials = true
        allow_origins = ["https://resume.bm27.xyz"]
        allow_methods = ["*"]
        allow_headers = ["date","keep-alive"]
        expose_headers = ["keep-alive", "date"]
        max_age = 86400
    }
}
