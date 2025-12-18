import json
import sys
from datetime import datetime
from jsonschema import Draft202012Validator
from urllib.parse import urlparse

format_checker = Draft202012Validator.FORMAT_CHECKER


@format_checker.checks("date-time", raises=ValueError)
def validate_rfc3339_datetime(instance: object) -> bool:
    if not isinstance(instance, str):
        return True

    # Require the RFC3339 date-time separator.
    if "T" not in instance:
        raise ValueError("missing time component")

    value = instance
    if value.endswith("Z"):
        value = f"{value[:-1]}+00:00"

    dt = datetime.fromisoformat(value)
    if dt.tzinfo is None:
        raise ValueError("timezone offset required")
    return True

schema_path = sys.argv[1]
instance_path = sys.argv[2]

@format_checker.checks("uri", raises=ValueError)
def validate_uri(instance: object) -> bool:
    if not isinstance(instance, str):
        return True

    result = urlparse(instance)
    if not all([result.scheme, result.netloc]):
        raise ValueError("invalid URI")
    return True


with open(schema_path) as f:
    schema = json.load(f)

with open(instance_path) as f:
    instance = json.load(f)

Draft202012Validator.check_schema(schema)
validator = Draft202012Validator(schema, format_checker=format_checker)
validator.validate(instance)
