import sqlite3
import os
import datetime

DB_PATH = "oiss_data.db"

def init_db():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    
    # Donors / Servers table
    cursor.execute('''
    CREATE TABLE IF NOT EXISTS servers (
        uid TEXT PRIMARY KEY,
        name TEXT,
        is_public BOOLEAN,
        max_users INTEGER,
        time_limit_minutes INTEGER,
        data_limit_mb REAL,
        upvotes INTEGER DEFAULT 0,
        downvotes INTEGER DEFAULT 0,
        total_data_shared_mb REAL DEFAULT 0.0,
        current_connections INTEGER DEFAULT 0,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        is_active BOOLEAN DEFAULT 1
    )
    ''')

    # Admins table
    cursor.execute('''
    CREATE TABLE IF NOT EXISTS admins (
        email TEXT PRIMARY KEY,
        added_by TEXT,
        added_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )
    ''')

    # Blocklist table
    cursor.execute('''
    CREATE TABLE IF NOT EXISTS blocklist (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        identifier TEXT UNIQUE, -- Can be IP or Device ID
        reason TEXT,
        blocked_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )
    ''')

    conn.commit()
    conn.close()

def get_connection():
    return sqlite3.connect(DB_PATH)

# --- Server / Gamification Functions ---

def register_server(uid, name, is_public, max_users=100, time_limit_minutes=0, data_limit_mb=0):
    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute('''
        INSERT OR REPLACE INTO servers 
        (uid, name, is_public, max_users, time_limit_minutes, data_limit_mb, is_active)
        VALUES (?, ?, ?, ?, ?, ?, 1)
    ''', (uid, name, is_public, max_users, time_limit_minutes, data_limit_mb))
    conn.commit()
    conn.close()

def get_public_servers():
    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute('''
        SELECT uid, name, max_users, time_limit_minutes, data_limit_mb, upvotes, downvotes, current_connections 
        FROM servers 
        WHERE is_public = 1 AND is_active = 1
        ORDER BY upvotes DESC
    ''')
    rows = cursor.fetchall()
    conn.close()
    
    servers = []
    for row in rows:
        servers.append({
            "uid": row[0],
            "name": row[1],
            "max_users": row[2],
            "time_limit_minutes": row[3],
            "data_limit_mb": row[4],
            "upvotes": row[5],
            "downvotes": row[6],
            "current_connections": row[7]
        })
    return servers

def get_leaderboard():
    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute('''
        SELECT uid, name, upvotes, total_data_shared_mb 
        FROM servers 
        ORDER BY upvotes DESC, total_data_shared_mb DESC
        LIMIT 20
    ''')
    rows = cursor.fetchall()
    conn.close()
    
    leaderboard = []
    for idx, row in enumerate(rows):
        leaderboard.append({
            "rank": idx + 1,
            "uid": row[0],
            "name": row[1],
            "upvotes": row[2],
            "total_data_shared_mb": row[3]
        })
    return leaderboard

def update_server_stats(uid, data_transferred_bytes=0, connections_delta=0, upvote=False, downvote=False):
    conn = get_connection()
    cursor = conn.cursor()
    
    mb_transferred = data_transferred_bytes / (1024 * 1024)
    
    up_val = 1 if upvote else 0
    down_val = 1 if downvote else 0
    
    cursor.execute('''
        UPDATE servers 
        SET total_data_shared_mb = total_data_shared_mb + ?,
            current_connections = MAX(0, current_connections + ?),
            upvotes = upvotes + ?,
            downvotes = downvotes + ?
        WHERE uid = ?
    ''', (mb_transferred, connections_delta, up_val, down_val, uid))
    
    conn.commit()
    conn.close()

# --- Admin & Blocklist Functions ---

def is_blocked(identifier):
    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute('SELECT 1 FROM blocklist WHERE identifier = ?', (identifier,))
    result = cursor.fetchone()
    conn.close()
    return result is not None

def add_to_blocklist(identifier, reason=""):
    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute('INSERT OR IGNORE INTO blocklist (identifier, reason) VALUES (?, ?)', (identifier, reason))
    conn.commit()
    conn.close()

def is_admin(email):
    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute('SELECT 1 FROM admins WHERE email = ?', (email,))
    result = cursor.fetchone()
    conn.close()
    return result is not None

def add_admin(email, added_by):
    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute('INSERT OR IGNORE INTO admins (email, added_by) VALUES (?, ?)', (email, added_by))
    conn.commit()
    conn.close()

def get_all_admins():
    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute('SELECT email, added_by, added_at FROM admins')
    rows = cursor.fetchall()
    conn.close()
    return [{"email": r[0], "added_by": r[1], "added_at": r[2]} for r in rows]

def remove_admin(email):
    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute('DELETE FROM admins WHERE email = ?', (email,))
    conn.commit()
    conn.close()

def get_all_blocked_users():
    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute('SELECT id, identifier, reason, blocked_at FROM blocklist')
    rows = cursor.fetchall()
    conn.close()
    return [{"id": r[0], "identifier": r[1], "reason": r[2], "blocked_at": r[3]} for r in rows]

def remove_from_blocklist(identifier):
    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute('DELETE FROM blocklist WHERE identifier = ?', (identifier,))
    conn.commit()
    conn.close()
