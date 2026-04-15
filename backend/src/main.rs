use axum::{
    Json, Router,
    extract::State,
    http::StatusCode,
    routing::{delete, get, patch, post, put},
};
use dotenvy::dotenv;
use scrypt::{
    Scrypt,
    password_hash::{PasswordHasher, PasswordVerifier, SaltString, rand_core::OsRng},
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
        .route("/api/question/{id}", patch(questions::modify_question))
        .route(
            "/api/question/{id}/upvote",
            post(questions::upvote_question),
        )
        .route("/api/question/{id}", delete(questions::delete_question))
        .route("/api/export", get(questions::export_questions))
        // surveys
        .route("/api/surveys", get(surveys::list_surveys))
        .route("/api/surveys", post(surveys::add_survey))
        .route("/api/survey/{id}", put(surveys::modify_survey))
        .route(
            "/api/survey/{id}/option/{option_id}/vote",
            put(surveys::vote_for_survey_option),
        )
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

    let salt = SaltString::generate(&mut OsRng);
    let password = std::env::var("NOCHFRAGEN_PASSWORD")
        .expect("set NOCHFRAGEN_PASSWORD environment variable with the moderation password");
    let app_state = AppState {
        db_pool,
        redis_pool,
        hashed_password: Scrypt
            .hash_password(password.as_bytes(), &salt)
            .expect("failed to hash password")
            .serialize(),
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
    match Scrypt.verify_password(
        request.password.as_bytes(),
        &state.hashed_password.password_hash(),
    ) {
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
