import os
import json
import boto3
from functools import lru_cache

_secrets = boto3.client("secretsmanager")

@lru_cache(maxsize=1)
def get_massive_api_key() -> str:
    arn = os.environ.get("MASSIVE_API_SECRET_ARN")
    if not arn:
        raise RuntimeError("MASSIVE_API_SECRET_ARN must be set")

    resp = _secrets.get_secret_value(SecretId=arn)
    s = resp.get("SecretString") or ""
    try:
        data = json.loads(s)
        return data["MASSIVE_API_Key"]
    except Exception:
        # if you stored it as raw string instead of JSON
        return s