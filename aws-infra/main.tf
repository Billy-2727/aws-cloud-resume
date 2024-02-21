provider "aws" {
  profile = "default"
  region  = "eu-west-2"
}

resource "aws_lambda_function" "terraform-func" {
  role             = aws_iam_role.lambda_exec_role.arn
  function_name    = "terraform-func"
  filename         = data.archive_file.zip.output_path
  source_code_hash = data.archive_file.zip.output_base64sha256
  handler          = "index.handler"
  runtime          = "python3.12"
  timeout          = 300
  memory_size      = 128
}

resource "aws_iam_role" "lambda_exec_role" {
  name               = "lambda_exec_role"
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

resource "aws_dynamodb_table" "lamba_table" {
  name           = "lamba_table"
  billing_mode   = "PROVISIONED"
  read_capacity  = 1
  write_capacity = 1
  hash_key       = "0"

  attribute {
    name = "0"
    type = "S"
  }

}

resource "aws_dynamodb_table_item" "lamba_table_item" {
  table_name = aws_dynamodb_table.lamba_table.name
  hash_key   = aws_dynamodb_table.lamba_table.hash_key

  item = <<ITEM
{
  "0": {
    "S": "0"
  },
  "views": {
    "N": "0"
  }
}
ITEM
}

resource "aws_iam_policy" "iam_policy_for_dynamodb_role" {
  name = "iam_policy_for_dynamodb_role"
  path = "/"
  policy = jsonencode(
    {
      "Version" : "2012-10-17",
      "Statement" : [
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
          "Action" : [
            "dynamodb:UpdateItem",
            "dynamodb:GetItem",
          ],
          "Resource" : "arn:aws:dynamodb:*:*:table/cloudresume"
        }
      ]
    }
  )
}

resource "aws_iam_role_policy_attachment" "attach_iam_policy_to_iam_role" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.iam_policy_for_dynamodb_role.arn

}

data "archive_file" "zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/"
  output_path = "${path.module}/packedlamda.zip"
}

resource "aws_lambda_function_url" "url1" {
  function_name      = aws_lambda_function.terraform-func.function_name
  authorization_type = "NONE"

  cors {
    allow_credentials = true
    allow_origins     = ["https://resume.bm27.xyz"]
    allow_methods     = ["*"]
    allow_headers     = ["date", "keep-alive"]
    expose_headers    = ["keep-alive", "date"]
    max_age           = 86400
  }
}

resource "aws_s3_bucket" "web_bucket" {
  bucket = "bm-cloud-resume1"
}

resource "aws_s3_object" "add_source_files" {
  bucket = aws_s3_bucket.web_bucket.id

  for_each     = fileset("${path.module}./website/", "**/*.*")
  key          = each.value
  source       = "${path.module}./website/${each.value}"
}

locals {
  s3_origin_id = "myS3Origin"
}

# Define CloudFront distribution
resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name              = aws_s3_bucket.web_bucket.bucket_domain_name
    origin_id                = aws_s3_bucket.web_bucket.id
    origin_access_control_id = aws_cloudfront_origin_access_control.Site_Access.id
  }



  # CloudFront distribution configuration
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html" # Specify default root object
  default_cache_behavior {
    target_origin_id       = aws_s3_bucket.web_bucket.id
    viewer_protocol_policy = "https-only" # Redirect HTTP to HTTPS
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }

  aliases = ["resume.bm27.xyz"]

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = "arn:aws:acm:us-east-1:851725161095:certificate/699232a6-0fbb-4bfd-ad1a-298819316e0e"
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2018"
  }
}

resource "aws_cloudfront_origin_access_control" "Site_Access" {
  name                              = "Site_Access_Control"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_s3_bucket_policy" "cloudfront_s3_bucket_policy" {
  bucket = aws_s3_bucket.web_bucket.id
  policy = jsonencode({
    Version = "2008-10-17"
    Id      = "PolicyForCloudFront"
    Statement = [
      {
        Sid    = "AllowCloudFrontServicePrincipal"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.web_bucket.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.s3_distribution.arn
          }
        }
      }
    ]
  })
}