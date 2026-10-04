# CN Project — Team Guide

**Team:** Pizza — Balajee (lead) · Pragya Kashyap · Siddhanth Raikar · Saransh Singh Tomar
**Goal:** A client laptop accesses `https://app.pizza.test`. Our private DNS translates that domain name into Mac 2's IP (`10.7.13.223`), Mac 2 (nginx) terminates TLS/HTTPS, and nginx round-robin load balances requests across Backend A (`10.7.16.100:3001`) and Backend B (`10.7.14.226:3002`). Every single layer is then proven with packet captures, curl inspects, and failure drills.

---

## 1. Team Roster & Network Architecture

### Machine & Role Assignment

| Laptop | Member | Student ID | IP Address | Script | Role & Assigned Tasks |
|---|---|---|---|---|---|
| **Mac 1** | **Pragya Kashyap** | `2401010522` | `10.7.18.133` | `./pragya.sh` | **Private DNS Server + Client**: LAN check (Task A), dnsmasq setup (Task B), TTL demo (Ext B), DNS failure drills |
| **Mac 2** | **Balajee** | `2401010123` | `10.7.13.223` | `./balajee.sh` | **Edge Reverse Proxy + Load Balancer + TLS**: TLS certificate (Task E), nginx edge (Task D), edge capture (Task G), HA failover (Ext D), cutover (Ext E) |
| **Mac 3** | **Siddhanth Raikar** | `2401020110` | `10.7.16.100` | `./siddhanth.sh` | **Backend A**: Service on port 3001 (Task C), HTTP caching & ETag (Task F), pf firewall isolation (Ext C), standby edge (Ext E) |
| **Mac 4** | **Saransh Singh Tomar** | `2401010418` | `10.7.14.226` | `./saransh.sh` | **Backend B + Backup DNS + Client**: Service on port 3002 (Task C), Wireshark capture (Task G), backup DNS (Ext A), pf firewall (Ext C) |

*All team members can also run `./everyone.sh` (shared diagnostics and verification checks).*

### LAN Network Specification
- **Subnet Mask**: `255.255.224.0`
- **CIDR**: `/19` (`10.7.0.0/19`)
- **Gateway**: `10.7.0.1`

### End-to-End Request Flow

```
Client (Mac 1: 10.7.18.133 / Mac 4: 10.7.14.226)
   │
   │ 1. DNS Query: "Where is app.pizza.test?"
   │    UDP 53 ──▶ Mac 1 (10.7.18.133) dnsmasq  [Backup: Mac 4 (10.7.14.226)]
   │    DNS Response ◀── "app.pizza.test is at 10.7.13.223 (TTL 30s)"
   │
   │ 2. HTTPS Request: "GET /api/status"
   │    TCP 443 ──▶ Mac 2 (10.7.13.223) nginx Edge [TLS Terminates Here]
   │                   │
   │                   ├── Round-Robin TCP 3001 ──▶ Mac 3 (10.7.16.100:3001) Backend A
   │                   │                            (X-Backend: A)
   │                   │
   │                   └── Round-Robin TCP 3002 ──▶ Mac 4 (10.7.14.226:3002) Backend B
   │                                                (X-Backend: B)
```

---

## 2. Step 0 — Setup & Environment Preparation (All Members)

1. **Install Prerequisites via Homebrew**:
   - Everyone:
     ```bash
     brew install --cask wireshark-app
     ```
   - Pragya (Mac 1) and Saransh (Mac 4):
     ```bash
     brew install dnsmasq
     ```
   - Balajee (Mac 2) and Siddhanth (Mac 3):
     ```bash
     brew install nginx openssl
     ```

2. **Network Connection**:
   - Ensure all 4 laptops are connected to the same local Wi-Fi router or mobile hotspot (avoid campus networks that enforce client isolation).
   - Ensure macOS stealth mode is disabled so pings respond:
     *System Settings → Network → Firewall → Options → turn off "Stealth Mode"*.

3. **Verify Local IP & Freeze IP Settings**:
   - Run:
     ```bash
     ./everyone.sh info
     ```
   - Verify that your IP matches your assigned IP in `team.env`:
     - Pragya: `10.7.18.133`
     - Balajee: `10.7.13.223`
     - Siddhanth: `10.7.16.100`
     - Saransh: `10.7.14.226`
   - In macOS *System Settings → Wi-Fi → Details → TCP/IP → Configure IPv4: Manually*, enter your assigned IP, subnet mask `255.255.224.0`, and router `10.7.0.1`.

