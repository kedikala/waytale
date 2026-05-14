import { NextResponse } from "next/server";

const REALTIME_CLIENT_SECRET_URL = "https://api.openai.com/v1/realtime/client_secrets";

const toolDefinitions = [
  {
    type: "function",
    name: "end_realtime_session",
    description:
      "End the live Waytale voice session only when the passenger clearly and explicitly asks to end the session or hang up. Do not call this for ordinary thanks, goodbye, silence, background speech, stop/pause audio, or unclear phrases.",
    parameters: { type: "object", properties: {}, required: [] }
  },
  {
    type: "function",
    name: "ask_with_web_search",
    description:
      "Ask the general trip assistant. It can use current GPS context, nearby POIs, official Iceland feed snippets, and OpenAI web search for live/current answers.",
    parameters: {
      type: "object",
      properties: {
        question: { type: "string" },
        lat: { type: "number" },
        lon: { type: "number" },
        dayId: { type: "string" }
      },
      required: ["question"]
    }
  },
  {
    type: "function",
    name: "get_current_context",
    description: "Get the user's current GPS context, active itinerary day, nearest stop, active drive leg, nearby POIs, and active alerts.",
    parameters: {
      type: "object",
      properties: {
        lat: { type: "number" },
        lon: { type: "number" },
        dayId: { type: "string" }
      },
      required: []
    }
  },
  {
    type: "function",
    name: "get_nearby_pois",
    description: "Find curated and supplemental tour-guide points near the current GPS position.",
    parameters: {
      type: "object",
      properties: {
        lat: { type: "number" },
        lon: { type: "number" },
        dayId: { type: "string" }
      },
      required: ["lat", "lon"]
    }
  },
  {
    type: "function",
    name: "get_itinerary_stop",
    description: "Get an itinerary stop by id or the nearest itinerary stop to the user's position.",
    parameters: {
      type: "object",
      properties: {
        id: { type: "string" },
        lat: { type: "number" },
        lon: { type: "number" },
        dayId: { type: "string" }
      },
      required: []
    }
  },
  {
    type: "function",
    name: "get_weather_and_wind",
    description: "Get official nearby road weather station measurements, including temperature, wind speed, and gusts.",
    parameters: {
      type: "object",
      properties: {
        lat: { type: "number" },
        lon: { type: "number" }
      },
      required: []
    }
  },
  {
    type: "function",
    name: "get_road_disruptions",
    description: "Get official Umferdin/Road.is road notifications and road conditions for route numbers or regions.",
    parameters: {
      type: "object",
      properties: {
        roads: { type: "string", description: "Comma-separated road numbers, for example 1,36,41" },
        regions: { type: "string", description: "Comma-separated regions or keywords, for example South,Reykjanes" }
      },
      required: []
    }
  },
  {
    type: "function",
    name: "get_volcano_status",
    description: "Get official Reykjanes, Sundhnúkur, Grindavík, eruption, gas, and lava-field safety callouts.",
    parameters: { type: "object", properties: {}, required: [] }
  },
  {
    type: "function",
    name: "get_safety_alerts",
    description: "Get official safety alerts from Vedur, SafeTravel, and Umferdin.",
    parameters: { type: "object", properties: {}, required: [] }
  }
];

export async function GET() {
  const apiKey = process.env.OPENAI_API_KEY;
  const model = process.env.OPENAI_REALTIME_MODEL || "gpt-realtime-2";
  const voice = process.env.OPENAI_REALTIME_VOICE || "cedar";
  if (!apiKey) {
    return NextResponse.json(
      {
        error: "OPENAI_API_KEY is not configured. Add it to .env.local locally and Vercel project settings for deployment."
      },
      { status: 503 }
    );
  }

  const response = await fetch(REALTIME_CLIENT_SECRET_URL, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      session: {
        type: "realtime",
        model,
        reasoning: {
          effort: "low"
        },
        instructions:
          "You are Waytale, an Iceland GPS voice guide for a June 27-July 3, 2026 road trip. Always speak in English only. Use a warm, lower-register documentary storyteller delivery: calm, confident, vivid, and unrushed, like a great road-trip narrator. The app opens this session after the passenger taps Ask Waytale, so respond naturally to the passenger's live questions and follow-ups. Keep the session open by default. Only call end_realtime_session when the passenger clearly says an explicit end-session command such as 'end session', 'end this session', 'hang up', 'disconnect Waytale', or 'stop this conversation'. Do not end the session for ordinary thanks, goodbye, silence, background speech, unclear phrases, or requests to stop/pause the current audio. If the passenger says 'stop' or 'pause', stop the current spoken response but keep the session open unless they specifically mention ending the session or conversation. Call ask_with_web_search when current information, web search, official feeds, GPS coordinates, or nearby-context lookup would help. Give rich 60-90 second audio-guide narration for nearby POIs when asked about the area. Never replace emergency services, Road.is, SafeTravel, Vedur, or Google Maps.",
        audio: {
          input: {
            noise_reduction: {
              type: "near_field"
            },
            transcription: {
              model: "gpt-4o-mini-transcribe"
            },
            turn_detection: {
              type: "semantic_vad",
              eagerness: "auto",
              create_response: true,
              interrupt_response: true
            }
          },
          output: {
            voice
          }
        },
        tools: toolDefinitions,
        tool_choice: "auto"
      }
    })
  });

  const data = await response.json();
  if (!response.ok) {
    return NextResponse.json(
      { error: data?.error?.message ?? "Unable to create OpenAI Realtime client secret." },
      { status: response.status }
    );
  }

  return NextResponse.json(data, {
    headers: {
      "Cache-Control": "no-store"
    }
  });
}
