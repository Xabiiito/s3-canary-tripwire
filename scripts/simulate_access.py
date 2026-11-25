import argparse
import datetime
import json
import sys
import boto3
from botocore.exceptions import ClientError


def simulate_canary_read(bucket_name: str, object_key: str, region: str, profile: str | None) -> int:
    session = boto3.Session(profile_name=profile, region_name=region) if profile else boto3.Session(region_name=region)
    s3_client = session.client("s3")

    timestamp = datetime.datetime.now(datetime.timezone.utc).isoformat()
    print(f"[{timestamp}] Simulating GetObject on s3://{bucket_name}/{object_key} ({region})...")

    try:
        response = s3_client.get_object(Bucket=bucket_name, Key=object_key)
        raw_body = response["Body"].read().decode("utf-8", errors="replace")
        print("Read succeeded. Decoy payload retrieved:")
        print(raw_body)
        return 0
    except ClientError as exc:
        error_code = exc.response.get("Error", {}).get("Code", "Unknown")
        error_msg = exc.response.get("Error", {}).get("Message", str(exc))
        print(f"Access attempt completed with ClientError [{error_code}]: {error_msg}", file=sys.stderr)
        return 1


def main() -> int:
    parser = argparse.ArgumentParser(description="Simulate a read access against an S3 canary object.")
    parser.add_argument("--bucket", required=True, help="Target S3 bucket name")
    parser.add_argument("--key", required=True, help="Target S3 object key")
    parser.add_argument("--region", default="eu-west-1", help="AWS region (default: eu-west-1)")
    parser.add_argument("--profile", default=None, help="Optional AWS CLI profile name")
    args = parser.parse_args()

    return simulate_canary_read(
        bucket_name=args.bucket,
        object_key=args.key,
        region=args.region,
        profile=args.profile,
    )


if __name__ == "__main__":
    sys.exit(main())