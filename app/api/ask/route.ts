import { NextRequest, NextResponse } from "next/server";
import { parsePosition } from "@/lib/api";
import { summarizeContext } from "@/lib/geo";
import { getRelevantRoadAlerts, getSafetyAlerts, getVolcanoAlerts, fetchWeatherStations } from "@/lib/officialFeeds";
import { curatedPois } from "@/data/pois";
import type { LatLng } from "@/lib/types";
import { classifyAskQuestion } from "@/lib/askClassifier";

const OPENAI_RESPONSES_URL = "https://api.openai.com/v1/responses";

type ResponseOutputItem = {
  type?: string;
  content?: Array<{
    type?: string;
    text?: string;
    annotations?: unknown[];
  }>;
  action?: {
    sources?: unknown[];
  };
};

function extractOutputText(data: { output_text?: string; output?: ResponseOutputItem[] }) {
  if (data.output_text) return data.output_text;
  return (
    data.output
      ?.flatMap((item) => item.content ?? [])
      .map((content) => content.text ?? "")
      .filter(Boolean)
      .join("\n\n") ?? ""
  );
}

function extractSources(data: { sources?: unknown[]; output?: ResponseOutputItem[] }) {
  if (data.sources) return data.sources;
  const actionSources = data.output?.flatMap((item) => item.action?.sources ?? []) ?? [];
  const annotationSources =
    data.output
      ?.flatMap((item) => item.content ?? [])
      .flatMap((content) => content.annotations ?? []) ?? [];
  return [...actionSources, ...annotationSources];
}

function isInIceland(position?: LatLng) {
  if (!position) return false;
  return position.lat >= 62.5 && position.lat <= 67.5 && position.lon >= -25.5 && position.lon <= -12;
}

function relevantTripKnowledge(question: string) {
  const lower = question.toLowerCase();
  const wantsWaterfalls = /waterfall|waterfalls|foss/.test(lower);
  const wantsVolcanoes = /volcano|volcanoes|eruption|lava|reykjanes|katla|eyjafjallaj/.test(lower);
  const wantsGlaciers = /glacier|glaciers|ice|lagoon|jokulsarlon|vatnajokull/.test(lower);

  const matches = curatedPois.filter((poi) => {
    if (wantsWaterfalls && (poi.type === "waterfall" || /foss/i.test(poi.name))) return true;
    if (wantsVolcanoes && poi.type === "volcano") return true;
    if (wantsGlaciers && poi.type === "glacier") return true;
    return lower.includes(poi.name.toLowerCase());
  });

  return matches.slice(0, 8).map((poi) => ({
    name: poi.name,
    type: poi.type,
    routeTags: poi.routeTags,
    narration: poi.narration,
    safetyNote: poi.safetyNote
  }));
}

function sanitizeNativeAppContext(context: unknown) {
  if (!context || typeof context !== "object") return context;
  const copy = structuredClone(context) as Record<string, unknown>;
  const coordinate = copy.coordinate as { latitude?: unknown; longitude?: unknown } | undefined;
  if (
    coordinate &&
    typeof coordinate.latitude === "number" &&
    typeof coordinate.longitude === "number" &&
    !isInIceland({ lat: coordinate.latitude, lon: coordinate.longitude })
  ) {
    copy.coordinate = undefined;
    copy.ignoredCoordinate = {
      ...coordinate,
      reason: "Outside Iceland; likely simulator/default GPS."
    };
  }
  return copy;
}

function asksForCurrentPlace(question: string) {
  return /\b(here|nearby|near us|near me|around us|where we are|where am i|current location|this place|right now|driving by|passing|nearest|close to us)\b/i.test(
    question
  );
}

