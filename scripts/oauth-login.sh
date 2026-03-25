#!/usr/bin/env bash
# OAuth PKCE login flow for Codeflash.
# Opens browser for authentication, exchanges code for API key,
# and saves it to the user's shell RC file.
#
# Usage:
#   ./oauth-login.sh                                  # Full browser flow
#   ./oauth-login.sh --exchange-code STATE_FILE CODE   # Complete headless flow
#
# Exit codes:
#   0 = success (API key saved)
#   1 = error
#   2 = headless mode (remote URL printed to stdout, state saved to temp file)

set -euo pipefail

CFWEBAPP_BASE_URL="https://app.codeflash.ai"
TOKEN_URL="${CFWEBAPP_BASE_URL}/codeflash/auth/oauth/token"
CLIENT_ID="cf-cli-app"
TIMEOUT=180

# --- Detect if a browser can be launched (matches codeflash's should_attempt_browser_launch) ---
can_open_browser() {
  # CI/CD or non-interactive environments
  if [ -n "${CI:-}" ] || [ "${DEBIAN_FRONTEND:-}" = "noninteractive" ]; then
    return 1
  fi

  # Text-only browsers
  local browser_env="${BROWSER:-}"
  case "$browser_env" in
    www-browser|lynx|links|w3m|elinks|links2) return 1 ;;
  esac

  local is_ssh="false"
  if [ -n "${SSH_CONNECTION:-}" ]; then
    is_ssh="true"
  fi

  # Linux: require a display server
  if [ "$(uname -s)" = "Linux" ]; then
    if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ] && [ -z "${MIR_SOCKET:-}" ]; then
      return 1
    fi
  fi

  # SSH on non-Linux (e.g. macOS remote) — no browser
  if [ "$is_ssh" = "true" ] && [ "$(uname -s)" != "Linux" ]; then
    return 1
  fi

  return 0
}

# --- Save API key to shell RC (matches codeflash's shell_utils.py logic) ---
save_api_key() {
  local api_key="$1"

  if [ "${OS:-}" = "Windows_NT" ] || [[ "$(uname -s 2>/dev/null)" == MINGW* ]]; then
    # Windows: use dedicated codeflash env files (same as codeflash CLI)
    if [ -n "${PSMODULEPATH:-}" ]; then
      RC_FILE="$HOME/codeflash_env.ps1"
      EXPORT_LINE="\$env:CODEFLASH_API_KEY = \"${api_key}\""
      REMOVE_PATTERN='^\$env:CODEFLASH_API_KEY'
    else
      RC_FILE="$HOME/codeflash_env.bat"
      EXPORT_LINE="set CODEFLASH_API_KEY=\"${api_key}\""
      REMOVE_PATTERN='^set CODEFLASH_API_KEY='
    fi
  else
    # Unix: use shell RC file (same mapping as codeflash CLI)
    SHELL_NAME=$(basename "${SHELL:-/bin/bash}")
    case "$SHELL_NAME" in
      zsh)      RC_FILE="$HOME/.zshrc" ;;
      ksh)      RC_FILE="$HOME/.kshrc" ;;
      csh|tcsh) RC_FILE="$HOME/.cshrc" ;;
      dash)     RC_FILE="$HOME/.profile" ;;
      *)        RC_FILE="$HOME/.bashrc" ;;
    esac
    EXPORT_LINE="export CODEFLASH_API_KEY=\"${api_key}\""
    REMOVE_PATTERN='^export CODEFLASH_API_KEY='
  fi

  # Remove any existing CODEFLASH_API_KEY lines and append the new one
  if [ -f "$RC_FILE" ]; then
    CLEANED=$(grep -v "$REMOVE_PATTERN" "$RC_FILE" || true)
    printf '%s\n' "$CLEANED" > "$RC_FILE"
  fi
  printf '%s\n' "$EXPORT_LINE" >> "$RC_FILE"

  # Also export for the current session
  export CODEFLASH_API_KEY="$api_key"
}

# --- Exchange code for token and save ---
exchange_and_save() {
  local auth_code="$1"
  local code_verifier="$2"
  local redirect_uri="$3"

  TOKEN_RESPONSE=$(curl -s -X POST "$TOKEN_URL" \
    -H "Content-Type: application/json" \
    -d "{
      \"grant_type\": \"authorization_code\",
      \"code\": \"${auth_code}\",
      \"code_verifier\": \"${code_verifier}\",
      \"redirect_uri\": \"${redirect_uri}\",
      \"client_id\": \"${CLIENT_ID}\"
    }")

  API_KEY=$(printf '%s' "$TOKEN_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))" 2>/dev/null || true)

  if [ -z "$API_KEY" ] || [[ ! "$API_KEY" == cf-* ]]; then
    exit 1
  fi

  save_api_key "$API_KEY"
}

