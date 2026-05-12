use dashmap::DashMap;
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use uuid::Uuid;

/// Peer in a room (holds tx channel for signaling)
#[derive(Clone)]
pub struct Peer {
    pub id: Uuid,
    // tx channel will be added in Phase 3 when WebSocket implemented
}

/// Room with password protection
pub struct Room {
    pub id: Uuid,
    pub password_hash: String,
    pub peers: Arc<DashMap<Uuid, Peer>>,
}

/// Global rooms store
pub type Rooms = Arc<DashMap<Uuid, Room>>;

/// Request/response types
#[derive(Deserialize)]
pub struct CreateRoomRequest {
    pub password: String,
}

#[derive(Serialize)]
pub struct CreateRoomResponse {
    pub room_id: String,
}

/// Create new room with password
pub fn create_room(rooms: &Rooms, password: String) -> Uuid {
    let room_id = Uuid::new_v4();
    
    // Hash password with bcrypt
    let password_hash = bcrypt::hash(&password, 12)
        .expect("Failed to hash password");
    
    let room = Room {
        id: room_id,
        password_hash,
        peers: Arc::new(DashMap::new()),
    };
    
    rooms.insert(room_id, room);
    
    tracing::info!("Created room {}", room_id);
    room_id
}

/// Verify password for room
pub fn verify_password(rooms: &Rooms, room_id: Uuid, password: String) -> bool {
    match rooms.get(&room_id) {
        Some(room) => {
            let valid = bcrypt::verify(&password, &room.password_hash)
                .unwrap_or(false);
            
            if valid {
                tracing::info!("Password verification succeeded for room {}", room_id);
            } else {
                tracing::warn!("Password verification failed for room {}", room_id);
            }
            
            valid
        }
        None => {
            tracing::warn!("Room {} not found", room_id);
            false
        }
    }
}
