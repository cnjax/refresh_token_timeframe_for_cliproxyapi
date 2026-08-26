import os
import sys
import time
import requests
import atexit
import signal

# Configuration
MANAGEMENT_KEY = os.environ.get("MANAGEMENT_KEY", "TEST_MANAGEMENT_KEY")
API_KEY = os.environ.get("API_KEY", "sk-TEST_API_KEY")
BASE_URL = os.environ.get("BASE_URL", "https://your-proxy-domain.com")

AUTH_FILES_ENDPOINT = f"{BASE_URL}/v0/management/auth-files"
STATUS_ENDPOINT = f"{BASE_URL}/v0/management/auth-files/status"
CHAT_ENDPOINT = f"{BASE_URL}/v1/chat/completions"

HEADERS_MGMT = {
    "Authorization": f"Bearer {MANAGEMENT_KEY}",
    "Content-Type": "application/json"
}

HEADERS_API = {
    "Authorization": f"Bearer {API_KEY}",
    "Content-Type": "application/json"
}

# List to keep track of files that need to be re-enabled
active_files_to_restore = []

# Disable warnings for unverified HTTPS requests to mimic 'curl -k'
import urllib3
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

def restore_state():
    """Cleanup function to restore the original active states of auth files."""
    if not active_files_to_restore:
        return
    print("\nRestoring original active states...")
    for name in active_files_to_restore:
        try:
            requests.patch(
                STATUS_ENDPOINT, 
                headers=HEADERS_MGMT, 
                json={"name": name, "disabled": False}, 
                verify=False
            )
        except Exception as e:
            print(f"Failed to restore {name}: {e}")
    active_files_to_restore.clear()
    print("Restoration complete.")

# Register cleanup handlers to ensure state is restored even if script exits/crashes
atexit.register(restore_state)

def signal_handler(sig, frame):
    sys.exit(0)  # This will trigger atexit automatically

signal.signal(signal.SIGINT, signal_handler)
signal.signal(signal.SIGTERM, signal_handler)

def set_disabled_status(name, disabled):
    """Helper to set the disabled status of an auth file via the Management API."""
    try:
        resp = requests.patch(
            STATUS_ENDPOINT, 
            headers=HEADERS_MGMT, 
            json={"name": name, "disabled": disabled}, 
            verify=False
        )
        resp.raise_for_status()
        return True
    except Exception as e:
        print(f"Failed to set disabled={disabled} for {name}: {e}")
        return False

def main():
    print("Fetching current auth files from proxy...")
    try:
        resp = requests.get(AUTH_FILES_ENDPOINT, headers=HEADERS_MGMT, verify=False)
        resp.raise_for_status()
        auth_files_data = resp.json()
    except Exception as e:
        print(f"Error fetching auth files: {e}")
        sys.exit(1)

    files = auth_files_data.get("files", [])
    if not files:
        print("Error: Received empty files list from server.")
        sys.exit(1)

    # Find all originally active (not disabled) files
    active_files = [f for f in files if not f.get("disabled", False)]
    
    if not active_files:
        print("No active auth files found to process.")
        sys.exit(0)

    print(f"Found {len(active_files)} active auth files. Disabling them temporarily...")

    # Disable all active ones
    for f in active_files:
        name = f["name"]
        active_files_to_restore.append(name)
        set_disabled_status(name, True)

    print("All active files disabled. Starting rotation loop via /v1/chat/completions...\n")

    for f in active_files:
        name = f["name"]
        provider = f.get("provider", "unknown")

        print("-" * 40)
        print(f"Processing: {name} ({provider})")

        # 1. Enable just this one credential
        set_disabled_status(name, False)
        
        # Wait a moment for the proxy to update its internal routing state
        time.sleep(1)

        # 2. Determine the model to use based on provider
        model = "gpt-5.6-luna" # default fallback
        if provider == "codex":
            model = "gpt-5.6-luna"
        elif provider == "claude":
            model = "claude-sonnet-4-6"
        elif provider in ("gemini-cli", "gemini", "antigravity"):
            model = "gemini-3.5-flash"

        print(f"Sending /v1/chat/completions request with model: {model}")

        payload = {
            "model": model,
            "messages": [{"role": "user", "content": "ping"}],
            "max_tokens": 1
        }

        try:
            chat_resp = requests.post(CHAT_ENDPOINT, headers=HEADERS_API, json=payload, verify=False)
            chat_data = chat_resp.json()
            
            # Check for error in JSON
            error_msg = chat_data.get("error", {}).get("message")
            if error_msg:
                print(f"Failed: {error_msg}")
            else:
                # Extract the content from the successful response
                choices = chat_data.get("choices", [])
                if choices:
                    content = choices[0].get("message", {}).get("content")
                    print(f"Success! AI Response: {content}")
                else:
                    print(f"Response: {chat_resp.text}")
        except Exception as e:
            print(f"Chat request failed: {e}")

        # 3. Disable it again before moving to the next
        set_disabled_status(name, True)

        # Wait to avoid rate limits
        time.sleep(2)

if __name__ == "__main__":
    main()
