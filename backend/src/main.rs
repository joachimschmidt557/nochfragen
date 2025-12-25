use axum::{
    Json, Router,
    extract::State,
    http::StatusCode,
    response::IntoResponse,
    routing::{delete, get, post, put},
};
use diesel::r2d2::{self, ConnectionManager};
use diesel::sqlite::SqliteConnection;
use diesel_migrations::{EmbeddedMigrations, MigrationHarness, embed_migrations};
use dotenvy::dotenv;
use fred::interfaces::*;
use fred::types::{Builder, config::Config};
use scrypt::{
    Scrypt,
    password_hash::{PasswordHash, PasswordVerifier},
};
use serde::{Deserialize, Serialize};
use time::Duration;
use tower_http::services::ServeDir;
use tower_sessions::{Expiry, Session, SessionManagerLayer};
use tower_sessions_redis_store::RedisStore;

use nochfragen::{AppResult, AppState};
use nochfragen::{questions, surveys};

pub const MIGRATIONS: EmbeddedMigrations = embed_migrations!("migrations");

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
    db_pool
        .get()
        .expect("Failed to get a connection from the db pool")
        .run_pending_migrations(MIGRATIONS)
        .expect("Failed to run migrations");

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
        .route("/api/questions", get(questions::list_questions))
        .route("/api/questions", post(questions::add_question))
        .route("/api/questions", delete(questions::delete_all_questions))
        .route("/api/question/{id}", put(questions::modify_question))
        .route("/api/question/{id}", delete(questions::delete_question))
        .route("/api/export", get(questions::export_questions))
        // surveys
        .route("/api/surveys", get(surveys::list_surveys))
        .route("/api/surveys", post(surveys::add_survey))
        .route("/api/survey/{id}", put(surveys::modify_survey))
        .route("/api/survey/{id}", delete(surveys::delete_survey))
        // static
        .fallback_service(serve_dir)
        // sessions
        .layer(session_layer)
        // state
        .with_state(app_state);

    let listener = tokio::net::TcpListener::bind(&listen_addr)
        .await
        .expect("Failed to bind to address");

    println!("Listening on {listen_addr}");
    axum::serve(listener, app).await.unwrap();
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct LoginStatusResponse {
    logged_in: bool,
}

async fn login_status(session: Session) -> Json<LoginStatusResponse> {
    let logged_in = session
        .get::<bool>("authenticated")
        .await
        .unwrap_or(None)
        .unwrap_or(false);
    Json(LoginStatusResponse { logged_in })
}

#[derive(Deserialize)]
struct LoginRequest {
    password: String,
}

async fn login(
    State(state): State<AppState>,
    session: Session,
    Json(request): Json<LoginRequest>,
) -> AppResult<StatusCode> {
    let hashed_password: Option<String> = state
        .redis_pool
        .get("nochfragen:password")
        .await
        .unwrap_or(None);

    let Some(hashed_password) = hashed_password else {
        // no password set
        return Ok(StatusCode::FORBIDDEN);
    };

    let Ok(hashed_password) = PasswordHash::new(&hashed_password) else {
        // db contains an invalid scrypt hash
        return Ok(StatusCode::FORBIDDEN);
    };

    match Scrypt.verify_password(request.password.as_bytes(), &hashed_password) {
        Ok(_) => {
            session.insert("authenticated", true).await?;
            Ok(StatusCode::OK)
        }
        Err(_) => Ok(StatusCode::FORBIDDEN),
    }
}

async fn logout(session: Session) -> AppResult<StatusCode> {
    session.insert("authenticated", false).await?;
    Ok(StatusCode::OK)
}
