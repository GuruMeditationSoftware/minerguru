#!/usr/bin/env python3
"""Builds /api/system/info test payloads for every Bitaxe and NerdOS variant.

Starts from two anonymised real responses (templates/) and adapts them per board and firmware
generation. Board data comes from the firmware sources:

- AxeOS:  bitaxeorg/ESP-Miner      main/device_config.h  (board versions, ASIC, chip count, default clock)
- NerdOS: shufps/ESP-Miner-NerdQAxePlus  main/boards/*.cpp  (deviceModel, ASIC, chip count, default clock)

AxeOS API generations (fields that matter for MinerGuru):
- <= 2.9   reports `asicCount`
- 2.10/11  no chip count at all (`axeOSVersion` appears)
- 2.12-14  chip count only via `hashrateMonitor.asics`
- >= 2.13  block template (`blockHeight`, `scriptsig`, `coinbaseOutputs`, …), filled live by mock_miner.py
- >= 2.15  pool slots (`pools`, `primaryPoolIndex`, `secondaryPoolIndex`)

Run:  python3 MockMiners/make_variants.py   (writes MockMiners/variants/*.json)
"""
import copy
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent
AXEOS_TEMPLATE = json.loads((ROOT / "templates/axeos-2.15-gamma-601.json").read_text())
NERDOS_TEMPLATE = json.loads((ROOT / "templates/nerdos-1.1-nerdqaxe-plusplus.json").read_text())

SMALL_CORES = {"BM1397": 672, "BM1366": 894, "BM1368": 1276, "BM1370": 2040, "BM1372/BM1373": 6725, "BM1373": 6725}

# file name, board, ASICModel, chips, default MHz, default mV, max power (W), nominal V, AxeOS version
BITAXE = [
    ("bitaxe-max-102_axeos-2.5.0",         "102",  "BM1397",        1, 425, 1400,  25,  5, "v2.5.0"),
    ("bitaxe-ultra-204_axeos-2.8.0",       "204",  "BM1366",        1, 485, 1200,  25,  5, "v2.8.0"),
    ("bitaxe-supra-401_axeos-2.10.0",      "401",  "BM1368",        1, 490, 1166,  40,  5, "v2.10.0"),
    ("bitaxe-hex-302_axeos-2.11.0",        "302",  "BM1366",        6, 485, 1200,  90, 12, "v2.11.0"),
    ("bitaxe-gamma-601_axeos-2.13.2",      "601",  "BM1370",        1, 525, 1150,  40,  5, "v2.13.2"),
    ("bitaxe-supra-hex-701_axeos-2.14.2",  "701",  "BM1368",        6, 490, 1166, 120, 12, "v2.14.2"),
    ("bitaxe-gamma-601_axeos-2.15.3",      "601",  "BM1370",        1, 525, 1150,  40,  5, "v2.15.3"),
    ("bitaxe-gamma-duo-650_axeos-2.15.4",  "650",  "BM1370",        2, 400, 1150,  40,  5, "v2.15.4"),
    ("bitaxe-gt-801_axeos-2.15.4",         "801",  "BM1370",        2, 525, 1150,  60, 12, "v2.15.4"),
    ("bitaxe-naja-duo-1201_axeos-2.15.4",  "1201", "BM1372/BM1373", 2, 327, 1000,  60, 12, "v2.15.4"),
    ("bitaxe-gamma-hex-1300_axeos-2.15.4", "1300", "BM1370",        6, 690, 1200, 180, 12, "v2.15.4"),
]

# file name, deviceModel, ASICModel, chips, default MHz, default mV, pool mode (None = no `stratum` block)
NERDOS = [
    ("nerdaxe_nerdos-1.1.0",            "NerdAxe",       "BM1366", 1,  485, 1200, 0),
    ("nerdaxe-gamma_nerdos-1.1.0",      "NerdAxeGamma",  "BM1370", 1,  515, 1150, 0),
    ("nerdaxe-gaia_nerdos-1.1.0",       "NerdAxeGaia",   "BM1373", 1,  350,  940, 0),
    ("nerdqaxe-plus_nerdos-1.1.0",      "NerdQAxe+",     "BM1368", 4,  490, 1250, 0),
    ("nerdqaxe-plusplus_nerdos-1.1.0",  "NerdQAxe++",    "BM1370", 4,  600, 1150, 1),
    ("nerdqaxe-plusplus_nerdos-legacy", "NerdQAxe++",    "BM1370", 4,  600, 1150, None),
    ("nerdqx_nerdos-1.1.0",             "NerdQX",        "BM1370", 4,  777, 1200, 0),
    ("nerdhaxe-gamma_nerdos-1.1.0",     "NerdHaxe-γ",    "BM1370", 6,  600, 1150, 0),
    ("nerdoctaxe-gamma_nerdos-1.1.0",   "NerdOCTAXE-γ",  "BM1370", 8,  700, 1210, 1),
    ("nerdoctaxe-plus_nerdos-1.1.0",    "NerdOCTAXE+",   "BM1368", 8,  490, 1250, 0),
    ("nerdeko_nerdos-1.1.0",            "NerdEKO",       "BM1370", 12, 600, 1150, 0),
    ("q1370_nerdos-1.1.0",              "Q1370",         "BM1370", 4,  600, 1150, 0),
    ("q1373_nerdos-1.1.0",              "Q1373",         "BM1373", 4,  425, 1010, 0),
]

