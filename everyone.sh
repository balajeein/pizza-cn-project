#!/usr/bin/env bash
# Commands ANY team member runs on their own Mac. ./everyone.sh <command>
cd "$(dirname "$0")"

if [ "${1:-}" = info ]; then   # works before team.env is filled
  IF=$(route -n get default | awk '/interface:/{print $2}')
  echo "name     $(scutil --get ComputerName)"
  echo "iface    $IF"
  echo "ip       $(ipconfig getifaddr "$IF")"
  echo "netmask  $(ipconfig getoption "$IF" subnet_mask)"
  echo "gateway  $(route -n get default | awk '/gateway:/{print $2}')"
  echo "mac      $(ifconfig "$IF" | awk '/ether/{print $2}')"
  echo "dns      $(scutil --dns | awk '/nameserver\[/{print $3}' | awk '!seen[$0]++' | tr '\n' ' ')"
  exit
fi

source ./lib.sh
set +e   # these are checks: keep going and show every result
case "${1:-}" in
  ping)  # Task A: ping all 4 Macs
    for ip in $MAC1_IP $MAC2_IP $MAC3_IP $MAC4_IP; do
      printf '%-15s ' "$ip"; ping -c 3 -t 5 "$ip" | tail -1 || echo "FAILED"
    done ;;

  use-dns)  # point this Mac at team DNS. use-dns | use-dns both | use-dns reset | use-dns <ip>
    case "${2:-}" in
      "")    servers="$MAC1_IP" ;;
      both)  servers="$MAC1_IP $MAC4_IP" ;;     # Phase 2 Ext A
      reset) servers="Empty" ;;                 # back to router default
      *)     servers="$2" ;;                    # e.g. 10.9.9.9 for the wrong-DNS demo
    esac
    sudo networksetup -setdnsservers Wi-Fi $servers
    sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
    echo "DNS now: $(networksetup -getdnsservers Wi-Fi | tr '\n' ' ')" ;;

  flush)  # clear this Mac's DNS cache
    sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder; echo "DNS cache flushed" ;;

  trust)  # trust our cert so the browser shows no warning (client Macs)
    sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain "$CRT"
    echo "trusted. Open https://$DOMAIN in Safari/Chrome - no warning." ;;

  untrust)  # undo trust
    sudo security remove-trusted-cert -d "$CRT" ;;

  demo)  # demo steps 3,4,5,7: dns, https, load balancing, caching
    echo "== 3. DNS ($DOMAIN should be $MAC2_IP)"
    dig +noall +answer +comments "$DOMAIN" | grep -E 'status|IN'
    dig "$DOMAIN" | grep SERVER
    echo "== 4+5. HTTPS + load balancing"
    for i in 1 2 3 4 5 6; do
      $CURL -s -o /dev/null -D - "https://$DOMAIN/api/status" | grep -iE '^(HTTP|x-backend|x-edge)' | tr -d '\r' | paste -sd' ' -
    done
    echo "== 7. caching: first a full 200, then a conditional 304"
    $CURL -sI "https://$DOMAIN/api/catalog" | grep -iE '^HTTP|cache-control|etag'
    ETAG=$($CURL -sI "https://$DOMAIN/api/catalog" | awk 'tolower($1)=="etag:"{print $2}' | tr -d '\r')
    $CURL -sI -H "If-None-Match: $ETAG" "https://$DOMAIN/api/catalog" | head -1 ;;

  diagnose)  # Ext F: check each layer in order, first FAIL = the broken layer
    step() { printf '\n== %s\n' "$1"; }
    step "1 DNS: does the name resolve?"
    r=$(dig +short +time=2 +tries=1 "$DOMAIN"); echo "${r:-FAILED - no answer}"
    step "2 TCP: can we connect to 443?"
    nc -vz -G 3 "$DOMAIN" 443 2>&1 || true
    step "3 TLS: handshake + cert valid?"
    openssl s_client -connect "$DOMAIN:443" -servername "$DOMAIN" -CAfile "$CRT" </dev/null 2>&1 \
      | grep -E 'Verify return code|^subject|Protocol *:|connect:' || true
    step "4 HTTP: does the app answer?"
    $CURL -s -m 5 -o /dev/null -w '%{http_code} via %{remote_ip}\n' "https://$DOMAIN/api/status" || echo "FAILED"
    step "5 backends directly (blocked if firewall is on - that's fine)"
    curl -s -m 3 "http://$MAC3_IP:3001/api/status" || echo "A unreachable"; echo
    curl -s -m 3 "http://$MAC4_IP:3002/api/status" || echo "B unreachable"; echo ;;

  *) usage ;;
esac
