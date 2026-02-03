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

class DecimalEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, Decimal):
            return float(obj)
        return super(DecimalEncoder, self).default(obj)
    
def lambda_handler(event, context):
    today = datetime.now()
    winners = []
    dates_to_fetch = [
        (today - timedelta(days=i)).strftime('%Y-%m-%d') for i in range(7)
    ]

    try:
        for date_str in dates_to_fetch:
            resp = table.query(
                KeyConditionExpression=Key('date').eq(date_str)
            )
        
            if 'Items' in resp and len(resp['Items']) > 0:
                winners.extend(resp['Items'])

        winners.sort(key=lambda x: x['date'], reverse=True)
        return {
            "statusCode": 200,
            "headers": {
                "Access-Control-Allow-Origin": "*",
                "Access-Control-Allow-Methods": "GET"
            },
            "body": json.dumps(winners, cls=DecimalEncoder)
        }
    
    except Exception as e:
        print(f"Error fetching weekly winners: {e}")
        return {
            "statusCode": 500,
            "body": json.dumps({"error": str(e)})
        }