V2_POOL_FIELDS = [key for key in AXEOS_TEMPLATE if "Protocol" in key or "V2" in key]
BLOCK_FIELDS = ["blockHeight", "scriptsig", "blockSignals", "coinbaseOutputs", "coinbaseValueTotalSatoshis",
                "coinbaseValueUserSatoshis", "stratumDecodeCoinbase", "fallbackStratumDecodeCoinbase"]
# Mine BTC solo on ckpool with coinbase decoding on, so the block card has outputs to show.
BTC_SOLO = {"bitaxe-supra-hex-701_axeos-2.14.2", "bitaxe-gamma-hex-1300_axeos-2.15.4"}


def version_tuple(version: str):
    return tuple(int(part) for part in version.lstrip("v").split("."))


def hashrate_ghs(mhz: int, asic: str, chips: int) -> float:
    return round(mhz * SMALL_CORES[asic] * chips / 1000 * 0.97, 1)


def bitaxe(board, asic, chips, mhz, mv, max_power, nominal_v, version):
    info = copy.deepcopy(AXEOS_TEMPLATE)
    rate = hashrate_ghs(mhz, asic, chips)
    info.update({
        "boardVersion": board, "ASICModel": asic, "smallCoreCount": SMALL_CORES[asic],
        "version": version, "frequency": mhz, "coreVoltage": mv, "coreVoltageActual": mv - 6,
        "maxPower": max_power, "nominalVoltage": nominal_v, "hostname": f"bitaxe-{board}",
        "hashRate": rate, "hashRate_1m": rate, "hashRate_10m": rate, "hashRate_1h": rate,
        "expectedHashrate": round(rate / 0.97, 1), "power": round(max_power * 0.45, 1),
    })
    gen = version_tuple(version)
    info["hashrateMonitor"] = {"asics": [
        {"total": round(rate / chips, 1), "errorCount": 0, "domains": [round(rate / chips / 4, 1)] * 4}
        for _ in range(chips)
    ]}
    if gen < (2, 15, 0):
        for key in ("pools", "primaryPoolIndex", "secondaryPoolIndex", "useFallbackStratum"):
            info.pop(key, None)
    if gen < (2, 14, 0):
        for key in V2_POOL_FIELDS:
            info.pop(key, None)
    if gen < (2, 13, 0):
        for key in BLOCK_FIELDS:
            info.pop(key, None)
    if gen < (2, 12, 0):
        info.pop("hashrateMonitor")
    if gen < (2, 10, 0):
        info.pop("axeOSVersion", None)
        info["asicCount"] = chips
    return info


def btc_solo(info):
    """Primary = the ckpool BTC slot (decoding on), fallback = the BCH slot."""
    btc = {"stratumURL": "eusolo.ckpool.org", "stratumPort": 3333,
           "stratumUser": "bc1qexamplewalletaddressxxxxxxxxxxxxxxxxxx.bitaxe", "stratumDecodeCoinbase": True}
    if "pools" in info:
        info["primaryPoolIndex"], info["secondaryPoolIndex"] = 0, 2
        btc = {key: info["pools"][0][key] for key in btc}
        fallback = info["pools"][2]
        for key in btc:
            info["fallbackS" + key[1:]] = fallback[key]
    for key, value in btc.items():
        info[key] = value
    return info


def nerdos(model, asic, chips, mhz, mv, pool_mode):
    info = copy.deepcopy(NERDOS_TEMPLATE)
    rate = hashrate_ghs(mhz, asic, chips)
    info.update({
        "deviceModel": model, "ASICModel": asic, "asicCount": chips, "smallCoreCount": SMALL_CORES[asic],
        "defaultFrequency": mhz, "defaultCoreVoltage": mv, "frequency": mhz, "coreVoltage": mv,
        "hostname": model.lower().replace("+", "plus").replace("γ", "gamma"),
        "hashRate": rate, "hashRate_1m": rate, "hashRate_10m": rate, "hashRate_1h": rate,
        "power": round(rate / 1000 * 17, 1),
    })
    if pool_mode is None:
        info.pop("stratum", None)
    else:
        stratum = info["stratum"]
        stratum["poolMode"] = pool_mode
        stratum["activePoolMode"] = pool_mode
        if pool_mode == 0:
            stratum["poolBalance"] = 50
            stratum["pools"][1]["connected"] = False
    return info


def main():
    out = ROOT / "variants"
    out.mkdir(exist_ok=True)
    for old in out.glob("*.json"):
        old.unlink()
    for name, *spec in BITAXE:
        info = bitaxe(*spec)
        if name in BTC_SOLO:
            btc_solo(info)
        (out / f"{name}.json").write_text(json.dumps(info, indent=2, sort_keys=True, ensure_ascii=False) + "\n")
    for name, *spec in NERDOS:
        (out / f"{name}.json").write_text(json.dumps(nerdos(*spec), indent=2, sort_keys=True, ensure_ascii=False) + "\n")
    print(f"{len(BITAXE) + len(NERDOS)} variants written to {out}")


if __name__ == "__main__":
    main()
