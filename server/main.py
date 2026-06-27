import json
import asyncio
import time
import os
import datetime
from fastapi import FastAPI, WebSocket, WebSocketDisconnect, HTTPException, Request, Form, Depends
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.templating import Jinja2Templates
from pydantic import BaseModel
from authlib.integrations.starlette_client import OAuth
from starlette.middleware.sessions import SessionMiddleware

from privacy import privacy_manager, logger
from relay_manager import relay_manager
import database
from google.oauth2 import id_token
from google.auth.transport import requests as google_requests
from google.oauth2.service_account import Credentials
from googleapiclient.discovery import build

# Initialize SQLite database
database.init_db()

app = FastAPI(title="OISS Backend Server")

# Secure session middleware for Authlib
app.add_middleware(SessionMiddleware, secret_key=os.getenv("SECRET_KEY", "super-secret-oiss-key"))

# Jinja2 Templates
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
templates = Jinja2Templates(directory=os.path.join(BASE_DIR, "templates"))

# Google OAuth Setup
oauth = OAuth()
oauth.register(
    name='google',
    client_id=os.getenv('GOOGLE_CLIENT_ID', ''),
    client_secret=os.getenv('GOOGLE_CLIENT_SECRET', ''),
    server_metadata_url='https://accounts.google.com/.well-known/openid-configuration',
    client_kwargs={
        'scope': 'openid email profile'
    }
)

ADMIN_EMAILS = ["markanm.official@gmail.com"]

connections = {}           # session_uuid -> WebSocket object
donors_by_code = {}        # code -> donor_session_uuid
receiver_state = {}        # receiver_session_uuid -> {"donor_uuid": uuid, "status": "pending" | "connected"}
donor_to_receivers = {}    # donor_session_uuid -> set of receiver_session_uuids
session_start_times = {}   

MAX_SESSION_DURATION = 4 * 3600
donor_limits = {} 

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

# --- WEB ADMIN ROUTES ---
@app.get("/", response_class=HTMLResponse)
async def root(request: Request):
    return templates.TemplateResponse(request=request, name="index.html")

@app.get("/admin", response_class=HTMLResponse)
async def admin_login(request: Request):
    user = request.session.get('user')
    if user:
        return RedirectResponse(url='/admin/dashboard')
    return templates.TemplateResponse(request=request, name="login.html")

@app.get("/admin/auth/login")
async def login(request: Request):
    if not os.getenv('GOOGLE_CLIENT_ID'):
        # Fallback for testing if Google OAuth is not configured
        request.session['user'] = {'email': 'markanm.official@gmail.com', 'name': 'OISS Admin'}
        return RedirectResponse(url='/admin/dashboard')
        
    redirect_uri = str(request.url_for('auth')).replace("http://", "https://")
    return await oauth.google.authorize_redirect(request, redirect_uri)

@app.get("/admin/auth")
async def auth(request: Request):
    token = await oauth.google.authorize_access_token(request)
    user = token.get('userinfo')
    if user:
        request.session['user'] = user
    return RedirectResponse(url='/admin/dashboard')

@app.get("/admin/logout")
async def logout(request: Request):
    request.session.pop('user', None)
    return RedirectResponse(url='/admin')

@app.get("/admin/dashboard", response_class=HTMLResponse)
async def admin_dashboard(request: Request):
    user = request.session.get('user')
    if not user:
        return RedirectResponse(url='/admin')
        
    if user['email'] not in ADMIN_EMAILS and not database.is_admin(user['email']):
        return HTMLResponse("<h1>Access Denied</h1><p>You are not an authorized OISS Administrator.</p>", status_code=403)
        
    active_connections = len(connections)
    total_public_servers = len(database.get_public_servers())
    leaderboard = database.get_leaderboard()
    admins_list = database.get_all_admins()
    blocked_list = database.get_all_blocked_users()
    
    # Pass active connections to template for direct messaging
    active_sessions = []
    for sid, _ in connections.items():
        name = "Unknown"
        if sid in donor_limits:
            name = "Donor Node"
        elif sid in receiver_state:
            name = "Receiver Client"
        elif sid in relay_manager.relays:
            name = "Relay Server"
        active_sessions.append({"id": sid, "name": name})
    
    return templates.TemplateResponse(
        request=request,
        name="dashboard.html",
        context={
            "user": user,
            "active_connections": active_connections,
            "total_servers": total_public_servers,
            "leaderboard": leaderboard,
            "admins": admins_list,
            "blocked_users": blocked_list,
            "active_sessions": active_sessions
        }
    )

