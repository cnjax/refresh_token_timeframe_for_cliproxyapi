#!/bin/bash

# Configuration
MANAGEMENT_KEY="${MANAGEMENT_KEY:-TEST_MANAGEMENT_KEY}"
API_KEY="${API_KEY:-sk-TEST_API_KEY}"
BASE_URL="${BASE_URL:-http://127.0.0.1:8317}"

AUTH_FILES_ENDPOINT="${BASE_URL}/v0/management/auth-files"
STATUS_ENDPOINT="${BASE_URL}/v0/management/auth-files/status"
CHAT_ENDPOINT="${BASE_URL}/v1/chat/completions"

# Check dependencies
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed."
    exit 1
fi

ACTIVE_LIST=$(mktemp)
TMP_LIST=$(mktemp)

# Cleanup function to restore state
restore_state() {
    echo ""
    echo "Restoring original active states..."
    if [[ -s "$ACTIVE_LIST" ]]; then
        while read -r name; do
            if [[ -n "$name" ]]; then
                curl -s -k -X PATCH "$STATUS_ENDPOINT" \
                    -H "Authorization: Bearer $MANAGEMENT_KEY" \
                    -H "Content-Type: application/json" \
                    -d "{\"name\":\"$name\",\"disabled\":false}" > /dev/null
            fi
        done < "$ACTIVE_LIST"
    fi
    rm -f "$ACTIVE_LIST" "$TMP_LIST"
    echo "Restoration complete."
}

# Trap signals to ensure we always restore state even if Ctrl+C is pressed
trap restore_state EXIT INT TERM

echo "Fetching current auth files from proxy..."
auth_files=$(curl -s -k -G "$AUTH_FILES_ENDPOINT" \
    -H "Authorization: Bearer $MANAGEMENT_KEY" \
    -H "Content-Type: application/json")

if [[ -z "$auth_files" || "$auth_files" == "null" ]]; then
    echo "Error: Received empty response from server."
    exit 1
fi

# Find all originally active (not disabled) files and save name|provider
echo "$auth_files" | jq -r '.files[] | select(.disabled != true) | "\(.name)|\(.provider)"' > "$TMP_LIST"

count=$(wc -l < "$TMP_LIST" | tr -d ' ')
if [[ "$count" -eq 0 ]]; then
    echo "No active auth files found to process."
    exit 0
fi

echo "Found $count active auth files. Disabling them temporarily..."

# Only save the names to ACTIVE_LIST for restoration
cut -d'|' -f1 "$TMP_LIST" > "$ACTIVE_LIST"

# Disable all active ones
while read -r line; do
    name=$(echo "$line" | cut -d'|' -f1)
    curl -s -k -X PATCH "$STATUS_ENDPOINT" \
        -H "Authorization: Bearer $MANAGEMENT_KEY" \
        -H "Content-Type: application/json" \
        -d "{\"name\":\"$name\",\"disabled\":true}" > /dev/null
done < "$TMP_LIST"

echo "All active files disabled. Starting rotation loop via /v1/chat/completions..."

while read -r line; do
    name=$(echo "$line" | cut -d'|' -f1)
    provider=$(echo "$line" | cut -d'|' -f2)
    
    echo "----------------------------------------"
    echo "Processing: $name ($provider)"
    
    # 1. Enable just this one credential
    curl -s -k -X PATCH "$STATUS_ENDPOINT" \
        -H "Authorization: Bearer $MANAGEMENT_KEY" \
        -H "Content-Type: application/json" \
        -d "{\"name\":\"$name\",\"disabled\":false}" > /dev/null
        
    # Wait a moment for the proxy to update its internal routing state
    sleep 1
    
    # 2. Determine the model to use based on provider
    model="gpt-5.4-mini" # default fallback
    case "$provider" in
        "codex")
            model="gpt-5.4-mini"
            ;;
        "claude")
            model="claude-sonnet-4-6"
            ;;
        "gemini-cli"|"gemini"|"antigravity")
            model="gemini-3.5-flash"
            ;;
    esac
    
    echo "Sending /v1/chat/completions request with model: $model"
    
    payload=$(jq -n \
        --arg model "$model" \
        '{
            model: $model,
            messages: [{ role: "user", content: "ping" }],
            max_tokens: 1
        }')
        
    response=$(curl -s -k -X POST "$CHAT_ENDPOINT" \
        -H "Authorization: Bearer $API_KEY" \
        -H "Content-Type: application/json" \
        -d "$payload")
        
    # Check for error in JSON
    error_msg=$(echo "$response" | jq -r '.error.message // empty')
    if [[ -n "$error_msg" ]]; then
        echo "Failed: $error_msg"
    else
        # Extract the content from the successful response
        content=$(echo "$response" | jq -r '.choices[0].message.content // empty')
        if [[ -n "$content" ]]; then
            echo "Success! AI Response: $content"
        else
            echo "Response: $response"
        fi
    fi
    
    # 3. Disable it again before moving to the next
    curl -s -k -X PATCH "$STATUS_ENDPOINT" \
        -H "Authorization: Bearer $MANAGEMENT_KEY" \
        -H "Content-Type: application/json" \
        -d "{\"name\":\"$name\",\"disabled\":true}" > /dev/null
        
    # Wait to avoid rate limits
    sleep 2
done < "$TMP_LIST"

# The trap will run restore_state() automatically upon exit
