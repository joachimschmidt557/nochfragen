use axum::{http::StatusCode, response::IntoResponse};

pub async fn list_surveys() -> impl IntoResponse {
    StatusCode::SERVICE_UNAVAILABLE
}

pub async fn add_survey() -> impl IntoResponse {
    StatusCode::SERVICE_UNAVAILABLE
}

pub async fn modify_survey() -> impl IntoResponse {
    StatusCode::SERVICE_UNAVAILABLE
}

pub async fn delete_survey() -> impl IntoResponse {
    StatusCode::SERVICE_UNAVAILABLE
}
