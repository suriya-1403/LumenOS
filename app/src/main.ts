import { invoke } from "@tauri-apps/api/core";

interface Weather {
  temp_f: number;
  feels_like_f: number;
  high_f: number;
  low_f: number;
  humidity: number;
  condition: string;
}

interface Portfolio {
  total_value: number;
  day_change_value: number;
  day_change_percent: number;
  holdings: Array<{
    symbol: string;
    price: number;
    percent_change: number;
    value: number;
    sparkline: number[];
  }>;
}

const SVG_NS = "http://www.w3.org/2000/svg" as const;
const prefersReducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");

const TICK_COUNT = 32;

function buildBaseline(container: HTMLDivElement) {
  for (let i = 0; i < TICK_COUNT; i++) {
    const tick = document.createElement("span");
    tick.className = "baseline-tick";
    tick.style.animationDelay = `${(i / TICK_COUNT) * 3.2}s`;
    container.appendChild(tick);
  }
}

const baseline = document.querySelector<HTMLDivElement>("#baseline")!;
buildBaseline(baseline);

const hoursEl = document.querySelector<HTMLSpanElement>("#clock-hours")!;
const minutesEl = document.querySelector<HTMLSpanElement>("#clock-minutes")!;
const meridiemEl = document.querySelector<HTMLSpanElement>("#clock-meridiem")!;
const dayEl = document.querySelector<HTMLSpanElement>("#date-day")!;
const mdEl = document.querySelector<HTMLSpanElement>("#date-md")!;

const DAYS = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"];
const MONTHS = [
  "JAN", "FEB", "MAR", "APR", "MAY", "JUN",
  "JUL", "AUG", "SEP", "OCT", "NOV", "DEC",
];

function pad(n: number) {
  return n.toString().padStart(2, "0");
}

function tick() {
  const now = new Date();
  let hours = now.getHours() % 12;
  if (hours === 0) hours = 12;

  hoursEl.textContent = pad(hours);
  minutesEl.textContent = pad(now.getMinutes());
  meridiemEl.textContent = now.getHours() >= 12 ? "PM" : "AM";

  dayEl.textContent = DAYS[now.getDay()];
  mdEl.textContent = `${MONTHS[now.getMonth()]} ${pad(now.getDate())}`;
}

tick();
setInterval(tick, 1000);

const weatherTempEl = document.querySelector<HTMLSpanElement>("#weather-temp-val")!;
const weatherConditionEl = document.querySelector<HTMLSpanElement>("#weather-condition")!;
const weatherHighEl = document.querySelector<HTMLSpanElement>("#weather-high")!;
const weatherLowEl = document.querySelector<HTMLSpanElement>("#weather-low")!;

async function refreshWeather() {
  try {
    const weather = await invoke<Weather>("get_weather");
    weatherTempEl.textContent = String(weather.temp_f);
    weatherConditionEl.textContent = weather.condition;
    weatherHighEl.textContent = String(weather.high_f);
    weatherLowEl.textContent = String(weather.low_f);
  } catch (err) {
    weatherConditionEl.textContent = "UNAVAILABLE";
    console.error("weather fetch failed", err);
  }
}

refreshWeather();
setInterval(refreshWeather, 10 * 60 * 1000);

const portfolioTotalEl = document.querySelector<HTMLSpanElement>("#portfolio-total")!;
const portfolioChangeEl = document.querySelector<HTMLDivElement>("#portfolio-change")!;
const portfolioChangeTextEl = document.querySelector<HTMLSpanElement>("#portfolio-change-text")!;
const holdingsEl = document.querySelector<HTMLDivElement>("#holdings")!;

