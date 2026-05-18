use axum::{
    routing::{get, post},
    Router,
    http::{header, StatusCode},
    response::IntoResponse,
    Json,
    extract::{State, Path, Multipart, DefaultBodyLimit},
};
use serde::Serialize;
use std::net::SocketAddr;
use std::sync::Arc;
use tower_http::cors::CorsLayer;
use tower_http::trace::TraceLayer;
use tower_http::services::ServeDir;
use tracing_subscriber;
use std::path::PathBuf;
use axum_server::tls_rustls::RustlsConfig;

mod rooms;
mod signaling;
pub mod grid;
use rooms::{Rooms, CreateRoomRequest, CreateRoomResponse, create_room};
use dashmap::DashMap;

#[derive(Serialize)]
struct ErrorResponse {
    error: String,
}

#[tokio::main]
async fn main() {
    // Initialize tracing
    tracing_subscriber::fmt()
        .with_env_filter("debug")
        .init();

    // Create rooms store
    let rooms: Rooms = Arc::new(DashMap::new());

    // Build router
    let app = Router::new()
        .route("/", get(serve_index))
        .route("/room/:id", get(serve_index))
        .route("/api/rooms", post(create_room_handler))
        .route("/api/rooms/:id/ws", axum::routing::get(signaling::ws_handler))
        .route("/api/rooms/:id/recording", post(upload_recording_handler).layer(DefaultBodyLimit::max(250 * 1024 * 1024)))
        .route("/api/local-ip", get(get_local_ip_handler))
        .nest_service("/assets", ServeDir::new("assets"))
        .layer(CorsLayer::permissive())
        .layer(TraceLayer::new_for_http())
        .with_state(rooms);

    // Bind and run
    // 0.0.0.0 = listen on all network interfaces (accessible from WiFi)
    // Port from env var or default 8443
    let port = std::env::var("PORT")
        .ok()
        .and_then(|p| p.parse::<u16>().ok())
        .unwrap_or(8443);
    
    let addr = SocketAddr::from(([0, 0, 0, 0], port));
    
    let config = RustlsConfig::from_pem_file(
        "localhost+3.pem",
        "localhost+3-key.pem",
    )
    .await
    .expect("Failed to load TLS config");

    tracing::info!("Server listening on https://{}", addr);
    tracing::info!("Access from other devices: https://<your-ip>:{}", port);

    axum_server::bind_rustls(addr, config)
        .serve(app.into_make_service())
        .await
        .expect("Server error");
}

async fn serve_index() -> impl IntoResponse {
    (
        [(header::CONTENT_TYPE, "text/html; charset=utf-8")],
        include_str!("../static/index.html"),
    )
}

async fn get_local_ip_handler() -> impl IntoResponse {
    let local_ip = get_local_ip().unwrap_or_else(|| "127.0.0.1".to_string());
    Json(serde_json::json!({
        "ip": local_ip
    }))
}

fn get_local_ip() -> Option<String> {
    // Try to get local IP by connecting to a public DNS server
    // This doesn't actually send data, just determines the local IP
    use std::net::UdpSocket;
    
    let socket = UdpSocket::bind("0.0.0.0:0").ok()?;
    socket.connect("8.8.8.8:80").ok()?;
    socket.local_addr().ok().map(|addr| addr.ip().to_string())
}

async fn create_room_handler(
    State(rooms): State<Rooms>,
    Json(payload): Json<CreateRoomRequest>,
) -> Result<Json<CreateRoomResponse>, (StatusCode, Json<ErrorResponse>)> {
    // Validate password not empty
    if payload.password.is_empty() {
        tracing::error!("Room creation failed: empty password");
        return Err((
            StatusCode::BAD_REQUEST,
            Json(ErrorResponse {
                error: "Password cannot be empty".to_string(),
            }),
        ));
    }

    // Create room
    match std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        create_room(&rooms, payload.password)
    })) {
        Ok(room_id) => {
            Ok(Json(CreateRoomResponse {
                room_id: room_id.to_string(),
            }))
        }
        Err(_) => {
            tracing::error!("Room creation failed: internal error");
            Err((
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ErrorResponse {
                    error: "Failed to create room".to_string(),
                }),
            ))
        }
    }
}

