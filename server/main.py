import json
import asyncio
import time
from fastapi import FastAPI, WebSocket, WebSocketDisconnect, HTTPException
from pydantic import BaseModel
from privacy import privacy_manager, logger
from relay_manager import relay_manager
import database

# Initialize SQLite database
database.init_db()

app = FastAPI(title="OISS Backend Server")

connections = {}           # session_uuid -> WebSocket object
donors_by_code = {}        # code -> donor_session_uuid
receiver_state = {}        # receiver_session_uuid -> {"donor_uuid": uuid, "status": "pending" | "connected"}
donor_to_receivers = {}    # donor_session_uuid -> set of receiver_session_uuids
session_start_times = {}   

MAX_SESSION_DURATION = 4 * 3600

# Gamification Trackers (In-memory cache for data usage before writing to DB)
donor_limits = {} # donor_session_uuid -> {"max_users": int, "data_limit_mb": float, "used_mb": float, "time_limit_minutes": int, "is_public": bool}

async def send_routed_message(target_session_id: str, message: dict):
    relay_id = relay_manager.get_relay_for_session(target_session_id)
    if relay_id and relay_id in connections:
        relay_ws = connections[relay_id]
        wrapped_msg = {
            "type": "relay_forward",
            "target_id": target_session_id,
            "payload": message
        }
        await relay_ws.send_text(json.dumps(wrapped_msg))
    else:
        target_ws = connections.get(target_session_id)
        if target_ws:
            await target_ws.send_text(json.dumps(message))

# --- REST APIs ---
@app.get("/api/servers")
def get_public_servers():
    return database.get_public_servers()

@app.get("/api/leaderboard")
def get_leaderboard():
    return database.get_leaderboard()

