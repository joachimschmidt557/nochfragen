use axum::{http::StatusCode, response::IntoResponse};
use diesel::{
    SqliteConnection,
    r2d2::{self, ConnectionManager},
};
use diesel_migrations::{EmbeddedMigrations, MigrationHarness, embed_migrations};
use fred::clients::Pool;
use fred::interfaces::*;
use fred::types::{Builder, config::Config};
use openidconnect::{
    Client, ClientId, ClientSecret, IssuerUrl, RedirectUrl,
    core::{CoreClient, CoreProviderMetadata},
    reqwest,
};
use scrypt::password_hash::PasswordHashString;
use time::Duration;
use tower_sessions::{Expiry, SessionManagerLayer};
use tower_sessions_redis_store::RedisStore;
use url::Url;

pub mod oidc_login;

pub mod models;
pub mod schema;

pub mod questions;
pub mod surveys;

type DbPool = r2d2::Pool<ConnectionManager<SqliteConnection>>;
pub type OidcClient = Client<
    openidconnect::EmptyAdditionalClaims,
    openidconnect::core::CoreAuthDisplay,
    openidconnect::core::CoreGenderClaim,
    openidconnect::core::CoreJweContentEncryptionAlgorithm,
    openidconnect::core::CoreJsonWebKey,
    openidconnect::core::CoreAuthPrompt,
    openidconnect::StandardErrorResponse<openidconnect::core::CoreErrorResponseType>,
    openidconnect::StandardTokenResponse<
        openidconnect::IdTokenFields<
            openidconnect::EmptyAdditionalClaims,
            openidconnect::EmptyExtraTokenFields,
            openidconnect::core::CoreGenderClaim,
            openidconnect::core::CoreJweContentEncryptionAlgorithm,
            openidconnect::core::CoreJwsSigningAlgorithm,
        >,
        openidconnect::core::CoreTokenType,
    >,
    openidconnect::StandardTokenIntrospectionResponse<
        openidconnect::EmptyExtraTokenFields,
        openidconnect::core::CoreTokenType,
    >,
    openidconnect::core::CoreRevocableToken,
    openidconnect::StandardErrorResponse<openidconnect::RevocationErrorResponseType>,
    openidconnect::EndpointSet,
    openidconnect::EndpointNotSet,
    openidconnect::EndpointNotSet,
    openidconnect::EndpointNotSet,
    openidconnect::EndpointMaybeSet,
    openidconnect::EndpointMaybeSet,
>;

#[derive(Clone)]
pub struct AppState {
    pub db_pool: DbPool,
    pub redis_pool: Pool,
    pub hashed_password: PasswordHashString,
    pub oidc_client: Option<OidcClient>,
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

pub async fn connect_openid_connect() -> Option<OidcClient> {
    let issuer_url = std::env::var("OIDC_ISSUER_URL").ok()?;
    let client_id = std::env::var("OIDC_CLIENT_ID").ok()?;
    let client_secret = std::env::var("OIDC_CLIENT_SECRET").ok()?;
    let base_url = Url::parse(&std::env::var("BASE_URL").ok()?).expect("Invalid BASE_URL");

    let http_client = reqwest::ClientBuilder::new()
        // Following redirects opens the client up to SSRF vulnerabilities.
        .redirect(reqwest::redirect::Policy::none())
        .build()
        .expect("Failed to build reqwest client");

    // Use OpenID Connect Discovery to fetch the provider metadata.
    let provider_metadata = CoreProviderMetadata::discover_async(
        IssuerUrl::new(issuer_url).expect("Invalid OIDC_ISSUER_URL"),
        &http_client,
    )
    .await
    .expect("Failed to fetch OIDC provider metadata");

    // Create an OpenID Connect client by specifying the client ID, client secret, authorization URL
    // and token URL.
    let client = CoreClient::from_provider_metadata(
        provider_metadata,
        ClientId::new(client_id),
        Some(ClientSecret::new(client_secret)),
    )
    // Set the URL the user will be redirected to after the authorization process.
    .set_redirect_uri(
        RedirectUrl::new(
            base_url
                .join("/api/openid-connect/callback")
                .expect("Failed to construct redirect URL")
                .to_string(),
        )
        .expect("Invalid OIDC redirect URL"),
    );

    Some(client)
}

pub fn create_session_layer(redis_pool: Pool) -> SessionManagerLayer<RedisStore<Pool>> {
    let session_store = RedisStore::new(redis_pool.clone());

    SessionManagerLayer::new(session_store).with_expiry(Expiry::OnInactivity(Duration::weeks(4)))
}
