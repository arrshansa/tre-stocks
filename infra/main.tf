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

# Creating an S3 bucket to store the website files such as HTML, CSS, and JS
resource "aws_s3_bucket" "my_bucket" {
  bucket = "stocks-bucket-16sa82k9"
  tags = {
    Name        = "Stocks Frontend Bucket"
    Environment = "Dev"
  }
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

# Creating the Lambda function to fetch stock prices and store them in DynamoDB
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
      S3_BUCKET_NAME         = aws_s3_bucket.my_bucket.bucket
      DYNAMODB_TABLE_NAME    = aws_dynamodb_table.stocks_db.name
      MASSIVE_API_SECRET_ARN = aws_secretsmanager_secret.massive_api.arn
      API_URL                = "https://api.massive.com/v1/open-close"
    }
  }
}

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

# Setting up a CloudWatch Event Rule to trigger the Lambda function every day at 4 pm EST
resource "aws_cloudwatch_event_rule" "console" {
  name                = "grab-stock-prices"
  description         = "Trigger Lambda every day at 4 pm EST (every 24 hours)"
  schedule_expression = "cron(0 21 * * ? *)" # UTC time for 4 pm EST (stock market closing time)
}

# Adding the Lambda function as the target for the CloudWatch Event Rule
resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.console.name
  target_id = "grab-stock-prices"
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
