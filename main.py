import time
from db import get_connection
from config import POLL_INTERVAL_SECONDS, MACHINE_GROUPS
from events import (
    handle_step10,
    handle_step13, 
    handle_step14_cip,
    handle_end_roll
)

# Previous state per machine — equivalent of trigger's "deleted" table
previous_state = {}

# In-memory cooldown tracking for Step 14
step14_cooldown = {}
splice_cooldown = {}  # in-memory cooldown for splicing signals

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
            continue  # first poll, no previous state yet
        
        curr_step = curr.get("Machine_Step_no")
        prev_step = prev.get("Machine_Step_no")

        # Log any state changes
        if curr_step != prev_step:
            print(f"[{machine}] Step change: {prev_step} → {curr_step}")

        curr_cip = curr.get("Signal_Final_CIP")
        prev_cip = prev.get("Signal_Final_CIP")
        if curr_cip != prev_cip:
            print(f"[{machine}] CIP change: {prev_cip} → {curr_cip}")

        for sig in ["Paper_Splicing_End_roll_Signal_Brik", "Strip_Splicing_Signal_Strip"]:
            if curr.get(sig) != prev.get(sig):
                print(f"[{machine}] {sig}: {prev.get(sig)} → {curr.get(sig)}")
        
        # Step 10 transition
        if machine == 'M1' and curr_step == 10 and prev_step != 10:
            handle_step10(machine, conn)

        # Step 13 transition
        if machine == 'M1' and curr_step == 13 and prev_step != 13:
            handle_step13(
                machine,
                curr.get("Counter_infeed"),
                curr.get("Counter_Outfeed"),
                conn
            )

        # Step 14 + CIP
        is_ad = machine.startswith("A") or machine.startswith("D")
        if machine == 'M1' and is_ad and curr_step == 14 and curr.get("Signal_Final_CIP") == True:
            handle_step14_cip(machine, step14_cooldown, conn)

        # End roll signal 0→1 transition
        if (machine == 'M1' and
            curr.get("Paper_Splicing_End_roll_Signal_Brik") == True and
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

        # Strip signal 0→1 transition
        if (machine == 'M1' and
            curr.get("Strip_Splicing_Signal_Strip") == True and
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
    print("Pipeline starting...")
    conn = get_connection()
    
    while True:
        try:
            current_state = get_current_state(conn)
            print(f"Reading {len(current_state)} machines...")
            process(current_state, previous_state, conn)
            previous_state.update(current_state)
            time.sleep(POLL_INTERVAL_SECONDS)
            print("Cycle complete.\n")

        except Exception as e:
            print(f"Error: {e}")
            # Reconnect on connection drop
            try:
                conn = get_connection()
            except:
                pass
            time.sleep(5)

if __name__ == "__main__":
    main()