# ===================================================================
# Mode: --exchange-code STATE_FILE CODE
# Complete a headless flow using a previously saved PKCE state file.
# ===================================================================
if [ "${1:-}" = "--exchange-code" ]; then
  STATE_FILE="${2:-}"
  MANUAL_CODE="${3:-}"

  if [ -z "$STATE_FILE" ] || [ -z "$MANUAL_CODE" ] || [ ! -f "$STATE_FILE" ]; then
    exit 1
  fi

  # Read saved state
  CODE_VERIFIER=$(python3 -c "import json; print(json.load(open('${STATE_FILE}')).get('code_verifier',''))" 2>/dev/null || true)
  REMOTE_REDIRECT=$(python3 -c "import json; print(json.load(open('${STATE_FILE}')).get('remote_redirect_uri',''))" 2>/dev/null || true)

  rm -f "$STATE_FILE"

  if [ -z "$CODE_VERIFIER" ] || [ -z "$REMOTE_REDIRECT" ]; then
    exit 1
  fi

  exchange_and_save "$MANUAL_CODE" "$CODE_VERIFIER" "$REMOTE_REDIRECT"
  exit 0
fi

# ===================================================================
# Mode: Full OAuth flow (default)
# ===================================================================

# --- PKCE pair ---
CODE_VERIFIER=$(openssl rand -base64 48 | tr -d '=/+\n' | head -c 64)
CODE_CHALLENGE=$(printf '%s' "$CODE_VERIFIER" | openssl dgst -sha256 -binary | openssl base64 -A | tr '+/' '-_' | tr -d '=')

# --- State ---
STATE=$(openssl rand -hex 16)

# --- Find a free port ---
PORT=$(python3 -c "import socket; s=socket.socket(); s.bind(('',0)); print(s.getsockname()[1]); s.close()")

LOCAL_REDIRECT_URI="http://localhost:${PORT}/callback"
REMOTE_REDIRECT_URI="${CFWEBAPP_BASE_URL}/codeflash/auth/callback"
ENCODED_LOCAL_REDIRECT=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${LOCAL_REDIRECT_URI}'))")
ENCODED_REMOTE_REDIRECT=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${REMOTE_REDIRECT_URI}'))")

AUTH_PARAMS="response_type=code&client_id=${CLIENT_ID}&code_challenge=${CODE_CHALLENGE}&code_challenge_method=S256&state=${STATE}"
LOCAL_AUTH_URL="${CFWEBAPP_BASE_URL}/codeflash/auth?${AUTH_PARAMS}&redirect_uri=${ENCODED_LOCAL_REDIRECT}"
REMOTE_AUTH_URL="${CFWEBAPP_BASE_URL}/codeflash/auth?${AUTH_PARAMS}&redirect_uri=${ENCODED_REMOTE_REDIRECT}"

# --- Headless detection ---
if ! can_open_browser; then
  # Save PKCE state so --exchange-code can complete the flow later
  HEADLESS_STATE_FILE=$(mktemp /tmp/codeflash-oauth-state-XXXXXX.json)
  python3 -c "
import json
json.dump({
    'code_verifier': '${CODE_VERIFIER}',
    'remote_redirect_uri': '${REMOTE_REDIRECT_URI}',
    'state': '${STATE}'
}, open('${HEADLESS_STATE_FILE}', 'w'))
"
  # Output JSON for Claude to parse — this is the ONLY stdout in headless mode
  printf '{"headless":true,"url":"%s","state_file":"%s"}\n' "$REMOTE_AUTH_URL" "$HEADLESS_STATE_FILE"
  exit 2
fi

# --- Temp file for callback result ---
RESULT_FILE=$(mktemp /tmp/codeflash-oauth-XXXXXX.json)
trap 'rm -f "$RESULT_FILE"' EXIT

# --- Start local callback server with Codeflash-styled pages ---
export PORT STATE RESULT_FILE TIMEOUT
python3 - "$PORT" "$STATE" "$RESULT_FILE" << 'PYEOF' &
import http.server, urllib.parse, json, sys, threading

port = int(sys.argv[1])
state = sys.argv[2]
result_file = sys.argv[3]

