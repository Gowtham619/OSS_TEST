"""
Lambda behind API Gateway. Receives a JSON body like {"query_text": "..."}
from the frontend, embeds it via Bedrock Titan, runs a k-NN similarity
search against whichever store(s) are configured, and returns the top
matching complaints as JSON.

Environment variables (set at least one):
  AOSS_ENDPOINT     full https:// URL
  CLUSTER_ENDPOINT  full https:// URL
"""
import json
import os
import boto3
import requests
from requests_aws4auth import AWS4Auth

REGION = os.environ.get("AWS_REGION", "eu-west-1")
TOP_K = int(os.environ.get("TOP_K", "5"))

CORS_HEADERS = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "Content-Type",
    "Access-Control-Allow-Methods": "POST,OPTIONS",
}


def get_embedding(text: str) -> list:
    bedrock = boto3.client("bedrock-runtime", region_name=REGION)
    resp = bedrock.invoke_model(
        modelId="amazon.titan-embed-text-v2:0",
        body=json.dumps({"inputText": text}),
    )
    body = json.loads(resp["body"].read())
    return body["embedding"]


def knn_search(endpoint: str, service: str, index_name: str, query_embedding: list, creds, k: int) -> list:
    auth = AWS4Auth(
        creds.access_key, creds.secret_key, REGION, service,
        session_token=creds.token,
    )
    body = {
        "size": k,
        "query": {"knn": {"embedding": {"vector": query_embedding, "k": k}}},
        "_source": ["text"],
    }
    r = requests.post(
        f"{endpoint}/{index_name}/_search", auth=auth,
        headers={"Content-Type": "application/json"},
        data=json.dumps(body), timeout=20,
    )
    if r.status_code != 200:
        return [{"error": f"{r.status_code}: {r.text[:300]}"}]

    hits = r.json().get("hits", {}).get("hits", [])
    return [
        {"text": h["_source"].get("text"), "score": h.get("_score")}
        for h in hits
    ]


def response(status_code: int, body: dict):
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json", **CORS_HEADERS},
        "body": json.dumps(body),
    }


def handler(event, context):
    # CORS preflight
    method = event.get("requestContext", {}).get("http", {}).get("method", "")
    if method == "OPTIONS":
        return response(200, {})

    try:
        payload = json.loads(event.get("body") or "{}")
    except json.JSONDecodeError:
        return response(400, {"error": "Body must be valid JSON"})

    query_text = payload.get("query_text", "").strip()
    if not query_text:
        return response(400, {"error": "Missing 'query_text' in request body"})

    session = boto3.Session()
    creds = session.get_credentials().get_frozen_credentials()

    try:
        query_embedding = get_embedding(query_text)
    except Exception as e:
        return response(502, {"error": f"Embedding call failed: {e}"})

    results = {}

    aoss_endpoint = os.environ.get("AOSS_ENDPOINT")
    if aoss_endpoint:
        results["aoss"] = knn_search(aoss_endpoint, "aoss", "test-complaints", query_embedding, creds, TOP_K)

    cluster_endpoint = os.environ.get("CLUSTER_ENDPOINT")
    if cluster_endpoint:
        results["cluster"] = knn_search(cluster_endpoint, "es", "test-complaints", query_embedding, creds, TOP_K)

    return response(200, {"query_text": query_text, "results": results})
