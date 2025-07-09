#!/bin/bash

# yt-dlp-sync.sh
# Script to synchronize a YouTube Music playlist using yt-dlp
# Executing yt-dlp as a specific user.

# --- Script's Own Directory ---
# This reliably determines the absolute path to the directory where this script is located.
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

# --- Source Configuration ---
# Load configuration variables from config/.env
# IMPORTANT: Users MUST copy .env.example to .env and fill in their values.
if [ -f "$SCRIPT_DIR/config/.env" ]; then
    source "$SCRIPT_DIR/config/.env"
else
    echo "CRITICAL ERROR: Configuration file '$SCRIPT_DIR/config/.env' not found."
    echo "Please copy '$SCRIPT_DIR/config/.env.example' to '.env' and fill in your details."
    exit 1
fi

# --- Validate essential variables loaded from .env ---
if [ -z "$RUN_AS_USER" ] || [ "$RUN_AS_USER" == "your_linux_username" ]; then
    echo "CRITICAL ERROR: RUN_AS_USER is not set or is still the placeholder in config/.env. Please edit the .env file."
    exit 1
fi

# --- Final Path Assignments (using defaults or overrides from .env) ---
# These variables are derived or set based on values loaded from .env
# They are kept here for clarity and to ensure consistent path resolution in the script logic.

# Paths for files in config/ subfolder (cookies, archive, logs)
COOKIES_FILE="${CUSTOM_COOKIES_FILE:-$SCRIPT_DIR/config/cookies.txt}"
ARCHIVE_FILE="${CUSTOM_ARCHIVE_FILE:-$SCRIPT_DIR/config/archive.txt}"
# Main log defaults to within config/logs folder
LOG_FILE="${CUSTOM_MAIN_LOG_FILE:-$SCRIPT_DIR/config/logs/yt-dlp-sync.log}"

# Paths for downloaded data
DOWNLOAD_DIR="${CUSTOM_DOWNLOAD_DIR:-$(sudo -u "$RUN_AS_USER" printenv HOME)/Music/Liked Songs}"
TEMP_DIR="${CUSTOM_TEMP_DIR:-$(sudo -u "$RUN_AS_USER" printenv HOME)/Music/temp_downloads}"

# Path to the separate post-processor script for renaming.
# This assumes yt-dlp-rename-postprocessor.sh is in the SAME directory as this script.
# Ensure this script is executable (+x) permission.
POST_PROCESSOR_SCRIPT="$SCRIPT_DIR/yt-dlp-rename-postprocessor.sh"

# Path to yt-dlp binary (if overridden in .env, otherwise defaults to /usr/local/bin/yt-dlp)
YT_DLP_CMD_TO_USE="${YT_DLP_BINARY_PATH:-/usr/local/bin/yt-dlp}"

# Reverse playlist order for downloading (true/false)
REVERSE_PLAYLIST_ORDER="${REVERSE_PLAYLIST_ORDER:-false}"


# --- Logging Function ---
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# --- Pre-flight Checks (Early checks for critical directories needed for logging) ---

# Ensure the config subdirectory exists and is writable by RUN_AS_USER
# This is derived from SCRIPT_DIR, so it's always relative to the script's location.
CONFIG_SUBDIR_PARENT=$(dirname "$ARCHIVE_FILE") # Get the parent dir of archive file, which is the config dir
if ! sudo -u "$RUN_AS_USER" mkdir -p "$CONFIG_SUBDIR_PARENT"; then
    echo "CRITICAL ERROR: Could not create config directory $CONFIG_SUBDIR_PARENT as user $RUN_AS_USER. Check permissions."
    exit 1
fi
if ! sudo -u "$RUN_AS_USER" test -w "$CONFIG_SUBDIR_PARENT" ; then
    echo "CRITICAL ERROR: User "$RUN_AS_USER" does not have write permissions to $CONFIG_SUBDIR_PARENT. Please adjust ownership/permissions."
    exit 1
fi

# Ensure the logs subdirectory within config exists and is writable
LOGS_SUBDIR="$(dirname "$LOG_FILE")"
if ! sudo -u "$RUN_AS_USER" mkdir -p "$LOGS_SUBDIR"; then
    echo "CRITICAL ERROR: Could not create logs directory $LOGS_SUBDIR as user $RUN_AS_USER. Check permissions."
    exit 1
