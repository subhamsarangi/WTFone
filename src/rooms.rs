use dashmap::DashMap;
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use uuid::Uuid;
use tokio::sync::mpsc;

/// Peer in a room (holds tx channel for signaling)
#[derive(Clone)]
pub struct Peer {
    pub id: Uuid,
    pub tx: mpsc::UnboundedSender<crate::signaling::ServerMessage>,
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

/// Add peer to room, return list of existing peers
pub fn add_peer_to_room(
    rooms: &Rooms,
    room_id: Uuid,
    peer: Peer,
) -> Option<Vec<Peer>> {
    rooms.get(&room_id).map(|room| {
        room.peers.insert(peer.id, peer.clone());
        room.peers
            .iter()
            .filter(|p| p.id != peer.id)
            .map(|p| p.value().clone())
            .collect()
    })
}

/// Remove peer from room, returns true if room is empty
pub fn remove_peer_from_room(rooms: &Rooms, room_id: Uuid, peer_id: Uuid) -> bool {
    if let Some(room) = rooms.get(&room_id) {
        room.peers.remove(&peer_id);
        return room.peers.is_empty();
    }
    true
}

/// Get peer from room
pub fn get_peer_from_room(rooms: &Rooms, room_id: Uuid, peer_id: Uuid) -> Option<Peer> {
    rooms
        .get(&room_id)
        .and_then(|room| room.peers.get(&peer_id).map(|p| p.clone()))
}
