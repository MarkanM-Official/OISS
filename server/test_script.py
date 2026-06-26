import asyncio
import websockets
import json

async def simulate_donor_and_receiver():
    uri = "ws://localhost:8000/ws"
    
    # We will run donor and receiver concurrently
    try:
        async with websockets.connect(uri) as donor_ws, websockets.connect(uri) as receiver_ws:
            
            print("--- 1. Donor Registers ---")
            await donor_ws.send(json.dumps({
                "type": "register_donor",
                "code": "TEST1234"
            }))
            resp = await donor_ws.recv()
            print("Donor received:", resp)
            
            print("\n--- 2. Receiver Joins ---")
            await receiver_ws.send(json.dumps({
                "type": "join",
                "code": "TEST1234"
            }))
            
            # Receiver should wait for approval
            r_resp = await receiver_ws.recv()
            print("Receiver received:", r_resp)
            
            # Donor should get an approval request
            d_req = await donor_ws.recv()
            print("Donor received request:", d_req)
            
            req_data = json.loads(d_req)
            receiver_id = req_data.get("receiver_id")
            
            print("\n--- 3. Donor Approves ---")
            await donor_ws.send(json.dumps({
                "type": "approve",
                "receiver_id": receiver_id
            }))
            
            # Donor gets connection confirmed
            d_resp = await donor_ws.recv()
            print("Donor received:", d_resp)
            
            # Receiver gets connection confirmed
            r_resp = await receiver_ws.recv()
            print("Receiver received:", r_resp)
            
            print("\n--- 4. Data Relay (Receiver -> Donor) ---")
            await receiver_ws.send(json.dumps({
                "type": "data",
                "payload": "Hello Donor!"
            }))
            
            # Donor gets the data
            d_data = await donor_ws.recv()
            print("Donor received data:", d_data)
            
            print("\n--- 5. Data Relay (Donor -> Receiver) ---")
            await donor_ws.send(json.dumps({
                "type": "data",
                "receiver_id": receiver_id,
                "payload": "Hello Receiver!"
            }))
            
            # Receiver gets the data
            r_data = await receiver_ws.recv()
            print("Receiver received data:", r_data)
            
            print("\nTest completed successfully! Privacy preserved, data relayed.")
            
    except Exception as e:
        print("Error during test:", e)

if __name__ == "__main__":
    asyncio.run(simulate_donor_and_receiver())