async fn upload_recording_handler(
    State(rooms): State<Rooms>,
    Path(room_id): Path<String>,
    mut multipart: Multipart,
) -> Result<impl IntoResponse, (StatusCode, Json<ErrorResponse>)> {
    tracing::info!("Recording upload for room {}", room_id);

    // Validate room ID format
    let parsed_uuid = match uuid::Uuid::parse_str(&room_id) {
        Ok(id) => id,
        Err(_) => {
            tracing::warn!("Invalid room_id format in upload: {}", room_id);
            return Err((
                StatusCode::BAD_REQUEST,
                Json(ErrorResponse {
                    error: "Invalid room ID format".to_string(),
                }),
            ));
        }
    };

    // Verify room exists in memory
    if !rooms.contains_key(&parsed_uuid) {
        tracing::warn!("Recording upload attempted for non-existent room: {}", room_id);
        return Err((
            StatusCode::NOT_FOUND,
            Json(ErrorResponse {
                error: "Room not found".to_string(),
            }),
        ));
    }

    // Create recordings directory
    let recordings_dir = PathBuf::from("recordings").join(&room_id);
    if let Err(e) = tokio::fs::create_dir_all(&recordings_dir).await {
        tracing::error!("Failed to create recordings directory: {}", e);
        return Err((
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ErrorResponse {
                error: "Failed to create recordings directory".to_string(),
            }),
        ));
    }

    // Process multipart form
    while let Some(field) = multipart.next_field().await.map_err(|e| {
        tracing::error!("Multipart error: {}", e);
        (
            StatusCode::BAD_REQUEST,
            Json(ErrorResponse {
                error: format!("Invalid multipart data: {}", e),
            }),
        )
    })? {
        let name = field.name().unwrap_or("").to_string();
        tracing::debug!("Multipart field: {}", name);
        
        if name == "file" {
            let filename = field.file_name()
                .map(|s| s.to_string())
                .unwrap_or_else(|| format!("{}_{}.webm", chrono::Utc::now().timestamp(), "unknown"));
            
            tracing::info!("Processing file: {}", filename);
            
            let data = field.bytes().await.map_err(|e| {
                tracing::error!("Failed to read file data: {}", e);
                (
                    StatusCode::BAD_REQUEST,
                    Json(ErrorResponse {
                        error: format!("Failed to read file data: {}", e),
                    }),
                )
            })?;

            tracing::info!("File size: {} bytes", data.len());

            use tokio::fs::OpenOptions;
            use tokio::io::AsyncWriteExt;

            let filepath = recordings_dir.join(&filename);
            let mut file = OpenOptions::new()
                .create(true)
                .append(true)
                .open(&filepath)
                .await
                .map_err(|e| {
                    tracing::error!("Failed to open file in append mode: {}", e);
                    (
                        StatusCode::INTERNAL_SERVER_ERROR,
                        Json(ErrorResponse {
                            error: format!("Failed to open file: {}", e),
                        }),
                    )
                })?;

            file.write_all(&data).await.map_err(|e| {
                tracing::error!("Failed to write chunk to file: {}", e);
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    Json(ErrorResponse {
                        error: format!("Failed to save chunk: {}", e),
                    }),
                )
            })?;

            tracing::info!("Saved recording: {:?}", filepath);
            return Ok((StatusCode::OK, Json(serde_json::json!({
                "success": true,
                "filename": filename,
                "size": data.len()
            }))));
        }
    }

    tracing::warn!("No file field found in multipart data");
    Err((
        StatusCode::BAD_REQUEST,
        Json(ErrorResponse {
            error: "No file provided".to_string(),
        }),
    ))
}
