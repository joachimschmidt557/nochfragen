use axum::{http::StatusCode, response::IntoResponse};
use diesel::{
    SqliteConnection,
    r2d2::{self, ConnectionManager},
};
use fred::clients::Pool;

pub mod models;
pub mod schema;

pub mod questions;
pub mod surveys;

type DbPool = r2d2::Pool<ConnectionManager<SqliteConnection>>;

#[derive(Clone)]
pub struct AppState {
    pub db_pool: DbPool,
    pub redis_pool: Pool,
}

pub struct AppErr(anyhow::Error);
pub type AppResult<T> = Result<T, AppErr>;

impl<E> From<E> for AppErr
where
    E: Into<anyhow::Error>,
{
    fn from(value: E) -> Self {
        Self(value.into())
    }
}

impl IntoResponse for AppErr {
    #[cfg(debug_assertions)]
    fn into_response(self) -> axum::response::Response {
        (StatusCode::INTERNAL_SERVER_ERROR, self.0.to_string()).into_response()
    }

    #[cfg(not(debug_assertions))]
    fn into_response(self) -> axum::response::Response {
        StatusCode::INTERNAL_SERVER_ERROR.into_response()
    }
}
