import random
import logging

logger = logging.getLogger("oiss_privacy")

class RelayManager:
    def __init__(self):
        # Set of active relay session UUIDs
        self.active_relays = set()
        
        # Route mapping: data_session_uuid -> relay_session_uuid
        self.assigned_routes = {}

    def register_relay(self, session_id: str):
        self.active_relays.add(session_id)
        logger.info(f"sess_{session_id} | registered_as_relay")

    def remove_relay(self, session_id: str):
        if session_id in self.active_relays:
            self.active_relays.remove(session_id)
            
        # Clean up any sessions that were using this relay
        dead_routes = [k for k, v in self.assigned_routes.items() if v == session_id]
        for k in dead_routes:
            del self.assigned_routes[k]
        logger.info(f"sess_{session_id} | removed_relay")

    def assign_relay(self, session_id: str) -> str:
        """
        Assigns a random active community relay to a session.
        Returns the relay's session UUID, or None if no relays are active.
        """
        if not self.active_relays:
            return None
            
        chosen_relay = random.choice(list(self.active_relays))
        self.assigned_routes[session_id] = chosen_relay
        logger.info(f"sess_{session_id} | assigned_to_relay_{chosen_relay}")
        return chosen_relay

    def get_relay_for_session(self, session_id: str) -> str:
        return self.assigned_routes.get(session_id)

relay_manager = RelayManager()