@app.get("/admin/test_sheets")
async def test_sheets(request: Request):
    user = request.session.get('user')
    if not user or (user['email'] not in ADMIN_EMAILS and not database.is_admin(user['email'])):
        return HTMLResponse("<h1>Access Denied</h1>", status_code=403)
        
    try:
        from google.oauth2.service_account import Credentials
        from googleapiclient.discovery import build
        import json
        import os
        
        sheet_json = os.getenv("GOOGLE_SHEET_JSON")
        sheet_id = os.getenv("GOOGLE_SHEET_ID")
        
        if not sheet_json or not sheet_id:
            return HTMLResponse("<h1>Error: Missing Env Variables!</h1><p>GOOGLE_SHEET_JSON or GOOGLE_SHEET_ID is not set on Render.</p>")
            
        creds_dict = json.loads(sheet_json)
        creds = Credentials.from_service_account_info(creds_dict, scopes=['https://www.googleapis.com/auth/spreadsheets'])
        service = build('sheets', 'v4', credentials=creds)
        
        values = [["Test Time", "Test Name", "Test Email", "Test IP", "Test MAC", "Test Device"]]
        body = {'values': values}
        
        result = service.spreadsheets().values().append(
            spreadsheetId=sheet_id,
            range="Sheet1!A:F",
            valueInputOption="USER_ENTERED",
            body=body
        ).execute()
        
        return {"success": True, "message": "Written to sheets successfully! Check your spreadsheet.", "result": result}
    except Exception as e:
        return {"success": False, "error_details": str(e)}

@app.post("/admin/broadcast")
async def broadcast_notification(request: Request, message: str = Form(...)):
    user = request.session.get('user')
    if not user or (user['email'] not in ADMIN_EMAILS and not database.is_admin(user['email'])):
        return RedirectResponse(url='/admin')
        
    # Send broadcast to all connected websockets
    broadcast_msg = {
        "type": "admin_notification",
        "message": message
    }
    
    for session_id, ws in connections.items():
        try:
            asyncio.create_task(ws.send_text(json.dumps(broadcast_msg)))
        except:
            pass
            
    return RedirectResponse(url='/admin/dashboard?msg=Broadcast+Sent', status_code=303)

@app.post("/admin/api/add_admin")
async def add_new_admin(request: Request, email: str = Form(...)):
    user = request.session.get('user')
    if not user or (user['email'] not in ADMIN_EMAILS and not database.is_admin(user['email'])):
        return RedirectResponse(url='/admin')
    database.add_admin(email.strip(), user['email'])
    return RedirectResponse(url='/admin/dashboard?msg=Admin+Added', status_code=303)

@app.post("/admin/api/remove_admin")
async def remove_existing_admin(request: Request, email: str = Form(...)):
    user = request.session.get('user')
    if not user or (user['email'] not in ADMIN_EMAILS and not database.is_admin(user['email'])):
        return RedirectResponse(url='/admin')
    database.remove_admin(email.strip())
    return RedirectResponse(url='/admin/dashboard?msg=Admin+Removed', status_code=303)

@app.post("/admin/api/block_user")
async def block_user(request: Request, identifier: str = Form(...), reason: str = Form("")):
    user = request.session.get('user')
    if not user or (user['email'] not in ADMIN_EMAILS and not database.is_admin(user['email'])):
        return RedirectResponse(url='/admin')
    database.add_to_blocklist(identifier.strip(), reason.strip())
    
    # Disconnect immediately if they are connected
    ident = identifier.strip()
    if ident in connections:
        try:
            asyncio.create_task(connections[ident].close(code=1008, reason="Blocked by Administrator"))
        except:
            pass
            
    return RedirectResponse(url='/admin/dashboard?msg=User+Blocked', status_code=303)

@app.post("/admin/api/unblock_user")
async def unblock_user(request: Request, identifier: str = Form(...)):
    user = request.session.get('user')
    if not user or (user['email'] not in ADMIN_EMAILS and not database.is_admin(user['email'])):
        return RedirectResponse(url='/admin')
    database.remove_from_blocklist(identifier.strip())
    return RedirectResponse(url='/admin/dashboard?msg=User+Unblocked', status_code=303)

@app.post("/admin/api/message_user")
async def message_specific_user(request: Request, session_id: str = Form(...), message: str = Form(...)):
    user = request.session.get('user')
    if not user or (user['email'] not in ADMIN_EMAILS and not database.is_admin(user['email'])):
        return RedirectResponse(url='/admin')
    
    sid = session_id.strip()
    if sid in connections:
        dm = {
            "type": "admin_notification",
            "message": message
        }
        try:
            asyncio.create_task(connections[sid].send_text(json.dumps(dm)))
        except:
            pass
    return RedirectResponse(url='/admin/dashboard?msg=Message+Sent', status_code=303)

# --- App Token Flow (For Desktop/All Platforms) ---
import jwt

SECRET_KEY = os.getenv("SECRET_KEY", "super-secret-key-for-app-tokens")

@app.get("/app/login")
async def app_login(request: Request):
    redirect_uri = str(request.url_for('app_auth')).replace("http://", "https://")
    return await oauth.google.authorize_redirect(request, redirect_uri)

