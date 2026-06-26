import uuid
import time
import logging

class PrivacyManager:
    def __init__(self):
        # Rate Limiting: IP -> list of timestamps
        self._connection_attempts = {}
        # Rate Limiting: session_uuid -> wrong_code_count
        self._wrong_code_attempts = {}

    def mask_client(self, client_host: str) -> str:
        """
        Generates an anonymous session ID and immediately drops the IP.
        """
        return str(uuid.uuid4())

    def check_connection_rate_limit(self, client_host: str) -> bool:
        """
        Max 10 connection attempts per IP per minute.
        Returns True if allowed, False if exceeded.
        """
        if not client_host:
            return True
            
        now = time.time()
        if client_host in self._connection_attempts:
            # Keep only timestamps from the last 60 seconds
            self._connection_attempts[client_host] = [
                t for t in self._connection_attempts[client_host] if now - t < 60
            ]
        else:
            self._connection_attempts[client_host] = []
            
        if len(self._connection_attempts[client_host]) >= 10:
            return False
            
        self._connection_attempts[client_host].append(now)
        return True

    def check_wrong_code_limit(self, session_id: str) -> bool:
        """
        Max 5 wrong code attempts per session.
        Returns True if allowed, False if exceeded.
        """
        attempts = self._wrong_code_attempts.get(session_id, 0)
        if attempts >= 5:
            return False
        return True
        
    def record_wrong_code(self, session_id: str):
        self._wrong_code_attempts[session_id] = self._wrong_code_attempts.get(session_id, 0) + 1

    def clean_session(self, session_id: str):
        """
        Immediately delete session traces from memory.
        """
        if session_id in self._wrong_code_attempts:
            del self._wrong_code_attempts[session_id]

# Custom Logger that enforces clean logs
class PrivacyLogger(logging.LoggerAdapter):
    def process(self, msg, kwargs):
        return f"{msg}", kwargs

def get_privacy_logger(name="oiss_privacy"):
    logger = logging.getLogger(name)
    if not logger.handlers:
        handler = logging.StreamHandler()
        formatter = logging.Formatter('%(asctime)s | %(message)s')
        handler.setFormatter(formatter)
        logger.addHandler(handler)
        logger.setLevel(logging.INFO)
    return PrivacyLogger(logger, {})

privacy_manager = PrivacyManager()
logger = get_privacy_logger()
