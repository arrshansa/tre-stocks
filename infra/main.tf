terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

#Configuring the provider so that the server is region us-east-1
provider "aws" {
  region = "us-east-1"
}

# Creating an S3 bucket to store the website files: index.html, app.js, styles.css
resource "aws_s3_bucket" "frontend" {
  bucket = "stocks-bucket-36jk94g"

  tags = {
    Name = "TRE Stocks Frontend"
  }
}

# Disabling Block on Public Access settings
resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# Public read bucket policy
resource "aws_s3_bucket_policy" "frontend_public_read" {
  bucket = aws_s3_bucket.frontend.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.frontend.arn}/*"
      }
    ]
  })

  depends_on = [
    aws_s3_bucket_public_access_block.frontend
  ]
}

# Enabling static website hosting on the S3 bucket
resource "aws_s3_bucket_website_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  index_document {
    suffix = "index.html"
  }
}

# Uploading index.html file to S3 bucket directly through terraform
resource "aws_s3_object" "frontend_index" {
  bucket       = aws_s3_bucket.frontend.id
  key          = "index.html"
  source       = "../frontend/index.html"
  content_type = "text/html"
  etag         = filemd5("../frontend/index.html")

  depends_on = [
    aws_s3_bucket_policy.frontend_public_read
  ]
}

# Uploading app.js file to S3 bucket directly through terraform
resource "aws_s3_object" "frontend_js" {
  bucket       = aws_s3_bucket.frontend.id
  key          = "app.js"
  source       = "../frontend/app.js"
  content_type = "application/javascript"
  etag         = filemd5("../frontend/app.js")

  depends_on = [
    aws_s3_bucket_policy.frontend_public_read
  ]
}

# Uploading styles.css file to S3 bucket directly through terraform
resource "aws_s3_object" "frontend_css" {
  bucket       = aws_s3_bucket.frontend.id
  key          = "styles.css"
  source       = "../frontend/styles.css"
  content_type = "text/css"
  etag         = filemd5("../frontend/styles.css")

  depends_on = [
    aws_s3_bucket_policy.frontend_public_read
  ]
}

# Website URL output to access the frontend 
output "frontend_website_url" {
  value = "http://${aws_s3_bucket_website_configuration.frontend.website_endpoint}"
}

# Creating an DynamoDB table to store stock data which will be fetched by the Lambda function from Massive API
resource "aws_dynamodb_table" "stocks_db" {
  name         = "stocks-table-88sj21"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "date"   #primary key
  range_key    = "symbol" #sort key

  attribute {
    name = "date"
    type = "S" #S stands for String
  }

  attribute {
    name = "symbol"
    type = "S"
  }

  tags = {
    Name        = "Stocks table"
    Environment = "Dev"
  }
}

# Creating a Secrets Manager secret to store the Massive API key securely instead of hardcoding it in the Lambda function 
# or using environment variables
resource "aws_secretsmanager_secret" "massive_api" {
  name        = "dev/massive-api-key"
  description = "Massive API key for grab-stock-prices"
}


# Creating an IAM role for the Lambda function with necessary permissions 
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

# Creating an IAM policy for the Lambda function to access DynamoDB, CloudWatch Logs, and Secrets Manager
resource "aws_iam_policy" "lambda_policy" {
  name        = "lambda-dynamodb-policy"
  description = "Policy for Lambda to access DynamoDB"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { # DynamoDB permissions
        Effect = "Allow",
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:GetItem",
          "dynamodb:Scan",
          "dynamodb:Query"
        ],
        Resource = aws_dynamodb_table.stocks_db.arn
      },
      { # CloudWatch Log permissions
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = aws_secretsmanager_secret.massive_api.arn
      }
    ]
  })
}

# Attaching the IAM policy to the IAM role
resource "aws_iam_role_policy_attachment" "lambda_policy_attach" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

# Zipping the Lambda function code
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "../backend"
  output_path = "lambda_function.zip"
}

# Creating the Lambda function to compute today's highest stock mover
resource "aws_lambda_function" "compute_todays_mover_lambda" {
  function_name    = "compute-todays-movers"
  role             = aws_iam_role.lambda_role.arn
  handler          = "todays_mover_lambda.lambda_handler"
  runtime          = "python3.14"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  timeout          = 30

  environment {
    variables = {
      S3_BUCKET_NAME         = aws_s3_bucket.frontend.bucket
      DYNAMODB_TABLE_NAME    = aws_dynamodb_table.stocks_db.name
      MASSIVE_API_SECRET_ARN = aws_secretsmanager_secret.massive_api.arn
      API_URL                = "https://api.massive.com/v1/open-close"
    }
  }
}

# Creating the Lambda function to get highest movers over the past 7 days from DynamoDB
resource "aws_lambda_function" "get_previous_movers_lambda" {
  function_name    = "get-previous-movers"
  role             = aws_iam_role.lambda_role.arn
  handler          = "previous_movers_lambda.lambda_handler"
  runtime          = "python3.14"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  timeout          = 10

  environment {
    variables = {
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.stocks_db.name
    }
  }
}

# Setting up API Gateway HTTP API to expose the Lambda function via a RESTful endpoint
resource "aws_apigatewayv2_api" "stocks_api" {
  name          = "stocks-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET"]
    allow_headers = ["*"]
  }
}

# Creating an integration between API Gateway and the Lambda function
resource "aws_apigatewayv2_integration" "movers_integration" {
  api_id           = aws_apigatewayv2_api.stocks_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.get_previous_movers_lambda.invoke_arn
}

# Creating a route for GET /movers to invoke the Lambda function
resource "aws_apigatewayv2_route" "get_movers" {
  api_id    = aws_apigatewayv2_api.stocks_api.id
  route_key = "GET /movers"
  target    = "integrations/${aws_apigatewayv2_integration.movers_integration.id}"
}

# Creating a stage for the API Gateway to deploy the API
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.stocks_api.id
  name        = "$default"
  auto_deploy = true
}

# Giving API Gateway permission to invoke the Lambda function
resource "aws_lambda_permission" "allow_http_api" {
  statement_id  = "AllowHttpApiInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_previous_movers_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.stocks_api.execution_arn}/*/*"
}

# Outputting the API base URL to access the GET /movers endpoint
output "api_base_url" {
  value = aws_apigatewayv2_api.stocks_api.api_endpoint
}

# Setting up a CloudWatch Event Rule to trigger the Lambda function every day at 4 pm EST
resource "aws_cloudwatch_event_rule" "console" {
  name                = "calculate-todays-movers"
  description         = "Trigger Lambda every day at 4 pm EST (every 24 hours)"
  schedule_expression = "cron(0 21 * * ? *)" # UTC time for 4 pm EST (stock market closing time)
}

# Adding the Lambda function as the target for the CloudWatch Event Rule
resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.console.name
  target_id = "calculate-todays-movers"
  arn       = aws_lambda_function.compute_todays_mover_lambda.arn
}

# Giving CloudWatch permission to invoke the Lambda function
resource "aws_lambda_permission" "allow_cloudwatch" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.compute_todays_mover_lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.console.arn
}
