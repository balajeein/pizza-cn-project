#!/usr/bin/env bash
# Saransh Singh Tomar - Mac 4 - backend B, client, Wireshark, backup DNS (Task C, G, Ext A). ./saransh.sh <command>
cd "$(dirname "$0")"; source ./lib.sh

case "${1:-}" in
  backend)  # Task C: run backend B on port 3002
    python3 backend/server.py B 3002 ;;

  capture)  # Task G: capture DNS + TCP + TLS 1.2 for one request -> evidence/06-wireshark/
    IF=$(route -n get default | awk '/interface:/{print $2}')
    mkdir -p evidence/06-wireshark
    OUT="evidence/06-wireshark/client-flow-$(date +%H%M%S).pcap"
    sudo -v                                   # ask for the password now, not in the background
    ./everyone.sh flush                       # force a real DNS query
    sudo tcpdump -i "$IF" -w "$OUT" "port 53 or tcp port 443" 2>/dev/null &
    sleep 2
    # TLS 1.2 on purpose: in TLS 1.3 the Certificate message is encrypted and can't be shown
    $CURL -v --tls-max 1.2 "https://$DOMAIN/api/status" 2>&1 | grep -E '^\*.*(Connected|SSL|TLS)|^< (HTTP|x-)' || true
    sleep 2; sudo pkill -INT tcpdump
    echo "saved $OUT -> open it in Wireshark, filter:  dns || tcp.port==443" ;;

  firewall-on)  # Ext C: only Mac 2 may reach port 3002 (test from Mac 1, not from this Mac)
    firewall_on 3002 ;;

  firewall-off)  # Ext C rollback
    firewall_off ;;

  backup-dns)  # Ext A: start the backup DNS here with the same records
    dns_start "$MAC4_IP" ;;

  backup-stop)  # stop the backup DNS
    sudo brew services stop dnsmasq ;;

  point)  # Phase 2: mirror Pragya's record change here too: ./saransh.sh point <ip>
    dns_point "${2:?give an IP}" ;;

  restore)  # put the record back to Mac 2 (Balajee)
    dns_point "$MAC2_IP" ;;

  *) usage ;;
esac