4. **Team Configuration (`team.env`)**:
   - `team.env` is pre-configured with team name **Pizza**, slug **pizza**, domains `app.pizza.test` and `api.pizza.test`, and all 4 IPs.

5. **Gate 1 — LAN Verification**:
   - Everyone runs:
     ```bash
     ./everyone.sh ping
     ```
   - All 4 IP lines must report `0.0% packet loss`.

---

## 3. Pragya Kashyap — Mac 1 — Private DNS Server + Client

### Phase 1 — Core DNS Setup
- [ ] **Task A (Topology & Ping Evidence)**:
  Run `./everyone.sh ping` and record `0.0% packet loss` to all 4 nodes.
- [ ] **Task B (Start Private DNS)**:
  ```bash
  ./pragya.sh dns
  ```
  Expected output:
  `app.pizza.test. 30 IN A 10.7.13.223`
  *(Note that 10.7.13.223 is Balajee's Mac 2, the edge load balancer).*
- [ ] **Point this Mac at Local DNS**:
  ```bash
  ./everyone.sh use-dns
  ```
- [ ] Ask **Siddhanth and Saransh** to configure their DNS resolver too:
  ```bash
  ./everyone.sh use-dns
  ```
- [ ] **Monitor Live DNS Queries**:
  ```bash
  ./pragya.sh log
  ```
  Keep this open in a tab to capture query logs in real time as clients resolve `app.pizza.test`.

### Phase 1 — DNS Failure Demonstrations
| Demo | Command / Action | Observable Effect | Rollback Command |
|---|---|---|---|
| **Wrong DNS Resolver** | On client: `./everyone.sh use-dns 10.9.9.9`<br>Then: `dig app.pizza.test` & `ping 10.7.13.223` | `dig` times out; `ping` succeeds.<br>Demonstrates that **DNS and IP routing operate at different network layers**. | `./everyone.sh use-dns` |
| **Wrong Record** | `./pragya.sh point 10.9.9.9`<br>Client runs: `./everyone.sh demo` | Name resolves (to wrong IP), but HTTPS connection fails.<br>Demonstrates that **DNS is a name mapping, not a connection**. | `./pragya.sh restore` |

### Phase 2 — Extension B (DNS TTL & Client Caching)
- [ ] Run the automated TTL demonstration:
  ```bash
  ./pragya.sh ttl-demo
  ```
  - Shows that client applications (e.g., ping/browser) keep resolving the old IP from local cache for the 30-second TTL duration, even while raw `dig` queries show the server record was updated immediately.
  - Re-run with `./everyone.sh flush` immediately after the change to show instantaneous cache invalidation.

> **Viva Insight**: DNS runs over UDP port 53. `dnsmasq` is authoritative for `pizza.test` (answering queries locally) and forwards all non-local domain requests to `8.8.8.8` / `1.1.1.1`. The TTL (30s) controls client-side cache persistence.

---

## 4. Balajee — Mac 2 — Edge, TLS Termination & Load Balancing

### Phase 1 — Edge Deployment & HTTPS
- [ ] **Task E (Generate TLS Certificate)**:
  ```bash
  ./balajee.sh cert
  ```
  Generates an RSA 2048-bit self-signed certificate with SAN entries `DNS:app.pizza.test` and `DNS:api.pizza.test`.
  Push the generated certificate to Git so team members receive it:
  ```bash
  git add edge/app.pizza.test.crt && git commit -m "edge cert for Pizza team" && git push
  ```
  *(The private key `app.pizza.test.key` remains exclusively on Mac 2 with 0600 permissions).*
- [ ] **Task D (Start Nginx Reverse Proxy & Load Balancer)**:
  Ensure Siddhanth (Mac 3) and Saransh (Mac 4) have started backends, then run:
  ```bash
  ./balajee.sh edge
  ```
- [ ] **Client Trust**:
  Client Macs run `./everyone.sh trust` once to add the certificate to macOS System Keychain.
- [ ] **Verify Load Balancing & HTTPS**:
  From client:
  ```bash
  ./everyone.sh demo
  ```
  Verify round-robin responses alternating between `X-Backend: A` and `X-Backend: B` over HTTP/2.
- [ ] **Open Browser**:
  Navigate to `https://app.pizza.test` in Safari — clean padlock, no warnings.
- [ ] **Monitor Edge Logs**:
  ```bash
  ./balajee.sh log
  ```
- [ ] **Task G (Edge Packet Capture)**:
  Run `./balajee.sh capture` while a client executes `./everyone.sh demo`.
  Wireshark will reveal that client-to-edge traffic on port 443 is fully encrypted, while edge-to-backend traffic on ports 3001/3002 is plaintext HTTP.

### Phase 2 — High Availability & Failure Drills
- [ ] **Ext D (Passive Backend Health Check & Failover)**:
  Siddhanth stops Backend A (Ctrl+C). Client runs `./everyone.sh demo`: 100% of requests are transparently routed to Backend B with zero dropped requests. Siddhanth restarts Backend A; within 10s (`fail_timeout=10s`), round-robin alternates again.
- [ ] **Ext E (Edge Cutover to Standby)**:
  AirDrop the certificate and private key from `/opt/homebrew/etc/nginx/certs/` to Siddhanth on Mac 3. Siddhanth starts `./siddhanth.sh standby-edge`. Pragya and Saransh execute `point 10.7.16.100`. Balajee runs `./balajee.sh stop`. Client demo shows `X-Edge` header shifts from Balajee's hostname to Siddhanth's without service disruption.
- [ ] **Ext F (Layer-by-Layer Fault Drills)**:
  Run `./everyone.sh diagnose` to isolate faults layer-by-layer (DNS → TCP → TLS → HTTP → Upstream).

> **Viva Insight**: Nginx acts as a reverse proxy. Clients only connect to Mac 2 (`10.7.13.223:443`). Nginx terminates TLS and creates distinct backend connections to `10.7.16.100:3001` and `10.7.14.226:3002`.

---

## 5. Siddhanth Raikar — Mac 3 — Backend A, Caching & Firewall

### Phase 1 — Backend A Operations
- [ ] **Task C (Start Backend A)**:
  ```bash
  ./siddhanth.sh backend
  ```
  Runs `python3 backend/server.py A 3001` listening on `0.0.0.0:3001`.
- [ ] **Verify Connectivity from Mac 2 (Balajee)**:
  Balajee checks:
  ```bash
  curl -i http://10.7.16.100:3001/api/status
  ```
  Should return HTTP 200 with `X-Backend: A`.
- [ ] **Task F (HTTP Caching & Conditional Requests)**:
  Client runs `./everyone.sh demo`. Observe the initial 200 response with `ETag` and `Cache-Control: max-age=60`, followed by a conditional `If-None-Match` request returning `304 Not Modified`.

### Phase 2 — Extension C (Firewall Isolation) & Ext E (Standby Edge)
- [ ] **Ext C (Host-Level Firewall via pfctl)**:
  ```bash
  ./siddhanth.sh firewall-on
  ```
  Enforces rules in anchor `com.apple/cnproject`:
  - From Mac 1 (Pragya): `nc -vz -G 3 10.7.16.100 3001` **times out** (dropped).
  - From Mac 2 (Balajee): `curl http://10.7.16.100:3001/api/status` **succeeds** (allowed).
  - Client `./everyone.sh demo` continues to function through the edge.
  - Roll back rules after testing:
    ```bash
    ./siddhanth.sh firewall-off
    ```
- [ ] **Ext E (Standby Edge Backup)**:
  Once cert and key are transferred from Mac 2, run `./siddhanth.sh standby-edge` and verify edge standby capability. Stop with `./siddhanth.sh standby-stop`.

> **Viva Insight**: Sockets are defined by IP and port pairs. `0.0.0.0` binds to all local network interfaces. HTTP 304 avoids re-transmitting payload data when the client's cached ETag matches the server's resource hash.

---

## 6. Saransh Singh Tomar — Mac 4 — Backend B, Wireshark & Backup DNS

### Phase 1 — Backend B & Protocol Inspection
- [ ] **Task C (Start Backend B)**:
  ```bash
  ./saransh.sh backend
  ```
  Runs `python3 backend/server.py B 3002` listening on `0.0.0.0:3002`.
- [ ] **Configure Client Settings**:
  ```bash
  ./everyone.sh use-dns
  ./everyone.sh trust
  ```
- [ ] **Task G (Client Packet Capture & OSI Analysis)**:
  In a separate terminal tab, run:
  ```bash
  ./saransh.sh capture
  ```
  Captures a full request flow into `evidence/06-wireshark/client-flow-*.pcap`.
  Open the capture in Wireshark and filter by `dns || tcp.port==443`:
  1. **DNS**: UDP 53 query and answer resolving `app.pizza.test` to `10.7.13.223`.
  2. **TCP**: Three-way handshake (`SYN` → `SYN-ACK` → `ACK`).
  3. **TLS 1.2**: `Client Hello` → `Server Hello` → `Certificate` → `Server Key Exchange` → `Server Hello Done` → `Client Key Exchange` → `Finished`.
  4. **Encrypted Application Data**: HTTP payload encrypted within TLS records.

### Phase 2 — Extension A (Secondary / Backup DNS Server)
- [ ] **Start Backup DNS**:
  ```bash
  ./saransh.sh backup-dns
  ```
- [ ] **Point Clients to Both Primary and Secondary DNS**:
  On client Macs:
  ```bash
  ./everyone.sh use-dns both
  ```
  Sets nameservers to `10.7.18.133 10.7.14.226`.
- [ ] **Test DNS Server Failover**:
  Pragya stops Mac 1 DNS (`./pragya.sh stop`).
  Client runs `dig app.pizza.test`. The query succeeds after a brief fallback pause, and the `SERVER:` line in dig confirms responses from `10.7.14.226`.
- [ ] **Ext C (Firewall for Port 3002)**:
  Run `./saransh.sh firewall-on` and `./saransh.sh firewall-off` to test backend isolation on port 3002.

> **Viva Insight**: When primary DNS fails, the client operating system resolver falls back to the secondary server. For record changes during Phase 2, both servers must be updated (`./pragya.sh point <ip>` and `./saransh.sh point <ip>`).

---

## 7. Evidence Directory Structure

Organize all screenshots, logs, and pcap traces in the `evidence/` directory:
```
evidence/
├── 01-lan/                  # Ping matrix (0% loss), ./everyone.sh info outputs
├── 02-dns/                  # dig queries, dnsmasq logs, wrong-DNS failure screenshots
├── 03-lb/                   # demo runs showing A and B alternating, nginx access logs
├── 04-tls/                  # Browser padlock screenshot, certificate SAN inspection
├── 05-caching/              # ETag 200 response followed by 304 Not Modified
├── 06-wireshark/            # client-flow-*.pcap and edge-*.pcap captures
├── 07-failures/             # 502 bad gateway demo, connection refused demo
├── 08-phase2-backup-dns/    # Secondary DNS takeover evidence
├── 08-phase2-ttl/           # TTL caching vs dig direct query comparison
├── 08-phase2-firewall/      # Direct backend blocked (timeout) vs edge proxy allowed
├── 08-phase2-failover/      # Backend A killed -> Backend B seamless takeover
└── 08-phase2-cutover/       # Edge cutover to Mac 3 standby nginx
```

---

## 8. Milestone Gates

| Gate | Criterion | Responsible Member |
|---|---|---|
| **Gate 1: LAN** | All 4 nodes reachable via `./everyone.sh ping`; static IPs verified | Pragya |
| **Gate 2: DNS & Backends** | `dig app.pizza.test` resolves; Mac 2 curls both 3001 & 3002 | Pragya, Siddhanth, Saransh |
| **Gate 3: Edge & TLS** | Browser accesses `https://app.pizza.test` with valid cert; LB alternates | Balajee |
| **Gate 4: Evidence** | 304 caching verified; Wireshark captures annotated; failure drills saved | All |
| **Gate 5: Phase 2 Extensions** | Backup DNS, TTL demo, firewall isolation, backend failover | All |
| **Gate 6: Standby Cutover** | Mac 3 takes over Edge role; `./everyone.sh diagnose` passes all layers | All |

---

## 9. Final 11-Step Demonstration Sequence

1. **Topology & Network Architecture**: Present IP assignments, subnet `/19`, and gateway.
2. **LAN Verification**: Execute `./everyone.sh ping` across all nodes.
3. **Private DNS Resolution**: Run `dig app.pizza.test` pointing to Mac 1.
4. **HTTPS & TLS**: Open `https://app.pizza.test` in browser (valid cert, HTTP/2).
5. **Round-Robin Load Balancing**: Run `./everyone.sh demo` to display alternating backends.
6. **Wireshark Analysis**: Review labeled `.pcap` showing DNS → TCP → TLS Handshake → Encrypted Data.
7. **HTTP Caching**: Demonstrate initial 200 response with ETag and subsequent 304 Not Modified.
8. **Backend Failover (Ext D)**: Stop Backend A; rerun demo to verify seamless routing to Backend B.
9. **Phase 2 Features**: Demonstrate Backup DNS failover, TTL client caching, or pfctl firewall drop.
10. **Automated Diagnostic Drill**: Run `./everyone.sh diagnose` to isolate faults layer by layer.
11. **Viva Defense**: Answer theoretical and practical questions on DNS, TCP, TLS, and Reverse Proxies.
