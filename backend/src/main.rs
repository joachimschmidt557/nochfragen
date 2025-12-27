use axum::{
    Json, Router,
    extract::State,
    http::StatusCode,
    routing::{delete, get, post, put},
};
use dotenvy::dotenv;
use fred::interfaces::*;
use scrypt::{
    Scrypt,
    password_hash::{PasswordHash, PasswordVerifier},
};
use serde::{Deserialize, Serialize};
use tower_http::services::ServeDir;

use nochfragen::{
    AppResult, AppState, connect_db, connect_redis, create_session_layer, questions, surveys,
};
use tower_sessions::Session;

fn app() -> Router<AppState> {
    Router::new()
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
}

#[tokio::main]
async fn main() {
    dotenv().ok();

    let root_dir = std::env::var("ROOT_DIR").unwrap_or("../build".to_string());
    let serve_dir = ServeDir::new(root_dir);

    let redis_pool = connect_redis().await;
    let db_pool = connect_db();
    let session_layer = create_session_layer(redis_pool.clone());

    let app_state = AppState {
        db_pool,
        redis_pool,
    };

    let app = app()
        // static
        .fallback_service(serve_dir)
        // sessions
        .layer(session_layer)
        // state
        .with_state(app_state);

    let listen_addr = std::env::var("LISTEN_ADDRESS").unwrap_or("127.0.0.1:8080".to_string());
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
