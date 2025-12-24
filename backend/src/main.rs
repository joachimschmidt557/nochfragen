use axum::{
    Router,
    routing::{delete, get, post, put},
};
use diesel::r2d2::{self, ConnectionManager};
use diesel::sqlite::SqliteConnection;
use dotenvy::dotenv;
use fred::clients::Pool;
use fred::interfaces::*;
use fred::types::{Builder, config::Config};
use time::Duration;
use tower_http::services::ServeDir;
use tower_sessions::{Expiry, SessionManagerLayer};
use tower_sessions_redis_store::RedisStore;

type DbPool = r2d2::Pool<ConnectionManager<SqliteConnection>>;

#[derive(Clone)]
struct AppState {
    db_pool: DbPool,
    redis_pool: Pool,
}

#[tokio::main]
async fn main() {
    dotenv().ok();

    let listen_addr = std::env::var("LISTEN_ADDRESS").unwrap_or("127.0.0.1:8080".to_string());
    let redis_addr = std::env::var("REDIS_ADDRESS").unwrap_or("127.0.0.1:6379".to_string());
    let root_dir = std::env::var("ROOT_DIR").unwrap_or("../build".to_string());
    let db_url = std::env::var("DATABASE_URL").unwrap_or("db.sqlite".to_string());

    let serve_dir = ServeDir::new(root_dir);

    let redis_config = Config::from_url(&format!("redis://{}", redis_addr))
        .expect("Failed to parse redis address");
    let redis_pool = Builder::from_config(redis_config)
        .build_pool(8)
        .expect("Failed to create redis pool");

    redis_pool.init().await.expect("Failed to connect to redis");

    let session_store = RedisStore::new(redis_pool.clone());
    let session_layer = SessionManagerLayer::new(session_store)
        .with_secure(false)
        .with_expiry(Expiry::OnInactivity(Duration::weeks(4)));

    let manager = ConnectionManager::<SqliteConnection>::new(db_url);
    let db_pool = r2d2::Pool::builder()
        .build(manager)
        .expect("Failed to create db pool.");

    let app_state = AppState {
        db_pool,
        redis_pool,
    };

    let app = Router::new()
        // authorization
        .route("/api/login", get(login_status))
        .route("/api/login", post(login))
        .route("/api/logout", post(logout))
        // questions
        .route("/api/questions", get(list_questions))
        .route("/api/questions", post(add_question))
        .route("/api/questions", delete(delete_all_questions))
        .route("/api/question/{id}", put(modify_question))
        .route("/api/question/{id}", delete(delete_question))
        .route("/api/export", get(export_questions))
        // surveys
        .route("/api/surveys", get(list_surveys))
        .route("/api/surveys", post(add_survey))
        .route("/api/survey/{id}", put(modify_survey))
        .route("/api/survey/{id}", delete(delete_survey))
        // static
        .fallback_service(serve_dir)
        // sessions
        .layer(session_layer)
        // state
        .with_state(app_state);

    let listener = tokio::net::TcpListener::bind(&listen_addr)
        .await
        .expect("Failed to bind to address");
    axum::serve(listener, app).await.unwrap();
}

async fn login_status() -> impl axum::response::IntoResponse {
    axum::http::StatusCode::SERVICE_UNAVAILABLE
}
async fn login() -> impl axum::response::IntoResponse {
    axum::http::StatusCode::SERVICE_UNAVAILABLE
}
async fn logout() -> impl axum::response::IntoResponse {
    axum::http::StatusCode::SERVICE_UNAVAILABLE
}

async fn list_questions() -> impl axum::response::IntoResponse {
    axum::http::StatusCode::SERVICE_UNAVAILABLE
}
async fn add_question() -> impl axum::response::IntoResponse {
    axum::http::StatusCode::SERVICE_UNAVAILABLE
}
async fn delete_all_questions() -> impl axum::response::IntoResponse {
    axum::http::StatusCode::SERVICE_UNAVAILABLE
}
async fn modify_question() -> impl axum::response::IntoResponse {
    axum::http::StatusCode::SERVICE_UNAVAILABLE
}
async fn delete_question() -> impl axum::response::IntoResponse {
    axum::http::StatusCode::SERVICE_UNAVAILABLE
}
async fn export_questions() -> impl axum::response::IntoResponse {
    axum::http::StatusCode::SERVICE_UNAVAILABLE
}

async fn list_surveys() -> impl axum::response::IntoResponse {
    axum::http::StatusCode::SERVICE_UNAVAILABLE
}
async fn add_survey() -> impl axum::response::IntoResponse {
    axum::http::StatusCode::SERVICE_UNAVAILABLE
}
async fn modify_survey() -> impl axum::response::IntoResponse {
    axum::http::StatusCode::SERVICE_UNAVAILABLE
}
async fn delete_survey() -> impl axum::response::IntoResponse {
    axum::http::StatusCode::SERVICE_UNAVAILABLE
}
