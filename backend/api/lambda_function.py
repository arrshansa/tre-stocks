import boto3 
import json 
import os
import urllib3
from datetime import datetime
from decimal import Decimal
from secrets_helper import get_massive_api_key

http = urllib3.PoolManager()
dynamodb = boto3.resource('dynamodb')

table_name = os.environ.get('DYNAMODB_TABLE_NAME')
table = dynamodb.Table(table_name)

api_url = os.environ.get('API_URL')
api_key = get_massive_api_key()

if not table_name:
    raise ValueError("Environment variable DYNAMODB_TABLE_NAME must be set.")
if not api_url:
    raise ValueError("Environment variable API_URL must be set.")
if not api_key:
    raise ValueError("Environment variable MASSIVE_API_Key must be set.")

print("DynamoDB Table Name:", table_name)

stocks_list = ['AAPL', 'MSFT', 'GOOGL', 'AMZN', 'TSLA']


class DecimalEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, Decimal):
            return float(obj)
        return super(DecimalEncoder, self).default(obj)
    

def lambda_handler(event, context):
    print(f"Fetching stock data from Massive API at {api_url}")
    fetched_data = []
    
    for symbol in stocks_list:
        try:
            print("Log: fetching data from external Massive API")

            symbols_query = ','.join(stocks_list)
            full_api_url = f"{api_url}/{symbol}/prev?adjusted=true&apiKey={api_key}"

            print(f"Fetching {symbol} -> {full_api_url}")
            response = http.request('GET', full_api_url)

            if response.status != 200:
                raise Exception(f"Failed to fetch {symbol}: {response.status}")

            stock_data = json.loads(response.data.decode('utf-8'))
            

            if stock_data.get("status") == "OK" and stock_data.get("results"):
                result = stock_data['results'][0]
                price = result.get('c') # 'c' is the Close Price
                            
                if price is None:
                    print(f"No close price for {symbol} in payload: {stock_data}")
                else:
                    stock_obj = {"symbol": symbol, "price": price}
                    fetched_data.append(stock_obj)
                    print(f"Fetched {symbol}: {price}")
            else:
                print(f"No data found for {symbol}")

        except Exception as e:
            print(f"Exception for {symbol}: {str(e)}")
                
    if fetched_data:
        store_in_dynamodb(fetched_data)
        return {
            "statusCode": 200,
            "body": json.dumps(
                {"message": "Success", "data": fetched_data},
                cls=DecimalEncoder
            )
        }
    else:
        return {
            "statusCode": 500,
            "body": json.dumps({"error": "Failed to fetch any stock data"})
        }
    
def store_in_dynamodb(stock_data):
    now = datetime.utcnow()
    today_str = now.strftime('%Y-%m-%d')

    for stock in stock_data:
        if 'symbol' not in stock or 'price' not in stock:
            print(f"Skipping invalid stock data: {stock}")
            continue

        price = Decimal(str(stock['price']))

        item = {
            'date': today_str,
            'symbol': stock['symbol'],
            'price': price,
            'fetched_at': now.isoformat()
        }
        table.put_item(Item=item)
        print(f"Stored item in DynamoDB: {item}")
