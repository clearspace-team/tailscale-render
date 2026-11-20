#!/usr/bin/env bash

# Starts Tailscale in userspace mode and, optionally:
#   - advertises subnet routes into the Render private network (ADVERTISE_ROUTES)
#   - forwards one TCP port to a private Render host (FORWARD_TARGET), published either on
#     this node or as a Tailscale Service (TAILSCALE_SERVICE)
#
# ADVERTISE_ROUTES   CIDRs to advertise. Unset = 10.0.0.0/8; set to an empty value to advertise
#                    nothing (forwarder only).
# FORWARD_TARGET     host:port inside the private network, for example dpg-abc123-a:5432.
#                    Unset = no forwarder.
# FORWARD_PORT       port to listen on. Default: the port in FORWARD_TARGET.
# TAILSCALE_SERVICE  Tailscale Service name, for example svc:ozone-db. The service must exist
#                    in the admin console and this node must be approved as a host. Unset = the
#                    port is served on this node's own tailnet address instead.

/render/tailscaled --tun=userspace-networking --socks5-server=localhost:1055 &
PID=$!

# "-" (not ":-") so an explicitly empty ADVERTISE_ROUTES turns route advertisement off. The
# flag is always passed, because `tailscale up` refuses to silently drop a setting that an
# earlier run stored in the state on disk.
ADVERTISE_ROUTES=${ADVERTISE_ROUTES-10.0.0.0/8}
until /render/tailscale up --authkey="${TAILSCALE_AUTHKEY}" --hostname="${RENDER_SERVICE_NAME}" --advertise-routes="$ADVERTISE_ROUTES"; do
  sleep 0.1
done
tailscale_ip=$(/render/tailscale ip)
echo "Tailscale is up at IP ${tailscale_ip}"
echo "Advertised routes: ${ADVERTISE_ROUTES:-none}"

if [ -n "${FORWARD_TARGET:-}" ]; then
  FORWARD_PORT=${FORWARD_PORT:-${FORWARD_TARGET##*:}}

  # socat listens on localhost only and opens a new connection to the target for every client,
  # so the target's hostname is resolved by Render's DNS each time: an IP change needs no
  # redeploy. The loop restarts it if it ever exits.
  (
    while true; do
      socat "TCP-LISTEN:${FORWARD_PORT},bind=127.0.0.1,reuseaddr,fork" "TCP:${FORWARD_TARGET}"
      echo "socat exited ($?), restarting" >&2
      sleep 1
    done
  ) &
  echo "Forwarding localhost:${FORWARD_PORT} -> ${FORWARD_TARGET}"

  # Publish the local port to the tailnet. The serve config is stored in the state on disk, so
  # rerunning this on every start is harmless. A failure here (service not defined yet, host
  # not approved) is logged and does not stop the router.
  if [ -n "${TAILSCALE_SERVICE:-}" ]; then
    if /render/tailscale serve --service="${TAILSCALE_SERVICE}" --tcp="${FORWARD_PORT}" "tcp://localhost:${FORWARD_PORT}"; then
      echo "Serving ${TAILSCALE_SERVICE} on tcp/${FORWARD_PORT}"
    else
      echo "tailscale serve for ${TAILSCALE_SERVICE} failed; check the service exists and this host is approved" >&2
    fi
  else
    if /render/tailscale serve --bg --tcp="${FORWARD_PORT}" "tcp://localhost:${FORWARD_PORT}"; then
      echo "Serving tcp/${FORWARD_PORT} on this node (${tailscale_ip})"
    else
      echo "tailscale serve on tcp/${FORWARD_PORT} failed" >&2
    fi
  fi
  /render/tailscale serve status || true
fi

export ALL_PROXY=socks5://localhost:1055/

wait ${PID}
