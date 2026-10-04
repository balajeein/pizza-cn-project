#!/usr/bin/env bash
# Siddhanth Raikar - Mac 3 - backend A, caching, firewall, standby edge (Task C, F, Ext C, E). ./siddhanth.sh <command>
cd "$(dirname "$0")"; source ./lib.sh

case "${1:-}" in
  backend)  # Task C: run backend A on port 3001 (Ctrl-C = "backend A is down")
    python3 backend/server.py A 3001 ;;

  firewall-on)  # Ext C: only Mac 2 (Balajee) may reach port 3001
    firewall_on 3001 ;;

  firewall-off)  # Ext C rollback
    firewall_off ;;

  standby-edge)  # Ext E: run a copy of Balajee's nginx here (needs cert + key from Balajee)
    edge_start ;;

  standby-stop)  # stop the standby nginx
    nginx -s stop ;;

  *) usage ;;
esac
