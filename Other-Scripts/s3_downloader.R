#!/usr/bin/env Rscript

#' S3 Data Downloader
#'
#' This script reads a list of Sentrix IDs from a CSV file and downloads their 
#' corresponding .idat files from an AWS S3 bucket.
#'
#' Usage:
#'   Rscript s3_downloader.R --csv ./Arizona_Pheno.csv --dest ./idats --profile gen2

suppressPackageStartupMessages({
  library(optparse)
  library(logger)
  library(paws)
  library(readr)
  library(fs)
  library(stringr)
})

# ==========================================
# Logging Configuration
# ==========================================
# Sets up console logging with timestamps and severity levels.
log_layout(layout_glue_generator(format = "{time} | {level} | {msg}"))
log_threshold(INFO)


# ==========================================
# Core Functions
# ==========================================

#' Load Sentrix IDs from CSV
#'
#' @param csv_path Character. The file path to the CSV.
#' @param column_name Character. The name of the column containing the IDs.
#' @return A character vector of cleaned Sentrix IDs.
load_sentrix_ids <- function(csv_path, column_name) {
  log_info("Loading Sentrix IDs from {csv_path}...")
  
  if (!file_exists(csv_path)) {
    log_error("CSV file not found at {csv_path}. Please check the path.")
    quit(status = 1)
  }
  
  # read_csv is safer and faster than base read.csv
  df <- tryCatch({
    read_csv(csv_path, show_col_types = FALSE)
  }, error = function(e) {
    log_error("Failed to read CSV: {e$message}")
    quit(status = 1)
  })
  
  if (!(column_name %in% names(df))) {
    log_error("Column '{column_name}' not found in the CSV.")
    quit(status = 1)
  }
  
  # Extract column, remove NAs, and ensure it's a character vector
  ids <- df[[column_name]]
  ids <- as.character(na.omit(ids))
  ids <- ids[ids != ""] # Remove empty strings if any
  
  log_info("Successfully loaded {length(ids)} IDs.")
  return(ids)
}

#' Download .idat files from S3
#'
#' @param aws_profile Character. The AWS CLI profile to use.
#' @param bucket_name Character. The target S3 Bucket.
#' @param source_path Character. The root S3 folder path.
#' @param dest_dir Character. Local directory to save files.
#' @param sentrix_ids Character vector. List of IDs to process.
download_idat_files <- function(aws_profile, bucket_name, source_path, dest_dir, sentrix_ids) {
  
  # Set AWS profile in environment for paws to pick up
  Sys.setenv(AWS_PROFILE = aws_profile)
  
  # Initialize S3 client
  s3 <- tryCatch({
    paws::s3()
  }, error = function(e) {
    log_error("Failed to initialize AWS S3 client with profile '{aws_profile}': {e$message}")
    quit(status = 1)
  })
  
  # Ensure destination directory exists (similar to exist_ok=True)
  dir_create(dest_dir)
  log_info("Destination directory set to {path_abs(dest_dir)}")
  
  download_count <- 0
  total_ids <- length(sentrix_ids)
  
  for (i in seq_along(sentrix_ids)) {
    s_id <- sentrix_ids[i]
    sub_dir <- str_split(s_id, "_")[[1]][1]
    prefix <- sprintf("%s/%s/%s", source_path, sub_dir, s_id)
    
    tryCatch({
      response <- s3$list_objects_v2(Bucket = bucket_name, Prefix = prefix)
      
      if (length(response$Contents) == 0) {
        log_warn("[{i}/{total_ids}] No files found for prefix: {prefix}")
        next
      }
      
      for (obj in response$Contents) {
        s3_key <- obj$Key
        
        # Only process .idat files
        if (!str_ends(s3_key, "\\.idat")) {
          next
        }
        
        # Extract filename and build local path safely
        file_name <- path_file(s3_key)
        local_path <- path(dest_dir, file_name)
        
        log_info("[{i}/{total_ids}] Downloading {file_name}...")
        
        # Download object to memory, then write binary to disk
        obj_data <- s3$get_object(Bucket = bucket_name, Key = s3_key)
        writeBin(obj_data$Body, as.character(local_path))
        
        log_info("Success: Saved {file_name}")
        download_count <- download_count + 1
      }
      
    }, error = function(e) {
      log_error("Error processing ID {s_id}: {e$message}")
    })
  }
  
  log_info("Job complete. Successfully downloaded {download_count} files.")
}

# ==========================================
# Main Execution Block
# ==========================================
main <- function() {
  option_list <- list(
    make_option(c("--csv"), type="character", default=NULL, 
                help="Path to the Arizona_Pheno.csv file [Required]"),
    make_option(c("--dest"), type="character", default=NULL, 
                help="Local directory to save the downloaded files [Required]"),
    make_option(c("--profile"), type="character", default="gen2", 
                help="AWS CLI profile to use (default: gen2)"),
    make_option(c("--bucket"), type="character", default="476-fhls-gen", 
                help="Target S3 Bucket"),
    make_option(c("--source"), type="character", default="iDAT files", 
                help="Root S3 folder path"),
    make_option(c("--col"), type="character", default="GWAS_SENTRIX", 
                help="CSV Column name containing the IDs")
  )
  
  parser <- OptionParser(
    usage = "%prog --csv <path> --dest <path> [options]", 
    option_list = option_list,
    description = "Download .idat files from S3 based on a CSV list."
  )
  
  args <- parse_args(parser)
  
  # Validate required arguments
  if (is.null(args$csv) || is.null(args$dest)) {
    print_help(parser)
    log_error("Both --csv and --dest arguments are required.")
    quit(status = 1)
  }
  
  # 1. Load the data
  sentrix_list <- load_sentrix_ids(args$csv, args$col)
  
  # 2. Execute the downloads
  download_idat_files(
    aws_profile = args$profile,
    bucket_name = args$bucket,
    source_path = args$source,
    dest_dir = args$dest,
    sentrix_ids = sentrix_list
  )
}

# Ensure script is run from the command line (similar to if __name__ == "__main__")
if (!interactive()) {
  main()
}