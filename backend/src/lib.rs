use axum::{http::StatusCode, response::IntoResponse};
use diesel::{
    SqliteConnection,
    r2d2::{self, ConnectionManager},
};
use diesel_migrations::{EmbeddedMigrations, MigrationHarness, embed_migrations};
use fred::clients::Pool;
use fred::interfaces::*;
use fred::types::{Builder, config::Config};
use time::Duration;
use tower_sessions::{Expiry, SessionManagerLayer};
use tower_sessions_redis_store::RedisStore;

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

pub const MIGRATIONS: EmbeddedMigrations = embed_migrations!("migrations");

pub async fn connect_redis() -> Pool {
    let redis_addr = std::env::var("REDIS_ADDRESS").unwrap_or("127.0.0.1:6379".to_string());

    let redis_config = Config::from_url(&format!("redis://{}", redis_addr))
        .expect("Failed to parse redis address");
    let redis_pool = Builder::from_config(redis_config)
        .build_pool(8)
        .expect("Failed to create redis pool");

    redis_pool.init().await.expect("Failed to connect to redis");

    redis_pool
}

pub fn connect_db() -> DbPool {
    let db_url = std::env::var("DATABASE_URL").unwrap_or("db.sqlite".to_string());

    let manager = ConnectionManager::<SqliteConnection>::new(db_url);
    let db_pool = r2d2::Pool::builder()
        .build(manager)
        .expect("Failed to create db pool.");
    db_pool
        .get()
        .expect("Failed to get a connection from the db pool")
        .run_pending_migrations(MIGRATIONS)
        .expect("Failed to run migrations");

    db_pool
}

pub fn create_session_layer(redis_pool: Pool) -> SessionManagerLayer<RedisStore<Pool>> {
    let session_store = RedisStore::new(redis_pool.clone());

    SessionManagerLayer::new(session_store).with_expiry(Expiry::OnInactivity(Duration::weeks(4)))
}
