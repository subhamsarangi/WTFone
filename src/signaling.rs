use serde::{Deserialize, Serialize};
use uuid::Uuid;
use axum::extract::ws::{WebSocket, WebSocketUpgrade};
use tokio::sync::mpsc;
use futures::{sink::SinkExt, stream::StreamExt};

/// Messages from client to server
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum ClientMessage {
    #[serde(rename = "join")]
    Join {
        room_id: String,
        password: String,
    },
    #[serde(rename = "offer")]
    Offer {
        to: String,
        sdp: String,
    },
    #[serde(rename = "answer")]
    Answer {
        to: String,
        sdp: String,
    },
    #[serde(rename = "ice")]
    Ice {
        to: String,
        candidate: String,
    },
}

/// Messages from server to client
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum ServerMessage {
    #[serde(rename = "joined")]
    Joined {
        peer_id: String,
        existing_peers: Vec<String>,
    },
    #[serde(rename = "peer_joined")]
    PeerJoined {
        peer_id: String,
    },
    #[serde(rename = "peer_left")]
    PeerLeft {
        peer_id: String,
    },
    #[serde(rename = "offer")]
    Offer {
        from: String,
        sdp: String,
    },
    #[serde(rename = "answer")]
    Answer {
        from: String,
        sdp: String,
    },
    #[serde(rename = "ice")]
    Ice {
        from: String,
        candidate: String,
    },
    #[serde(rename = "error")]
    Error {
        message: String,
    },
}

/// WebSocket handler for room connection
pub async fn ws_handler(
    ws: WebSocketUpgrade,
    axum::extract::Path(room_id_str): axum::extract::Path<String>,
    axum::extract::State(rooms): axum::extract::State<crate::rooms::Rooms>,
) -> impl axum::response::IntoResponse {
    ws.on_upgrade(|socket| handle_socket(socket, room_id_str, rooms))
}

