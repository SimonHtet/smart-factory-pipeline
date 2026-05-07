from db import get_connection

conn = get_connection()
cursor = conn.cursor()
cursor.execute("SELECT Machine, Machine_Step_no, Signal_Final_CIP FROM T_M_Filler_Process ORDER BY Machine")
for row in cursor.fetchall():
    print(row.Machine, "= Step", row.Machine_Step_no, "| CIP =", row.Signal_Final_CIP)