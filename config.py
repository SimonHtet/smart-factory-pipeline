MACHINE_GROUPS = {
    "step14_cip": ["A1", "A4", "A5", "B1", "B2", "D1", "D2", "D3"],   # Step 14 + CIP=1 for end
    "step13":     ["F1", "F2", "F3", "F4", "G1", "G2", "G3", "H1", "H2", "H3", "K1", "K2"],  # Step 13 for end
    "tbd":        ["E1", "J1"],                # unknown yet
}

POLL_INTERVAL_SECONDS = 1
COOLDOWN_STEP14_SECONDS = 3600   # 1 hour
COOLDOWN_SPLICE_MS = 30000       # 30 seconds