# YouTube Music Playlist Sync Script

This repository contains a set of Bash scripts designed to automatically synchronize a YouTube Music playlist to local storage, downloading audio files and managing their filenames and metadata.

## Features

* **Playlist Synchronization:** Keeps your local music library in sync with a specified YouTube Music playlist.
* **Audio Extraction:** Downloads videos as high-quality MP3 audio files.
* **Metadata Embedding:** Embeds track title, artist, album art (thumbnail), and other relevant metadata into the MP3 files.
* **Persistent Archive:** Uses a download archive to prevent re-downloading or re-processing already handled tracks, saving bandwidth and time.
* **Temporary Download Directory:** Utilizes a separate temporary directory for downloads before moving final files, useful for managing storage on different drives.
* **Smart Filenaming:** Automatically names files as `Artist - Title [VideoID].mp3`.
* **"NA" Artist Handling:** If the artist metadata is "NA" (or empty), the script automatically removes the "NA - " prefix from the filename for cleaner organization.
* **Cleanup:** Identifies and removes local files that are no longer present in the source playlist.
* **Robust Logging:** Provides detailed logs for monitoring sync operations and troubleshooting.

## Prerequisites

Before you begin, ensure you have the following installed on your Linux system (e.g., DietPi):

* **`yt-dlp`**: The primary tool for downloading and processing YouTube content.

    ```bash
    sudo apt update
    sudo apt install yt-dlp
    # Ensure it's updated to the latest version
    sudo yt-dlp -U
    ```

* **`ffmpeg`**: Required by `yt-dlp` for audio extraction, format conversion, and embedding metadata/thumbnails.

    ```bash
    sudo apt install ffmpeg
    ```

## Setup

Follow these steps to set up the synchronization script:

### 1. Clone the Repository

Start by cloning this repository to your desired location on your Linux system (e.g., in your home directory):

```bash
git clone [https://github.com/Sunrizd/yt-dlp-sync.git](https://github.com/Sunrizd/yt-dlp-sync.git)
cd yt-dlp-sync
```

### 2. Create Configuration Directory and .env File
The scripts uses a .env file for all configuration.

Create the .env file from the example:
```bash
cp config/.env.example config/.env
```
Edit config/.env: Open config/.env in a text editor and fill in your specific values for RUN_AS_USER, and optionally override any default paths.

Example config/.env (after editing):
```bash
RUN_AS_USER="user"
REVERSE_PLAYLIST_ORDER="false" # Set to "true" to download from last added to first
# CUSTOM_DOWNLOAD_DIR="/mnt/my_external_drive/Music/MySyncedPlaylist"
# CUSTOM_TEMP_DIR="/var/tmp/yt-dlp_temp"
# CUSTOM_COOKIES_FILE="/home/dietpi/.config/yt-dlp/cookies.txt"

```

### 3. Create cookies.txt
yt-dlp needs your YouTube/YouTube Music cookies to access private playlists, bypass age restrictions, or avoid bot detection.

Method: Use a browser extension like Get cookies.txt (for Chrome) or Cookies.txt (for Firefox) to export your cookies.

Location: Place the cookies.txt file in the config directory within your cloned repository (e.g., yt-dlp-sync/config/cookies.txt). This is the default path used by the scripts. If you set CUSTOM_COOKIES_FILE in .env, place it there instead.

Permissions: Ensure the RUN_AS_USER has read access to this file:
```bash
sudo chown RUN_AS_USER:RUN_AS_USER config/cookies.txt
sudo chmod 600 config/cookies.txt
```
(Replace RUN_AS_USER with your actual username).

### 4. Set Permissions for Data Directories
The script will attempt to create these directories if they don't exist, but you might need to manually adjust ownership for external drives. Ensure the RUN_AS_USER has appropriate permissions for the download and temporary directories.
```bash
# Example if using default paths (within RUN_AS_USER's home)
sudo mkdir -p /home/your_linux_username/Music
sudo mkdir -p /home/your_linux_username/Music/temp_downloads
sudo chown -R your_linux_username:your_linux_username /home/your_linux_username/Music
```
```bash
# Example if using custom paths (adjust as per your .env configuration)
# sudo mkdir -p /mnt/your_external_drive/Music/MySyncedPlaylist
# sudo mkdir -p /var/tmp/yt-dlp_temp
# sudo chown -R your_linux_username:your_linux_username /mnt/your_external_drive/Music/MySyncedPlaylist
# sudo chown -R your_linux_username:your_linux_username /var/tmp/yt-dlp_temp
```
(Replace your_linux_username with the actual username you set for RUN_AS_USER in config/.env).

### 5. Make Scripts Executable
Make both scripts executable:
```bash
chmod +x yt-dlp-sync.sh
chmod +x yt-dlp-rename-postprocessor.sh
```
Usage
To run the synchronization:
```bash
./yt-dlp-sync.sh
```
You can also set up a cron job to run this script automatically at regular intervals (e.g., daily):
```bash
# Open cron editor for root user
sudo crontab -e

# Add a line to run the script daily at 3:00 AM
# 0 3 * * * /path/to/your/cloned/repo/yt-dlp-sync.sh >> /path/to/your/cloned/repo/config/yt-dlp-sync.log 2>&1
```
Important Note for Cron Jobs: When running scripts via cron, the PATH environment variable is often very limited (e.g., /usr/bin:/bin). If yt-dlp is installed in a directory not typically included in cron's default PATH (like /usr/local/bin), the script might fail with a "command not found" error for yt-dlp. You may need to explicitly set the PATH within your cron job or at the beginning of your script if yt-dlp is not found. For example: PATH=/usr/local/bin:$PATH /path/to/your/cloned/repo/yt-dlp-sync.sh.

Project Structure
```

.
├── config/
│   ├── .env.example
│   ├── cookies.txt
├── yt-dlp-sync.sh
└── yt-dlp-rename-postprocessor.sh
```
