"""Product-wide limits shared by the engine, API, and module schema."""

# Friends-scale hunts. Changing this requires schema seeker_count max to match.
# Seeker count bounds in schemas/modules.py and presets/classic.py read this value.
MAX_GAME_PLAYERS = 40