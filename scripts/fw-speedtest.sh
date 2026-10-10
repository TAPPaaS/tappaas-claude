#!/usr/bin/env bash
#
# fw-speedtest.sh — load the OPNsense firewall (WAN, inter-zone, Caddy, WireGuard) and meter its CPU.
#
# Usage: fw-speedtest.sh <site> [options]      (from the Mac; re-runs itself on cicd-<site>)
#        fw-speedtest.sh --here [options]      (on a cicd, i.e. inside the mgmt zone)
# Options:
#   --direction D   down | up | both (default both)
#   --duration S    seconds per load phase (default 20)
#   --per-source N  download streams per source (default 2)
#   --sources LIST  comma list of source names to use (default: all; see --probe)
#   --streams N     upload streams (default 8)
#   --idle S        idle baseline seconds before the load (default 5)
#   --fw TARGET     firewall ssh target (default root@10.0.0.1, key ~/.ssh/tappaas-fw)
#   --host T:IF     also meter the physical WAN NIC on the Proxmox host, e.g.
#                   root@10.0.0.12:enp3s0 (shows what really crossed the wire)
#   --iperf H[:P]   instead of the internet, run iperf3 against tappaas@H (a VM in
#                   another zone on the same node, so traffic is routed through the
#                   firewall but never leaves the host): the firewall's forwarding limit.
#                   Starts a temporary iperf3 server on port P (default 5201; must be
#                   open in the VM's own firewall); uses --streams both ways.
#   --udp           with --iperf: UDP at full rate (-u -b 0 -l 1400) instead of TCP;
#                   the reachability pre-check is skipped (UDP has no handshake)
#   --caddy URL     load Caddy on the firewall instead: phase "bulk" = --streams
#                   keep-alive connections fetching URL (a static file) over and over,
#                   phase "handshake" = --streams loops of one fresh TLS connection per
#                   request (no session reuse) for the site root "/" (tiny response).
#                   Meters the firewall's mgmt-side interface.
#   --watch S       generate no load: just meter for S seconds (phase "watch") while
#                   load comes from elsewhere, e.g. the Mac over the WireGuard tunnel
#   --if IF         meter this firewall interface instead of the auto-detected one
#   --wg            (Mac side only) WireGuard through the admin tunnel: the Mac pulls
#                   from, then pushes to, the cicd's mgmt address for --duration s each
#                   while the firewall's wg0 is metered (needs the site's tunnel up)
#   --probe         time each download source alone (one stream, 6s) and exit
#   -h, --help      this help
#
# Load:  download = --per-source curl streams to EVERY source in the pool at once
#        (OVH, Scaleway, Vultr, Hetzner, ...), so no single server caps the result;
#        upload   = --streams curl POST streams to speed.cloudflare.com/__up.
# Meter: the firewall itself, once a second: per-core busy % from kern.cp_times
#        (sys/intr split out) and WAN rx/tx Mbit/s + kpps from the interface counters,
#        so the numbers are what actually crossed the WAN (other traffic included —
#        the idle phase shows that background). A `top -SH` snapshot is taken mid-phase.
# Output: per-second table + per-phase summary on stdout; CSV in ~/fw-speedtest/ on the cicd.
#
set -euo pipefail

usage() { sed -n '3,46p' "${BASH_SOURCE[0]:-$0}" | sed 's/^# \{0,1\}//'; }

