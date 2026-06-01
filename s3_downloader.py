"""
S3 Data Downloader

This module reads a list of Sentrix IDs from a CSV file and downloads their 
corresponding .idat files from an AWS S3 bucket.

Usage:
    python s3_downloader.py --profile gen2 --csv ./Arizona_Pheno.csv --dest ./idats
"""

import argparse
import logging
import sys
from pathlib import Path
from typing import List

import boto3
import pandas as pd
from botocore.exceptions import BotoCoreError, ClientError

# ==========================================
# Logging Configuration
# ==========================================
# In production, print() is replaced by logging. This ensures outputs have 
# timestamps, severity levels, and can be easily written to server logs.
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)-8s | %(message)s",
    handlers=[logging.StreamHandler(sys.stdout)]
)
logger = logging.getLogger(__name__)


# ==========================================
# Core Functions
# ==========================================
def load_sentrix_ids(csv_path: Path, column_name: str) -> List[str]:
    """
    Reads Sentrix IDs from a specified CSV file.

    Args:
        csv_path (Path): The file path to the CSV.
        column_name (str): The name of the column containing the IDs.

    Returns:
        List[str]: A list of cleaned Sentrix IDs as strings.
    """
    try:
        logger.info(f"Loading Sentrix IDs from {csv_path}...")
        df = pd.read_csv(csv_path)
        
        if column_name not in df.columns:
            logger.error(f"Column '{column_name}' not found in the CSV.")
            sys.exit(1)
            
        # Drop empty rows, convert to string, and return as a list
        ids = df[column_name].dropna().astype(str).tolist()
        logger.info(f"Successfully loaded {len(ids)} IDs.")
        return ids
        
    except FileNotFoundError:
        logger.error(f"CSV file not found at {csv_path}. Please check the path.")
        sys.exit(1)
    except Exception as e:
        logger.error(f"Failed to read CSV: {e}")
        sys.exit(1)


def download_idat_files(
    aws_profile: str,
    bucket_name: str,
    source_path: str,
    dest_dir: Path,
    sentrix_ids: List[str]
) -> None:
    """
    Iterates through Sentrix IDs, queries S3 for matching .idat files, 
    and downloads them to a local directory.
    """
    # Initialize the S3 client
    try:
        session = boto3.Session(profile_name=aws_profile)
        s3_client = session.client("s3")
    except Exception as e:
        logger.error(f"Failed to initialize boto3 session with profile '{aws_profile}': {e}")
        sys.exit(1)

    # Ensure destination directory exists
    dest_dir.mkdir(parents=True, exist_ok=True)
    logger.info(f"Destination directory set to {dest_dir.resolve()}")

    download_count = 0

    for i, s_id in enumerate(sentrix_ids, start=1):
        sub_dir = s_id.split("_")[0]
        prefix = f"{source_path}/{sub_dir}/{s_id}"
        
        try:
            response = s3_client.list_objects_v2(Bucket=bucket_name, Prefix=prefix)
            
            if 'Contents' not in response:
                logger.warning(f"[{i}/{len(sentrix_ids)}] No files found for prefix: {prefix}")
                continue

            for obj in response['Contents']:
                s3_key = obj['Key']
                
                # Only process .idat files
                if not s3_key.endswith('.idat'):
                    continue
                
                # Use Pathlib to extract the filename and build the local path safely
                file_name = Path(s3_key).name
                local_path = dest_dir / file_name
                
                logger.info(f"[{i}/{len(sentrix_ids)}] Downloading {file_name}...")
                s3_client.download_file(
                    Bucket=bucket_name, 
                    Key=s3_key, 
                    Filename=str(local_path)
                )
                logger.info(f"Success: Saved {file_name}")
                download_count += 1
                
        except (BotoCoreError, ClientError) as aws_err:
            logger.error(f"AWS Error processing ID {s_id}: {aws_err}")
        except Exception as e:
            logger.error(f"Unexpected error processing ID {s_id}: {e}")

    logger.info(f"Job complete. Successfully downloaded {download_count} files.")


# ==========================================
# Main Execution Block
# ==========================================
def main() -> None:
    """
    Parses command-line arguments and orchestrates the download pipeline.
    """
    parser = argparse.ArgumentParser(description="Download .idat files from S3 based on a CSV list.")
    
    # Define terminal arguments
    parser.add_argument("--csv", required=True, help="Path to the Arizona_Pheno.csv file")
    parser.add_argument("--dest", required=True, help="Local directory to save the downloaded files")
    parser.add_argument("--profile", default="gen2", help="AWS CLI profile to use (default: gen2)")
    parser.add_argument("--bucket", default="476-fhls-gen", help="Target S3 Bucket")
    parser.add_argument("--source", default="iDAT files", help="Root S3 folder path")
    parser.add_argument("--col", default="GWAS_SENTRIX", help="CSV Column name containing the IDs")

    args = parser.parse_args()

    # Convert string paths to Pathlib objects
    csv_path = Path(args.csv)
    dest_dir = Path(args.dest)

    # 1. Load the data
    sentrix_list = load_sentrix_ids(csv_path, args.col)

    # 2. Execute the downloads
    download_idat_files(
        aws_profile=args.profile,
        bucket_name=args.bucket,
        source_path=args.source,
        dest_dir=dest_dir,
        sentrix_ids=sentrix_list
    )

if __name__ == "__main__":
    main()