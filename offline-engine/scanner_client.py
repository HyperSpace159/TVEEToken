#!/usr/bin/env python3
"""
T-VEE Offline Scanner Client Simulator
จำลองระบบสแกนเนอร์มือถือของชาวบ้าน / แม่ค้าตลาดสด
เพื่อสแกน JAB Code ซิงค์เงินเข้าระบบ หรือเคลมเงินรางวัลริบทรัพย์ 10 เท่า
"""

import os
import json
import sys

def simulate_scan(meta_file_path, claimant_address):
    if not os.path.exists(meta_file_path):
        print(f"Error: Metadata file {meta_file_path} not found.")
        return

    with open(meta_file_path, "r", encoding="utf-8") as f:
        meta = json.load(f)

    print("=" * 60)
    print("📲 T-VEE MOBILE SCANNER SYNC")
    print("=" * 60)
    print(f"Detected Color Tone: {meta['color']}")
    print(f"Target Face Value:   {meta['targetValue']} TVEE")
    print(f"Token Hash:          {meta['tokenHash']}")
    print(f"Vault Origin:        {meta['vaultOrigin']}")
    print(f"Claimant Address:    {claimant_address}")
    print("-" * 60)

    print("Checking Blockchain Sync State on Layer 2 Rollup...")
    print("Executing: firstSyncWinsAndSlash(tokenHash, claimant)")
    print("\nResult:")
    print("✅ STATUS: SYNC_SUCCESS")
    print(f"🎉 Credited {meta['targetValue']} TVEE directly into wallet {claimant_address[:8]}...{claimant_address[-6:]}")
    print("Notice: First-to-sync registered. Physical token is now settled on-chain.")
    print("=" * 60)

if __name__ == "__main__":
    sample_dir = os.path.join(os.path.dirname(__file__), "..", "sample_notes")
    green_meta = os.path.join(sample_dir, "note_green_meta.json")
    user_wallet = "0x90F79bf6EB2c4f870365E785982E1f101E93b906"
    simulate_scan(green_meta, user_wallet)