# ---- Mac side: ship this script to the site's cicd and run it there -------------------
if [[ "${1:-}" != "--here" ]]; then
    [[ -z "${1:-}" || "$1" == -h || "$1" == --help ]] && { usage; exit 0; }
    site="$1"; shift
    wg=0 dur=15 args=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --wg)       wg=1; shift ;;
            --duration) dur="$2"; args+=("$1" "$2"); shift 2 ;;
            *)          args+=("$1"); shift ;;
        esac
    done
    if (( wg )); then
        # The load must cross the tunnel, so it runs here; the cicd only meters wg0.
        mgmt="$(ssh "cicd-${site}" "ip -4 -o route get 1.1.1.1 | grep -oP 'src \K\S+'")"
        ssh -o BatchMode=yes -o ConnectTimeout=5 "tappaas@${mgmt}" true 2>/dev/null \
            || { echo "cicd mgmt address ${mgmt} not reachable — is the ${site} tunnel up?" >&2; exit 2; }
        out="$(mktemp)"
        "$0" "${site}" --watch $(( 2 * dur + 8 )) --if wg0 > "${out}" 2>&1 & meter=$!
        sleep 16  # meter start-up: ssh, 2s settle, 5s idle, 3s cool
        echo "== wg download (cicd -> here), ${dur}s"
        ssh -o BatchMode=yes "tappaas@${mgmt}" "timeout ${dur} cat /dev/zero" | dd of=/dev/null bs=1m 2>&1 | tail -1 || true
        sleep 2
        echo "== wg upload (here -> cicd), ${dur}s"
        dd if=/dev/zero bs=1m count=1000000 2>/dev/null \
            | ssh -o BatchMode=yes "tappaas@${mgmt}" "timeout -s INT ${dur} dd of=/dev/null bs=1M 2>&1 | tail -1" || true
        wait "${meter}"
        grep -v -E '^client-side|^    watch' "${out}"; rm -f "${out}"
        exit 0
    fi
    set -- "${args[@]}"
    exec ssh "cicd-${site}" "bash -s -- --here $(printf '%q ' "$@")" < "${BASH_SOURCE[0]}"
fi
shift

DIRECTION=both DURATION=20 STREAMS=8 PER_SOURCE=2 IDLE=5 SOURCES="" PROBE=0 HOST="" IPERF="" UDP=0 CADDY="" WATCH=0 METER_IF=""
FW=root@10.0.0.1 FW_KEY="${HOME}/.ssh/tappaas-fw"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --direction) DIRECTION="$2"; shift 2 ;;
        --duration)  DURATION="$2"; shift 2 ;;
        --streams)   STREAMS="$2"; shift 2 ;;
        --per-source) PER_SOURCE="$2"; shift 2 ;;
        --sources)   SOURCES="$2"; shift 2 ;;
        --probe)     PROBE=1; shift ;;
        --udp)       UDP=1; shift ;;
        --caddy)     CADDY="$2"; shift 2 ;;
        --watch)     WATCH="$2"; shift 2 ;;
        --if)        METER_IF="$2"; shift 2 ;;
        --idle)      IDLE="$2"; shift 2 ;;
        --fw)        FW="$2"; shift 2 ;;
        --host)      HOST="$2"; shift 2 ;;
        --iperf)     IPERF="${2%%:*}"; IPORT="${2#*:}"; [[ "$2" == *:* ]] || IPORT=5201; shift 2 ;;
        -h|--help)   usage; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done
[[ "${DIRECTION}" =~ ^(down|up|both)$ ]] || { echo "bad --direction" >&2; exit 2; }

# Download pool: "name url". Large files on different providers/networks; single-stream
# speeds from hrossen 2026-10-08: ovh 1.9G, online 2.1G, vultr-sto 2.2G, scaleway 1.2G,
# vultr-ams 0.8G, hetzner/serverius/linode 0.5-0.6G. Re-check with --probe.
POOL=(
    "ovh-rbx     https://proof.ovh.net/files/10Gb.dat"
    "online-par  http://ping.online.net/10000Mo.dat"
    "scaleway    https://scaleway.testdebit.info/10G.iso"
    "vultr-sto   https://sto-se-ping.vultr.com/vultr.com.1000MB.bin"
    "vultr-ams   https://ams-nl-ping.vultr.com/vultr.com.1000MB.bin"
    "vultr-fra   https://fra-de-ping.vultr.com/vultr.com.1000MB.bin"
    "hetzner-fsn https://fsn1-speed.hetzner.com/10GB.bin"
    "hetzner-nbg https://nbg1-speed.hetzner.com/10GB.bin"
    "hetzner-hel https://hel1-speed.hetzner.com/10GB.bin"
    "serverius   https://speedtest.serverius.net/files/10000mb.bin"
    "linode-fra  https://speedtest.frankfurt.linode.com/garbage.php?ckSize=2000"
)
SRC_NAMES=() SRC_URLS=()
for e in "${POOL[@]}"; do
    read -r n u <<< "$e"
    [[ -z "${SOURCES}" || ",${SOURCES}," == *",$n,"* ]] || continue
    SRC_NAMES+=("$n"); SRC_URLS+=("$u")
