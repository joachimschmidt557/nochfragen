use diesel::{
    SqliteConnection,
    r2d2::{self, ConnectionManager},
};
use fred::clients::Pool;

pub mod questions;
pub mod surveys;

type DbPool = r2d2::Pool<ConnectionManager<SqliteConnection>>;

#[derive(Clone)]
pub struct AppState {
    pub db_pool: DbPool,
    pub redis_pool: Pool,
}