# --- WEBSOCKET ---
@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    client_host = websocket.client.host if websocket.client else "unknown"
    
    # 1. Blocklist Check
    if database.is_blocked(client_host):
        await websocket.accept()
        await websocket.close(code=1008, reason="Your device/IP is blocked from the OISS network.")
        return

    # 2. Rate Limit Check
    if not privacy_manager.check_connection_rate_limit(client_host):
        await websocket.accept()
        await websocket.close(code=1008, reason="Rate limit exceeded")
        return
        
    await websocket.accept()
    session_id = privacy_manager.mask_client(client_host)
    del client_host  
    
    # Blocklist check by masked session id as well
    if database.is_blocked(session_id):
        await websocket.close(code=1008, reason="Your device/IP is blocked from the OISS network.")
        return

    connections[session_id] = websocket
    session_start_times[session_id] = time.time()
    logger.info(f"sess_{session_id} | client_connected")
    
    try:
        while True:
            # Check Master Time Limit
            if time.time() - session_start_times.get(session_id, 0) > MAX_SESSION_DURATION:
                await websocket.close(code=1008, reason="Session max duration reached")
                break
                
            data = await websocket.receive_text()
            try:
                msg = json.loads(data)
            except json.JSONDecodeError:
                continue
                
            msg_type = msg.get("type")
            
            # --- RELAY NODE ---
            if msg_type == "register_relay":
                relay_manager.register_relay(session_id)
                await websocket.send_text(json.dumps({"type": "relay_registered"}))
                
            elif msg_type == "relay_forwarded":
                target_id = msg.get("target_id")
                payload = msg.get("payload")
                target_ws = connections.get(target_id)
                if target_ws:
                    await target_ws.send_text(json.dumps(payload))
            
            # --- DONOR HANDLER ---
            elif msg_type == "register_donor":
                code = msg.get("code")
                is_public = msg.get("is_public", False)
                name = msg.get("name", "Anonymous OISS Node")
                max_users = msg.get("max_users", 100)
                time_limit = msg.get("time_limit_minutes", 0)
                data_limit = msg.get("data_limit_mb", 0.0)

                # Store session details
                donors_by_code[code] = session_id
                donor_to_receivers[session_id] = set()
                donor_limits[session_id] = {
                    "max_users": max_users,
                    "data_limit_mb": data_limit,
                    "used_mb": 0.0,
                    "time_limit_minutes": time_limit,
                    "is_public": is_public
                }
                
                # Register in SQLite (For Global Directory & Leaderboard)
                database.register_server(
                    uid=session_id, 
                    name=name, 
                    is_public=is_public, 
                    max_users=max_users, 
                    time_limit_minutes=time_limit, 
                    data_limit_mb=data_limit
                )
                
                relay_manager.assign_relay(session_id)
                logger.info(f"sess_{session_id} | registered_donor")
                await websocket.send_text(json.dumps({"type": "registered", "code": code, "uid": session_id}))
                
            # --- RECEIVER JOIN HANDLER ---
            elif msg_type == "join":
                if not privacy_manager.check_wrong_code_limit(session_id):
                    await websocket.close(code=1008, reason="Too many wrong attempts")
                    break
                    
                code = msg.get("code")
                
                # Check if it's a pairing code OR a direct UUID (from Public Servers)
                donor_uuid = donors_by_code.get(code)
                if not donor_uuid and code in donor_to_receivers:
                    donor_uuid = code

                
                if not donor_uuid:
                    privacy_manager.record_wrong_code(session_id)
                    await websocket.send_text(json.dumps({"type": "error", "message": "Invalid code"}))
                    continue
                
                # Check Donor limits before joining
                limits = donor_limits.get(donor_uuid)
                if limits:
                    if len(donor_to_receivers.get(donor_uuid, set())) >= limits["max_users"]:
                        await websocket.send_text(json.dumps({"type": "error", "message": "Server is full"}))
                        continue

                relay_manager.assign_relay(session_id)
                receiver_state[session_id] = {"donor_uuid": donor_uuid, "status": "pending"}
                
                await send_routed_message(session_id, {"type": "waiting_approval"})
                await send_routed_message(donor_uuid, {"type": "approval_request", "receiver_id": session_id})
                    
            # --- APPROVE / REJECT HANDLER ---
            elif msg_type == "approve":
                receiver_id = msg.get("receiver_id")
                if session_id in donor_to_receivers and receiver_id in receiver_state:
                    state = receiver_state[receiver_id]
                    if state["donor_uuid"] == session_id:
                        state["status"] = "connected"
                        donor_to_receivers[session_id].add(receiver_id)
                        
                        # Update DB connections count
                        database.update_server_stats(session_id, connections_delta=1)

                        await send_routed_message(session_id, {"type": "connected", "peer": receiver_id})
                        await send_routed_message(receiver_id, {"type": "connected"})
                            
            elif msg_type == "reject":
                receiver_id = msg.get("receiver_id")
                if session_id in donor_to_receivers and receiver_id in receiver_state:
                    if receiver_state[receiver_id]["donor_uuid"] == session_id:
                        await send_routed_message(receiver_id, {"type": "rejected"})
                        del receiver_state[receiver_id]
                        
            # --- UPVOTE / DOWNVOTE ---
            elif msg_type == "vote":
                donor_uuid = msg.get("donor_uuid")
                vote_type = msg.get("vote_type")
                if donor_uuid:
                    if vote_type == "up":
                        database.update_server_stats(donor_uuid, upvote=True)
                    elif vote_type == "down":
                        database.update_server_stats(donor_uuid, downvote=True)

            # --- DATA TRANSFER HANDLER ---
            elif msg_type == "data" or msg_type == "file_transfer":
                payload = msg.get("payload", "")
                filename = msg.get("filename") 
                
                # Calculate bytes (approximate payload length in bytes)
                data_bytes = len(payload)
                mb_size = data_bytes / (1024 * 1024)
                
                # Find the donor session associated with this transfer
                donor_uuid = None
                if session_id in donor_to_receivers:
                    donor_uuid = session_id
                elif session_id in receiver_state:
                    donor_uuid = receiver_state[session_id]["donor_uuid"]
                
                # Check data limits
                if donor_uuid and donor_uuid in donor_limits:
                    limits = donor_limits[donor_uuid]
                    limits["used_mb"] += mb_size
                    
                    # Update SQLite Total Data Shared asynchronously
                    database.update_server_stats(donor_uuid, data_transferred_bytes=data_bytes)
                    
                    if limits["data_limit_mb"] > 0 and limits["used_mb"] >= limits["data_limit_mb"]:
                        # Limit exceeded! Disconnect everyone.
                        await send_routed_message(donor_uuid, {"type": "error", "message": "Data limit reached."})
                        for r_id in list(donor_to_receivers[donor_uuid]):
                            await send_routed_message(r_id, {"type": "error", "message": "Host data limit reached."})
                            if r_id in connections:
                                await connections[r_id].close(code=1008, reason="Host data limit reached")
                        
                        if donor_uuid in connections:
                            await connections[donor_uuid].close(code=1008, reason="Data limit reached")
                        continue

                # Forward message
                msg_to_send = {"type": msg_type, "payload": payload}
                if filename:
                    msg_to_send["filename"] = filename
                
                if session_id in donor_to_receivers:
                    target_receiver_id = msg.get("receiver_id")
                    if target_receiver_id and target_receiver_id in donor_to_receivers[session_id]:
                        await send_routed_message(target_receiver_id, msg_to_send)
                            
                elif session_id in receiver_state and receiver_state[session_id]["status"] == "connected":
                    msg_to_send["receiver_id"] = session_id
                    await send_routed_message(donor_uuid, msg_to_send)

    except WebSocketDisconnect:
        pass
        
    finally:
        logger.info(f"sess_{session_id} | client_disconnected")
        
        privacy_manager.clean_session(session_id)
        relay_manager.remove_relay(session_id)
        
        if session_id in session_start_times:
            del session_start_times[session_id]
            
        if session_id in connections:
            del connections[session_id]
            
        # If donor disconnected
        if session_id in donor_to_receivers:
            database.register_server(session_id, name="", is_public=False) # Simplistic way to deactivate, better is updating is_active
            
            receivers = donor_to_receivers[session_id]
            for r_id in list(receivers):
                asyncio.create_task(send_routed_message(r_id, {"type": "donor_disconnected"}))
            
            codes_to_delete = [c for c, d in donors_by_code.items() if d == session_id]
            for c in codes_to_delete:
                del donors_by_code[c]
            del donor_to_receivers[session_id]
            if session_id in donor_limits:
                del donor_limits[session_id]
            
        # If receiver disconnected
        if session_id in receiver_state:
            donor_uuid = receiver_state[session_id]["donor_uuid"]
            if donor_uuid in donor_to_receivers and session_id in donor_to_receivers[donor_uuid]:
                donor_to_receivers[donor_uuid].remove(session_id)
                database.update_server_stats(donor_uuid, connections_delta=-1)
            del receiver_state[session_id]
