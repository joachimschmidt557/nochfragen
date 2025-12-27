use clap::{Parser, Subcommand};
use fred::prelude::KeysInterface;
use nochfragen::connect_redis;
use scrypt::{
    Scrypt,
    password_hash::{PasswordHasher, SaltString, rand_core::OsRng},
};

#[derive(Parser)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Change the moderation password
    SetPassword { password: String },
}

#[tokio::main]
async fn main() {
    let args = Cli::parse();

    match args.command {
        Commands::SetPassword { password } => {
            let redis_pool = connect_redis().await;

            let salt = SaltString::generate(&mut OsRng);
            let hashed_password = Scrypt
                .hash_password(password.as_bytes(), &salt)
                .expect("Failed to hash password")
                .to_string();

            redis_pool
                .set::<(), _, _>("nochfragen", hashed_password, None, None, false)
                .await
                .expect("Failed to write password to redis");
        }
    }
}
