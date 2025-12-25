use diesel::prelude::*;

#[derive(Queryable, Selectable)]
#[diesel(table_name = crate::schema::questions)]
#[diesel(check_for_backend(diesel::sqlite::Sqlite))]
pub struct Post {
    pub id: i32,
    pub text: String,
    pub upvotes: i32,
    pub created_at: i32,
    pub modified_at: i32,
    pub answering_at: i32,
    pub answered_at: i32,
}
