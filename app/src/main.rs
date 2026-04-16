use axum::{routing::get, Json, Router};
use serde::Serialize;
use std::net::SocketAddr;

const VERSION: &str = env!("CARGO_PKG_VERSION");
const COMMIT: Option<&str> = option_env!("GIT_COMMIT");

#[derive(Serialize)]
struct VersionResponse {
    version: &'static str,
    commit: &'static str,
}

async fn version() -> Json<VersionResponse> {
    Json(VersionResponse {
        version: VERSION,
        commit: COMMIT.unwrap_or("unknown"),
    })
}

async fn health() -> &'static str {
    "ok"
}

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "info".into()),
        )
        .init();

    let app = Router::new()
        .route("/version", get(version))
        .route("/health", get(health));

    let addr = SocketAddr::from(([0, 0, 0, 0], 8080));
    tracing::info!(%addr, version = VERSION, commit = COMMIT.unwrap_or("unknown"), "starting rust-demo");

    let listener = tokio::net::TcpListener::bind(addr).await.unwrap();
    axum::serve(listener, app).await.unwrap();
}
