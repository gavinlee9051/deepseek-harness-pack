#!/usr/bin/env bash
# gen-cert.sh - Create/reuse a self-signed TLS cert for the LAN proxy.
# Browsers only expose crypto.randomUUID() (and WebCrypto) in a "secure
# context", so the proxy must serve HTTPS. Regenerates only when the cert is
# missing or no longer covers the current LAN IP.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CERT_DIR="$SCRIPT_DIR/cert"
mkdir -p "$CERT_DIR"
KEY="$CERT_DIR/key.pem"
CRT="$CERT_DIR/cert.pem"

LAN_IP="$(ip -4 route get 1 2>/dev/null | awk '{print $7; exit}')"
HOST="$(hostname)"

SAN="DNS:localhost,IP:127.0.0.1"
if [ -n "$LAN_IP" ]; then SAN="$SAN,IP:$LAN_IP"; fi
SAN="$SAN,DNS:$HOST"

NEED=0
if [ ! -f "$CRT" ]; then NEED=1; fi
if [ "$NEED" -eq 0 ] && [ -n "$LAN_IP" ]; then
  if ! openssl x509 -in "$CRT" -noout -ext subjectAltName 2>/dev/null | grep -qF -- "$LAN_IP"; then
    NEED=1
  fi
fi

if [ "$NEED" -eq 0 ]; then
  echo "[cert] existing cert already covers ${LAN_IP:-localhost}, reusing"
  exit 0
fi

echo "[cert] generating self-signed cert (SAN: $SAN)"
openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout "$KEY" -out "$CRT" -days 825 \
  -subj "/CN=deepseek-harness" \
  -addext "subjectAltName=$SAN" 2>/dev/null
echo "[cert] written: $CRT"
