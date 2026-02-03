import json
from urllib.request import urlopen, Request
from urllib.error import HTTPError, URLError
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

# Choosing this as Stock Market opening and closing are based on New York time
NEW_YORK_TIMEZONE = ZoneInfo("America/New_York")

# Fetches the opening and closing prices for a given ticker symbol on a specific market date
def fetch_open_close(api_base_url: str, api_key: str, ticker_symbol: str, market_date_iso: str) -> dict | None:
    request_url = (
        f"{api_base_url}/{ticker_symbol}/{market_date_iso}"
        f"?adjusted=true&apiKey={api_key}"
    )

    
    try:
        request = Request(
            request_url,
            headers={"User-Agent": "stocks-lambda/1.0"}
        )

        with urlopen(request, timeout=10) as response:
            response_body = response.read().decode("utf-8")
            response_json = json.loads(response_body)

    # Handle HTTP and URL errors gracefully
    except HTTPError as e:
        error_body = e.read().decode("utf-8", errors="ignore")
        print(f"HTTPError for {ticker_symbol}: {e.code} {error_body}")
        return None
    except URLError as e:
        print(f"URLError for {ticker_symbol}: {e.reason}")
        return None
    except Exception as e:
        print(f"Unexpected error for {ticker_symbol}: {e}")
        return None

    # Some API responses may be valid JSON but missing open/close (e.g., no market data for that date)
    opening_price = response_json.get("open")
    closing_price = response_json.get("close")

    if opening_price is None or closing_price is None:
        return None

    return {
        "ticker": ticker_symbol,
        "open": opening_price,
        "close": closing_price
    }

# Get the previous trading day (skipping weekends)
def get_previous_trading_day(current_date):
    previous_date = current_date - timedelta(days=1)

    while previous_date.weekday() >= 5:  # Saturday or Sunday
        previous_date -= timedelta(days=1)

    return previous_date

# Find the most recent trading date (up to max_days_back) that returns open/close data for a probe ticker (default: AAPL)
def get_latest_market_date(api_base_url: str, api_key: str, probe_ticker: str = "AAPL", max_days_back:int = 7) -> str:
    current_market_date = datetime.now(NEW_YORK_TIMEZONE).date()

    # If today is a weekend, move back to the most recent trading day (Friday)
    while current_market_date.weekday() >= 5:
        current_market_date = get_previous_trading_day(current_market_date)

    days_checked = 0

    while days_checked < max_days_back:
        market_date_iso = current_market_date.isoformat()

        open_close_data = fetch_open_close(
            api_base_url,
            api_key,
            probe_ticker,
            market_date_iso
        )

        if open_close_data is not None:
            return market_date_iso

        current_market_date = get_previous_trading_day(current_market_date)
        days_checked += 1

    # Fallback: return the last checked trading date even if no data was found within max_days_back
    return current_market_date.isoformat()
