use axum::{http::StatusCode, response::IntoResponse};

pub async fn list_questions() -> impl IntoResponse {
    StatusCode::SERVICE_UNAVAILABLE
}

pub async fn add_question() -> impl IntoResponse {
    StatusCode::SERVICE_UNAVAILABLE
}

pub async fn delete_all_questions() -> impl IntoResponse {
    StatusCode::SERVICE_UNAVAILABLE
}

pub async fn modify_question() -> impl IntoResponse {
    StatusCode::SERVICE_UNAVAILABLE
}

pub async fn delete_question() -> impl IntoResponse {
    StatusCode::SERVICE_UNAVAILABLE
}

pub async fn export_questions() -> impl IntoResponse {
    StatusCode::SERVICE_UNAVAILABLE
}
