import boto3 
import json 
import os
from datetime import datetime, timezone
from decimal import Decimal
from secrets_helper import get_massive_api_key
from data_helper import get_market_date_str, fetch_open_close


dynamodb = boto3.resource('dynamodb')

table_name = os.environ.get('DYNAMODB_TABLE_NAME')
if not table_name:
    raise ValueError("Environment variable DYNAMODB_TABLE_NAME must be set.")
table = dynamodb.Table(table_name)
print("DynamoDB Table Name:", table_name)

api_url = os.environ.get('API_URL')
if not api_url:
    raise ValueError("Environment variable API_URL must be set.")

api_key = get_massive_api_key()
if not api_key:
    raise ValueError("Massive API key could not be loaded (check Secrets Manager secret value and MASSIVE_API_SECRET_ARN).")


stocks_list = ['AAPL', 'MSFT', 'GOOGL', 'AMZN', 'TSLA', 'NVDA']

class DecimalEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, Decimal):
            return float(obj)
        return super(DecimalEncoder, self).default(obj)
    

def lambda_handler(event, context):
    market_date = get_market_date_str()
    print(f"Computing biggest mover for {market_date}")

    best = None

    for symbol in stocks_list:
        try:
            data = fetch_open_close(api_url, api_key, symbol, market_date)
            if not data:
                continue

            open_price = data["open"]
            close_price = data["close"]
            pct = ((close_price - open_price) / open_price) * 100.0  # percent change

            print(f"{symbol}: open={open_price} close={close_price} pct_change={pct:.4f}%")

            if best is None or abs(pct) > abs(best["pct_change"]):
                best = {
                    "date": market_date,
                    "symbol": symbol,
                    "pct_change": pct,
                    "close": close_price,
                }

        except Exception as e:
            print(f"Exception for {symbol}: {e}")

    if not best:
        return {
            "statusCode": 500,
            "body": json.dumps({"error": f"No open/close data found for {market_date}"}),
        }

    store_winner_in_dynamodb(best)

    return {
        "statusCode": 200,
        "body": json.dumps({"message": "Winner stored", "winner": best}, cls=DecimalEncoder),
    }

    
def store_winner_in_dynamodb(winner: dict):
    fetched_at = datetime.now(timezone.utc).isoformat()

    item = {
        "date": winner["date"],
        "symbol": winner["symbol"],  # you can keep as sort key
        "percent_change": Decimal(str(winner["pct_change"])),
        "close": Decimal(str(winner["close"])),
        "fetched_at": fetched_at,
    }

    table.put_item(Item=item)
    print(f"Stored WINNER in DynamoDB: {item}")
