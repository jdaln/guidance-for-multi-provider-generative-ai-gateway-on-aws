"""Import the middleware app for unit tests without AWS credentials or a database.

app.py creates a boto3 client at import time (needs a region) and connects to
Postgres only on the FastAPI startup event, which pytest never triggers.
"""
import os
import sys

os.environ.setdefault("AWS_DEFAULT_REGION", "eu-north-1")
os.environ.setdefault("AWS_REGION", "eu-north-1")
os.environ.setdefault("CONVERSE_COMPAT_MODULE", "app")
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "middleware"))
