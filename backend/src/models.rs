use diesel::{
    backend::Backend,
    deserialize::{self, FromSql, FromSqlRow},
    expression::AsExpression,
    prelude::*,
    serialize::{self, ToSql},
    sql_types::Integer,
};
use serde::Serialize;
use serde_repr::{Deserialize_repr, Serialize_repr};

#[repr(i32)]
#[derive(Serialize_repr, Deserialize_repr, FromSqlRow, Debug, AsExpression)]
#[diesel(sql_type = Integer)]
pub enum QuestionState {
    Hidden = 0,
    Unanswered = 1,
    Answering = 2,
    Answered = 3,
    HiddenAnswered = 4,
}

impl QuestionState {
    pub fn to_string(self) -> String {
        match self {
            QuestionState::Hidden => "hidden",
            QuestionState::Unanswered => "unanswered",
            QuestionState::Answering => "answering",
            QuestionState::Answered => "answered",
            QuestionState::HiddenAnswered => "hidden_answered",
        }
        .into()
    }
}

impl<DB> FromSql<Integer, DB> for QuestionState
where
    DB: Backend,
    i32: FromSql<Integer, DB>,
{
    fn from_sql(bytes: DB::RawValue<'_>) -> deserialize::Result<Self> {
        match i32::from_sql(bytes)? {
            0 => Ok(QuestionState::Hidden),
            1 => Ok(QuestionState::Unanswered),
            2 => Ok(QuestionState::Answering),
            3 => Ok(QuestionState::Answered),
            4 => Ok(QuestionState::HiddenAnswered),
            x => Err(format!("Unrecognized variant {}", x).into()),
        }
    }
}

impl<DB> ToSql<Integer, DB> for QuestionState
where
    DB: Backend,
    i32: ToSql<Integer, DB>,
{
    fn to_sql<'b>(&'b self, out: &mut serialize::Output<'b, '_, DB>) -> serialize::Result {
        match self {
            QuestionState::Hidden => 0.to_sql(out),
            QuestionState::Unanswered => 1.to_sql(out),
            QuestionState::Answering => 2.to_sql(out),
            QuestionState::Answered => 3.to_sql(out),
            QuestionState::HiddenAnswered => 4.to_sql(out),
        }
    }
}

#[derive(Serialize, Queryable, Selectable)]
#[diesel(table_name = crate::schema::questions)]
#[diesel(check_for_backend(diesel::sqlite::Sqlite))]
pub struct Question {
    pub id: i32,
    pub text: String,
    pub state: QuestionState,
    pub upvotes: i32,
    pub created_at: i32,
    pub modified_at: i32,
    pub answering_at: i32,
    pub answered_at: i32,
}

/// Same as Question, just without id
#[derive(Insertable)]
#[diesel(table_name = crate::schema::questions)]
pub struct NewQuestion {
    pub text: String,
    pub state: QuestionState,
    pub upvotes: i32,
    pub created_at: i32,
    pub modified_at: i32,
    pub answering_at: i32,
    pub answered_at: i32,
}

#[repr(i32)]
#[derive(Serialize_repr, Deserialize_repr, FromSqlRow, Debug, AsExpression)]
#[diesel(sql_type = Integer)]
pub enum SurveyState {
    Hidden = 0,
    Open = 1,
}

impl<DB> FromSql<Integer, DB> for SurveyState
where
    DB: Backend,
    i32: FromSql<Integer, DB>,
{
    fn from_sql(bytes: DB::RawValue<'_>) -> deserialize::Result<Self> {
        match i32::from_sql(bytes)? {
            0 => Ok(SurveyState::Hidden),
            1 => Ok(SurveyState::Open),
            x => Err(format!("Unrecognized variant {}", x).into()),
        }
    }
}

impl<DB> ToSql<Integer, DB> for SurveyState
where
    DB: Backend,
    i32: ToSql<Integer, DB>,
{
    fn to_sql<'b>(&'b self, out: &mut serialize::Output<'b, '_, DB>) -> serialize::Result {
        match self {
            SurveyState::Hidden => 0.to_sql(out),
            SurveyState::Open => 1.to_sql(out),
        }
    }
}

#[derive(Serialize, Queryable, Selectable, Identifiable)]
#[diesel(table_name = crate::schema::surveys)]
#[diesel(check_for_backend(diesel::sqlite::Sqlite))]
pub struct Survey {
    pub id: i32,
    pub text: String,
    pub state: SurveyState,
}

/// Same as Survey, just without id
#[derive(Insertable)]
#[diesel(table_name = crate::schema::surveys)]
pub struct NewSurvey {
    pub text: String,
    pub state: SurveyState,
}

#[derive(Serialize, Queryable, Selectable, Associations, Identifiable)]
#[diesel(belongs_to(Survey, foreign_key = survey))]
#[diesel(table_name = crate::schema::survey_options)]
#[diesel(check_for_backend(diesel::sqlite::Sqlite))]
pub struct SurveyOption {
    pub id: i32,
    pub survey: i32,
    pub text: String,
    pub votes: i32,
}

/// same as SurveyOption, just without id
#[derive(Insertable)]
#[diesel(table_name = crate::schema::survey_options)]
pub struct NewSurveyOption {
    pub survey: i32,
    pub text: String,
    pub votes: i32,
}
