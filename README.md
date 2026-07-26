# Home Air Quality Monitor — PMS5003 + Raspberry Pi + VictoriaMetrics

A tiny, RAM-frugal stack that reads a Plantower **PMS5003** particulate sensor over UART on a
**Raspberry Pi 3 B+ (1 GB RAM)**, stores every reading for 10 years, and serves a live
single-page wall display — public and login-free over a Cloudflare Tunnel.

Full write-up: [Building a Home Air Quality Monitor with a Raspberry Pi and Grafana](https://blog.bikramtuladhar.com.np/posts/home-air-quality-monitor-raspberry-pi-grafana.html)

## The stack

```
PMS5003 sensor ──UART──> exporter (:8000) ──scrape──> VictoriaMetrics (:8428, 10y)
                                                              │
                                                        wall.py (:3000)
                                                              │
                                                       Cloudflare Tunnel ──> public URL
```

**Why VictoriaMetrics instead of Prometheus?** On a 1 GB Pi with no swap, full Prometheus +
Docker risks OOM. VictoriaMetrics is a single ~30 MB binary that both scrapes and
stores, speaks PromQL, compresses far better, and does 10-year retention on almost no disk.

## Files

| File | What it does |
|------|--------------|
| `pms5003_exporter.py` | Reads the 32-byte PMS5003 frame over UART, exposes all 14 fields as Prometheus metrics on `:8000` |
| `prometheus.yml` | Scrape config used by VictoriaMetrics |
| `wall.py` | ~40-line stdlib HTTP server on `:3000` — serves `wall.html`, proxies `/api/*` to VictoriaMetrics (same-origin, no CORS) |
| `wall.html` | The dashboard: AQI banner, PM mass chart, PM2.5 stat, particle-count chart. Canvas, no dependencies, ~15 MB RAM total vs Grafana's ~250 MB |
| `setup.sh` | Installs exporter + VictoriaMetrics + wall + a 1 GB swapfile as systemd services (purges Grafana if present) |
| `tunnel_setup.sh` | Sets up a Cloudflare Tunnel to expose the wall publicly (no port-forwarding) |

## Quick start (on the Pi)

```bash
# 1. wire the sensor, enable UART (see the blog post for the Ubuntu specifics)
# 2. copy the files to the Pi, then:
sudo bash setup.sh          # exporter + VictoriaMetrics + wall + swap

# optional — expose it publicly on your own domain:
cloudflared tunnel login    # one-time browser auth
bash tunnel_setup.sh        # edit HOST at the top first
```

Then open the wall at `http://<pi-ip>:3000`. It is read-only and unauthenticated by design —
only the two chart queries are ever run.

## Metrics exposed

All 14 fields from the sensor frame:

- `pms5003_pm_ugm3{size,calibration}` — PM1.0 / 2.5 / 10, both atmospheric and CF=1 (6 series)
- `pms5003_particles{size_um}` — cumulative particle counts ≥0.3 … 10 µm (6 series)
- `pms5003_error_code` — 0 = healthy
- `pms5003_firmware_version`

## License

MIT
