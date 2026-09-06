use axum::{
    Json,
    extract::State,
    http::StatusCode,
    response::{IntoResponse, Response},
};
use diesel::prelude::*;
use serde::{Deserialize, Serialize};
use tower_sessions::Session;

use crate::{AppResult, AppState, models::NewSetting, schema::settings};

pub const KEY_ASK_QUESTIONS_ENABLED: &str = "ask_questions_enabled";

fn bool_to_value(flag: bool) -> String {
    if flag {
        "true".to_string()
    } else {
        "false".to_string()
    }
}

fn value_to_bool(value: &str) -> bool {
    value.eq_ignore_ascii_case("true")
}

/// Returns whether asking questions is enabled. Missing rows default to
/// enabled so existing installs keep working without migrating any data.
pub fn ask_questions_enabled(conn: &mut SqliteConnection) -> AppResult<bool> {
    let row: Option<String> = settings::table
        .filter(settings::key.eq(KEY_ASK_QUESTIONS_ENABLED))
        .select(settings::value)
        .first(conn)
        .optional()?;

    match row {
        Some(value) => Ok(value_to_bool(&value)),
        None => Ok(true),
    }
}

#[derive(Serialize)]
pub struct AskQuestionsEnabledResponse {
    pub enabled: bool,
}

pub async fn get_ask_questions_enabled(
    State(app_state): State<AppState>,
) -> AppResult<Json<AskQuestionsEnabledResponse>> {
    let mut connection = app_state.db_pool.get()?;

    let enabled = ask_questions_enabled(&mut connection)?;

    Ok(Json(AskQuestionsEnabledResponse { enabled }))
}

#[derive(Deserialize)]
pub struct ModifyAskQuestionsEnabledRequest {
    enabled: bool,
}

pub async fn modify_ask_questions_enabled(
    State(app_state): State<AppState>,
    session: Session,
    Json(request): Json<ModifyAskQuestionsEnabledRequest>,
) -> AppResult<Response> {
    let mut connection = app_state.db_pool.get()?;

    let logged_in = session
        .get::<bool>("authenticated")
        .await
        .unwrap_or(None)
        .unwrap_or(false);
    if !logged_in {
        return Ok(StatusCode::FORBIDDEN.into_response());
    }

    let value = bool_to_value(request.enabled);

    diesel::insert_into(settings::table)
        .values(NewSetting {
            key: KEY_ASK_QUESTIONS_ENABLED.to_string(),
            value: value.clone(),
        })
        .on_conflict(settings::key)
        .do_update()
        .set(settings::value.eq(&value))
        .execute(&mut connection)?;

    Ok(StatusCode::OK.into_response())
}
