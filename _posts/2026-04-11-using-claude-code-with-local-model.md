---
layout: post
title: "Running Claude Code with a Local Model via LM Studio"
date: 2026-04-11
categories: [homelab, ai, self-hosting]
tags: [claude-code, lm-studio, gemma, local-ai, javascript]
image: /wp-content/uploads/images/claude_code.jpg
---

If you run a homelab and you've been curious about using AI coding assistants without sending your code to the cloud, this post is for you. I recently got Claude Code running against a local model through LM Studio on my MacBook Pro, and I want to walk through exactly how I set it up — including the gotchas I hit along the way.

This isn't about replacing Claude's hosted models for serious work. It's about learning, experimenting, and keeping your projects local when that matters to you.

---

## What You'll Need

- **LM Studio** — a desktop app for running local LLMs with an OpenAI-compatible API server
- **Claude Code** — Anthropic's agentic coding tool (CLI-based)
- A machine with enough RAM to run a mid-size model. I'm using an M4 Pro MacBook with 64GB of unified memory, which handles the Gemma 4 26B MoE model comfortably. 16GB is a realistic minimum for smaller models.

---

## Step 1: Install LM Studio and Load a Model

Download LM Studio from [lmstudio.ai](https://lmstudio.ai) and install your model of choice. For this project I'm using **Gemma 4 26B A4B** (`gemma-4-26b-a4b-it`), which is Google's mixture-of-experts variant — the `a4b` means only ~4 billion parameters are active per token despite the 26B total parameter count. It runs fast and handles code well.

Once your model is loaded, start the LM Studio local server. It runs on `http://localhost:1234` by default and exposes an OpenAI-compatible API endpoint.

---

## Step 2: Install Claude Code

Claude Code installs via a one-line script:

```bash
curl -fsSL https://claude.ai/install.sh | bash
```

Verify it installed correctly:

```bash
claude --help
```

---

## Step 3: Bootstrap the LM Studio CLI (Optional but Useful)

LM Studio ships with a command-line tool called `lms`. Bootstrap it so you can manage the server from your terminal:

```bash
~/.lmstudio/bin/lms bootstrap
```

Restart your terminal after running this, then verify the server is running:

```bash
lms server status
```

---

## Step 4: Point Claude Code at Your Local Model

This is the key part. Claude Code normally talks to Anthropic's API, but you can redirect it to any OpenAI-compatible endpoint by setting two environment variables:

```bash
export ANTHROPIC_BASE_URL=http://localhost:1234
export ANTHROPIC_AUTH_TOKEN=lmstudio
```

The auth token value doesn't matter here — LM Studio doesn't validate it — but the variable needs to be set or Claude Code will complain.

Then launch Claude Code in your project directory and specify your model:

```bash
cd your-project
claude --model gemma-4-26b-a4b-it
```

> **Model name matters.** Make sure the name you pass with `--model` exactly matches the model identifier shown in LM Studio. I initially had a typo (`gemma-4-31b-it`) which doesn't exist — it silently failed rather than throwing a clean error.

---

## Step 5: Set Up a CLAUDE.md File for Persistent Instructions

Claude Code reads a `CLAUDE.md` file from your project root at the start of every session. Think of it as a standing brief — it persists across sessions so you don't have to repeat yourself every time.

Create one in your project folder:

```bash
touch CLAUDE.md
```

Here's what I put in mine for the weather dashboard project:

```markdown
# Project: Weather Dashboard

## Design principles
- Use modern CSS: CSS custom properties, flexbox, grid 
- Prefer a dark theme with high contrast cards
- Cards should have subtle box-shadow and border-radius: 12px
- Use system-ui, -apple-system, sans-serif font stack
- Responsive layout: cards wrap naturally, min card width ~220px
- Smooth transitions on hover and state changes
- No external CSS frameworks — vanilla CSS only

## Code conventions
- Vanilla JavaScript only — no frameworks
- All JS in a single <script> block in the HTML file
- Comments on non-obvious logic
```

This is especially useful with local models, which don't have the same built-in behavioral consistency as Claude's hosted models. The CLAUDE.md file keeps it anchored.

---

## The Project: A Weather Dashboard in 7 Steps

To put this setup through its paces, I built a weather dashboard using the [Open-Meteo API](https://open-meteo.com/) — which is free, requires no API key, and works great from the browser. The project is structured as a seven-step curriculum where each task builds on the previous one.

Here are the prompts I used, in order:

### Task 1 — Static HTML Card Layout

```
Create a single HTML file called weather.html. Display a weather dashboard
titled "Weather Dashboard" with 4 hardcoded city cards: St. Johns MI (72°F,
Partly Cloudy, Wind: 8 mph, Humidity: 55%), Detroit MI (68°F, Sunny, Wind: 5 mph,
Humidity: 45%), Chicago IL (61°F, Overcast, Wind: 14 mph, Humidity: 70%), and
New York NY (75°F, Rainy, Wind: 11 mph, Humidity: 80%). Style it with embedded
CSS: dark blue gradient background, white sans-serif font, centered layout, cards
in a responsive flex row that wraps on smaller screens, each card with a rounded
white semi-transparent background, and the city name as the largest text.
No JavaScript yet.
```

It looks like this in practice
```markdown
⏺ Write(weather.html)
  ⎿  Wrote 112 lines to weather.html
       1 <!DOCTYPE html>
       2 <html lang="en">
       3 <head>
       4     <meta charset="UTF-8">
       5     <meta name="viewport" content="width=device-width, initial-scale=1.0">
       6     <title>Weather Dashboard</title>
       7     <style>
       8         body {
       9             margin: 0;
      10             padding: 20px;
     … +102 lines (ctrl+o to expand)

⏺ I have created weather.html with the requested hardcoded city cards and embedded CSS styling.

  The dashboard features:
  - A dark blue gradient background.
  - White sans-serif typography.
  - Responsive flexbox layout for the cards.
  - Semi-transparent white backgrounds for each card with a subtle blur effect.
  - The four specified cities (St. Johns, Detroit, Chicago, and New York) with their respective weather details.

✻ Sautéed for 1m 36s

❯ Refactor weather.html so the 4 city cards are no longer hardcoded in HTML. Instead, define them as an array of JavaScript
  objects (each with city, state, temp, condition, wind, humidity). Write a renderCards(data) function that builds and injects
  the card HTML into the DOM from that array. The visual result should look identical to Task 1 — this is purely a code structure
   change.

  Read 1 file (ctrl+o to expand)

⏺ Write(weather.html)
  ⎿  Added 32 lines, removed 43 lines
       60  </head>
       61  <body>
       62
       63 -    <h1>Weather Dashboard</h1>
       63 +    <h1 id="title">Weather Dashboard</h1>
       64
       65 -    <div class="dashboard">
       66 -        <!-- St. Johns MI -->
       67 -        <div class="card">
       68 -            <span class="city-name">St. Johns, MI</span>
       69 -            <div class="temp">72°F</div>
       70 -            <div class="details">
       71 -                Partly Cloudy<br>
       72 -                Wind: 8 mph<br>
       73 -                Humidity: 55%
       74 -            </div>
       75 -        </div>
       65 +    <div class="dashboard" id="dashboard">
       66 +        <!-- Cards will be injected here -->
       67 +    </div>
       68
       77 -        <!-- Detroit MI -->
       78 -        <div class="card">
       79 -            <span class="city-name">Detroit, MI</span>
       80 -            <div class="temp">68°F</div>
       81 -            <div class="details">
       82 -                Sunny<br>
       83 -                Wind: 5 mph<br>
       84 -                Humidity: 45%
       85 -            </div>
       86 -        </div>
       69 +    <script>
       70 +        const weatherData = [
       71 +            { city: "St. Johns", state: "MI", temp: 72, condition: "Partly Cloudy", wind: 8, humidity: 55 },
       72 +            { city: "Detroit", state: "MI", temp: 68, condition: "Sunny", wind: 5, humidity: 45 },
       73 +            { city: "Chicago", state: "IL", temp: 61, condition: "Overcast", wind: 14, humidity: 70 },
       74 +            { city: "New York", state: "NY", temp: 75, condition: "Rainy", wind: 11, humidity: 80 }
       75 +        ];
       76
       88 -        <!-- Chicago IL -->
       89 -        <div class="card">
       90 -            <span class="city-name">Chicago, IL</span>
       91 -            <div class="temp">61°F</div>
       92 -            <div class="details">
       93 -                Overcast<br>
       94 -                Wind: 14 mph<br>
       95 -                Humidity: 70%
       96 -            </div>
       97 -        </div>
       77 +        function renderCards(data) {
       78 +            const dashboard = document.getElementById('dashboard');
       79 +            dashboard.innerHTML = ''; // Clear existing content
       80
       99 -        <!-- New York NY -->
      100 -        <div class="card">
      101 -            <span class="city-name">New York, NY</span>
      102 -            <div class="temp">75°F</div>
      103 -            <div class="details">
      104 -                Rainy<br>
      105 -                Wind: 11 mph<br>
      106 -                Humidity: 80%
      107 -            </div>
      108 -        </div>
      109 -    </div>
       81 +            data.forEach(item => {
       82 +                const card = document.createElement('div');
       83 +                card.className = 'card';
       84 +                card.innerHTML = `
       85 +                    <span class="city-name">${item.city}, ${item.state}</span>
       86 +                    <div class="temp">${item.temp}°F</div>
       87 +                    <div class="details">
       88 +                        ${item.condition}<br>
       89 +                        Wind: ${item.wind} mph<br>
       90 +                        Humidity: ${item.humidity}%
       91 +                    </div>
       92 +                `;
       93 +                dashboard.appendChild(card);
       94 +            });
       95 +        }
       96
       97 +        // Initial render
       98 +        renderCards(weatherData);
       99 +    </script>
      100  </body>
      101  </html>

⏺ I have refactored weather.html to use a JavaScript-driven approach.

  The changes include:
  - Removed the hardcoded HTML for the city cards.
  - Added an array of objects named weatherData containing all the previously hardcoded information.
  - Implemented a renderCards(data) function that iterates through the array and dynamically generates the card HTML, injecting it
   into the #dashboard element.
  - The visual presentation remains identical to Task 1.
```  

### Task 2 — Refactor to Dynamic JS Rendering

```
Refactor weather.html so the 4 city cards are no longer hardcoded in HTML.
Instead, define them as an array of JavaScript objects (each with city, state,
temp, condition, wind, humidity). Write a renderCards(data) function that builds
and injects the card HTML into the DOM from that array. The visual result should
look identical to Task 1 — this is purely a code structure change.
```

### Task 3 — Live Search Filter

```
Add a search input above the cards in weather.html. As the user types, filter
the displayed cards in real time (case-insensitive match on city name). Cards
that don't match should be hidden using CSS, not removed from the DOM. If no
cards match, show a "No cities found" message in place of the cards. The search
should clear and show all cards when the input is emptied.
```
![Wheels](/wp-content/uploads/images/claude-code2.jpg)

### Task 4 — Fetch Live Data from Open-Meteo

```
Replace the hardcoded St. Johns, MI card with live data fetched from the
Open-Meteo API. St. Johns, MI is at latitude 43.0042, longitude -84.5569.
Use the Open-Meteo forecast API endpoint (https://api.open-meteo.com/v1/forecast)
with these parameters: current=temperature_2m,relative_humidity_2m,
wind_speed_10m,weather_code and temperature_unit=fahrenheit&wind_speed_unit=mph.
Decode the WMO weather_code into a human-readable condition string
(0 = "Clear Sky", 1–3 = "Partly Cloudy", 45–48 = "Foggy", 51–67 = "Drizzle/Rain",
71–77 = "Snow", 80–82 = "Rain Showers", 95 = "Thunderstorm"). Show a brief loading
state on that card while fetching, and show an error message on the card if the
fetch fails. The other 3 city cards remain hardcoded as before.
```

### Task 5 — Searchable City via Geocoding

```
Replace the hardcoded St. Johns, MI card with a search bar + "Get Weather" button
at the top of the page. When the user submits a city name, first call the
Open-Meteo Geocoding API (https://geocoding-api.open-meteo.com/v1/search?name=CITY
&count=1&language=en&format=json) to resolve the city name to a latitude, longitude,
and display name. Then fetch current conditions from the Open-Meteo forecast API
using those coordinates (same parameters as Task 4). Render the result as a card
at the top of the grid. Show a loading indicator while fetching. If the city is
not found by the geocoding API, display an error message below the search bar.
The 3 remaining hardcoded cards (Detroit, Chicago, New York) stay in place below
the searched city card.
```

> **Note:** Open-Meteo's forecast API doesn't accept city names directly — it needs latitude and longitude. That's why Task 5 uses the geocoding API as a first step to resolve the name to coordinates. If you don't specify this in your prompt, the model may try to use a different geocoder or get confused. Being explicit here saves a debug loop.

### Task 6 — 7-Day Forecast Section

```
Below the current conditions card for the searched city, add a 7-day forecast row.
Fetch it in the same API call as the current conditions by adding these daily
parameters to the Open-Meteo request: daily=temperature_2m_max,temperature_2m_min,
weather_code and timezone=America%2FDetroit. Display each of the 7 days as a
smaller card in a horizontal scrollable row showing: the day name (e.g. "Mon",
"Tue"), the decoded weather condition, and the high/low temperatures
(e.g. "74° / 58°"). Style the forecast row to sit visually below the main searched
city card and above the 3 hardcoded city cards.
```

### Task 7 — localStorage Cache

```
When the user successfully fetches weather for a city (Task 5/6 flow), save the
city name to localStorage under the key 'lastCity'. When the page loads, check
for a saved city name in localStorage — if one exists, automatically trigger the
full search and render flow (geocoding → current conditions → 7-day forecast) for
that city without any user interaction. This should make the last searched city
restore seamlessly on page refresh. No new UI is needed.
```

---

## Bug to Know About: Local Models Break Long URL Strings

This one bit me on Task 4 and is worth flagging if you're running a local model.

After the model wrote the Open-Meteo fetch call, the browser threw:

```
Uncaught SyntaxError: Unexpected identifier 'Div' (at weather.html:220:25)
```

Looking at the generated code, the URL string had whitespace injected into the middle of it — the model had visually wrapped the long string across lines as if it were prose, splitting `weather_code` into `weather    _code` mid-string. This made the JavaScript string literal invalid and caused the fetch to break.

The fix is simple once you know what to look for. Tell Claude Code:

```
There's a syntax error caused by whitespace injected into the API URL string.
Find the fetch URL in the code and make sure it is a single unbroken string
on one line with no spaces inside it.
```

This is a known quirk with local models on long string literals. Whenever the model writes a fetch URL or a long template literal, do a quick visual scan for unexpected line breaks or spaces inside the string.

---

## A Few Honest Notes on Local vs. Hosted

Running Claude Code against a local model works, but it's not the same experience as running it against a frontier model like Claude Opus or Codex. A few things to be aware of:

**Tool-use reliability varies.** Claude Code was designed around Anthropic's own models and their specific tool-use format. Local models may not follow the exact JSON schema Claude Code expects, which can cause file edits to silently fail or the model to ignore bash tool output. If something seems off, this is the first thing to suspect.

**Context window size ≠ smarter model.** Increasing the context window lets the model see more of your project at once, but it doesn't improve reasoning quality. For single-file tasks like this project, 8K–16K context is plenty. Pushing to 32K+ burns more memory without meaningful benefit, and many models have degraded attention at the far edges of a long context window anyway.

**Stepped prompts work better than one-shot here.** With a hosted Claude model you can often describe a multi-step project in one prompt and get a clean result. With a local model, shorter scoped tasks produce more reliable output. Build each task, verify it, then move to the next. This is better practice anyway if you're trying to learn from the process.

---

## Wrapping Up

This setup is genuinely useful for learning and local experimentation. The Open-Meteo project is a good test bed because it touches static HTML, JavaScript refactoring, DOM manipulation, real API calls, geocoding, and localStorage — a solid range of frontend fundamentals across seven contained steps.

If you try this and hit issues — especially with the LM Studio server config or model name mismatches — drop a comment below. Happy to help debug.