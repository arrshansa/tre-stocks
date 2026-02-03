import boto3 
import json
import os
from decimal import Decimal
from datetime import datetime, timedelta
from boto3.dynamodb.conditions import Key

dynamodb = boto3.resource('dynamodb')

table_name = os.environ.get('DYNAMODB_TABLE_NAME')
if not table_name:
    raise ValueError("Environment variable DYNAMODB_TABLE_NAME must be set.")

table = dynamodb.Table(table_name)
print("DynamoDB Table Name:", table_name)

CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET,OPTIONS",
  "Access-Control-Allow-Headers": "*",
  "Content-Type": "application/json",
}

# Encoder to convert DynamoDB Decimal types to float for JSON serialization
class DecimalEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, Decimal):
            return float(obj)
        return super(DecimalEncoder, self).default(obj)
    
# Lambda handler to fetch the previous 7 trading days' movers
def lambda_handler(event, context):
    try:
        resp = table.scan()
        items = resp.get("Items", [])

        # Sort newest → oldest by date (YYYY-MM-DD works lexicographically)
        items.sort(key=lambda x: x["date"], reverse=True)

        # Take the most recent 7 trading days (excluding today). So that the past 7 days are shown
        latest = items[:8]

        return {
            "statusCode": 200,
            "headers": CORS_HEADERS,
            "body": json.dumps(latest, cls=DecimalEncoder)
        }

    except Exception as e:
        print(f"Error fetching previous movers: {e}")
        return {
            "statusCode": 500,
            "headers": CORS_HEADERS,
            "body": json.dumps({"error": str(e)})
        }
