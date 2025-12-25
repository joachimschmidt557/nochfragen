use axum::Json;
use axum::extract::Path;
use axum::http::{HeaderMap, HeaderValue, header};
use axum::response::Response;
use axum::{extract::State, http::StatusCode, response::IntoResponse};
use diesel::prelude::*;
use diesel::{QueryDsl, RunQueryDsl, SelectableHelper};
use serde::{Deserialize, Serialize};
use time::UtcDateTime;
use time::format_description::well_known::iso8601::TimePrecision;
use time::format_description::well_known::{Iso8601, iso8601};
use tower_sessions::Session;

use crate::models::{NewQuestion, Question, QuestionState};
use crate::{AppResult, AppState};

const MAX_QUESTION_LEN: usize = 500;

#[derive(Serialize)]
pub struct QuestionResponse {
    id: i32,
    text: String,
    upvotes: i32,
    state: QuestionState,
    upvoted: bool,
}

pub async fn list_questions(
    State(app_state): State<AppState>,
    session: Session,
) -> AppResult<Json<Vec<QuestionResponse>>> {
    let mut connection = app_state.db_pool.get()?;

    let logged_in = session
        .get::<bool>("authenticated")
        .await
        .unwrap_or(None)
        .unwrap_or(false);

    use crate::schema::questions::dsl::*;
    let result = if logged_in {
        questions
            .select(Question::as_select())
            .load(&mut connection)
    } else {
        questions
            .filter(state.eq_any(vec![
                QuestionState::Unanswered,
                QuestionState::Answering,
                QuestionState::Answered,
            ]))
            .select(Question::as_select())
            .load(&mut connection)
    };

    let result: Vec<QuestionResponse> =
        futures::future::join_all(result?.into_iter().map(async |question| {
            let question_id = question.id;

            QuestionResponse {
                id: question.id,
                text: question.text,
                upvotes: question.upvotes,
                state: question.state,
                upvoted: session
                    .get::<bool>(&format!("question:{question_id}").to_string())
                    .await
                    .unwrap_or(None)
                    .unwrap_or(false),
            }
        }))
        .await;

    Ok(Json(result))
}

#[derive(Deserialize)]
pub struct AddQuestionRequest {
    text: String,
}

pub async fn add_question(
    State(app_state): State<AppState>,
    Json(request): Json<AddQuestionRequest>,
) -> AppResult<Response> {
    let mut connection = app_state.db_pool.get()?;

    let text = request.text;

    if text.len() == 0 {
        return Ok((StatusCode::BAD_REQUEST, "Empty question").into_response());
    }

    if text.len() > MAX_QUESTION_LEN {
        return Ok((StatusCode::BAD_REQUEST, "Maximum question length exceeded").into_response());
    }

    let current_time = UtcDateTime::now().unix_timestamp().try_into()?;

    use crate::schema::questions;
    diesel::insert_into(questions::table)
        .values(NewQuestion {
            text,
            state: QuestionState::Hidden,
            upvotes: 0,
            created_at: current_time,
            modified_at: -1,
            answering_at: -1,
            answered_at: -1,
        })
        .execute(&mut connection)?;

    Ok(StatusCode::OK.into_response())
}

pub async fn delete_all_questions(
    State(app_state): State<AppState>,
    session: Session,
) -> AppResult<StatusCode> {
    let mut connection = app_state.db_pool.get()?;

    let logged_in = session
        .get::<bool>("authenticated")
        .await
        .unwrap_or(None)
        .unwrap_or(false);
    if !logged_in {
        return Ok(StatusCode::FORBIDDEN);
    };

    use crate::schema::questions;
    diesel::delete(questions::table).execute(&mut connection)?;

    Ok(StatusCode::OK)
}

#[derive(Deserialize)]
pub struct ModifyQuestionRequest {
    upvote: bool,
    state: QuestionState,
}