fi
if ! sudo -u "$RUN_AS_USER" test -w "$LOGS_SUBDIR" ; then
    echo "CRITICAL ERROR: User "$RUN_AS_USER" does not have write permissions to $LOGS_SUBDIR. Please adjust ownership/permissions."
    exit 1
fi

# Now that log directories are confirmed, start logging.
log_message "Starting YouTube Music playlist sync..."
log_message "Running sync as user: $RUN_AS_USER"

# --- Get Playlist URL ---
# Check if PLAYLIST_URL is defined in the .env file. If not, prompt the user.
if [ -z "$PLAYLIST_URL" ]; then
    log_message "Playlist URL not found in config. Prompting for input."
    echo "---"
    read -p "Enter YouTube Music playlist URL or ID: " PLAYLIST_URL
    echo "---"
else
    log_message "Using Playlist URL from config file."
fi

# Validate PLAYLIST_URL after getting it from config or prompt
if [ -z "$PLAYLIST_URL" ]; then
    log_message "ERROR: Playlist URL or ID cannot be empty. Exiting."
    exit 1
fi

# Removed the 'command -v' check for yt-dlp as it was causing false negatives.
# The script will now directly attempt to execute YT_DLP_CMD_TO_USE.
# If it fails, yt-dlp's own error message will be captured and logged.

# Check if cookies file exists and is readable by RUN_AS_USER
if [ ! -f "$COOKIES_FILE" ]; then
    log_message "ERROR: Cookies file not found at $COOKIES_FILE. Please create it and ensure correct path."
    exit 1
fi
# Note: Further cookie readability check is done via sudo -u, which will fail if permissions are wrong.

# Check if download directory exists and is writable by RUN_AS_USER
if [ ! -d "$DOWNLOAD_DIR" ]; then
    log_message "ERROR: Download directory not found at $DOWNLOAD_DIR. Creating it..."
    if ! sudo -u "$RUN_AS_USER" mkdir -p "$DOWNLOAD_DIR"; then
        log_message "CRITICAL ERROR: Could not create download directory $DOWNLOAD_DIR as user $RUN_AS_USER. Check permissions."
        exit 1
    fi
    log_message "Download directory $DOWNLOAD_DIR created."
fi
if ! sudo -u "$RUN_AS_USER" test -w "$DOWNLOAD_DIR" ; then
    log_message "CRITICAL ERROR: User "$RUN_AS_USER" does not have write permissions to $DOWNLOAD_DIR. Please adjust ownership/permissions."
    exit 1
fi

# Check if temporary directory exists and is writable by RUN_AS_USER (since it's explicitly used)
if [ -n "$TEMP_DIR" ]; then # Only check if TEMP_DIR is defined
    if [ ! -d "$TEMP_DIR" ]; then
        log_message "INFO: Temporary download directory not found at $TEMP_DIR. Creating it..."
        if ! sudo -u "$RUN_AS_USER" mkdir -p "$TEMP_DIR"; then
            log_message "CRITICAL ERROR: Could not create temporary download directory $TEMP_DIR as user $RUN_AS_USER. Check permissions."
            exit 1
        fi
        log_message "Temporary download directory $TEMP_DIR created."
    fi
    if ! sudo -u "$RUN_AS_USER" test -w "$TEMP_DIR" ; then
        log_message "CRITICAL ERROR: User "$RUN_AS_USER" does not have write permissions to $TEMP_DIR. Please adjust ownership/permissions."
        exit 1
    fi
fi

