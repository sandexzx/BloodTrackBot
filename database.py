import sqlite3
from datetime import datetime
from typing import List, Tuple

class Database:
    def __init__(self, db_file: str = "blood_pressure.db"):
        self.db_file = db_file
        self.init_db()

    def init_db(self):
        """Initialize database and create tables if they don't exist"""
        conn = sqlite3.connect(self.db_file)
        c = conn.cursor()
        c.execute('''
            CREATE TABLE IF NOT EXISTS measurements (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER NOT NULL,
                systolic INTEGER NOT NULL,
                diastolic INTEGER NOT NULL,
                pulse INTEGER NOT NULL,
                timestamp DATETIME NOT NULL
            )
        ''')
        conn.commit()
        conn.close()

    def add_measurement(self, user_id: int, systolic: int, diastolic: int, pulse: int) -> None:
        """Add new measurement to database"""
        conn = sqlite3.connect(self.db_file)
        c = conn.cursor()
        c.execute(
            "INSERT INTO measurements (user_id, systolic, diastolic, pulse, timestamp) VALUES (?, ?, ?, ?, ?)",
            (user_id, systolic, diastolic, pulse, datetime.now())
        )
        conn.commit()
        conn.close()

    def get_user_measurements(self, user_id: int, limit: int = 10) -> List[Tuple]:
        """Get last measurements for specific user"""
        conn = sqlite3.connect(self.db_file)
        c = conn.cursor()
        c.execute(
            "SELECT systolic, diastolic, pulse, timestamp FROM measurements "
            "WHERE user_id = ? ORDER BY timestamp DESC LIMIT ?",
            (user_id, limit)
        )
        measurements = c.fetchall()
        conn.close()
        return measurements

    def get_user_statistics(self, user_id: int) -> dict:
        """Get statistics for specific user"""
        conn = sqlite3.connect(self.db_file)
        c = conn.cursor()
        
        # Get average values
        c.execute("""
            SELECT 
                AVG(systolic) as avg_systolic,
                AVG(diastolic) as avg_diastolic,
                AVG(pulse) as avg_pulse
            FROM measurements 
            WHERE user_id = ?
        """, (user_id,))
        averages = c.fetchone()
        
        # Get min/max values
        c.execute("""
            SELECT 
                MIN(systolic) as min_systolic,
                MAX(systolic) as max_systolic,
                MIN(diastolic) as min_diastolic,
                MAX(diastolic) as max_diastolic,
                MIN(pulse) as min_pulse,
                MAX(pulse) as max_pulse
            FROM measurements 
            WHERE user_id = ?
        """, (user_id,))
        min_max = c.fetchone()
        
        conn.close()
        
        return {
            "averages": {
                "systolic": round(averages[0], 1) if averages[0] else None,
                "diastolic": round(averages[1], 1) if averages[1] else None,
                "pulse": round(averages[2], 1) if averages[2] else None
            },
            "min_max": {
                "systolic": {"min": min_max[0], "max": min_max[1]},
                "diastolic": {"min": min_max[2], "max": min_max[3]},
                "pulse": {"min": min_max[4], "max": min_max[5]}
            }
        }

    def get_all_user_measurements(self, user_id: int) -> List[Tuple]:
        """Get all measurements for specific user"""
        conn = sqlite3.connect(self.db_file)
        c = conn.cursor()
        c.execute(
            "SELECT systolic, diastolic, pulse, timestamp FROM measurements "
            "WHERE user_id = ? ORDER BY timestamp DESC",
            (user_id,)
        )
        measurements = c.fetchall()
        conn.close()
        return measurements 