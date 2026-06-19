#!/usr/bin/env bash
# run_agent.sh - Execute agentic coding task on target repo
# Priority: Stock OpenCode (efficient) → OMO (autonomous) → Direct LLM API
set -euo pipefail

PACKET_FILE="${1:?Usage: run_agent.sh <packet.json> <target-root>}"
TARGET_ROOT="${2:?Usage: run_agent.sh <packet.json> <target-root>}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Extract task details from packet
read -r TARGET_REPO TASK_TEXT MODE < <(python3 - <<'PY' "$PACKET_FILE"
import json, sys
from pathlib import Path
packet = json.loads(Path(sys.argv[1]).read_text())
repo = packet.get('target_repo', packet.get('repo', ''))
task = packet.get('task', packet.get('task_summary', 'implement the project'))
mode = packet.get('mode', 'implement')
print(f"{repo}\t{task[:500]}\t{mode}")
PY
)

echo "=== Runner Agent ==="
echo "Repo: $TARGET_REPO"
echo "Task: ${TASK_TEXT:0:100}..."
echo "Mode: $MODE"

cd "$TARGET_ROOT"

# Write task file for reference
cat > .runner-task.md << EOF
# Agentic Coding Task

**Repository:** $TARGET_REPO
**Mode:** $MODE

## Task Description

$TASK_TEXT

## Instructions

Implement this project following these principles:
1. Use simple, maintainable code
2. Add appropriate error handling
3. Include basic tests if applicable
4. Update README.md with usage instructions
EOF

AGENT_SUCCESS=false

# =============================================================================
# OPTION 1: Stock OpenCode (most token-efficient)
# =============================================================================
if command -v opencode &>/dev/null; then
    echo ">>> Trying stock OpenCode (efficient mode)..."
    
    # Copy runner config if not exists
    if [ -f "$SCRIPT_DIR/opencode-runner.json" ]; then
        cp "$SCRIPT_DIR/opencode-runner.json" .opencode.json
    fi
    
    # Set API keys from environment
    export OPENCODE_PROVIDER_VPS_GATEWAY_API_KEY="${PROXY_API_KEY:-GATEWAY_KEY_REDACTED}"
    export OPENCODE_PROVIDER_GROQ_FALLBACK_API_KEY="${GROQ_API_KEY:-}"
    
    # Run OpenCode with task piped in, fully autonomous
    # --dangerously-skip-permissions ensures no prompts
    if timeout 3600 bash -c "echo '$TASK_TEXT' | opencode --dangerously-skip-permissions 2>&1" | tee .runner-log.txt; then
        echo ">>> OpenCode completed successfully"
        AGENT_SUCCESS=true
    else
        echo ">>> OpenCode failed or timed out, trying fallback..."
    fi
fi

# =============================================================================
# OPTION 2: oh-my-opencode (more autonomous, higher token usage)
# =============================================================================
if [ "$AGENT_SUCCESS" = false ]; then
    if command -v omo &>/dev/null || command -v bunx &>/dev/null; then
        echo ">>> Trying oh-my-opencode (autonomous mode)..."
        
        # Install omo if not present
        if ! command -v omo &>/dev/null; then
            bunx oh-my-opencode install --no-tui --claude=no --openai=no --gemini=no --opencode-go=no 2>/dev/null || true
        fi
        
        # Run omo with the task
        if command -v omo &>/dev/null; then
            if timeout 3600 omo --task "$TASK_TEXT" --auto-approve 2>&1 | tee -a .runner-log.txt; then
                echo ">>> OMO completed successfully"
                AGENT_SUCCESS=true
            fi
        fi
    fi
fi

# =============================================================================
# OPTION 3: Direct LLM API (fallback for simple code generation)
# =============================================================================
if [ "$AGENT_SUCCESS" = false ]; then
    # Only use direct API if no code files exist yet
    if [ ! -f "src/main.py" ] && [ ! -f "index.js" ] && [ ! -f "main.go" ] && [ ! -f "main.rs" ]; then
        echo ">>> Generating initial project structure via direct LLM API..."
        
        python3 << 'PYGEN' "$TASK_TEXT" "$TARGET_ROOT"
import json, os, sys
import urllib.request

task = sys.argv[1]
root = sys.argv[2]

prompt = f"""Create a simple implementation for this project idea:

{task}

Respond with ONLY a JSON object containing files to create:
{{"files": [{{"path": "src/main.py", "content": "..."}}]}}

Keep it simple and functional. Include a README.md with usage instructions."""

# Try VPS gateway first (VPS_IP_REDACTED:8000)
endpoints = [
    ("http://VPS_IP_REDACTED:8000/v1/chat/completions", os.environ.get("PROXY_API_KEY", "GATEWAY_KEY_REDACTED"), "coding-elite"),
    ("https://api.groq.com/openai/v1/chat/completions", os.environ.get("GROQ_API_KEY", ""), "llama-3.3-70b-versatile"),
]

result = None
for url, api_key, model in endpoints:
    if not api_key:
        continue
    try:
        headers = {
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json"
        }
        data = json.dumps({
            "model": model,
            "messages": [{"role": "user", "content": prompt}],
            "max_tokens": 4000,
            "temperature": 0.3
        }).encode()
        
        req = urllib.request.Request(url, data, headers)
        resp = urllib.request.urlopen(req, timeout=120)
        result = json.loads(resp.read())
        print(f"Using: {url} ({model})")
        break
    except Exception as e:
        print(f"Endpoint {url} failed: {e}")
        continue

if result:
    content = result["choices"][0]["message"]["content"]
    
    # Extract JSON from response
    import re
    match = re.search(r'\{[\s\S]*"files"[\s\S]*\}', content)
    if match:
        files_data = json.loads(match.group())
        for f in files_data.get("files", []):
            path = os.path.join(root, f["path"])
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "w") as fp:
                fp.write(f["content"])
            print(f"Created: {f['path']}")
else:
    print("All LLM endpoints failed")
PYGEN
    fi
fi

# Ensure README exists
if [ ! -f README.md ]; then
    cat > README.md << EOF
# $(basename "$TARGET_REPO")

$TASK_TEXT

## Setup

\`\`\`bash
# Install dependencies (if any)
pip install -r requirements.txt  # or npm install
\`\`\`

## Usage

See source files for implementation details.

---
*Generated by autonomous coding agent*
EOF
fi

echo "=== Agent run complete ==="
ls -la