# Check if archive file's directory exists and is writable by RUN_AS_USER
# The archive file is in the config directory, so this check is mostly redundant if CONFIG_SUBDIR_PARENT is good
ARCHIVE_DIR_PARENT=$(dirname "$ARCHIVE_FILE")
# Only perform mkdir/test -w if parent dir has not been created by CONFIG_SUBDIR_PARENT check.
# The CONFIG_SUBDIR_PARENT check already covers this. Re-checking only if ARCHIVE_DIR_PARENT is different.
if [[ "$ARCHIVE_DIR_PARENT" != "$CONFIG_SUBDIR_PARENT" ]]; then
    if ! sudo -u "$RUN_AS_USER" mkdir -p "$ARCHIVE_DIR_PARENT"; then
        log_message "CRITICAL ERROR: Could not create archive directory parent $ARCHIVE_DIR_PARENT as user "$RUN_AS_USER". Check permissions."
        exit 1
    fi
    if ! sudo -u "$RUN_AS_USER" test -w "$ARCHIVE_DIR_PARENT" ; then
        log_message "CRITICAL ERROR: User "$RUN_AS_USER" does not have write permissions to "$ARCHIVE_DIR_PARENT". Please adjust ownership/permissions."
        exit 1
    fi
fi

# Check if the post-processor script exists and is executable
if [ ! -x "$POST_PROCESSOR_SCRIPT" ]; then
    log_message "CRITICAL ERROR: Post-processor script not found or not executable at $POST_PROCESSOR_SCRIPT. Please create it and set +x permissions."
    exit 1
fi

# --- Get current video IDs in the playlist ---
log_message "Attempting to retrieve current video IDs from playlist: $PLAYLIST_URL"
# Use --flat-playlist for speed and --print to get only IDs
# Capture stderr into stdout (2>&1) for better error reporting in the variable
PLAYLIST_VIDEO_IDS_RAW=$(sudo -u "$RUN_AS_USER" "$YT_DLP_CMD_TO_USE" \
    --flat-playlist \
    --skip-download \
    --print "%(id)s" \
    --cookies "$COOKIES_FILE" \
    "$PLAYLIST_URL" 2>&1)

# Check if the command succeeded
if [ $? -ne 0 ]; then
    log_message "ERROR: Failed to get video IDs from yt-dlp. This might indicate expired cookies, IP blocking, or other authentication/network issues."
    log_message "yt-dlp output (raw): $PLAYLIST_VIDEO_IDS_RAW"
    log_message "Please check your cookies, internet connection, and the PLAYLIST_URL."
    exit 1
fi

# Filter out potential warning/error messages from yt-dlp output, keeping only valid IDs
PLAYLIST_VIDEO_IDS=$(echo "$PLAYLIST_VIDEO_IDS_RAW" | grep -E '^[a-zA-Z0-9_-]{11}$')
NUM_PLAYLIST_VIDEOS=$(echo "$PLAYLIST_VIDEO_IDS" | wc -l)
log_message "Successfully retrieved $NUM_PLAYLIST_VIDEOS video IDs from the playlist."

if [ "$NUM_PLAYLIST_VIDEOS" -eq 0 ]; then
    log_message "WARNING: No video IDs were found in the playlist. This might mean the playlist is empty, or there's a problem fetching its contents."
    exit 0 # Exit gracefully if playlist is empty or fetch failed to yield IDs
fi

# --- Get IDs of already downloaded files ---
log_message "Checking for already downloaded files in: $DOWNLOAD_DIR"
# Assuming files are named like 'Artist - Title [VideoID].mp3'
# This requires yt-dlp to output the video ID in the filename.

# Find existing files and extract IDs
# This regex matches the pattern [ID].ext at the end of filenames
DOWNLOADED_VIDEO_IDS=$(sudo -u "$RUN_AS_USER" find "$DOWNLOAD_DIR" -type f -name '*.[mMpP][34aAcC]*' -print0 | \
    xargs -0 -r -n 1 basename | \
    grep -oP '\[([a-zA-Z0-9_-]{11})\]\.(mp3|m4a|aac|opus|flac)$' | \
    grep -oP '[a-zA-Z0-9_-]{11}') # Extract just the ID

NUM_DOWNLOADED_VIDEOS=$(echo "$DOWNLOADED_VIDEO_IDS" | wc -l)
log_message "Found $NUM_DOWNLOADED_VIDEOS already downloaded videos."

# --- Determine videos to download ---
# Now simply pass ALL playlist IDs to yt-dlp; it will use the archive to skip existing ones.
# The `VIDEOS_TO_DOWNLOAD` list is no longer created by comparing against local files.
VIDEOS_TO_DOWNLOAD="$PLAYLIST_VIDEO_IDS"

