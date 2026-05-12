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
                        
                        // Send joined message
                        {
                            let mut s = sender.lock().await;
                            let _ = s
                                .send(axum::extract::ws::Message::Text(
                                    serde_json::to_string(&ServerMessage::Joined {
                                        peer_id: peer_id.to_string(),
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
                    // Handle offer/answer/ice messages (Phase 4)
                    // For now, just log
                    tracing::debug!("Received message from peer {}: {:?}", peer_id, client_msg);
                }
            }
            axum::extract::ws::Message::Close(_) => {
                break;
            }
            _ => {}
        }
    }

    // Cleanup on disconnect
    crate::rooms::remove_peer_from_room(&rooms, room_id, peer_id);
    tracing::info!("Peer {} left room {}", peer_id, room_id);
}
