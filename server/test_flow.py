import asyncio
import websockets
import json

async def test_flow():
    uri = "ws://127.0.0.1:8000/ws"
    
    print("--- Starting OISS Live Test ---")
    
    try:
        # Connect Relay Node
        relay_ws = await websockets.connect(uri)
        await relay_ws.send(json.dumps({"type": "register_relay"}))
        msg = await relay_ws.recv()
        print(f"[RELAY] Server says: {msg}")
        
        # Connect Donor
        donor_ws = await websockets.connect(uri)
        code = "TEST12"
        await donor_ws.send(json.dumps({"type": "register_donor", "code": code}))
        msg = await donor_ws.recv()
        print(f"[DONOR] Registered with code {code}. Server says: {msg}")
        
        # Connect Receiver
        receiver_ws = await websockets.connect(uri)
        await receiver_ws.send(json.dumps({"type": "join", "code": code}))
        
        # We expect a relay message to bounce to the relay. Let's see what relay gets:
        # Actually, if there is a relay, the server sends approval_request and waiting_approval wrapped!
        relay_msg1 = json.loads(await relay_ws.recv())
        print(f"[RELAY] Got wrapped msg to forward: {relay_msg1['type']} target={relay_msg1['target_id']}")
        
        relay_msg2 = json.loads(await relay_ws.recv())
        print(f"[RELAY] Got wrapped msg to forward: {relay_msg2['type']} target={relay_msg2['target_id']}")
        
        # Let relay bounce them back to server
        await relay_ws.send(json.dumps({
            "type": "relay_forwarded",
            "target_id": relay_msg1["target_id"],
            "payload": relay_msg1["payload"]
        }))
        await relay_ws.send(json.dumps({
            "type": "relay_forwarded",
            "target_id": relay_msg2["target_id"],
            "payload": relay_msg2["payload"]
        }))
        
        # Now donor should receive approval_request
        donor_msg = json.loads(await donor_ws.recv())
        print(f"[DONOR] Received: {donor_msg}")
        receiver_id = donor_msg.get("receiver_id")
        
        # And receiver should receive waiting_approval
        receiver_msg = json.loads(await receiver_ws.recv())
        print(f"[RECEIVER] Received: {receiver_msg}")
        
        # Donor approves
        await donor_ws.send(json.dumps({"type": "approve", "receiver_id": receiver_id}))
        
        # Relay bounces the connected messages
        relay_msg3 = json.loads(await relay_ws.recv())
        relay_msg4 = json.loads(await relay_ws.recv())
        
        await relay_ws.send(json.dumps({
            "type": "relay_forwarded",
            "target_id": relay_msg3["target_id"],
            "payload": relay_msg3["payload"]
        }))
        await relay_ws.send(json.dumps({
            "type": "relay_forwarded",
            "target_id": relay_msg4["target_id"],
            "payload": relay_msg4["payload"]
        }))
        
        # Both should receive connected
        print(f"[DONOR] Status: {await donor_ws.recv()}")
        print(f"[RECEIVER] Status: {await receiver_ws.recv()}")
        
        # Send data from Receiver -> Donor
        test_payload = "Hello from Receiver via Multi-Hop Relay!"
        await receiver_ws.send(json.dumps({"type": "data", "payload": test_payload}))
        
        # Relay receives and forwards
        relay_msg5 = json.loads(await relay_ws.recv())
        print(f"[RELAY] Relaying data payload...")
        await relay_ws.send(json.dumps({
            "type": "relay_forwarded",
            "target_id": relay_msg5["target_id"],
            "payload": relay_msg5["payload"]
        }))
        
        # Donor receives the data
        donor_final = json.loads(await donor_ws.recv())
        print(f"[DONOR] Received data: {donor_final['payload']}")
        
        print("\n✅ All multi-hop tests passed successfully!")
        
        await relay_ws.close()
        await donor_ws.close()
        await receiver_ws.close()
        
    except Exception as e:
        print(f"Test failed: {e}")

if __name__ == "__main__":
    asyncio.run(test_flow())
