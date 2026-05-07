from datetime import datetime, timezone
from db import get_connection

def utcnow():
    return datetime.utcnow()

def handle_step10(machine, conn):
    """Step 10 fired — write Splicing time 1 (batch start)"""
    cursor = conn.cursor()
    
    # Change paper brik — only if Splicing time 1 is NULL
    cursor.execute("""
        UPDATE [Change paper brik]
        SET [Splicing time 1] = ?
        WHERE Machine = ?
        AND [Splicing time 1] IS NULL
    """, utcnow(), machine)
    
    # Change strip — only latest open row
    cursor.execute("""
        UPDATE [Change strip]
        SET [Splicing time 1] = ?
        WHERE Machine = ?
        AND ID = (SELECT MAX(ID) FROM [Change strip] WHERE Machine = ?)
        AND [Splicing time 1] IS NULL
    """, utcnow(), machine, machine)
    
    conn.commit()
    print(f"[{machine}] Step 10 — Splicing time 1 written")

def handle_step13(machine, infeed, outfeed, conn):
    """Step 13 fired — write end time + counts"""
    cursor = conn.cursor()
    now = utcnow()
    
    is_ad_machine = machine.startswith("A") or machine.startswith("D")
    
    cursor.execute("""
        UPDATE [Change paper brik]
        SET [end time] = ?,
            [In_Feed_MC] = ?,
            [Out_Feed_MC] = ?,
            End_time_CIP = CASE WHEN ? = 1 THEN ? ELSE End_time_CIP END
        WHERE Machine = ?
        AND [end time] IS NULL
        AND [Splicing time 1] IS NOT NULL
    """, now, infeed, outfeed, 1 if is_ad_machine else 0, now, machine)
    
    cursor.execute("""
        UPDATE [Change strip]
        SET [end time] = ?
        WHERE Machine = ?
        AND ID = (SELECT MAX(ID) FROM [Change strip] WHERE Machine = ?)
        AND [end time] IS NULL
        AND [Splicing time 1] IS NOT NULL
    """, now, machine, machine)
    
    conn.commit()
    print(f"[{machine}] Step 13 — end time written")

def handle_step14_cip(machine, cooldown_log, conn):
    """Step 14 + CIP=1 — only A/D machines, 1hr cooldown"""
    
    # Check cooldown in memory first
    last_time = cooldown_log.get(machine)
    now = utcnow()
    
    if last_time:
        diff = (now - last_time).total_seconds()
        if 0 <= diff < 3600:
            print(f"[{machine}] Step 14 CIP — COOLDOWN ({int(3600-diff)}s remaining)")
            return
    
    cursor = conn.cursor()
    
    # Get latest closed record
    cursor.execute("""
        SELECT TOP 1 ID, [end time], [Out_Feed_MC]
        FROM [Change paper brik]
        WHERE Machine = ?
        AND [end time] IS NOT NULL
        ORDER BY ID DESC
    """, machine)
    
    row = cursor.fetchone()
    if not row:
        return
    
    gid, end_time, outfeed = row
    
    # Write End_time_CIP
    cursor.execute("""
        UPDATE [Change paper brik]
        SET End_time_CIP = ?
        WHERE ID = ?
    """, end_time, gid)
    
    # Log to endtime_log_test
    cursor.execute("""
        INSERT INTO [endtime_log_test] (Machine, Step, Signal_CIP, Outfeed, End_Time, Log_Time)
        VALUES (?, 14, 1, ?, ?, ?)
    """, machine, str(outfeed), end_time, now)
    
    # Log to t_log
    cursor.execute("""
        INSERT INTO t_log (txt) VALUES (?)
    """, f"{machine}_S14:CIP=1:ID={gid}:Outfeed={outfeed}:EndTime={end_time}-PYTHON")
    
    conn.commit()
    
    # Update cooldown in memory
    cooldown_log[machine] = now
    print(f"[{machine}] Step 14 CIP — End_time_CIP written")

def handle_end_roll(machine, gid, splicing_count, last_splice_time, conn, table="Change paper brik", splice_cooldown=None):
    if splice_cooldown is None:
        splice_cooldown = {}
    splicing_count = int(splicing_count)
    now = datetime.utcnow()
    cursor = conn.cursor()
    
    # Check cooldown from memory
    last_entry = splice_cooldown.get(f"{machine}_{table}")
    if last_entry:
        last_time, last_count = last_entry  # unpack both time AND count
        diff_ms = (now - last_time).total_seconds() * 1000
        if 0 <= diff_ms < 30000:
            col = f"Splicing time {last_count + 1}"  # use stored count
            cursor.execute(f"""
                UPDATE [{table}]
                SET [{col}] = ?
                WHERE ID = ?
            """, now, gid)
            print(f"[{machine}] {table} COOLDOWN — rewrote {col}")
            conn.commit()
            return
    
    # New splice — store time AND new_count in cooldown
    new_count = splicing_count + 1
    col = f"Splicing time {new_count + 1}"
    splice_cooldown[f"{machine}_{table}"] = (now, new_count)  # store tuple
    
    cursor.execute(f"""
        UPDATE [{table}]
        SET [{col}] = ?,
            Splicing_Count = ?,
            Last_Splice_Time = ?
        WHERE ID = ?
    """, now, new_count, now, gid)
    
    conn.commit()
    print(f"[{machine}] End roll — wrote {col} | Splicing_Count updated to {new_count} | ID={gid}")