# Reverse playlist order if configured
if [[ "$REVERSE_PLAYLIST_ORDER" == "true" ]]; then
    log_message "Reversing playlist order for download."
    VIDEOS_TO_DOWNLOAD=$(echo "$VIDEOS_TO_DOWNLOAD" | tac) # Use 'tac' to reverse lines
fi

NUM_TO_DOWNLOAD=$(echo "$VIDEOS_TO_DOWNLOAD" | wc -l)
if [ -z "$VIDEOS_TO_DOWNLOAD" ]; then # check if variable is empty
    NUM_TO_DOWNLOAD=0
fi

log_message "Found $NUM_TO_DOWNLOAD videos to process (new or already archived)."

if [ "$NUM_TO_DOWNLOAD" -eq 0 ]; then
    log_message "No new videos to download. Playlist is already synced."
else
    log_message "Initiating download for new videos..."
    # Construct the download command using the identified IDs
    # yt-dlp can take multiple URLs/IDs as arguments

    # Convert the list of IDs into space-separated string for yt-dlp
    DOWNLOAD_LIST_ARG=$(echo "$VIDEOS_TO_DOWNLOAD" | xargs)

    if [ -n "$DOWNLOAD_LIST_ARG" ]; then
        log_message "Running yt-dlp download command for new videos..."
        # Add '--' to explicitly mark subsequent arguments as URLs, not options
        DOWNLOAD_OUTPUT=$(sudo -u "$RUN_AS_USER" "$YT_DLP_CMD_TO_USE" \
            -x \
            --audio-format mp3 \
            --audio-quality 0 \
            --output "%(artist)s - %(title)s [%(id)s].%(ext)s" \
            --add-metadata \
            --embed-thumbnail \
            --no-mtime \
            --no-continue \
            --no-part \
            --ignore-errors \
            --download-archive "$ARCHIVE_FILE" \
            --playlist-reverse \
            --cookies "$COOKIES_FILE" \
            --paths "home:$DOWNLOAD_DIR" \
            --paths "temp:$TEMP_DIR" \
            --exec "$POST_PROCESSOR_SCRIPT {}" \
            -- $DOWNLOAD_LIST_ARG 2>&1) # Removed quotes around $DOWNLOAD_LIST_ARG for proper word splitting

        if [ $? -ne 0 ]; then
            log_message "ERROR: yt-dlp download command failed. See output for details."
            log_message "yt-dlp output (raw): $DOWNLOAD_OUTPUT"
            log_message "Partial success may have occurred. Check $DOWNLOAD_DIR."
        else
            log_message "Download completed successfully for new videos."
            log_message "yt-dlp download output: $DOWNLOAD_OUTPUT"
        fi
    else
        log_message "No videos in the generated download list. This should not happen if NUM_TO_DOWNLOAD > 0."
    fi
fi

# --- Identify and remove deleted/removed videos from local storage ---
log_message "Checking for locally downloaded videos no longer in the playlist..."

# Find IDs that are in the downloaded list but not in the playlist
VIDEOS_TO_DELETE=$(comm -13 <(printf "%s\n" "${playlist_array[@]}" | sort -u) <(printf "%s\n" "${downloaded_array[@]}" | sort -u))

NUM_TO_DELETE=$(echo "$VIDEOS_TO_DELETE" | wc -l)
if [ -z "$VIDEOS_TO_DELETE" ]; then # check if variable is empty
    NUM_TO_DELETE=0
fi

if [ "$NUM_TO_DELETE" -gt 0 ]; then
    log_message "Found $NUM_TO_DELETE videos to remove from local storage (no longer in playlist)."
    for video_id in $VIDEOS_TO_DELETE; do
        # Find files matching the ID pattern and remove them
        log_message "Removing: $video_id"
        # Use find with -delete for safety, and limit scope to DOWNLOAD_DIR
        sudo -u "$RUN_AS_USER" find "$DOWNLOAD_DIR" -type f -name "*[$video_id].*" -delete
        if [ $? -ne 0 ]; then
            log_message "WARNING: Failed to remove file(s) for ID $video_id. Check permissions."
        fi
    done
    log_message "Cleanup of removed videos complete."
else
    log_message "No videos to remove from local storage."
fi

log_message "YouTube Music playlist sync complete."
exit 0