pub async fn modify_question(
    Path(question_id): Path<i32>,
    State(app_state): State<AppState>,
    session: Session,
    Json(request): Json<ModifyQuestionRequest>,
) -> AppResult<Response> {
    let mut connection = app_state.db_pool.get()?;

    if request.upvote {
        let str_id = format!("question:{question_id}").to_string();

        let upvoted = session
            .get::<bool>(&str_id)
            .await
            .unwrap_or(None)
            .unwrap_or(false);
        if upvoted {
            return Ok((StatusCode::FORBIDDEN, "Already upvoted").into_response());
        }

        use crate::schema::questions::dsl::*;
        diesel::update(questions.find(question_id))
            .set(upvotes.eq(upvotes + 1))
            .execute(&mut connection)?;

        session.insert(&str_id, true).await?;
    } else {
        let logged_in = session
            .get::<bool>("authenticated")
            .await
            .unwrap_or(None)
            .unwrap_or(false);
        if !logged_in {
            return Ok(StatusCode::FORBIDDEN.into_response());
        };

        let current_time: i32 = UtcDateTime::now().unix_timestamp().try_into()?;

        use crate::schema::questions::dsl::*;
        match request.state {
            QuestionState::Hidden | QuestionState::Unanswered | QuestionState::HiddenAnswered => {
                diesel::update(questions.find(question_id))
                    .set((state.eq(request.state), modified_at.eq(current_time)))
                    .execute(&mut connection)?;
            }

            QuestionState::Answering => {
                diesel::update(questions.find(question_id))
                    .set((state.eq(request.state), answering_at.eq(current_time)))
                    .execute(&mut connection)?;
            }

            QuestionState::Answered => {
                diesel::update(questions.find(question_id))
                    .set((state.eq(request.state), answered_at.eq(current_time)))
                    .execute(&mut connection)?;
            }
        }
    }

    Ok(StatusCode::OK.into_response())
}

pub async fn delete_question(
    Path(question_id): Path<i32>,
    State(app_state): State<AppState>,
    session: Session,
) -> AppResult<StatusCode> {
    let mut connection = app_state.db_pool.get()?;

    let logged_in = session
        .get::<bool>("authenticated")
        .await
        .unwrap_or(None)
        .unwrap_or(false);
    if !logged_in {
        return Ok(StatusCode::FORBIDDEN);
    };

    use crate::schema::questions::dsl::*;
    diesel::delete(questions.find(question_id)).execute(&mut connection)?;

    Ok(StatusCode::OK)
}

fn unix_timestamp_to_str(timestamp: i32) -> anyhow::Result<String> {
    const CONFIG: iso8601::Config =
        iso8601::Config::DEFAULT.set_time_precision(TimePrecision::Second {
            decimal_digits: None,
        });
    let format = Iso8601::<{ CONFIG.encode() }>;

    let timestamp = UtcDateTime::from_unix_timestamp(timestamp.into())?;
    Ok(timestamp.format(&format)?)
}

pub async fn export_questions(
    State(app_state): State<AppState>,
    session: Session,
) -> AppResult<Response> {
    let mut connection = app_state.db_pool.get()?;

    let logged_in = session
        .get::<bool>("authenticated")
        .await
        .unwrap_or(None)
        .unwrap_or(false);
    if !logged_in {
        return Ok(StatusCode::FORBIDDEN.into_response());
    };

    use crate::schema::questions::dsl::*;
    let result = questions
        .select(Question::as_select())
        .load(&mut connection)?;

    #[derive(Serialize)]
    struct Row {
        text: String,
        upvotes: i32,
        state: String,
        created_at: String,
        modified_at: String,
        answering_at: String,
        answered_at: String,
    }

    impl TryFrom<Question> for Row {
        type Error = anyhow::Error;

        fn try_from(question: Question) -> Result<Self, Self::Error> {
            Ok(Self {
                text: question.text,
                upvotes: question.upvotes,
                state: question.state.to_string(),
                created_at: unix_timestamp_to_str(question.created_at)?,
                modified_at: unix_timestamp_to_str(question.modified_at)?,
                answering_at: unix_timestamp_to_str(question.answering_at)?,
                answered_at: unix_timestamp_to_str(question.answered_at)?,
            })
        }
    }

    let rows: Vec<Row> = result
        .into_iter()
        .map(Row::try_from)
        .collect::<anyhow::Result<Vec<Row>>>()?;

    let mut writer = csv::Writer::from_writer(vec![]);
    for row in rows {
        writer.serialize(row)?;
    }

    let mut headers = HeaderMap::new();
    headers.append(
        header::CONTENT_DISPOSITION,
        HeaderValue::from_str("attachment; filename=\"questions.csv\"")
            .expect("Static header should always be valid"),
    );

    Ok((headers, String::from_utf8(writer.into_inner()?)?).into_response())
}