export async function POST(request: NextRequest) {
  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) {
    return NextResponse.json({ error: "OPENAI_API_KEY is not configured." }, { status: 503 });
  }

  const body = (await request.json()) as {
    question?: string;
    lat?: number;
    lon?: number;
    dayId?: string;
    context?: unknown;
  };
  const question = body.question?.trim();
  if (!question) return NextResponse.json({ error: "Missing question." }, { status: 400 });

  const searchParams = new URLSearchParams();
  if (Number.isFinite(body.lat)) searchParams.set("lat", String(body.lat));
  if (Number.isFinite(body.lon)) searchParams.set("lon", String(body.lon));
  const rawPosition = parsePosition(searchParams);
  const position = isInIceland(rawPosition) ? rawPosition : undefined;
  const dayId = body.dayId ?? "2026-06-29";
  const serverContext = summarizeContext(position, dayId);
  const classification = classifyAskQuestion(question);
  const usePlaceContext = asksForCurrentPlace(question) || classification.useWeather || classification.useSafety;
  const sanitizedNativeAppContext = usePlaceContext ? sanitizeNativeAppContext(body.context) : undefined;

  const officialContext: string[] = [];
  if (classification.useWeather && position) {
    const stations = await fetchWeatherStations(position).catch(() => []);
    const nearest = stations[0];
    if (nearest) {
      officialContext.push(
        `Nearest official road weather station: ${nearest.name}, last update ${nearest.lastUpdate}, temperature ${nearest.temperature ?? "unknown"} C, wind ${nearest.wind?.speed ?? "unknown"} m/s, gust ${nearest.wind?.gust ?? "unknown"} m/s, direction ${nearest.windDirection?.description ?? "unknown"}.`
      );
    }
  }
  if (classification.useSafety) {
    const [safety, volcano, road] = await Promise.allSettled([
      getSafetyAlerts(),
      getVolcanoAlerts(),
      getRelevantRoadAlerts(serverContext.activeLeg?.roadNumbers ?? [], ["South", "Reykjanes", "Southwest"])
    ]);
    const alerts = [
      ...(safety.status === "fulfilled" ? safety.value.slice(0, 3) : []),
      ...(volcano.status === "fulfilled" ? volcano.value.slice(0, 2) : []),
      ...(road.status === "fulfilled" ? road.value.slice(0, 3) : [])
    ];
    for (const alert of alerts) {
      officialContext.push(
        `${alert.source} ${alert.severity}: ${alert.title}. ${alert.summary} ${alert.lastUpdated ? `Updated ${alert.lastUpdated}.` : ""} ${alert.url ? `URL: ${alert.url}` : ""}`
      );
    }
  }

  const input = [
    {
      role: "system",
      content:
        "You are a practical Iceland road-trip voice assistant. Answer in English only. Use Iceland trip context and curated POI notes first. Only speak as if the user is physically near a place when the question asks about here/nearby/current location or current conditions. If GPS is missing, omitted, or ignored because it is outside Iceland, do not infer the user wants information about that outside location; answer for the Iceland trip/day context instead. Use live/current caveats only when the question asks for current conditions. Keep answers spoken, useful in a car, and avoid over-explaining implementation details. Do not replace emergency services, SafeTravel, Vedur, Road.is, or navigation apps."
    },
    {
      role: "user",
      content: JSON.stringify({
        question,
        currentGps: usePlaceContext ? position : undefined,
        ignoredGps:
          usePlaceContext && rawPosition && !position
            ? { ...rawPosition, reason: "Outside Iceland; likely simulator/default GPS." }
            : undefined,
        activeDayId: dayId,
        nearestStop: usePlaceContext ? serverContext.nearestStop : undefined,
        nearestStopDistanceM: usePlaceContext ? serverContext.nearestStopDistanceM : undefined,
        activeLeg: usePlaceContext ? serverContext.activeLeg : undefined,
        nearbyPois: usePlaceContext ? serverContext.nearbyPois : undefined,
        nativeAppContext: sanitizedNativeAppContext,
        relevantTripKnowledge: relevantTripKnowledge(question),
        officialContext,
        routing: classification
      })
    }
  ];

  const responsePayload: Record<string, unknown> = {
    model: classification.useWebSearch
      ? process.env.OPENAI_ASK_LIVE_MODEL || process.env.OPENAI_ASK_MODEL || "gpt-4.1-mini"
      : process.env.OPENAI_ASK_FAST_MODEL || "gpt-4.1-mini",
    max_output_tokens: classification.useWebSearch ? 900 : 650,
    input
  };

  if (classification.useWebSearch) {
    responsePayload.tools = [
      {
        type: "web_search",
        user_location: {
          type: "approximate",
          country: "IS",
          timezone: "Atlantic/Reykjavik"
        }
      }
    ];
    responsePayload.tool_choice = "auto";
    responsePayload.include = ["web_search_call.action.sources"];
  }

  const response = await fetch(OPENAI_RESPONSES_URL, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify(responsePayload)
  });

  const data = await response.json();
  if (!response.ok) {
    return NextResponse.json(
      { error: data?.error?.message ?? "OpenAI ask request failed." },
      { status: response.status }
    );
  }

  return NextResponse.json({
    answer: extractOutputText(data),
    sources: extractSources(data),
    raw: data
  });
}
