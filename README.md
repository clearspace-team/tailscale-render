# Run Tailscale on Render

![image](https://github.com/render-examples/tailscale/assets/168030/2513267e-6503-45c6-b596-3713160ae4ec)

[Tailscale](https://tailscale.com) is a zero-config VPN service built on top of [Wireguard](https://www.wireguard.com/). It's great for accessing devices and applications behind firewalls, and you can use it to connect to all your private services on Render with this repo.

A Tailscale [subnet router](https://tailscale.com/kb/1019/subnets/) acts as a gateway to your Render private network, enabling connections to any and all internal IPs (of the form `10.x.x.x`) in your Render network.

## Deployment

### One Click Deploy

Use the button below to deploy a Tailscale subnet router on Render. [Generate a Tailscale auth key](https://login.tailscale.com/admin/settings/authkeys) and provide that as the `TAILSCALE_AUTHKEY` environment variable in Render. Use a one-off key for maximum security.

The build downloads a static Linux binary from the Tailscale [stable track](https://pkgs.tailscale.com/stable/). Pin the release with `TAILSCALE_VERSION` (set in `render.yaml` for Blueprint deploys, or override in the Render dashboard). Bump it when you want to pick up a newer stable client.

<a href="https://render.com/deploy?repo=https://github.com/render-examples/tailscale/tree/main">
  <img src="https://render.com/images/deploy-to-render-button.svg" alt="Deploy to Render">
</a>

## Usage
Deploying this repo will create a subnet router in your Tailscale network. The first time you deploy, you'll need to [enable the subnet routes](https://tailscale.com/kb/1019/subnets/#step-3-enable-subnet-routes-from-the-admin-panel) you want access to from the Tailscale admin panel. Once the subnet router is up and running, you can connect to other private services in your Render network. To find the internal IP address for a Render private service, go to the web shell for your subnet router service and run `dig` with the [private service's host name](https://render.com/docs/private-services#connecting-to-a-private-service) as the only argument.

## Forwarding one port by name (ozone-db)

Clients should not have to know a `10.x` address, which Render can change. When `FORWARD_TARGET` is set, the service also runs a TCP forwarder (`socat`) to that private host and publishes it on the tailnet with `tailscale serve`. The host name is resolved inside Render on every connection.

| Variable | Meaning |
|---|---|
| `FORWARD_TARGET` | `host:port` inside the private network, for example `dpg-abc123-a:5432`. Unset = no forwarder. |
| `FORWARD_PORT` | Port to publish. Defaults to the port in `FORWARD_TARGET`. |
| `TAILSCALE_SERVICE` | [Tailscale Service](https://tailscale.com/docs/features/tailscale-services) name, for example `svc:ozone-db`. Clients connect to `ozone-db.<tailnet>.ts.net`. Unset = the port is served on this node's own name (`<service-name>.<tailnet>.ts.net`). |
| `ADVERTISE_ROUTES` | Unset = `10.0.0.0/8`. Set to an empty value to advertise no routes, so the forwarded port is the only thing reachable. |

One-time setup in the Tailscale admin console for `TAILSCALE_SERVICE`:

1. Services → define `ozone-db` with endpoint `tcp:5432`.
2. Deploy this service, then approve it as a host of `ozone-db` (or add an `autoApprovers.services` entry for `tag:render-router`).
3. Add a grant so the right group can reach `svc:ozone-db`.

`FORWARD_TARGET` is `sync: false` in `render.yaml`: on a service that already exists, set it by hand in the Render dashboard.

