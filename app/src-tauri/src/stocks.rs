use futures::future::join_all;
use serde::{Deserialize, Serialize};

// Holdings as of the portfolio screenshot on 2026-09-18. Edit share counts
// here as the portfolio changes — there's no brokerage integration, just
// live price lookups against these fixed positions.
const HOLDINGS: &[(&str, f64)] = &[
    ("VOO", 1.11),
    ("SCHD", 6.0),
    ("NVDA", 1.00),
    ("GOOGL", 1.01),
    ("GLD", 1.67),
    ("AAPL", 0.178469),
    ("PANW", 0.008751),
    ("LLY", 0.020427),
    ("AMZN", 1.0),
];

#[derive(Debug, Serialize)]
pub struct HoldingQuote {
    pub symbol: String,
    pub price: f64,
    pub percent_change: f64,
    pub value: f64,
    pub sparkline: Vec<f64>,
}

#[derive(Debug, Serialize)]
pub struct Portfolio {
    pub total_value: f64,
    pub day_change_value: f64,
    pub day_change_percent: f64,
    pub holdings: Vec<HoldingQuote>,
}

#[derive(Debug, Deserialize)]
struct FinnhubQuote {
    c: f64,  // current price
    #[allow(dead_code)]
    d: f64, // change
    dp: f64, // percent change
    pc: f64, // previous close
}

async fn fetch_quote(symbol: &str, api_key: &str) -> Result<FinnhubQuote, String> {
    let url = format!("https://finnhub.io/api/v1/quote?symbol={symbol}&token={api_key}");
    reqwest::get(&url)
        .await
        .map_err(|e| format!("{symbol}: request failed: {e}"))?
        .json::<FinnhubQuote>()
        .await
        .map_err(|e| format!("{symbol}: parse failed: {e}"))
}

#[derive(Debug, Deserialize)]
struct YahooChartResponse {
    chart: YahooChart,
}

#[derive(Debug, Deserialize)]
struct YahooChart {
    result: Option<Vec<YahooResult>>,
}

#[derive(Debug, Deserialize)]
struct YahooResult {
    indicators: YahooIndicators,
}

#[derive(Debug, Deserialize)]
struct YahooIndicators {
    quote: Vec<YahooQuote>,
}

#[derive(Debug, Deserialize)]
struct YahooQuote {
    close: Vec<Option<f64>>,
}

/// Last month of daily closes, for the sparkline only. Finnhub's free tier
/// doesn't include historical candles, so this hits Yahoo's public (unofficial,
/// no key needed) chart endpoint instead. Best-effort: on any failure this
/// returns an empty vec rather than failing the whole portfolio fetch.
async fn fetch_sparkline(symbol: &str, client: &reqwest::Client) -> Vec<f64> {
    let url = format!(
        "https://query1.finance.yahoo.com/v8/finance/chart/{symbol}?range=1mo&interval=1d"
    );

    let Ok(response) = client.get(&url).send().await else {
        return Vec::new();
    };
    let Ok(parsed) = response.json::<YahooChartResponse>().await else {
        return Vec::new();
    };

    parsed
        .chart
        .result
        .and_then(|mut results| results.pop())
        .and_then(|r| r.indicators.quote.into_iter().next())
        .map(|q| q.close.into_iter().flatten().collect())
        .unwrap_or_default()
}

pub async fn fetch_portfolio() -> Result<Portfolio, String> {
    let api_key = std::env::var("FINNHUB_API_KEY")
        .map_err(|_| "FINNHUB_API_KEY not set in .env.local".to_string())?;

    let client = reqwest::Client::builder()
        .user_agent("Mozilla/5.0 (compatible; LumenOS/0.1)")
        .build()
        .map_err(|e| format!("http client build failed: {e}"))?;

    let fetches = HOLDINGS.iter().map(|(symbol, shares)| {
        let client = &client;
        let api_key = &api_key;
        async move {
            let quote = fetch_quote(symbol, api_key).await;
            let sparkline = fetch_sparkline(symbol, client).await;
            (*symbol, *shares, quote, sparkline)
        }
    });
    let results = join_all(fetches).await;

    let mut holdings = Vec::with_capacity(HOLDINGS.len());
    let mut total_value = 0.0;
    let mut prev_total_value = 0.0;

    for (symbol, shares, quote, sparkline) in results {
        let quote = quote?;
        let value = quote.c * shares;
        total_value += value;
        prev_total_value += quote.pc * shares;

        holdings.push(HoldingQuote {
            symbol: symbol.to_string(),
            price: quote.c,
            percent_change: quote.dp,
            value,
            sparkline,
        });
    }

    let day_change_value = total_value - prev_total_value;
    let day_change_percent = if prev_total_value > 0.0 {
        (day_change_value / prev_total_value) * 100.0
    } else {
        0.0
    };

    Ok(Portfolio {
        total_value,
        day_change_value,
        day_change_percent,
        holdings,
    })
}
