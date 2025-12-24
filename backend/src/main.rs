use axum::{
    Router,
    routing::{delete, get, post, put},
};
use tower_http::services::ServeDir;

#[tokio::main]
async fn main() {
    let listen_addr = std::env::var("LISTEN_ADDRESS").unwrap_or("127.0.0.1:8080".to_string());
    let root_dir = std::env::var("ROOT_DIR").unwrap_or("../build".to_string());

    let serve_dir = ServeDir::new(root_dir);

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
        .fallback_service(serve_dir);

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
