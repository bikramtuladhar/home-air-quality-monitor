#!/usr/bin/env python3
"""Read a PMS5003 over UART and expose the readings as Prometheus metrics.

Prometheus scrapes http://<pi>:8000/metrics; Grafana graphs it from there.

Requires: pip install pyserial prometheus_client
Run:      python3 pms5003_exporter.py
"""
import struct
import time
import serial
from prometheus_client import Gauge, start_http_server

PORT = "/dev/ttyAMA0"
BAUD = 9600
FRAME_LEN = 32
START1, START2 = 0x42, 0x4D

# One gauge per reading. Labels keep it flat; Grafana filters on them.
PM = Gauge("pms5003_pm_ugm3", "PM mass concentration (ug/m3)", ["size", "calibration"])
COUNT = Gauge("pms5003_particles", "Particle count per 0.1L, cumulative above size", ["size_um"])
INFO = Gauge("pms5003_error_code", "Sensor error code (0 = ok)")
FW = Gauge("pms5003_firmware_version", "Sensor firmware version byte")


def read_frame(ser):
    while True:
        b = ser.read(1)
        if not b:
            return None
        if b[0] != START1:
            continue
        if ser.read(1)[:1] != bytes([START2]):
            continue
        break
    body = ser.read(FRAME_LEN - 2)
    if len(body) != FRAME_LEN - 2:
        return None
    checksum = (START1 + START2 + sum(body[:-2])) & 0xFFFF
    expected = (body[-2] << 8) | body[-1]
    if checksum != expected:
        return None
    v = struct.unpack(">13H", body[2:28])
    return {
        "pm1_0_cf1": v[0], "pm2_5_cf1": v[1], "pm10_cf1": v[2],
        "pm1_0": v[3], "pm2_5": v[4], "pm10": v[5],
        "n0_3": v[6], "n0_5": v[7], "n1_0": v[8],
        "n2_5": v[9], "n5_0": v[10], "n10": v[11],
        "version": v[12] >> 8, "error": v[12] & 0xFF,
    }


def publish(d):
    PM.labels("pm1.0", "atm").set(d["pm1_0"])
    PM.labels("pm2.5", "atm").set(d["pm2_5"])
    PM.labels("pm10", "atm").set(d["pm10"])
    PM.labels("pm1.0", "cf1").set(d["pm1_0_cf1"])
    PM.labels("pm2.5", "cf1").set(d["pm2_5_cf1"])
    PM.labels("pm10", "cf1").set(d["pm10_cf1"])
    for size, key in (("0.3", "n0_3"), ("0.5", "n0_5"), ("1.0", "n1_0"),
                      ("2.5", "n2_5"), ("5.0", "n5_0"), ("10", "n10")):
        COUNT.labels(size).set(d[key])
    INFO.set(d["error"])
    FW.set(d["version"])


def main():
    start_http_server(8000)  # /metrics
    with serial.Serial(PORT, BAUD, timeout=2) as ser:
        ser.reset_input_buffer()
        while True:
            d = read_frame(ser)
            if d:
                publish(d)
            time.sleep(1)


if __name__ == "__main__":
    main()
