use serde::{Deserialize, Serialize};

// Phoenix, AZ (fixed — this is a wall-mounted device, not something that travels).
const LATITUDE: f64 = 33.44838;
const LONGITUDE: f64 = -112.07404;
const TIMEZONE: &str = "America/Phoenix";

#[derive(Debug, Serialize, Deserialize)]
pub struct Weather {
    pub temp_f: i32,
    pub feels_like_f: i32,
    pub high_f: i32,
    pub low_f: i32,
    pub humidity: i32,
    pub condition: String,
}

#[derive(Debug, Deserialize)]
struct OpenMeteoResponse {
    current: CurrentBlock,
    daily: DailyBlock,
}

#[derive(Debug, Deserialize)]
struct CurrentBlock {
    temperature_2m: f64,
    apparent_temperature: f64,
    weather_code: i32,
    relative_humidity_2m: i32,
}

#[derive(Debug, Deserialize)]
struct DailyBlock {
    temperature_2m_max: Vec<f64>,
    temperature_2m_min: Vec<f64>,
}

fn describe_wmo_code(code: i32) -> &'static str {
    match code {
        0 => "CLEAR",
        1 | 2 => "PARTLY CLOUDY",
        3 => "OVERCAST",
        45 | 48 => "FOG",
        51 | 53 | 55 => "DRIZZLE",
        56 | 57 => "FREEZING DRIZZLE",
        61 | 63 | 65 => "RAIN",
        66 | 67 => "FREEZING RAIN",
        71 | 73 | 75 | 77 => "SNOW",
        80 | 81 | 82 => "SHOWERS",
        85 | 86 => "SNOW SHOWERS",
        95 => "THUNDERSTORM",
        96 | 99 => "SEVERE STORM",
        _ => "UNKNOWN",
    }
}

pub async fn fetch_weather() -> Result<Weather, String> {
    let url = format!(
        "https://api.open-meteo.com/v1/forecast?latitude={lat}&longitude={lon}&current=temperature_2m,apparent_temperature,weather_code,relative_humidity_2m&daily=temperature_2m_max,temperature_2m_min&temperature_unit=fahrenheit&timezone={tz}",
        lat = LATITUDE,
        lon = LONGITUDE,
        tz = TIMEZONE,
    );

    let response = reqwest::get(&url)
        .await
        .map_err(|e| format!("weather request failed: {e}"))?
        .json::<OpenMeteoResponse>()
        .await
        .map_err(|e| format!("weather response parse failed: {e}"))?;

    Ok(Weather {
        temp_f: response.current.temperature_2m.round() as i32,
        feels_like_f: response.current.apparent_temperature.round() as i32,
        high_f: response.daily.temperature_2m_max.first().copied().unwrap_or_default().round() as i32,
        low_f: response.daily.temperature_2m_min.first().copied().unwrap_or_default().round() as i32,
        humidity: response.current.relative_humidity_2m,
        condition: describe_wmo_code(response.current.weather_code).to_string(),
    })
}
