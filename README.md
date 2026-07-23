# AWS_CLI

These scripts are writen to configure and copy data from your local storage to Amazon Relational Database Service (RDS) using AWS CLI tool. 

## Installation
`
conda install -c conda-forge awscli
`
## Configuration
Set the variable in `aws.args` file and then run the following command:  

`
bash aws.config.sh aws.args
`

## Downloading and uploading files 
To download data from RDS into your local storage, set the `Source` variable in `aws.args` to the file or folder path in RDS and `Destination` variable to the destination path in your local computer and then run the following command:

`
bash aws.download.sh aws.args
`

To upload files from your local storage into RDS, set the `Source` variable in `aws.args` to the file or folder path in your local computer and `Destination` variable to the destination path in RDS and then run the following command:
`
bash aws.upload.sh aws.args
`

The `Source` variable can be the full path of a single file or a directory. If you set the `Source` variable to a directory, all files in that directory will be copied to `Destination`.

You can find some other useful scripts in `Other-Scripts` folder to download from a bucket using `boto3` in python and `paws` in R.

The following bash functions can also be added to the `.bashrc` as an alternative way to use AWS CLI. 

`
aws_upload() {
    # 1. Validate that exactly 3 arguments were provided
    if [ "$#" -ne 3 ]; then
        echo "Error: Incorrect number of arguments."
        echo "Usage: aws_upload <Profile> <Source> <Destination>"
        return 1
    fi

    local Profile="$1"
    local Source="$2"
    local Destination="$3"

    # 2. Dynamically fetch Bucket_Name and Endpoint_URL from AWS config
    local Bucket_Name
    local Endpoint_URL

    # Capture the values from the config file
    Bucket_Name=$(aws configure get bucket_name --profile "$Profile" 2>/dev/null)
    Endpoint_URL=$(aws configure get endpoint_url --profile "$Profile" 2>/dev/null)

    # Validate that we successfully retrieved the bucket name
    if [ -z "$Bucket_Name" ]; then
        echo "Error: Could not find 'bucket_name' in AWS config for profile '$Profile'."
        return 1
    fi

    # 3. Clean up Destination slashes
    Destination="${Destination#/}"
    Destination="${Destination%/}"

    # 4. Build the base AWS command
    # If the endpoint URL exists in the config, append the flag. If not, use standard AWS S3.
    local AWS_CMD=(aws --profile "$Profile")
    if [ -n "$Endpoint_URL" ]; then
        # Remove quotes if aws configure get pulled them in
        Endpoint_URL="${Endpoint_URL%\"}"
        Endpoint_URL="${Endpoint_URL#\"}"
        AWS_CMD+=(--endpoint-url="${Endpoint_URL}")
    fi
    AWS_CMD+=(s3)

    # 5. Execute the appropriate upload command
    if [[ -d "$Source" ]]; then
        echo "Uploading directory '$Source' to 's3://${Bucket_Name}/${Destination}' using profile '$Profile'..."
        "${AWS_CMD[@]}" sync "$Source" "s3://${Bucket_Name}/${Destination}" --no-progress --cli-read-timeout 0

    elif [[ -f "$Source" ]]; then
        echo "Uploading file '$Source' to 's3://${Bucket_Name}/${Destination}/' using profile '$Profile'..."
        "${AWS_CMD[@]}" cp "$Source" "s3://${Bucket_Name}/${Destination}/$(basename "$Source")" --no-progress --cli-read-timeout 0

    else
        echo "Error: Source '$Source' is not valid or does not exist."
        return 1
    fi

    # 6. Check if the command succeeded
    if [ "$?" -eq 0 ]; then
        echo "Upload completed successfully."
    else
        echo "Error: Upload failed."
        return 1
    fi
}

`
`
aws_download() {
    if [ "$#" -ne 3 ]; then
        echo "Error: Incorrect number of arguments."
        echo "Usage: aws_download <Profile> <S3_Source> <Local_Destination>"
        return 1
    fi

    local Profile="$1"
    local S3_Source="$2"
    local Destination="$3"

    local Bucket_Name=$(aws configure get bucket_name --profile "$Profile" 2>/dev/null)
    local Endpoint_URL=$(aws configure get endpoint_url --profile "$Profile" 2>/dev/null)

    if [ -z "$Bucket_Name" ]; then
        echo "Error: Could not find 'bucket_name' in AWS config for profile '$Profile'."
        return 1
    fi

    S3_Source="${S3_Source#/}"
    S3_Source="${S3_Source%/}"

    # Build the base AWS command (without appending 's3' yet)
    local AWS_CMD=(aws --profile "$Profile")
    if [ -n "$Endpoint_URL" ]; then
        Endpoint_URL="${Endpoint_URL%\"}"
        Endpoint_URL="${Endpoint_URL#\"}"
        AWS_CMD+=(--endpoint-url="${Endpoint_URL}")
    fi

    # 1. Fast File Check (head-object)
    local is_file=""
    if "${AWS_CMD[@]}" s3api head-object --bucket "$Bucket_Name" --key "$S3_Source" >/dev/null 2>&1; then
        is_file="true"
    fi

    # 2. Fast Directory Check (list-objects-v2 with --max-keys 1)
    # Only run this if it wasn't already identified as a file
    local is_dir=""
    if [ -z "$is_file" ]; then
        local dir_check=$("${AWS_CMD[@]}" s3api list-objects-v2 \
            --bucket "$Bucket_Name" \
            --prefix "${S3_Source}/" \
            --max-keys 1 \
            --query 'Contents[0].Key' \
            --output text 2>/dev/null)

        # AWS CLI returns the string "None" if the query finds no objects
        if [[ "$dir_check" != "None" && -n "$dir_check" ]]; then
            is_dir="true"
        fi
    fi

    # 3. Execute the appropriate transfer
    if [ -n "$is_dir" ]; then
        echo "Downloading S3 directory 's3://${Bucket_Name}/${S3_Source}' to '${Destination}'..."
        mkdir -p "$Destination"
        "${AWS_CMD[@]}" s3 sync "s3://${Bucket_Name}/${S3_Source}" "$Destination" --no-progress --cli-read-timeout 0

    elif [ -n "$is_file" ]; then
        echo "Downloading S3 file 's3://${Bucket_Name}/${S3_Source}' to '${Destination}'..."
        "${AWS_CMD[@]}" s3 cp "s3://${Bucket_Name}/${S3_Source}" "$Destination" --no-progress --cli-read-timeout 0

    else
        echo "Error: S3 Source 's3://${Bucket_Name}/${S3_Source}' is not valid or does not exist."
        return 1
    fi

    if [ "$?" -eq 0 ]; then
        echo "Download completed successfully."
    else
        echo "Error: Download failed."
        return 1
    fi
}
`
`
aws_remove() {
    # 1. Validate that exactly 2 arguments were provided
    if [ "$#" -ne 2 ]; then
        echo "Error: Incorrect number of arguments."
        echo "Usage: aws_remove <Profile> <S3_Target>"
        echo "Example: aws_remove work raw_data/batch1"
        return 1
    fi

    local Profile="$1"
    local S3_Target="$2"

    # 2. Dynamically fetch Bucket_Name and Endpoint_URL from AWS config
    local Bucket_Name=$(aws configure get bucket_name --profile "$Profile" 2>/dev/null)
    local Endpoint_URL=$(aws configure get endpoint_url --profile "$Profile" 2>/dev/null)

    if [ -z "$Bucket_Name" ]; then
        echo "Error: Could not find 'bucket_name' in AWS config for profile '$Profile'."
        return 1
    fi

    # 3. Clean up S3_Target slashes
    S3_Target="${S3_Target#/}"
    S3_Target="${S3_Target%/}"

    # CRITICAL SAFETY CHECK: Prevent accidental full-bucket deletion
    if [ -z "$S3_Target" ]; then
        echo "Error: S3 Target cannot be empty or root (/). Please specify a file or folder path."
        return 1
    fi

    # 4. Build the base AWS command
    local AWS_CMD=(aws --profile "$Profile")
    if [ -n "$Endpoint_URL" ]; then
        Endpoint_URL="${Endpoint_URL%\"}"
        Endpoint_URL="${Endpoint_URL#\"}"
        AWS_CMD+=(--endpoint-url="${Endpoint_URL}")
    fi

    # 5. Fast File Check (head-object)
    local is_file=""
    if "${AWS_CMD[@]}" s3api head-object --bucket "$Bucket_Name" --key "$S3_Target" >/dev/null 2>&1; then
        is_file="true"
    fi

    # 6. Fast Directory Check (list-objects-v2)
    local is_dir=""
    if [ -z "$is_file" ]; then
        local dir_check=$("${AWS_CMD[@]}" s3api list-objects-v2 \
            --bucket "$Bucket_Name" \
            --prefix "${S3_Target}/" \
            --max-keys 1 \
            --query 'Contents[0].Key' \
            --output text 2>/dev/null)

        if [[ "$dir_check" != "None" && -n "$dir_check" ]]; then
            is_dir="true"
        fi
    fi

    # 7. Execute the appropriate deletion command
    if [ -n "$is_dir" ]; then
        echo "Removing S3 directory and all its contents: 's3://${Bucket_Name}/${S3_Target}/'..."
        # Requires the --recursive flag for directories
        "${AWS_CMD[@]}" s3 rm "s3://${Bucket_Name}/${S3_Target}/" --recursive

    elif [ -n "$is_file" ]; then
        echo "Removing S3 file: 's3://${Bucket_Name}/${S3_Target}'..."
        "${AWS_CMD[@]}" s3 rm "s3://${Bucket_Name}/${S3_Target}"

    else
        echo "Error: S3 Target 's3://${Bucket_Name}/${S3_Target}' does not exist."
        return 1
    fi

    # 8. Check if the command succeeded
    if [ "$?" -eq 0 ]; then
        echo "Removal completed successfully."
    else
        echo "Error: Removal failed."
        return 1
    fi
}


`
