mod stocks;
mod weather;

use stocks::Portfolio;
use weather::Weather;

#[tauri::command]
async fn get_weather() -> Result<Weather, String> {
    weather::fetch_weather().await
}

#[tauri::command]
async fn get_portfolio() -> Result<Portfolio, String> {
    stocks::fetch_portfolio().await
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    dotenvy::from_filename(concat!(env!("CARGO_MANIFEST_DIR"), "/.env.local")).ok();

    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .invoke_handler(tauri::generate_handler![get_weather, get_portfolio])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
