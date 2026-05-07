import time
import logging
from db import get_connection
from config import POLL_INTERVAL_SECONDS, MACHINE_GROUPS
from events import (
    handle_step10,
    handle_step13,
    handle_step14_cip,
    handle_end_roll
)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
log = logging.getLogger(__name__)

previous_state = {}
step14_cooldown = {}
splice_cooldown = {}

STEP14_CIP_MACHINES = set(MACHINE_GROUPS["step14_cip"])
STEP13_MACHINES = set(MACHINE_GROUPS["step13"])
ALL_ACTIVE_MACHINES = STEP14_CIP_MACHINES | STEP13_MACHINES


def get_current_state(conn):
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM T_M_Filler_Process")
    columns = [col[0] for col in cursor.description]
    rows = cursor.fetchall()
    return {row_dict['Machine']: row_dict for row_dict in [dict(zip(columns, row)) for row in rows]}


def process(current, previous, conn):
    for machine, curr in current.items():
        prev = previous.get(machine)
        if not prev:
            continue

        if machine not in ALL_ACTIVE_MACHINES:
            continue

        curr_step = curr.get("Machine_Step_no")
        prev_step = prev.get("Machine_Step_no")

        if curr_step != prev_step:
            log.info("[%s] Step change: %s → %s", machine, prev_step, curr_step)

        curr_cip = curr.get("Signal_Final_CIP")
        prev_cip = prev.get("Signal_Final_CIP")
        if curr_cip != prev_cip:
            log.info("[%s] CIP change: %s → %s", machine, prev_cip, curr_cip)

        for sig in ["Paper_Splicing_End_roll_Signal_Brik", "Strip_Splicing_Signal_Strip"]:
            if curr.get(sig) != prev.get(sig):
                log.info("[%s] %s: %s → %s", machine, sig, prev.get(sig), curr.get(sig))

        # Step 10 — batch start (all active machines)
        if curr_step == 10 and prev_step != 10:
            handle_step10(machine, conn)

        # Step 13 — batch end (step13 group only)
        if machine in STEP13_MACHINES and curr_step == 13 and prev_step != 13:
            handle_step13(
                machine,
                curr.get("Counter_infeed"),
                curr.get("Counter_Outfeed"),
                conn
            )

        # Step 14 + CIP — batch end (step14_cip group only)
        if machine in STEP14_CIP_MACHINES and curr_step == 14 and curr.get("Signal_Final_CIP") == True:
            handle_step14_cip(machine, step14_cooldown, conn)

        # Paper end roll signal 0→1
        if (curr.get("Paper_Splicing_End_roll_Signal_Brik") == True and
                prev.get("Paper_Splicing_End_roll_Signal_Brik") == False):
            cursor = conn.cursor()
            cursor.execute("""
                SELECT TOP 1 ID, Splicing_Count, Last_Splice_Time
                FROM [Change paper brik]
                WHERE Machine = ?
                AND [end time] IS NULL
                ORDER BY ID DESC
            """, machine)
            row = cursor.fetchone()
            if row:
                handle_end_roll(machine, row[0], row[1] or 0, row[2], conn, "Change paper brik", splice_cooldown)

        # Strip signal 0→1
        if (curr.get("Strip_Splicing_Signal_Strip") == True and
                prev.get("Strip_Splicing_Signal_Strip") == False):
            cursor = conn.cursor()
            cursor.execute("""
                SELECT TOP 1 ID, Splicing_Count, Last_Splice_Time
                FROM [Change strip]
                WHERE Machine = ?
                AND [end time] IS NULL
                ORDER BY ID DESC
            """, machine)
            row = cursor.fetchone()
            if row:
                handle_end_roll(machine, row[0], row[1] or 0, row[2], conn, "Change strip", splice_cooldown)


def main():
    log.info("Pipeline starting...")
    conn = get_connection()

    while True:
        try:
            current_state = get_current_state(conn)
            log.debug("Polled %d machines", len(current_state))
            process(current_state, previous_state, conn)
            previous_state.update(current_state)
            time.sleep(POLL_INTERVAL_SECONDS)

        except Exception as e:
            log.error("Poll error: %s", e)
            try:
                conn = get_connection()
                log.info("Reconnected to database")
            except Exception as reconnect_err:
                log.error("Reconnect failed: %s", reconnect_err)
            time.sleep(5)


if __name__ == "__main__":
    main()