async fn handle_socket(
    socket: WebSocket,
    room_id_str: String,
    rooms: crate::rooms::Rooms,
) {
    let (sender, mut receiver) = socket.split();
    let sender = std::sync::Arc::new(tokio::sync::Mutex::new(sender));
    
    // Parse room_id
    let room_id = match uuid::Uuid::parse_str(&room_id_str) {
        Ok(id) => id,
        Err(_) => {
            tracing::warn!("Invalid room_id format: {}", room_id_str);
            return;
        }
    };

    // Wait for join message
    let (peer_id, mut rx) = loop {
        match receiver.next().await {
            Some(Ok(axum::extract::ws::Message::Text(text))) => {
                match serde_json::from_str::<ClientMessage>(&text) {
                    Ok(ClientMessage::Join { password, .. }) => {
                        // Verify password
                        if !crate::rooms::verify_password(&rooms, room_id, password) {
                            let mut s = sender.lock().await;
                            let _ = s
                                .send(axum::extract::ws::Message::Text(
                                    serde_json::to_string(&ServerMessage::Error {
                                        message: "Invalid password".to_string(),
                                    })
                                    .unwrap(),
                                ))
                                .await;
                            return;
                        }

                        // Generate peer_id
                        let peer_id = Uuid::new_v4();
                        
                        // Create channel for this peer
                        let (tx, rx) = mpsc::unbounded_channel();
                        
                        // Create peer
                        let peer = crate::rooms::Peer { id: peer_id, tx };
                        
                        // Add to room and get existing peers
                        let existing_peers =
                            match crate::rooms::add_peer_to_room(&rooms, room_id, peer) {
                                Some(peers) => peers,
                                None => {
                                    let mut s = sender.lock().await;
                                    let _ = s
                                        .send(axum::extract::ws::Message::Text(
                                            serde_json::to_string(&ServerMessage::Error {
                                                message: "Room not found".to_string(),
                                            })
                                            .unwrap(),
                                        ))
                                        .await;
                                    return;
                                }
                            };
                        
                        // Send joined message with existing peers
                        {
                            let mut s = sender.lock().await;
                            let existing_peer_ids: Vec<String> = existing_peers
                                .iter()
                                .map(|p| p.id.to_string())
                                .collect();
                            let _ = s
                                .send(axum::extract::ws::Message::Text(
                                    serde_json::to_string(&ServerMessage::Joined {
                                        peer_id: peer_id.to_string(),
                                        existing_peers: existing_peer_ids,
                                    })
                                    .unwrap(),
                                ))
                                .await;
                        }
                        
                        tracing::info!(
                            "Peer {} joined room {} (existing peers: {})",
                            peer_id,
                            room_id,
                            existing_peers.len()
                        );
                        
                        // Broadcast peer_joined to existing peers
                        for peer in existing_peers {
                            let _ = peer.tx.send(ServerMessage::PeerJoined {
                                peer_id: peer_id.to_string(),
                            });
                        }
                        
                        break (peer_id, rx);
                    }
                    _ => {
                        let mut s = sender.lock().await;
                        let _ = s
                            .send(axum::extract::ws::Message::Text(
                                serde_json::to_string(&ServerMessage::Error {
                                    message: "Expected join message".to_string(),
                                })
                                .unwrap(),
                            ))
                            .await;
                        return;
                    }
                }
            }
            Some(Ok(axum::extract::ws::Message::Close(_))) => {
                return;
            }
            _ => {
                return;
            }
        }
    };

    // Spawn write task
    let sender_clone = sender.clone();
    tokio::spawn(async move {
        while let Some(msg) = rx.recv().await {
            let text = serde_json::to_string(&msg).unwrap();
            let mut s = sender_clone.lock().await;
            if s.send(axum::extract::ws::Message::Text(text))
                .await
                .is_err()
            {
                break;
            }
        }
    });

    // Read task
    while let Some(Ok(msg)) = receiver.next().await {
        match msg {
            axum::extract::ws::Message::Text(text) => {
                if let Ok(client_msg) = serde_json::from_str::<ClientMessage>(&text) {
                    match client_msg {
                        ClientMessage::Offer { to, sdp } => {
                            // Find target peer
                            if let Some(target_peer) = crate::rooms::get_peer_from_room(&rooms, room_id, Uuid::parse_str(&to).unwrap_or_default()) {
                                let msg = ServerMessage::Offer {
                                    from: peer_id.to_string(),
                                    sdp,
                                };
                                let _ = target_peer.tx.send(msg);
                                tracing::debug!("Relayed offer from {} to {}", peer_id, to);
                            } else {
                                tracing::warn!("Target peer {} not found in room {}", to, room_id);
                            }
                        }
                        ClientMessage::Answer { to, sdp } => {
                            // Find target peer
                            if let Some(target_peer) = crate::rooms::get_peer_from_room(&rooms, room_id, Uuid::parse_str(&to).unwrap_or_default()) {
                                let msg = ServerMessage::Answer {
                                    from: peer_id.to_string(),
                                    sdp,
                                };
                                let _ = target_peer.tx.send(msg);
                                tracing::debug!("Relayed answer from {} to {}", peer_id, to);
                            } else {
                                tracing::warn!("Target peer {} not found in room {}", to, room_id);
                            }
                        }
                        ClientMessage::Ice { to, candidate } => {
                            // Find target peer
                            if let Some(target_peer) = crate::rooms::get_peer_from_room(&rooms, room_id, Uuid::parse_str(&to).unwrap_or_default()) {
                                let msg = ServerMessage::Ice {
                                    from: peer_id.to_string(),
                                    candidate,
                                };
                                let _ = target_peer.tx.send(msg);
                                tracing::debug!("Relayed ICE candidate from {} to {}", peer_id, to);
                            } else {
                                tracing::warn!("Target peer {} not found in room {}", to, room_id);
                            }
                        }
                        _ => {
                            tracing::debug!("Received message from peer {}: {:?}", peer_id, client_msg);
                        }
                    }
                }
            }
            axum::extract::ws::Message::Close(_) => {
                break;
            }
            _ => {}
        }
    }

    // Cleanup on disconnect
    if let Some(room) = rooms.get(&room_id) {
        // Broadcast peer_left to remaining peers
        for peer in room.peers.iter() {
            let _ = peer.tx.send(ServerMessage::PeerLeft {
                peer_id: peer_id.to_string(),
            });
        }
    }
    
    let is_empty = crate::rooms::remove_peer_from_room(&rooms, room_id, peer_id);
    tracing::info!("Peer {} left room {}", peer_id, room_id);

    if is_empty {
        tracing::info!("Room {} is empty! Triggering smart grid build.", room_id);
        crate::grid::spawn_grid_processing(room_id.to_string());
    }
}
