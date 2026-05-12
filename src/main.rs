use axum::{
    routing::{get, post},
    Router,
    http::{header, StatusCode},
    response::IntoResponse,
    Json,
    extract::State,
};
use serde::Serialize;
use std::net::SocketAddr;
use std::sync::Arc;
use tower_http::cors::CorsLayer;
use tower_http::trace::TraceLayer;
use tracing_subscriber;

mod rooms;
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
        .route("/api/rooms", post(create_room_handler))
        .layer(CorsLayer::permissive())
        .layer(TraceLayer::new_for_http())
        .with_state(rooms);

    // Bind and run
    let addr = SocketAddr::from(([127, 0, 0, 1], 3000));
    tracing::info!("Server listening on {}", addr);

    let listener = tokio::net::TcpListener::bind(addr)
        .await
        .expect("Failed to bind");

    axum::serve(listener, app)
        .await
        .expect("Server error");
}

async fn serve_index() -> impl IntoResponse {
    (
        [(header::CONTENT_TYPE, "text/html; charset=utf-8")],
        include_str!("../static/index.html"),
    )
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
