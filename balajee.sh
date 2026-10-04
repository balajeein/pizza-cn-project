#!/usr/bin/env bash
# Balajee - Mac 2 - edge: nginx, TLS, load balancing (Task D, E, Ext D, E). ./balajee.sh <command>
cd "$(dirname "$0")"; source ./lib.sh

case "${1:-}" in
  cert)  # Task E (do first): make the TLS cert, then commit edge/*.crt so everyone gets it
    OPENSSL="$(brew --prefix openssl 2>/dev/null || echo "/opt/homebrew/opt/openssl")/bin/openssl"
    DIR="$BREW/etc/nginx/certs"; mkdir -p "$DIR"
    "$OPENSSL" req -x509 -newkey rsa:2048 -nodes -sha256 -days 365 \
      -keyout "$DIR/$DOMAIN.key" -out "$DIR/$DOMAIN.crt" -subj "/CN=$DOMAIN" \
      -addext "subjectAltName=DNS:$DOMAIN,DNS:$API_DOMAIN" \
      -addext "extendedKeyUsage=serverAuth" 2>/dev/null
    chmod 600 "$DIR/$DOMAIN.key"
    cp "$DIR/$DOMAIN.crt" "$CRT"
    "$OPENSSL" x509 -in "$CRT" -noout -subject -ext subjectAltName -dates
    echo "now: git add edge/$DOMAIN.crt && git commit -m 'edge cert' && git push   (the .key stays here)" ;;

  edge)  # Task D: start/reload nginx with the IPs from team.env
    edge_start ;;

  stop)  # stop nginx (Ext E: prove the standby edge took over)
    nginx -s stop ;;

  log)  # which backend served each request (Ctrl-C to quit)
    tail -f "$BREW/var/log/nginx/access.log" ;;

  capture)  # Task G: capture both sides of the edge -> evidence/06-wireshark/ (Ctrl-C to stop)
    IF=$(route -n get default | awk '/interface:/{print $2}')
    mkdir -p evidence/06-wireshark
    OUT="evidence/06-wireshark/edge-$(date +%H%M%S).pcap"
    echo "capturing on $IF -> $OUT  (client->edge 443 is encrypted, edge->backend 3001/3002 is plain http)"
    sudo tcpdump -i "$IF" -w "$OUT" 'tcp port 443 or tcp port 3001 or tcp port 3002' ;;

  *) usage ;;
esac