done
(( ${#SRC_NAMES[@]} > 0 )) || { echo "no source matches --sources ${SOURCES}" >&2; exit 2; }
UP_URL="https://speed.cloudflare.com/__up"
UA="Mozilla/5.0 (X11; Linux x86_64) fw-speedtest"

if (( PROBE )); then
    echo "single-stream speed per source (6s each):"
    for i in "${!SRC_NAMES[@]}"; do
        { curl -sL -A "${UA}" -o /dev/null --max-time 6 \
             -w '%{http_code} %{speed_download} %{remote_ip}\n' "${SRC_URLS[i]}" 2>/dev/null || true; } \
        | awk -v n="${SRC_NAMES[i]}" '{printf "  %-12s %s %6.0f Mbit/s  %s\n", n, $1, $2*8/1e6, $3}'
    done
    exit 0
fi

fw() { ssh -i "${FW_KEY}" -o BatchMode=yes -o ConnectTimeout=10 "${FW}" 'sh -s'; }

OUT_DIR="${HOME}/fw-speedtest"; mkdir -p "${OUT_DIR}"
STAMP="$(date +%Y%m%d-%H%M%S)"
CSV="${OUT_DIR}/${STAMP}.csv"
WORK="$(mktemp -d)"
PHASE_FILE="${WORK}/phase"; echo setup > "${PHASE_FILE}"
PIDS=()
cleanup() {
    for p in "${PIDS[@]}"; do kill "$p" 2>/dev/null || true; done
    pkill -P $$ curl 2>/dev/null || true
    [[ -n "${IPERF}" ]] && ssh -n -o BatchMode=yes "tappaas@${IPERF}" "pkill -f 'bin/iperf3 -s -p ${IPORT}'" 2>/dev/null
    rm -rf "${WORK}"
}
trap cleanup EXIT INT TERM

# ---- discover the WAN interface (default route) ----------------------------------------
METER_TARGET="${IPERF:-default}"
[[ -n "${CADDY}" ]] && METER_TARGET="$(ip -4 -o route get 1.1.1.1 | grep -oP 'src \K\S+')"
(( WATCH > 0 )) && DURATION="${WATCH}"
read -r WAN_IF NCPU FW_MODEL < <(fw <<EOF
printf '%s %s %s\n' "\$(route -n get -inet ${METER_TARGET} | awk '/interface:/{print \$2}')" \
    "\$(sysctl -n hw.ncpu)" "\$(sysctl -n hw.model | tr -s ' ' '_')"
EOF
)
WAN_IF="${METER_IF:-${WAN_IF}}"
echo "firewall ${FW}: ${NCPU} CPU (${FW_MODEL//_/ }), metered interface ${WAN_IF}"
if [[ -n "${CADDY}" ]]; then
    echo "caddy: ${STREAMS} connections to ${CADDY}; ${DURATION}s per phase"
elif (( WATCH > 0 )); then
    echo "watch: metering ${WATCH}s, no load generated here"
elif [[ -n "${IPERF}" ]]; then
    echo "iperf3 ${IPERF}:${IPORT}: ${STREAMS} streams each way (download = ${IPERF} -> here); ${DURATION}s per phase"
    IPERF_BIN="$(nix-shell -p iperf3 --run 'command -v iperf3' 2>/dev/null)"
    [[ -x "${IPERF_BIN}" ]] || { echo "cannot get iperf3 via nix-shell" >&2; exit 2; }
else
    echo "download: ${#SRC_NAMES[@]} sources x ${PER_SOURCE} streams (${SRC_NAMES[*]})"
    echo "upload: ${STREAMS} streams; ${DURATION}s per phase, ${IDLE}s idle baseline"
fi

# ---- sampler: raw counters from the firewall, tagged with the local phase -------------
nload=1; [[ "${DIRECTION}" == both || -n "${CADDY}" ]] && nload=2
total=$(( IDLE + nload * (DURATION + 3) + 20 ))  # generous; killed when done
[[ -n "${IPERF}" ]] && total=$(( total + 60 ))  # iperf3 server start-up
sampler() {
    fw <<EOF
i=0
while [ \$i -lt ${total} ]; do
    echo "\$(sysctl -n kern.cp_times) \$(netstat -I ${WAN_IF} -bn | awk 'NR==2{print \$5,\$8,\$9,\$11}')"
    sleep 1; i=\$((i+1))
done
EOF
}
sampler | while read -r line; do
    printf '%s %s %s\n' "$(date +%s.%N)" "$(cat "${PHASE_FILE}")" "${line}"
done > "${WORK}/raw" &
PIDS+=($!)

if [[ -n "${HOST}" ]]; then  # physical NIC counters on the Proxmox host, same phase tags
    ssh -n -o BatchMode=yes -o ConnectTimeout=10 "${HOST%%:*}" \
        "d=/sys/class/net/${HOST#*:}/statistics; for i in \$(seq ${total}); do echo \$(cat \$d/rx_bytes \$d/tx_bytes); sleep 1; done" \
    | while read -r line; do
        printf '%s %s %s\n' "$(date +%s.%N)" "$(cat "${PHASE_FILE}")" "${line}"
    done > "${WORK}/host" &
    PIDS+=($!)
fi

if [[ -n "${IPERF}" ]]; then  # temporary server, removed by timeout and by cleanup
    ssh -n -o BatchMode=yes "tappaas@${IPERF}" \
        "b=\$(nix-shell -p iperf3 --run 'command -v iperf3') && nohup timeout ${total} \$b -s -p ${IPORT} > /dev/null 2>&1 &
         for i in \$(seq 20); do ss -ltn | grep -q ':${IPORT} ' && exit 0; sleep 1; done; exit 1" \
        || { echo "iperf3 server did not start on ${IPERF}:${IPORT}" >&2; exit 2; }
    (( UDP )) || timeout 5 bash -c "</dev/tcp/${IPERF}/${IPORT}" 2>/dev/null \
        || { echo "${IPERF}:${IPORT} not reachable from here (firewall?)" >&2; exit 2; }
fi

UDP_FLAGS=""; (( UDP )) && UDP_FLAGS="-u -b 0 -l 1400"
iperf_load() {  # $1 = phase name, $2 = extra iperf3 flag (-R = server sends)
    "${IPERF_BIN}" -c "${IPERF}" -p "${IPORT}" --connect-timeout 5000 -P "${STREAMS}" -t "${DURATION}" ${2:-} ${UDP_FLAGS} --json \
    | python3 -c '
import json, sys
e = json.load(sys.stdin)["end"]
if "sum_received" in e:
    print("iperf3", int(e["sum_received"]["bytes"]))
else:  # UDP: sender bytes minus the loss the server saw
    lost = e["sum"].get("lost_percent", 0)
    print("iperf3-udp-loss-%.1f%%" % lost, 0)
    print("iperf3", int(e["sum"]["bytes"] * (1 - lost / 100)))' \
        >> "${WORK}/bytes-$1" || true
}

snapshot() {  # $1 = phase; top threads on the firewall mid-phase
    sleep $(( DURATION / 2 ))
    fw <<'EOF' > "${WORK}/top-$1" 2>&1 || true
top -b -S -H -o cpu -d 2 15 | awk 'BEGIN{n=0} /^last pid/{n++} n==2'
EOF
}

load_down() {
    [[ -n "${IPERF}" ]] && { iperf_load download -R; return; }
    local end=$(( $(date +%s) + DURATION )) i pids=()
    for (( i = 0; i < ${#SRC_NAMES[@]} * PER_SOURCE; i++ )); do
        local s=$(( i % ${#SRC_NAMES[@]} ))
        ( while (( $(date +%s) < end )); do
              curl -sL -A "${UA}" -o /dev/null -w "${SRC_NAMES[s]} %{size_download}\n" \
                   --max-time $(( end - $(date +%s) + 1 )) "${SRC_URLS[s]}" >> "${WORK}/bytes-download" || true
          done ) & pids+=($!)
    done
    wait "${pids[@]}"
}

load_up() {
    [[ -n "${IPERF}" ]] && { iperf_load upload; return; }
    local end=$(( $(date +%s) + DURATION )) i pids=()
    for (( i = 0; i < STREAMS; i++ )); do
        ( while (( $(date +%s) < end )); do
              head -c 500000000 /dev/zero | curl -s -A "${UA}" -o /dev/null -w 'cloudflare %{size_upload}\n' \
                   --max-time $(( end - $(date +%s) + 1 )) --data-binary @- "${UP_URL}" >> "${WORK}/bytes-upload" || true
          done ) & pids+=($!)
    done
    wait "${pids[@]}"
}

load_caddy_bulk() {  # keep-alive: 50 fetches per curl run, so TLS is set up once per run
    local end=$(( $(date +%s) + DURATION )) i pids=() cfg="${WORK}/caddy.cfg"
    for (( i = 0; i < 50; i++ )); do printf 'url = "%s"\noutput = "/dev/null"\n' "${CADDY}"; done > "${cfg}"
    for (( i = 0; i < STREAMS; i++ )); do
        ( while (( $(date +%s) < end )); do
              curl -sk -A "${UA}" -K "${cfg}" -w 'caddy %{size_download}\n' >> "${WORK}/bytes-bulk" || true
          done ) & pids+=($!)
    done
    wait "${pids[@]}"
}

load_caddy_hs() {  # one full TLS handshake per request: fresh connection, no session ids
    local end=$(( $(date +%s) + DURATION )) i pids=() cfg="${WORK}/caddy-hs.cfg"
    local root; root="$(grep -oE '^https?://[^/]+' <<< "${CADDY}")/"
    for (( i = 0; i < 100; i++ )); do printf 'url = "%s"\noutput = "/dev/null"\n' "${root}"; done > "${cfg}"
    for (( i = 0; i < STREAMS; i++ )); do
        ( while (( $(date +%s) < end )); do
              curl -sk -A "${UA}" --no-sessionid --http1.1 -H 'Connection: close' -K "${cfg}" \
                   -w 'caddy %{size_download}\n' >> "${WORK}/bytes-handshake" || true
          done ) & pids+=($!)
    done
    wait "${pids[@]}"
}

load_watch() { sleep "${WATCH}"; echo "watch 0" >> "${WORK}/bytes-watch"; }

phase() {  # $1 = name, $2 = load function or empty for idle
    echo "$1" > "${PHASE_FILE}"; echo "== phase $1"
    if [[ -n "${2:-}" ]]; then
        snapshot "$1" & local snap=$!
        head -n1 /proc/stat > "${WORK}/cpu-$1"
        "$2"
        head -n1 /proc/stat >> "${WORK}/cpu-$1"
        wait "${snap}"
    else
        sleep "${IDLE}"
    fi
    echo cool > "${PHASE_FILE}"; sleep 3
}

sleep 2
phase idle
if [[ -n "${CADDY}" ]]; then
    phase bulk load_caddy_bulk
    phase handshake load_caddy_hs
elif (( WATCH > 0 )); then
    phase watch load_watch
else
    [[ "${DIRECTION}" != up ]]   && phase download load_down
    [[ "${DIRECTION}" != down ]] && phase upload load_up
fi
echo done > "${PHASE_FILE}"; sleep 1
for p in "${PIDS[@]}"; do kill "$p" 2>/dev/null || true; done; wait 2>/dev/null || true

# ---- report -----------------------------------------------------------------------------
awk -v ncpu="${NCPU}" -v csv="${CSV}" '
{
    t = $1; ph = $2; n = 0
    for (c = 0; c < ncpu; c++) for (k = 0; k < 5; k++) cur[c, k] = $(3 + c * 5 + k)
    base = 3 + ncpu * 5; ipk = $base; ib = $(base + 1); opk = $(base + 2); ob = $(base + 3)
    if (seen && ph != "setup" && ph != "done") {
        dt = t - pt; tb = 0; ti = 0; tsys = 0; tint = 0; tusr = 0; mx = 0; cores = ""
        for (c = 0; c < ncpu; c++) {
            tot = 0; for (k = 0; k < 5; k++) tot += cur[c, k] - prev[c, k]
            if (tot <= 0) tot = 1
            busy = 100 * (1 - (cur[c, 4] - prev[c, 4]) / tot)
            tusr += 100 * (cur[c, 0] + cur[c, 1] - prev[c, 0] - prev[c, 1]) / tot
            tsys += 100 * (cur[c, 2] - prev[c, 2]) / tot; tint += 100 * (cur[c, 3] - prev[c, 3]) / tot
            tb += busy; if (busy > mx) mx = busy; cores = cores sprintf(" %3.0f", busy)
        }
        cpu = tb / ncpu; usr = tusr / ncpu; sys = tsys / ncpu; intr = tint / ncpu
        rx = (ib - pib) * 8 / dt / 1e6; tx = (ob - pob) * 8 / dt / 1e6
        pps = ((ipk - pipk) + (opk - popk)) / dt / 1000
        if (!hdr++) {
            printf "%-9s %8s %8s %7s %6s %5s %5s %5s %5s  per-core busy %%\n", "phase", "rx Mb/s", "tx Mb/s", "kpps", "cpu%", "user", "sys", "intr", "max"
            print "phase,rx_mbit,tx_mbit,kpps,cpu_pct,user_pct,sys_pct,intr_pct,max_core_pct" > csv
        }
        printf "%-9s %8.1f %8.1f %7.1f %6.1f %5.1f %5.1f %5.1f %5.0f %s\n", ph, rx, tx, pps, cpu, usr, sys, intr, mx, cores
        printf "%s,%.1f,%.1f,%.1f,%.1f,%.1f,%.1f,%.1f,%.0f\n", ph, rx, tx, pps, cpu, usr, sys, intr, mx >> csv
        if (ph != "cool") {
            if (!(ph in N)) order[++np] = ph
            N[ph]++; RX[ph] += rx; TX[ph] += tx; CPU[ph] += cpu; PPS[ph] += pps; USR[ph] += usr
            if (rx > PRX[ph]) PRX[ph] = rx; if (tx > PTX[ph]) PTX[ph] = tx
            if (cpu > PCPU[ph]) PCPU[ph] = cpu; if (mx > PMX[ph]) PMX[ph] = mx
        }
    }
    for (c = 0; c < ncpu; c++) for (k = 0; k < 5; k++) prev[c, k] = cur[c, k]
    pt = t; pib = ib; pob = ob; pipk = ipk; popk = opk; seen = 1
}
END {
    printf "\nsummary     avg rx  peak rx   avg tx  peak tx   kpps  avg cpu  avg user  peak cpu  peak core\n"
    for (i = 1; i <= np; i++) { p = order[i]; n = N[p]
        printf "%-9s %8.0f %8.0f %8.0f %8.0f %6.1f %7.1f%% %8.1f%% %8.1f%% %9.0f%%\n", p,
            RX[p]/n, PRX[p], TX[p]/n, PTX[p], PPS[p]/n, CPU[p]/n, USR[p]/n, PCPU[p], PMX[p] }
}' "${WORK}/raw"

if [[ -s "${WORK}/host" ]]; then
    awk -v h="${HOST}" '
        seen && $2 != "cool" && $2 != "setup" && $2 != "done" {
            dt = $1 - pt; if (!($2 in N)) o[++n] = $2; N[$2]++
            r = ($3 - pr) * 8 / dt / 1e6; x = ($4 - px) * 8 / dt / 1e6
            RX[$2] += r; TX[$2] += x; if (r > PR[$2]) PR[$2] = r; if (x > PX[$2]) PX[$2] = x }
        { pt = $1; pr = $3; px = $4; seen = 1 }
        END { printf "\nhost NIC %s (wire)\n", h
              for (i = 1; i <= n; i++) { p = o[i]
                  printf "%-9s %8.0f %8.0f %8.0f %8.0f\n", p, RX[p]/N[p], PR[p], TX[p]/N[p], PX[p] } }' "${WORK}/host"
fi

echo
for f in "${WORK}"/bytes-*; do
    [[ -s "$f" ]] || continue
    p="${f##*/bytes-}"
    cpu=$(awk 'NR==1{for(i=2;i<=NF;i++){a+=$i}; ai=$5+$6} NR==2{for(i=2;i<=NF;i++){b+=$i}; bi=$5+$6}
               END{printf "%.0f", 100*(1-(bi-ai)/(b-a))}' "${WORK}/cpu-$p")
    awk -v p="$p" -v d="${DURATION}" -v cpu="${cpu}" '{b[$1] += $2; t += $2; r++}
        END {printf "client-side %-9s %6.0f Mbit/s  (%.2f GB in %ss, %d req = %.0f req/s; cicd CPU %s%%)\n", p, t*8/d/1e6, t/1e9, d, r, r/d, cpu
             for (n in b) printf "    %-12s %6.0f Mbit/s\n", n, b[n]*8/d/1e6}' "$f" \
        | { IFS= read -r head; echo "${head}"; sort -k2 -rn; }
done
for f in "${WORK}"/top-*; do
    [[ -s "$f" ]] || continue
    printf '\n== firewall top threads mid-%s\n' "${f##*/top-}"; head -n 22 "$f"
done
echo; echo "CSV: ${CSV}"
