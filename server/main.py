import json
import asyncio
import time
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from privacy import privacy_manager, logger
from relay_manager import relay_manager

app = FastAPI(title="OISS Relay Server")

connections = {}           # session_uuid -> WebSocket object
donors_by_code = {}        # code -> donor_session_uuid
receiver_state = {}        # receiver_session_uuid -> {"donor_uuid": uuid, "status": "pending" | "connected"}
donor_to_receivers = {}    # donor_session_uuid -> set of receiver_session_uuids
session_start_times = {}   

MAX_SESSION_DURATION = 4 * 3600

async def send_routed_message(target_session_id: str, message: dict):
    """
    Sends a message to the target. If the target is assigned a relay,
    routes the message through the relay node first.
    """
    relay_id = relay_manager.get_relay_for_session(target_session_id)
    if relay_id and relay_id in connections:
        relay_ws = connections[relay_id]
        # Wrap message for relay
        wrapped_msg = {
            "type": "relay_forward",
            "target_id": target_session_id,
            "payload": message
        }
        await relay_ws.send_text(json.dumps(wrapped_msg))
    else:
        # Direct route (fallback or no relays active)
        target_ws = connections.get(target_session_id)
        if target_ws:
            await target_ws.send_text(json.dumps(message))

@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    client_host = websocket.client.host if websocket.client else "unknown"
    
    if not privacy_manager.check_connection_rate_limit(client_host):
        await websocket.accept()
        await websocket.close(code=1008, reason="Rate limit exceeded")
        return
        
    await websocket.accept()
    session_id = privacy_manager.mask_client(client_host)
    del client_host  
    
    connections[session_id] = websocket
    session_start_times[session_id] = time.time()
    logger.info(f"sess_{session_id} | client_connected")
    
    try:
        while True:
            if time.time() - session_start_times.get(session_id, 0) > MAX_SESSION_DURATION:
                await websocket.close(code=1008, reason="Session max duration reached")
                break
                
            data = await websocket.receive_text()
            try:
                msg = json.loads(data)
            except json.JSONDecodeError:
                continue
                
            msg_type = msg.get("type")
            
            # --- 0. RELAY NODE HANDLERS ---
            if msg_type == "register_relay":
                relay_manager.register_relay(session_id)
                await websocket.send_text(json.dumps({"type": "relay_registered"}))
                
            elif msg_type == "relay_forwarded":
                # Relay sends the wrapped packet back to be delivered
                target_id = msg.get("target_id")
                payload = msg.get("payload")
                target_ws = connections.get(target_id)
                if target_ws:
                    await target_ws.send_text(json.dumps(payload))
            
            # --- 1. REGISTER DONOR HANDLER ---
            elif msg_type == "register_donor":
                code = msg.get("code")
                if not code:
                    continue
                donors_by_code[code] = session_id
                donor_to_receivers[session_id] = set()
                
                # Assign a relay to donor if available
                relay_manager.assign_relay(session_id)
                
                logger.info(f"sess_{session_id} | registered_donor")
                await websocket.send_text(json.dumps({"type": "registered", "code": code}))
                
            # --- 2. JOIN HANDLER ---
            elif msg_type == "join":
                if not privacy_manager.check_wrong_code_limit(session_id):
                    await websocket.close(code=1008, reason="Too many wrong attempts")
                    break
                    
                code = msg.get("code")
                donor_uuid = donors_by_code.get(code)
                
                if not donor_uuid:
                    privacy_manager.record_wrong_code(session_id)
                    await websocket.send_text(json.dumps({"type": "error", "message": "Invalid code"}))
                    continue
                
                # Assign relay to receiver
                relay_manager.assign_relay(session_id)
                
                receiver_state[session_id] = {"donor_uuid": donor_uuid, "status": "pending"}
                await send_routed_message(session_id, {"type": "waiting_approval"})
                
                await send_routed_message(donor_uuid, {
                    "type": "approval_request",
                    "receiver_id": session_id
                })
                    
            # --- 3. APPROVE / REJECT HANDLER ---
            elif msg_type == "approve":
                receiver_id = msg.get("receiver_id")
                if session_id in donor_to_receivers and receiver_id in receiver_state:
                    state = receiver_state[receiver_id]
                    if state["donor_uuid"] == session_id:
                        state["status"] = "connected"
                        donor_to_receivers[session_id].add(receiver_id)
                        
                        await send_routed_message(session_id, {"type": "connected", "peer": receiver_id})
                        await send_routed_message(receiver_id, {"type": "connected"})
                            
            elif msg_type == "reject":
                receiver_id = msg.get("receiver_id")
                if session_id in donor_to_receivers and receiver_id in receiver_state:
                    if receiver_state[receiver_id]["donor_uuid"] == session_id:
                        await send_routed_message(receiver_id, {"type": "rejected"})
                        del receiver_state[receiver_id]
                        
            # --- 4. DATA RELAY HANDLER ---
            elif msg_type == "data" or msg_type == "file_transfer":
                payload = msg.get("payload")
                filename = msg.get("filename") # Only present for file_transfer
                
                msg_to_send = {
                    "type": msg_type, 
                    "payload": payload
                }
                if filename:
                    msg_to_send["filename"] = filename
                
                if session_id in donor_to_receivers:
                    target_receiver_id = msg.get("receiver_id")
                    if target_receiver_id and target_receiver_id in donor_to_receivers[session_id]:
                        await send_routed_message(target_receiver_id, msg_to_send)
                            
                elif session_id in receiver_state and receiver_state[session_id]["status"] == "connected":
                    donor_uuid = receiver_state[session_id]["donor_uuid"]
                    msg_to_send["receiver_id"] = session_id
                    await send_routed_message(donor_uuid, msg_to_send)

    except WebSocketDisconnect:
        pass
        
    finally:
        logger.info(f"sess_{session_id} | client_disconnected")
        
        # Clean up
        privacy_manager.clean_session(session_id)
        relay_manager.remove_relay(session_id)
        
        if session_id in session_start_times:
            del session_start_times[session_id]
            
        if session_id in connections:
            del connections[session_id]
            
        if session_id in donor_to_receivers:
            receivers = donor_to_receivers[session_id]
            for r_id in list(receivers):
                asyncio.create_task(send_routed_message(r_id, {"type": "donor_disconnected"}))
            
            codes_to_delete = [c for c, d in donors_by_code.items() if d == session_id]
            for c in codes_to_delete:
                del donors_by_code[c]
            del donor_to_receivers[session_id]
            
        if session_id in receiver_state:
            donor_uuid = receiver_state[session_id]["donor_uuid"]
            if donor_uuid in donor_to_receivers and session_id in donor_to_receivers[donor_uuid]:
                donor_to_receivers[donor_uuid].remove(session_id)
            del receiver_state[session_id]