@app.get("/app/auth")
async def app_auth(request: Request):
    try:
        token = await oauth.google.authorize_access_token(request)
        user = token.get('userinfo')
        if not user:
            user = await oauth.google.parse_id_token(request, token)
            
        # Create a simple JWT token for the app
        app_token = jwt.encode(
            {"email": user.get("email"), "name": user.get("name"), "exp": datetime.datetime.utcnow() + datetime.timedelta(hours=1)},
            SECRET_KEY,
            algorithm="HS256"
        )
        
        html_content = f"""
        <html>
            <head>
                <title>OISS App Login</title>
                <style>
                    body {{ font-family: Arial, sans-serif; background-color: #121212; color: white; display: flex; flex-direction: column; align-items: center; justify-content: center; height: 100vh; margin: 0; }}
                    .box {{ background: #1E1E1E; padding: 40px; border-radius: 10px; text-align: center; box-shadow: 0 4px 10px rgba(0,0,0,0.5); }}
                    input {{ padding: 10px; width: 300px; font-size: 16px; margin: 20px 0; text-align: center; border-radius: 5px; border: none; }}
                    button {{ padding: 10px 20px; font-size: 16px; cursor: pointer; background: #2196F3; color: white; border: none; border-radius: 5px; }}
                </style>
            </head>
            <body>
                <div class="box">
                    <h2>Login Successful!</h2>
                    <p>Please copy the token below and paste it into the OISS App:</p>
                    <input type="text" id="tokenField" value="{app_token}" readonly>
                    <br>
                    <button onclick="copyToken()">Copy Token</button>
                    <script>
                        function copyToken() {{
                            var copyText = document.getElementById("tokenField");
                            copyText.select();
                            document.execCommand("copy");
                            alert("Token copied to clipboard! Now return to the OISS app.");
                        }}
                    </script>
                </div>
            </body>
        </html>
        """
        return HTMLResponse(content=html_content)
    except Exception as e:
        logger.error(f"App auth error: {e}")
        return HTMLResponse("<h1>Authentication Failed</h1>")

class TokenVerifyRequest(BaseModel):
    id_token: str
    mac_address: str = ""
    device_name: str = ""

@app.post("/api/auth/verify_token")
async def verify_flutter_token(req: TokenVerifyRequest, request: Request):
    try:
        # Decode the custom JWT token
        payload = jwt.decode(req.id_token, SECRET_KEY, algorithms=["HS256"])
        email = payload.get("email", "")
        name = payload.get("name", "")
        
        # Log to Google Sheets
        sheet_json = os.getenv("GOOGLE_SHEET_JSON")
        sheet_id = os.getenv("GOOGLE_SHEET_ID")
        if sheet_json and sheet_id:
            try:
                creds_dict = json.loads(sheet_json)
                creds = Credentials.from_service_account_info(creds_dict, scopes=['https://www.googleapis.com/auth/spreadsheets'])
                service = build('sheets', 'v4', credentials=creds)
                
                client_ip = request.client.host if request.client else "unknown"
                now_str = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                
                # Check for duplicates
                result = service.spreadsheets().values().get(
                    spreadsheetId=sheet_id,
                    range="Sheet1!C:C"
                ).execute()
                
                existing_emails = [row[0] for row in result.get('values', []) if row]
                
                if email not in existing_emails:
                    values = [[now_str, name, email, client_ip, req.mac_address, req.device_name]]
                    body = {'values': values}
                    
                    service.spreadsheets().values().append(
                        spreadsheetId=sheet_id,
                        range="Sheet1!A:F",
                        valueInputOption="USER_ENTERED",
                        body=body
                    ).execute()
            except Exception as e:
                logger.error(f"Failed to log to Google Sheets: {e}")
                
        return {"status": "success", "email": email, "name": name}
    except ValueError:
        raise HTTPException(status_code=401, detail="Invalid token")

@app.get("/api/servers")
def get_public_servers():
    # Temporarily disabled due to security review
    return []

@app.get("/api/leaderboard")
def get_leaderboard():
    return database.get_leaderboard()