STYLE = (
    ":root{"
    "--bg:hsl(0,0%,99%);--fg:hsl(222.2,84%,4.9%);--card:hsl(0,0%,100%);"
    "--card-fg:hsl(222.2,84%,4.9%);--primary:hsl(38,100%,63%);"
    "--muted-fg:hsl(41,8%,46%);--border:hsl(41,30%,90%);"
    "--destructive:hsl(0,84.2%,60.2%);--destructive-fg:#fff;"
    "--success:hsl(142,76%,36%)}"
    "html.dark{"
    "--bg:hsl(0,6%,5%);--fg:#fff;--card:hsl(0,3%,11%);"
    "--card-fg:#fff;--primary:hsl(38,100%,63%);"
    "--muted-fg:hsl(48,20%,65%);--border:hsl(48,20%,25%);"
    "--destructive:hsl(0,62.8%,30.6%)}"
    "*{margin:0;padding:0;box-sizing:border-box}"
    "body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',system-ui,sans-serif;"
    "background:var(--bg);color:var(--fg);min-height:100vh;"
    "display:flex;align-items:center;justify-content:center;padding:20px;position:relative}"
    "body::before{content:'';position:fixed;inset:0;"
    "background:linear-gradient(to bottom,hsl(38,100%,63%,.1),hsl(38,100%,63%,.05),transparent);"
    "pointer-events:none;z-index:0}"
    "body::after{content:'';position:fixed;inset:0;"
    "background-image:linear-gradient(to right,rgba(128,128,128,.03) 1px,transparent 1px),"
    "linear-gradient(to bottom,rgba(128,128,128,.03) 1px,transparent 1px);"
    "background-size:24px 24px;pointer-events:none;z-index:0}"
    ".ctr{max-width:420px;width:100%;position:relative;z-index:1}"
    ".logo-ctr{display:flex;justify-content:center;margin-bottom:48px}"
    ".logo{height:40px;width:auto}"
    ".ll{display:block}.ld{display:none}"
    "html.dark .ll{display:none}html.dark .ld{display:block}"
    ".card{background:var(--card);color:var(--card-fg);border:1px solid var(--border);"
    "border-radius:16px;box-shadow:0 10px 15px -3px rgba(0,0,0,.1),0 4px 6px -2px rgba(0,0,0,.05);"
    "padding:48px;animation:fadeIn .3s ease-out forwards}"
    "@keyframes fadeIn{from{opacity:0;transform:translateY(10px)}to{opacity:1;transform:translateY(0)}}"
    ".ic{width:48px;height:48px;background:hsl(38,100%,63%,.1);border-radius:12px;"
    "display:flex;align-items:center;justify-content:center;margin:0 auto 24px}"
    ".spinner{width:24px;height:24px;border:2px solid var(--border);"
    "border-top-color:var(--primary);border-radius:50%;animation:spin .8s linear infinite}"
    "@keyframes spin{to{transform:rotate(360deg)}}"
    ".si{width:64px;height:64px;background:hsl(142,76%,36%,.1);border-radius:12px;"
    "display:flex;align-items:center;justify-content:center;margin:0 auto 24px}"
    ".sc{width:32px;height:32px;stroke:hsl(142,76%,36%)}"
    "h1{font-size:24px;font-weight:600;margin:0 0 12px;color:var(--card-fg);text-align:center}"
    "p{color:var(--muted-fg);margin:0;font-size:14px;line-height:1.5;text-align:center}"
    ".eb{background:var(--destructive);color:var(--destructive-fg);"
    "padding:14px 18px;border-radius:8px;margin-top:24px;font-size:14px;line-height:1.5;text-align:center}"
    "@media(max-width:480px){.card{padding:32px 24px}h1{font-size:20px}.logo{height:32px}}"
)

LOGO = (
    '<div class="logo-ctr">'
    '<img src="https://app.codeflash.ai/images/codeflash_light.svg" alt="CodeFlash" class="logo ll"/>'
    '<img src="https://app.codeflash.ai/images/codeflash_darkmode.svg" alt="CodeFlash" class="logo ld"/>'
    '</div>'
)

# Pre-built static HTML fragments (no user data)
SUCCESS_FRAG = (
    '<div class="si"><svg class="sc" fill="none" stroke="currentColor" viewBox="0 0 24 24">'
    '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>'
    '</svg></div><h1>Success!</h1>'
    '<p>Authentication completed. You can close this window and return to your terminal.</p>'
)

ERR_ICON_FRAG = (
    '<div class="ic" style="background:hsl(0,84.2%,60.2%,.1)">'
    '<svg width="24" height="24" fill="none" stroke="hsl(0,84.2%,60.2%)" viewBox="0 0 24 24">'
    '<circle cx="12" cy="12" r="10" stroke-width="2"/>'
    '<line x1="12" y1="8" x2="12" y2="12" stroke-width="2" stroke-linecap="round"/>'
    '<line x1="12" y1="16" x2="12.01" y2="16" stroke-width="2" stroke-linecap="round"/>'
    '</svg></div><h1>Authentication Failed</h1>'
)


