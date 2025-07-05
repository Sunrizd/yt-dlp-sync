#!/bin/bash

# yt-dlp-rename-postprocessor.sh
# This script is executed by yt-dlp's --exec option to handle filename renaming.

# Arguments:
# $1: Full path to the downloaded file (e.g., /mnt/e-music/Music/Liked Songs/Artist - Title [ID].mp3)

# --- Script's Own Directory ---
# This reliably determines the absolute path to the directory where this script is located.
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

# --- Source Configuration ---
# Load all configuration variables from config/.env
# This script relies on the .env file being sourced by the main script,
# but it's good practice to source it here too for standalone testing or direct execution.
if [ -f "$SCRIPT_DIR/config/.env" ]; then
    source "$SCRIPT_DIR/config/.env"
else
    # Fallback for logging if .env isn't found (though main script should catch this)
    echo "$(date '+%Y-%m-%d %H:%M:%S') - POST-PROCESSOR: CRITICAL ERROR: Configuration file '$SCRIPT_DIR/config/.env' not found. Cannot proceed." | tee -a "/tmp/yt-dlp-postprocessor-error.log"
    exit 1
fi

# --- Final Path Assignments (using defaults or overrides from .env) ---
# These variables are derived or set based on values loaded from .env
# They are kept here for clarity and to ensure consistent path resolution in the script logic.
POST_PROCESSOR_LOG_FILE="${CUSTOM_POST_PROCESSOR_LOG_FILE:-$SCRIPT_DIR/config/logs/yt-dlp-sync-postprocessor.log}" # Default to config/logs folder
COOKIES_FILE="${CUSTOM_COOKIES_FILE:-$SCRIPT_DIR/config/cookies.txt}"
DOWNLOAD_DIR="${CUSTOM_DOWNLOAD_DIR:-$(sudo -u "$RUN_AS_USER" printenv HOME)/Music/Liked Songs}" # Need DOWNLOAD_DIR for mv command
YT_DLP_CMD_TO_USE="${YT_DLP_BINARY_PATH:-/usr/local/bin/yt-dlp}" # Uses override from .env or 'yt-dlp' from PATH


# Function to log messages from this post-processor
post_log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - POST-PROCESSOR: $1" | tee -a "$POST_PROCESSOR_LOG_FILE"
}

# --- Start Script Logic ---

FILE_PATH="$1"

if [ ! -f "$FILE_PATH" ]; then
    post_log_message "ERROR: File not found for post-processing: $FILE_PATH"
    exit 1
fi

ORIGINAL_NAME="$(basename "$FILE_PATH")"
# DOWNLOAD_DIR is sourced from .env, ensuring it's the correct final destination path.

# Extract VIDEO_ID from the filename using regex
VIDEO_ID=$(echo "$ORIGINAL_NAME" | grep -oP '\[([a-zA-Z0-9_-]{11})\]\.(mp3|m4a|aac|opus|flac)$' | grep -oP '[a-zA-Z0-9_-]{11}')

if [ -z "$VIDEO_ID" ]; then
    post_log_message "WARNING: Could not extract VIDEO_ID from filename: '$ORIGINAL_NAME'. Skipping artist check."
    exit 0 # Exit gracefully if ID can't be found (preventing further errors)
fi

# Get the artist using yt-dlp. Rely on PATH environment variable.
# Ensure yt-dlp is in the PATH of the user executing this script.
ARTIST_RAW="$(sudo -u "$RUN_AS_USER" "$YT_DLP_CMD_TO_USE" --print "%(artist)s" "$VIDEO_ID" --restrict-filenames --no-warnings --quiet --cookies "$COOKIES_FILE")"

# Remove control characters or unwanted whitespace from ARTIST
ARTIST=$(echo "$ARTIST_RAW" | tr -d '\n\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

post_log_message "Processing: '$ORIGINAL_NAME', ID: '$VIDEO_ID', Detected Artist: '$ARTIST'"

# Check if ARTIST is "NA" (case-insensitive) or empty
if [[ "$ARTIST" =~ ^[Nn][Aa]$ || -z "$ARTIST" ]]; then
    # Use sed to remove "NA ", "NA-", "na ", "na-" from the beginning
    NEW_NAME="$(echo "$ORIGINAL_NAME" | sed -E 's/^[Nn][Aa][[:space:]]*-?[[:space:]]?//')"

    # Only rename if the name actually changed
    if [[ "$ORIGINAL_NAME" != "$NEW_NAME" ]]; then
        mv -v "$FILE_PATH" "$DOWNLOAD_DIR/$NEW_NAME"
        if [ $? -eq 0 ]; then
            # Log the original name explicitly here to avoid the cosmetic issue
            post_log_message "Renamed: '$ORIGINAL_NAME' to '$NEW_NAME'"
        else
            post_log_message "ERROR: Failed to rename '$ORIGINAL_NAME' to '$NEW_NAME'. Check permissions."
            exit 1
        fi
    else
        post_log_message "No rename needed for '$ORIGINAL_NAME' (artist is 'NA' or empty, but no 'NA' prefix found to remove)."
    fi
else
    post_log_message "No rename needed for '$ORIGINAL_NAME' (artist is '$ARTIST')."
fi

exit 0
