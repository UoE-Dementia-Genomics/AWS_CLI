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