def loading_page():
    # Inline the static fragments as JS string constants so the polling
    # script only inserts pre-defined trusted HTML, never user data.
    success_js = json.dumps(SUCCESS_FRAG)
    err_icon_js = json.dumps(ERR_ICON_FRAG)
    return (
        '<!DOCTYPE html><html><head><meta charset="UTF-8">'
        '<meta name="viewport" content="width=device-width,initial-scale=1.0">'
        '<title>CodeFlash Authentication</title>'
        f'<style>{STYLE}</style>'
        '<script>if(window.matchMedia&&window.matchMedia("(prefers-color-scheme:dark)").matches)'
        '{document.documentElement.classList.add("dark")}</script>'
        '</head><body>'
        f'<div class="ctr">{LOGO}'
        '<div class="card" id="c">'
        '<div class="ic"><div class="spinner"></div></div>'
        '<h1>Authenticating</h1>'
        '<p>Please wait while we verify your credentials...</p>'
        '</div></div>'
        '<script>'
        f'var SF={success_js},EI={err_icon_js};'
        'var n=0,mx=60;'
        'function ck(){'
        'fetch("/status").then(function(r){return r.json()}).then(function(d){'
        'var e=document.getElementById("c");'
        'if(d.success){while(e.firstChild)e.removeChild(e.firstChild);'
        'e.insertAdjacentHTML("beforeend",SF)}'
        'else if(d.error){while(e.firstChild)e.removeChild(e.firstChild);'
        'e.insertAdjacentHTML("beforeend",EI);'
        'var b=document.createElement("div");b.className="eb";b.textContent=d.error;e.appendChild(b)}'
        'else if(n<mx){n++;setTimeout(ck,500)}'
        'else{while(e.firstChild)e.removeChild(e.firstChild);'
        'e.insertAdjacentHTML("beforeend",EI);'
        'var b2=document.createElement("div");b2.className="eb";'
        'b2.textContent="Authentication timed out. Please try again.";e.appendChild(b2)}'
        '}).catch(function(){if(n<mx){n++;setTimeout(ck,500)}})}'
        'setTimeout(ck,1000);'
        '</script></body></html>'
    )


class H(http.server.BaseHTTPRequestHandler):
    server_version = "CFHTTP"

    def do_GET(self):
        p = urllib.parse.urlparse(self.path)

        if p.path == "/status":
            self.send_response(200)
            self.send_header("Content-type", "application/json")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            body = json.dumps({
                "success": self.server.token_error is None and self.server.auth_code is not None,
                "error": self.server.token_error,
            })
            self.wfile.write(body.encode())
            return

        if p.path != "/callback":
            self.send_response(404)
            self.end_headers()
            return

        params = urllib.parse.parse_qs(p.query)
        code = params.get("code", [None])[0]
        recv_state = params.get("state", [None])[0]
        error = params.get("error", [None])[0]

        if error or not code or recv_state != state:
            self.server.token_error = error or "state_mismatch"
        else:
            self.server.auth_code = code
            with open(result_file, "w") as f:
                json.dump({"code": code}, f)

        self.send_response(200)
        self.send_header("Content-type", "text/html")
        self.end_headers()
        self.wfile.write(loading_page().encode())

    def log_message(self, *a):
        pass


httpd = http.server.HTTPServer(("localhost", port), H)
httpd.auth_code = None
httpd.token_error = None
httpd.serve_forever()
PYEOF
SERVER_PID=$!

# --- Open browser (macOS, Linux, WSL) ---
if [[ "$(uname)" == "Darwin" ]]; then
  open "$LOCAL_AUTH_URL" 2>/dev/null || true
elif command -v wslview >/dev/null 2>&1; then
  wslview "$LOCAL_AUTH_URL" 2>/dev/null || true
elif command -v xdg-open >/dev/null 2>&1; then
  xdg-open "$LOCAL_AUTH_URL" 2>/dev/null || true
elif command -v cmd.exe >/dev/null 2>&1; then
  cmd.exe /c start "" "$LOCAL_AUTH_URL" 2>/dev/null || true
fi

# --- Wait for callback ---
WAITED=0
while [ ! -s "$RESULT_FILE" ] && [ "$WAITED" -lt "$TIMEOUT" ]; do
  sleep 1
  WAITED=$((WAITED + 1))
  if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    break
  fi
done

if [ ! -s "$RESULT_FILE" ]; then
  kill "$SERVER_PID" 2>/dev/null || true
  wait "$SERVER_PID" 2>/dev/null || true
  exit 1
fi

# --- Parse callback result ---
AUTH_CODE=$(python3 -c "import json; print(json.load(open('${RESULT_FILE}')).get('code',''))" 2>/dev/null || true)

if [ -z "$AUTH_CODE" ]; then
  kill "$SERVER_PID" 2>/dev/null || true
  wait "$SERVER_PID" 2>/dev/null || true
  exit 1
fi

# --- Exchange code for token ---
exchange_and_save "$AUTH_CODE" "$CODE_VERIFIER" "$LOCAL_REDIRECT_URI"

# Give the browser a moment to poll /status and see success, then shut down
sleep 2
kill "$SERVER_PID" 2>/dev/null || true
wait "$SERVER_PID" 2>/dev/null || true