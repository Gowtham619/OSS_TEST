"""
Test Lambda: gets a real embedding from Bedrock Titan, then writes and
searches a test document in whichever store(s) are configured via
environment variables. Uses the Lambda's own execution role credentials —
no assume-role step needed, since the embedding/retrieval Lambda roles
are already granted data-plane access to both vector stores by the
Terraform modules.

Environment variables (set at least one):
  AOSS_ENDPOINT     e.g. https://xxxx.eu-west-1.aoss.amazonaws.com
  CLUSTER_ENDPOINT  e.g. https://vpc-xxxx.eu-west-1.es.amazonaws.com
"""
import json
import os
import boto3
import requests
from requests_aws4auth import AWS4Auth

REGION = os.environ.get("AWS_REGION", "eu-west-1")
TEST_COMPLAINT = "Customer complained about an unauthorized $200 charge on their card"


def get_embedding(text: str) -> list:
    bedrock = boto3.client("bedrock-runtime", region_name=REGION)
    resp = bedrock.invoke_model(
        modelId="amazon.titan-embed-text-v2:0",
        body=json.dumps({"inputText": text}),
    )
    body = json.loads(resp["body"].read())
    return body["embedding"]


def bootstrap_cluster_role_mapping(cluster_endpoint: str):
    """
    One-time (idempotent) setup: OpenSearch's internal Security plugin
    grants no privileges to any identity except the master user, no
    matter what the IAM access policy allows. This maps the embedding
    and retrieval Lambda roles to 'all_access' inside the domain, using
    the admin role (the master user) via STS assume-role. Safe to call
    on every invoke — PUT is idempotent.
    """
    sts = boto3.client("sts", region_name=REGION)
    admin_role_arn = os.environ["ADMIN_ROLE_ARN"]
    assumed = sts.assume_role(RoleArn=admin_role_arn, RoleSessionName="ingestion-test-bootstrap")
    creds = assumed["Credentials"]

    auth = AWS4Auth(
        creds["AccessKeyId"], creds["SecretAccessKey"], REGION, "es",
        session_token=creds["SessionToken"],
    )

    body = {
        "backend_roles": [
            os.environ["EMBEDDING_LAMBDA_ROLE_ARN"],
            os.environ["RETRIEVAL_LAMBDA_ROLE_ARN"],
        ],
        "users": [],
        "hosts": [],
    }
    r = requests.put(
        f"{cluster_endpoint}/_plugins/_security/api/rolesmapping/all_access",
        auth=auth, headers={"Content-Type": "application/json"},
        data=json.dumps(body), timeout=20,
    )
    return {"status": r.status_code, "body": r.text[:300]}


def test_store(endpoint: str, service: str, index_name: str, embedding: list, creds) -> dict:
    auth = AWS4Auth(
        creds.access_key, creds.secret_key, REGION, service,
        session_token=creds.token,
    )
    headers = {"Content-Type": "application/json"}
    results = {}

    create_body = {
        "settings": {"index.knn": True},
        "mappings": {
            "properties": {
                "embedding": {
                    "type": "knn_vector",
                    "dimension": len(embedding),
                    "method": {"name": "hnsw", "engine": "nmslib"},
                },
                "text": {"type": "text"},
            }
        },
    }
    r = requests.put(f"{endpoint}/{index_name}", auth=auth, headers=headers,
                      data=json.dumps(create_body), timeout=20)
    results["create_index"] = {"status": r.status_code, "body": r.text[:300]}

    doc = {"text": TEST_COMPLAINT, "embedding": embedding}
    r = requests.post(f"{endpoint}/{index_name}/_doc", auth=auth, headers=headers,
                       data=json.dumps(doc), timeout=20)
    results["index_doc"] = {"status": r.status_code, "body": r.text[:300]}

    r = requests.post(f"{endpoint}/{index_name}/_search", auth=auth, headers=headers,
                       data=json.dumps({"query": {"match_all": {}}}), timeout=20)
    results["search"] = {"status": r.status_code, "body": r.text[:500]}

    return results


def knn_search(endpoint: str, service: str, index_name: str, query_embedding: list, creds, k: int = 5) -> dict:
    """
    Real RAG retrieval query: finds the k complaints whose embeddings are
    closest to query_embedding. This is what a retrieval Lambda would call
    with the embedding of an incoming user question.
    """
    auth = AWS4Auth(
        creds.access_key, creds.secret_key, REGION, service,
        session_token=creds.token,
    )
    body = {
        "size": k,
        "query": {
            "knn": {
                "embedding": {
                    "vector": query_embedding,
                    "k": k,
                }
            }
        },
        "_source": ["text"],  # skip returning the big embedding array
    }
    r = requests.post(
        f"{endpoint}/{index_name}/_search", auth=auth,
        headers={"Content-Type": "application/json"},
        data=json.dumps(body), timeout=20,
    )
    return {"status": r.status_code, "body": r.text[:1000]}


def handler(event, context):
    session = boto3.Session()
    creds = session.get_credentials().get_frozen_credentials()

    # Query mode: invoke with {"query_text": "your question here"} to run
    # a real k-NN similarity search instead of the ingestion self-test.
    query_text = (event or {}).get("query_text")
    if query_text:
        query_embedding = get_embedding(query_text)
        output = {"query_text": query_text, "embedding_dimensions": len(query_embedding)}

        aoss_endpoint = os.environ.get("AOSS_ENDPOINT")
        if aoss_endpoint:
            output["aoss"] = knn_search(aoss_endpoint, "aoss", "test-complaints", query_embedding, creds)

        cluster_endpoint = os.environ.get("CLUSTER_ENDPOINT")
        if cluster_endpoint:
            output["cluster"] = knn_search(cluster_endpoint, "es", "test-complaints", query_embedding, creds)

        return output

    # Default mode: the original ingestion self-test (create index, write
    # a doc, match_all search) — unchanged from before.
    embedding = get_embedding(TEST_COMPLAINT)
    output = {"embedding_dimensions": len(embedding)}

    aoss_endpoint = os.environ.get("AOSS_ENDPOINT")
    if aoss_endpoint:
        output["aoss"] = test_store(aoss_endpoint, "aoss", "test-complaints", embedding, creds)

    cluster_endpoint = os.environ.get("CLUSTER_ENDPOINT")
    if cluster_endpoint:
        output["cluster_role_mapping"] = bootstrap_cluster_role_mapping(cluster_endpoint)
        output["cluster"] = test_store(cluster_endpoint, "es", "test-complaints", embedding, creds)

    return output
