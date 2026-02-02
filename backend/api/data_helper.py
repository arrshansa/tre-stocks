import json
import urllib3
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

http = urllib3.PoolManager()
NY_TZ = ZoneInfo("America/New_York") # Eastern Time Zone for market hours (but I might want to switch it to Pacific Time later)

def get_market_date_str() -> str:
    market_date = datetime.now(NY_TZ).date()
    while market_date.weekday() >= 5:  # If the day is in the weekend move back to Friday (last market day)
        market_date -= timedelta(days=1)
    return market_date.isoformat()

def fetch_open_close(api_url: str, api_key: str, symbol: str, date_str: str) -> dict | None:
    url = f"{api_url}/{symbol}/{date_str}?adjusted=true&apiKey={api_key}"
    resp = http.request("GET", url)

    if resp.status != 200:
        body = resp.data.decode("utf-8", errors="replace")[:200]
        print(f"Open/Close failed for {symbol}: {resp.status} body={body}")
        return None

    api_response = json.loads(resp.data.decode("utf-8"))
    open_price = api_response.get("open")
    close_price = api_response.get("close")

    if open_price is None or close_price is None or open_price == 0:
        print(f"Invalid open/close for {symbol}: {api_response}")
        return None

    return {
        "symbol": symbol,
        "open": float(open_price),
        "close": float(close_price)
    }
