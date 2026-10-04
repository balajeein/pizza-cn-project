#!/usr/bin/env bash
# Pragya Kashyap - Mac 1 - Private DNS (Task A, B, Ext B). ./pragya.sh <command>
cd "$(dirname "$0")"; source ./lib.sh

case "${1:-}" in
  dns)  # Task B: start primary DNS (dnsmasq) with our records
    dns_start "$MAC1_IP" ;;

  stop)  # stop primary DNS (for Saransh's backup-DNS demo, Ext A)
    sudo brew services stop dnsmasq ;;

  log)  # watch every DNS query live (Ctrl-C to quit)
    tail -f "$BREW/var/log/dnsmasq.log" ;;

  point)  # change the record live: ./pragya.sh point <ip>   (wrong-record demo, Ext E cutover)
    dns_point "${2:?give an IP, e.g. $MAC3_IP}" ;;

  restore)  # put the record back to Mac 2 (Balajee)
    dns_point "$MAC2_IP" ;;

  ttl-demo)  # Ext B: show the client cache keeps the old IP until TTL (30s) runs out
    ./everyone.sh use-dns >/dev/null   # this Mac is the client, using itself
    ./everyone.sh flush
    resolved() { ping -c1 -t1 "$DOMAIN" 2>/dev/null | head -1 | sed 's/.*(\(.*\)).*/\1/' || true; }
    echo "t=0   client resolves $DOMAIN -> $(resolved)   (now cached for 30s)"
    dns_point "$MAC3_IP" >/dev/null
    echo "      record changed on server to $MAC3_IP"
    for t in 5 10 15 20 25 30 35 40; do
      sleep 5
      echo "t=$t  client sees $(resolved)    (dig, which skips the cache: $(dig +short "$DOMAIN"))"
    done
    dns_point "$MAC2_IP" >/dev/null
    echo "record restored to $MAC2_IP. Now run it again but do './everyone.sh flush' right after the change -> instant." ;;

  *) usage ;;
esac