# --- WEBSOCKET ---
@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    client_host = websocket.client.host if websocket.client else "unknown"
    
    if database.is_blocked(client_host):
        await websocket.accept()
        await websocket.close(code=1008, reason="Your device/IP is blocked.")
        return

    if not privacy_manager.check_connection_rate_limit(client_host):
        await websocket.accept()
        await websocket.close(code=1008, reason="Rate limit exceeded")
        return
        
    await websocket.accept()
    session_id = privacy_manager.mask_client(client_host)
    del client_host  
    
    if database.is_blocked(session_id):
        await websocket.close(code=1008, reason="Your device/IP is blocked.")
        return

    connections[session_id] = websocket
    session_start_times[session_id] = time.time()
    
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
                code = str(msg.get("code", "")).strip()
                is_public = msg.get("is_public", False)
                name = msg.get("name", "Anonymous OISS Node")
                max_users = msg.get("max_users", 100)
                time_limit = msg.get("time_limit_minutes", 0)
                data_limit = msg.get("data_limit_mb", 0.0)

                donors_by_code[code] = session_id
                donor_to_receivers[session_id] = set()
                donor_limits[session_id] = {
                    "max_users": max_users,
                    "data_limit_mb": data_limit,
                    "used_mb": 0.0,
                    "time_limit_minutes": time_limit,
                    "is_public": is_public
                }
                
                database.register_server(
                    uid=session_id, 
                    name=name, 
                    is_public=is_public, 
                    max_users=max_users, 
                    time_limit_minutes=time_limit, 
                    data_limit_mb=data_limit
                )
                
                relay_manager.assign_relay(session_id)
                await websocket.send_text(json.dumps({"type": "registered", "code": code, "uid": session_id}))
                
            # --- RECEIVER JOIN HANDLER ---
            elif msg_type == "join":
                if not privacy_manager.check_wrong_code_limit(session_id):
                    await websocket.close(code=1008, reason="Too many wrong attempts")
                    break
                    
                code = str(msg.get("code", "")).strip()
                
                donor_uuid = donors_by_code.get(code)
                if not donor_uuid and code in donor_to_receivers:
                    donor_uuid = code
                
                if not donor_uuid:
                    privacy_manager.record_wrong_code(session_id)
                    await websocket.send_text(json.dumps({"type": "error", "message": "Invalid code"}))
                    continue
                
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
                        database.update_server_stats(session_id, connections_delta=1)
                        await send_routed_message(session_id, {"type": "connected", "peer": receiver_id})
                        await send_routed_message(receiver_id, {"type": "connected"})
                            
            elif msg_type == "reject":
                receiver_id = msg.get("receiver_id")
                if session_id in donor_to_receivers and receiver_id in receiver_state:
                    if receiver_state[receiver_id]["donor_uuid"] == session_id:
                        await send_routed_message(receiver_id, {"type": "rejected"})
                        del receiver_state[receiver_id]
                        
            # --- DATA TRANSFER HANDLER ---
            elif msg_type in ["data", "file_transfer", "proxy_connect", "proxy_connected", "proxy_data", "proxy_disconnect"]:
                payload = msg.get("payload", "")
                filename = msg.get("filename") 
                
                data_bytes = len(payload)
                mb_size = data_bytes / (1024 * 1024)
                
                donor_uuid = None
                if session_id in donor_to_receivers:
                    donor_uuid = session_id
                elif session_id in receiver_state:
                    donor_uuid = receiver_state[session_id]["donor_uuid"]
                
                if donor_uuid and donor_uuid in donor_limits:
                    limits = donor_limits[donor_uuid]
                    limits["used_mb"] += mb_size
                    database.update_server_stats(donor_uuid, data_transferred_bytes=data_bytes)
                    
                    if limits["data_limit_mb"] > 0 and limits["used_mb"] >= limits["data_limit_mb"]:
                        await send_routed_message(donor_uuid, {"type": "error", "message": "Data limit reached."})
                        for r_id in list(donor_to_receivers[donor_uuid]):
                            await send_routed_message(r_id, {"type": "error", "message": "Host data limit reached."})
                            if r_id in connections:
                                await connections[r_id].close(code=1008, reason="Host data limit reached")
                        
                        if donor_uuid in connections:
                            await connections[donor_uuid].close(code=1008, reason="Data limit reached")
                        continue

                msg_to_send = msg.copy()
                
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
        privacy_manager.clean_session(session_id)
        relay_manager.remove_relay(session_id)
        
        if session_id in session_start_times:
            del session_start_times[session_id]
            
        if session_id in connections:
            del connections[session_id]
            
        if session_id in donor_to_receivers:
            database.register_server(session_id, name="", is_public=False)
            receivers = donor_to_receivers[session_id]
            for r_id in list(receivers):
                asyncio.create_task(send_routed_message(r_id, {"type": "donor_disconnected"}))
            
            codes_to_delete = [c for c, d in donors_by_code.items() if d == session_id]
            for c in codes_to_delete:
                del donors_by_code[c]
            del donor_to_receivers[session_id]
            if session_id in donor_limits:
                del donor_limits[session_id]
            
        if session_id in receiver_state:
            donor_uuid = receiver_state[session_id]["donor_uuid"]
            if donor_uuid in donor_to_receivers and session_id in donor_to_receivers[donor_uuid]:
                donor_to_receivers[donor_uuid].remove(session_id)
                database.update_server_stats(donor_uuid, connections_delta=-1)
            del receiver_state[session_id]
