use axum::{
    Json,
    extract::{Path, State},
    http::StatusCode,
    response::{IntoResponse, Response},
};
use diesel::prelude::*;
use serde::{Deserialize, Serialize};
use tower_sessions::Session;

use crate::{
    AppResult, AppState,
    models::{NewSurveyOption, Survey, SurveyOption, SurveyState},
};
use crate::{
    models::NewSurvey,
    schema::{survey_options, surveys},
};

const MAX_QUESTION_LEN: usize = 500;

#[derive(Serialize)]
pub struct SurveyReponseOption {
    id: i32,
    text: String,
    votes: i32,
}

#[derive(Serialize)]
pub struct SurveyResponseSurvey {
    id: i32,
    text: String,
    state: SurveyState,
    voted: bool,
}

#[derive(Serialize)]
pub struct SurveyResponse {
    #[serde(flatten)]
    survey: SurveyResponseSurvey,
    options: Vec<SurveyReponseOption>,
}

pub async fn list_surveys(
    State(app_state): State<AppState>,
    session: Session,
) -> AppResult<Json<Vec<SurveyResponse>>> {
    let mut connection = app_state.db_pool.get()?;

    let logged_in = session
        .get::<bool>("authenticated")
        .await
        .unwrap_or(None)
        .unwrap_or(false);

    let all_questions = if logged_in {
        surveys::table
            .select(Survey::as_select())
            .load(&mut connection)?
    } else {
        surveys::table
            .filter(surveys::state.eq(SurveyState::Open))
            .select(Survey::as_select())
            .load(&mut connection)?
    };

    let all_survey_options = SurveyOption::belonging_to(&all_questions)
        .select(SurveyOption::as_select())
        .load(&mut connection)?;

    let surveys_and_options: Vec<(Survey, Vec<SurveyOption>)> = all_survey_options
        .grouped_by(&all_questions)
        .into_iter()
        .zip(all_questions)
        .map(|(options, survey)| (survey, options))
        .collect();

    let response: Vec<SurveyResponse> =
        futures::future::join_all(surveys_and_options.into_iter().map(
            async |(survey, options)| {
                let survey_id = survey.id;
                let voted = session
                    .get::<bool>(&format!("survey:{survey_id}").to_string())
                    .await
                    .unwrap_or(None)
                    .unwrap_or(false);

                SurveyResponse {
                    survey: SurveyResponseSurvey {
                        id: survey_id,
                        text: survey.text,
                        state: survey.state,
                        voted: voted,
                    },
                    options: options
                        .into_iter()
                        .map(|option| SurveyReponseOption {
                            id: option.id,
                            text: option.text,
                            votes: option.votes,
                        })
                        .collect(),
                }
            },
        ))
        .await;

    Ok(Json(response))
}

#[derive(Deserialize)]
pub struct AddSurveyRequest {
    text: String,
    options: Vec<String>,
}

pub async fn add_survey(
    State(app_state): State<AppState>,
    Json(request): Json<AddSurveyRequest>,
) -> AppResult<Response> {
    let mut connection = app_state.db_pool.get()?;

    let text = request.text;
    let options = request.options;

    if text.len() == 0 {
        return Ok((StatusCode::BAD_REQUEST, "Empty question").into_response());
    }

    if text.len() > MAX_QUESTION_LEN {
        return Ok((StatusCode::BAD_REQUEST, "Maximum question length exceeded").into_response());
    }

    if options.len() == 0 {
        return Ok((StatusCode::BAD_REQUEST, "No options provided").into_response());
    }

    let new_survey_id: i32 = diesel::insert_into(surveys::table)
        .values(NewSurvey {
            text,
            state: SurveyState::Hidden,
        })
        .returning(surveys::id)
        .get_result(&mut connection)?;

    diesel::insert_into(survey_options::table)
        .values(
            options
                .into_iter()
                .map(|text| NewSurveyOption {
                    survey: new_survey_id,
                    text,
                    votes: 0,
                })
                .collect::<Vec<NewSurveyOption>>(),
        )
        .execute(&mut connection)?;

    Ok(StatusCode::OK.into_response())
}

#[derive(Deserialize)]
pub struct ModifySurveyRequest {
    mode: i32,
    vote: i32,
    state: SurveyState,
}

pub async fn modify_survey(
    Path(survey_id): Path<i32>,
    State(app_state): State<AppState>,
    session: Session,
    Json(request): Json<ModifySurveyRequest>,
) -> AppResult<Response> {
    let mut connection = app_state.db_pool.get()?;

    match request.mode {
        0 => {
            let str_id = format!("survey:{survey_id}").to_string();

            let upvoted = session
                .get::<bool>(&str_id)
                .await
                .unwrap_or(None)
                .unwrap_or(false);
            if upvoted {
                return Ok((StatusCode::FORBIDDEN, "Already voted").into_response());
            }

            diesel::update(
                survey_options::table
                    .find(request.vote)
                    .filter(survey_options::survey.eq(survey_id)),
            )
            .set(survey_options::votes.eq(survey_options::votes + 1))
            .execute(&mut connection)?;

            session.insert(&str_id, true).await?;
        }
        1 => {
            let logged_in = session
                .get::<bool>("authenticated")
                .await
                .unwrap_or(None)
                .unwrap_or(false);
            if !logged_in {
                return Ok(StatusCode::FORBIDDEN.into_response());
            };

            diesel::update(surveys::table.find(survey_id))
                .set(surveys::state.eq(request.state))
                .execute(&mut connection)?;
        }
        _ => return Ok((StatusCode::BAD_REQUEST, "Invalid mode").into_response()),
    }

    Ok(StatusCode::OK.into_response())
}

pub async fn delete_survey(
    Path(survey_id): Path<i32>,
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

    diesel::delete(surveys::table.find(survey_id)).execute(&mut connection)?;

    Ok(StatusCode::OK)
}
