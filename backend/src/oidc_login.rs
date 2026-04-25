use anyhow::anyhow;
use axum::{
    extract::{Query, State},
    http::StatusCode,
    response::{IntoResponse, Redirect, Response},
};
use axum_extra::extract::cookie::{Cookie, CookieJar};
use openidconnect::{
    AccessTokenHash, AuthorizationCode, CsrfToken, Nonce, OAuth2TokenResponse, Scope,
    TokenResponse, core::CoreAuthenticationFlow, reqwest,
};
use serde::Deserialize;
use tower_sessions::Session;

use crate::{AppResult, AppState};

pub async fn login(State(state): State<AppState>, jar: CookieJar) -> AppResult<Response> {
    let Some(client) = state.oidc_client else {
        return Ok(StatusCode::NOT_FOUND.into_response());
    };

    // Generate the full authorization URL.
    let (auth_url, csrf_token, nonce) = client
        .authorize_url(
            CoreAuthenticationFlow::AuthorizationCode,
            CsrfToken::new_random,
            Nonce::new_random,
        )
        // Set the desired scopes.
        .add_scope(Scope::new("openid".to_string()))
        .url();

    let jar = jar
        .add(Cookie::new("state", csrf_token.into_secret()))
        .add(Cookie::new("nonce", String::from(nonce.secret())));

    Ok((jar, Redirect::to(auth_url.as_str())).into_response())
}

#[derive(Deserialize)]
pub struct CallbackQuery {
    code: String,
    state: String,
}

pub async fn callback(
    State(state): State<AppState>,
    session: Session,
    Query(query): Query<CallbackQuery>,
    jar: CookieJar,
) -> AppResult<Response> {
    let Some(client) = state.oidc_client else {
        return Ok(StatusCode::NOT_FOUND.into_response());
    };

    let http_client = reqwest::ClientBuilder::new()
        // Following redirects opens the client up to SSRF vulnerabilities.
        .redirect(reqwest::redirect::Policy::none())
        .build()
        .expect("Failed to build reqwest client");

    let cookie_state = jar
        .get("state")
        .ok_or(anyhow!("No state cookie set"))?
        .value()
        .to_string();
    let jar = jar.remove("state");

    let cookie_nonce = jar
        .get("nonce")
        .ok_or(anyhow!("No nonce cookie set"))?
        .value()
        .to_string();
    let jar = jar.remove("nonce");

    if cookie_state != query.state {
        return Ok((
            jar,
            (
                StatusCode::BAD_REQUEST,
                "Query state does not equal saved state",
            ),
        )
            .into_response());
    }

    let token_response = client
        .exchange_code(AuthorizationCode::new(query.code))?
        .request_async(&http_client)
        .await?;

    // Extract the ID token claims after verifying its authenticity and nonce.
    let id_token = token_response
        .id_token()
        .ok_or_else(|| anyhow!("Server did not return an ID token"))?;
    let id_token_verifier = client.id_token_verifier();
    let claims = id_token.claims(&id_token_verifier, &Nonce::new(cookie_nonce))?;

    // Verify the access token hash to ensure that the access token hasn't been substituted for
    // another user's.
    if let Some(expected_access_token_hash) = claims.access_token_hash() {
        let actual_access_token_hash = AccessTokenHash::from_token(
            token_response.access_token(),
            id_token.signing_alg()?,
            id_token.signing_key(&id_token_verifier)?,
        )?;
        if actual_access_token_hash != *expected_access_token_hash {
            return Ok((jar, (StatusCode::BAD_REQUEST, "Invalid access token")).into_response());
        }
    }

    session.insert("authenticated", true).await?;

    Ok((jar, Redirect::to("/")).into_response())
}
