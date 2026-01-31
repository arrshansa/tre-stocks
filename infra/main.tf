terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

#Configuring the provider
provider "aws" {
  region = "us-east-1"
}

resource "aws_s3_bucket" "my_bucket" {
  bucket = "stocks-bucket-16sa82k9"
  tags = {
    Name        = "Stocks bucket"
    Environment = "Dev"
  }
}


resource "aws_dynamodb_table" "stocks_db" {
  name         = "stocks-table-88sj21"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "date"

  attribute {
    name = "date"
    type = "S"
  }

  tags = {
    Name        = "Stocks table"
    Environment = "Dev"
  }
}

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
      },
    ]
  })

}

resource "aws_lambda" "stocks_lambda" {

}


resource "aws_cloudwatch_rule" "console" {
  name        = "grab-stock-prices"
  description = "Trigger Lambda every day at 2 pm (every 24 hours)"

}
