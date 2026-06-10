# Trigger Token Management

This directory contains scripts for rotating and refreshing authentication tokens by triggering `/v1/chat/completions` requests across all active credentials.

## Scripts

### `refresh_via_v1.sh` (Shell Version)

This script automates the process of validating and refreshing auth files.

### `refresh_via_v1.py` (Python Version)

A Python implementation of the same logic, offering better error handling and cross-platform compatibility.

## How it Works

1. Fetches all currently active auth files from the cliproxyapi.
2. Disables them temporarily.
3. Iterates through each one, enabling it, sending a "ping" request to `/v1/chat/completions`, and then disabling it again.
4. Restores the original active state of all files upon completion or interruption.

#### Configuration

The scripts use environment variables with defaults:

- `MANAGEMENT_KEY`: The secret key for the Management API (default: `TEST_MANAGEMENT_KEY`).
- `API_KEY`: A valid API key for the cliproxyapi (default: `sk-TEST_API_KEY`).
- `BASE_URL`: The base URL of the cliproxyapi (default: `http://127.0.0.1:8317`).

#### Usage

**Shell:**
```bash
chmod +x refresh_via_v1.sh
./refresh_via_v1.sh
```

**Python:**
```bash
python3 refresh_via_v1.py
```

To override configuration:
```bash
MANAGEMENT_KEY="your-secret" BASE_URL="https://proxy.example.com" ./refresh_via_v1.sh
```

## Scheduled Tasks (Crontab)

To run the refresh automatically (e.g., at 7:00 AM and 12:00 PM every day), add the following to your crontab (`crontab -e`):

```cron
0 7,12 * * * /bin/bash /path/to/cliproxyapi/triggertoken/refresh_via_v1.sh >> /path/to/cliproxyapi/triggertoken/refresh.log 2>&1
```

## Requirements

- `curl`
- `jq` (for Shell version)
- `python3` & `requests` library (for Python version)