function formatMoney(n: number): string {
  return n.toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

const SPARK_W = 64;
const SPARK_H = 22;

// Builds the sparkline: a filled trend line, a dim reference line at the
// period's opening price (so "up/down from where this window started" reads
// at a glance, not just the raw shape), and a marker on the latest price.
// Reports the trend direction so the caller can color everything to match.
function buildSparkline(svg: SVGElement, values: number[]): "gain" | "loss" | "flat" {
  svg.innerHTML = "";
  svg.setAttribute("viewBox", `0 0 ${SPARK_W} ${SPARK_H}`);
  if (values.length < 2) return "flat";

  const min = Math.min(...values);
  const max = Math.max(...values);
  const range = max - min || 1;
  const toXY = (v: number, i: number): [number, number] => [
    (i / (values.length - 1)) * SPARK_W,
    SPARK_H - ((v - min) / range) * SPARK_H,
  ];

  const coords = values.map(toXY);
  const trend = values[values.length - 1] - values[0];
  const direction: "gain" | "loss" | "flat" =
    trend > 0.0001 ? "gain" : trend < -0.0001 ? "loss" : "flat";

  // Reference line at the opening price of the window.
  const [, openY] = toXY(values[0], 0);
  const baseline = document.createElementNS(SVG_NS, "line");
  baseline.setAttribute("x1", "0");
  baseline.setAttribute("x2", String(SPARK_W));
  baseline.setAttribute("y1", openY.toFixed(1));
  baseline.setAttribute("y2", openY.toFixed(1));
  baseline.setAttribute("class", "holding-spark-baseline");
  svg.appendChild(baseline);

  // Fill under the line, so the magnitude of the move reads as area, not
  // just a thin stroke.
  const fillPoints = [
    "0," + SPARK_H,
    ...coords.map(([x, y]) => `${x.toFixed(1)},${y.toFixed(1)}`),
    `${SPARK_W},${SPARK_H}`,
  ].join(" ");
  const fill = document.createElementNS(SVG_NS, "polygon");
  fill.setAttribute("points", fillPoints);
  fill.setAttribute("class", `holding-spark-fill is-${direction}`);
  svg.appendChild(fill);

  // The trend line itself — drawn with a left-to-right reveal on mount.
  const points = coords.map(([x, y]) => `${x.toFixed(1)},${y.toFixed(1)}`).join(" ");
  const line = document.createElementNS(SVG_NS, "polyline");
  line.setAttribute("points", points);
  line.setAttribute("class", `holding-spark-line is-${direction}`);
  svg.appendChild(line);

  const length = line.getTotalLength();
  line.style.strokeDasharray = `${length}`;
  line.style.strokeDashoffset = `${length}`;

  // Marker on the latest price — pulses gently, echoing the status-LED
  // language used elsewhere in the HUD.
  const [lastX, lastY] = coords[coords.length - 1];
  const dot = document.createElementNS(SVG_NS, "rect");
  dot.setAttribute("x", (lastX - 1.5).toFixed(1));
  dot.setAttribute("y", (lastY - 1.5).toFixed(1));
  dot.setAttribute("width", "3");
  dot.setAttribute("height", "3");
  dot.setAttribute("class", `holding-spark-dot is-${direction}`);
  svg.appendChild(dot);

  return direction;
}

function renderHoldings(holdings: Portfolio["holdings"]) {
  holdingsEl.innerHTML = "";
  holdings.forEach((h, i) => {
    const row = document.createElement("div");
    row.className = "holding-row";

    const symbol = document.createElement("span");
    symbol.className = "holding-symbol";
    symbol.textContent = h.symbol;

    const svg = document.createElementNS(SVG_NS, "svg");
    svg.setAttribute("class", "holding-spark");
    buildSparkline(svg, h.sparkline);

    const value = document.createElement("span");
    value.className = "holding-value";
    value.textContent = `$${h.value.toFixed(2)}`;

    const change = document.createElement("span");
    const isGain = h.percent_change >= 0;
    change.className = `holding-change is-${isGain ? "gain" : "loss"}`;
    change.textContent = `${isGain ? "+" : ""}${h.percent_change.toFixed(2)}%`;

    row.append(symbol, svg, value, change);
    holdingsEl.appendChild(row);

    // Stagger each row's line draw-in slightly so a refresh reads as one
    // cascading "coming online" moment rather than nine cards updating at
    // once — same one-orchestrated-moment principle as the boot flicker.
    const line = svg.querySelector<SVGPolylineElement>(".holding-spark-line")!;
    if (prefersReducedMotion.matches) {
      line.style.strokeDashoffset = "0";
    } else {
      line.animate(
        [{ strokeDashoffset: line.style.strokeDashoffset }, { strokeDashoffset: "0" }],
        { duration: 550, delay: i * 70, easing: "ease-out", fill: "forwards" },
      );
    }
  });
}

async function refreshPortfolio() {
  try {
    const portfolio = await invoke<Portfolio>("get_portfolio");
    portfolioTotalEl.textContent = formatMoney(portfolio.total_value);

    const sign = portfolio.day_change_value >= 0 ? "+" : "-";
    const abs = Math.abs(portfolio.day_change_value);
    const absPct = Math.abs(portfolio.day_change_percent);
    portfolioChangeTextEl.textContent = `${sign}$${formatMoney(abs)} (${sign}${absPct.toFixed(2)}%) TODAY`;

    portfolioChangeEl.classList.remove("is-gain", "is-loss");
    portfolioChangeEl.classList.add(portfolio.day_change_value >= 0 ? "is-gain" : "is-loss");

    renderHoldings(portfolio.holdings);
  } catch (err) {
    portfolioChangeTextEl.textContent = "UNAVAILABLE";
    console.error("portfolio fetch failed", err);
  }
}

refreshPortfolio();
setInterval(refreshPortfolio, 60 * 1000);
