# OISS Relay Server (Phase 0)

This is the Python FastAPI WebSocket Relay Server for the Open Internet Sharing System (OISS).

## Core Principles
- **Privacy First:** We NEVER store, log, or send IP addresses to the peers. All connections are identified by anonymous UUIDs kept only in memory.
- **Double-Blind Architecture:** Donors and Receivers never know each other's real identity or location.

## Quick Start

### 1. Install Dependencies
Make sure you have Python 3 installed. Run the following command:
```bash
pip install -r requirements.txt
```

### 2. Run the Server
Run the FastAPI server using Uvicorn:
```bash
uvicorn main:app --reload
```
The WebSocket endpoint will be available at `ws://localhost:8000/ws`.

## Test Section
To verify the system is working and privacy rules are upheld, we have provided a simple test script.

1. Ensure the server is running (Step 2 above) in one terminal.
2. Open a second terminal and run:
```bash
python test_script.py
```
This script simulates a Donor and a Receiver concurrently. It will:
- Register the donor.
- Join the receiver.
- Let the donor approve the receiver.
- Relay messages back and forth.
If successful, you will see the logs confirming that data was sent between peers securely.
