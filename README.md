# Open Internet Sharing System (OISS)

![License](https://img.shields.io/badge/license-GPLv3-blue.svg)
![Platform](https://img.shields.io/badge/platform-Android%20%7C%20iOS%20%7C%20Web%20%7C%20Desktop-lightgrey)

OISS is an open-source platform that enables users to securely and anonymously share their internet connection. Designed with privacy as the core principle, OISS uses WebSockets to relay data between a Donor and a Receiver without exposing IP addresses or logging sensitive data.

## Features
- **Privacy First:** IP addresses are masked immediately into anonymous UUIDs.
- **Cross-Platform:** Works on Android, iOS, Windows, macOS, Linux, and Web (built with Flutter).
- **Donor Controls:** Set custom speed limits, data caps, connection limits, and timers.
- **Secure Relay:** Python backend limits connection attempts and implements robust rate limiting.

## Project Structure
- `app/` - The Flutter frontend.
- `server/` - The Python FastAPI WebSocket relay backend.
- `build_all.sh` - Automated script to build across platforms.

## Quick Start

### 1. Run the Backend
```bash
cd server
pip install -r requirements.txt
uvicorn main:app --host 0.0.0.1 --port 8000
```

### 2. Run the App
```bash
cd app
flutter pub get
flutter run
```

## Contributing
We welcome all contributions! Please read `CONTRIBUTING.md` before making pull requests. Be sure to respect the rules in `CODE_OF_CONDUCT.md`.

## Security
If you find any vulnerabilities, do not open a public issue. See `SECURITY.md` for reporting instructions.

## License
This project is licensed under the GNU GPL v3 License - see the `LICENSE` file for details.
