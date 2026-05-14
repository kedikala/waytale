import type { LatLng, LiveAlert } from "@/lib/types";
import { distanceMeters } from "@/lib/geo";

const VEDUR_CAP_FEED = "https://api.vedur.is/cap/v1/capbroker/active/feed/met";
const SAFETRAVEL_ALERT_FEED = "https://safetravel.is/alert/feed/";
const SAFETRAVEL_REYKJANES = "https://safetravel.is/eruption-in-reykjanes/";
const UMFERDIN_GRAPHQL = "https://umferdin.is/graphql";

type GraphQlResponse<T> = {
  data?: T;
  errors?: Array<{ message: string }>;
};

function stripHtml(value: string) {
  return value
    .replace(/<!\[CDATA\[/g, "")
    .replace(/\]\]>/g, "")
    .replace(/<[^>]*>/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function xmlDecode(value: string) {
  return stripHtml(value)
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'");
}

function extractItems(xml: string) {
  const itemMatches = xml.match(/<item[\s\S]*?<\/item>/gi) ?? [];
  return itemMatches.map((item) => {
    const tag = (name: string) => {
      const match = item.match(new RegExp(`<${name}[^>]*>([\\s\\S]*?)<\\/${name}>`, "i"));
      return match ? xmlDecode(match[1]) : "";
    };
    return {
      title: tag("title"),
      description: tag("description"),
      link: tag("link"),
      pubDate: tag("pubDate"),
      guid: tag("guid")
    };
  });
}

function severityFromText(text: string): LiveAlert["severity"] {
  const lower = text.toLowerCase();
  if (/\b(red|closed|evacuat|eruption|danger|do not|gas)\b/.test(lower)) return "critical";
  if (/\b(orange|warning|storm|hazard|prohibited|closure|yellow)\b/.test(lower)) return "warning";
  if (/\b(watch|unrest|caution|advisory|slippery)\b/.test(lower)) return "watch";
  return "info";
}

export async function fetchVedurAlerts(): Promise<LiveAlert[]> {
  const response = await fetch(VEDUR_CAP_FEED, { next: { revalidate: 300 } });
  if (!response.ok) throw new Error(`Vedur CAP feed failed: ${response.status}`);
  const xml = await response.text();
  return extractItems(xml).map((item, index) => ({
    id: item.guid || `vedur-${index}-${item.pubDate}`,
    source: "Vedur",
    severity: severityFromText(`${item.title} ${item.description}`),
    title: item.title || "Icelandic Met Office alert",
    summary: item.description || "Official meteorological alert.",
    url: item.link || VEDUR_CAP_FEED,
    lastUpdated: item.pubDate
  }));
}

export async function fetchSafeTravelAlerts(): Promise<LiveAlert[]> {
  const response = await fetch(SAFETRAVEL_ALERT_FEED, { next: { revalidate: 300 } });
  if (!response.ok) throw new Error(`SafeTravel alert feed failed: ${response.status}`);
  const xml = await response.text();
  return extractItems(xml).map((item, index) => ({
    id: item.guid || `safetravel-${index}-${item.pubDate}`,
    source: "SafeTravel",
    severity: severityFromText(`${item.title} ${item.description}`),
    title: item.title || "SafeTravel alert",
    summary: item.description || "Official SafeTravel alert.",
    url: item.link || SAFETRAVEL_ALERT_FEED,
    lastUpdated: item.pubDate
  }));
}

async function umferdinQuery<T>(query: string, variables?: Record<string, unknown>) {
  const response = await fetch(UMFERDIN_GRAPHQL, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ query, variables }),
    next: { revalidate: 180 }
  });
  if (!response.ok) throw new Error(`Umferdin GraphQL failed: ${response.status}`);
  const json = (await response.json()) as GraphQlResponse<T>;
  if (json.errors?.length) throw new Error(json.errors.map((error) => error.message).join("; "));
  return json.data as T;
}

export async function fetchRoadNotifications(): Promise<LiveAlert[]> {
  const data = await umferdinQuery<{
    RoadNotifications: {
      results: Array<{
        id: string;
        category: string | null;
        key: string | null;
        subCategory: string | null;
        text: string;
        tags: string[];
        date: string;
      }>;
    };
  }>(
    `query RoadNotifications($language: RoadNotificationsLanguage) {
      RoadNotifications(language: $language) {
        results { id category key subCategory text tags date }
      }
    }`,
    { language: "EN" }
  );

  return (data.RoadNotifications?.results ?? []).map((item) => ({
    id: `road-${item.id}`,
    source: "Umferdin",
    severity: severityFromText(item.text),
    title: [item.category, item.subCategory].filter(Boolean).join(" · ") || "Road notification",
    summary: item.text.trim(),
    region: item.category ?? item.key ?? undefined,
    url: "https://umferdin.is/en",
    lastUpdated: item.date
  }));
}

export async function fetchRoadConditions() {
  return umferdinQuery<{
    RoadCondition: {
      lastUpdate: string;
      results: Array<{
        id: string;
        name: string;
        condition?: { code: string; category: string; description: string; date: string };
        conditionMarkers: Array<{ description: string; code: string; lastUpdate: string }>;
        roads: Array<{ name: string; nr: string }>;
      }>;
    };
  }>(
    `fragment RoadConditionInfo on RoadConditionInfo {
      code category description date
    }
    query RoadCondition($testdata: Boolean, $lang: Languages) {
      RoadCondition(testdata: $testdata, lang: $lang) {
        lastUpdate
        results {
          id name
          condition { ...RoadConditionInfo }
          conditionMarkers { description code lastUpdate }
          roads { name nr }
        }
      }
    }`,
    { testdata: false, lang: "EN" }
  );
}

export async function fetchWeatherStations(position?: LatLng) {
  const data = await umferdinQuery<{
    WeatherStations: {
      results: Array<{
        id: string;
        name: string;
        owner: string;
        lastUpdate: string;
        wind?: { speed: number | null; gust: number | null };
        windAlert?: string | null;
        windDirection?: { description: string; degrees: number };
        temperature?: number | null;
        roadTemperature?: number | null;
        coordinates: LatLng;
      }>;
    };
  }>(
    `fragment WeatherStationsResult on WeatherStation {
      id name owner lastUpdate
      wind { speed gust }
      windAlert
      windDirection { description degrees }
      temperature roadTemperature
      coordinates { lat lon }
    }
    query WeatherStations($testdata: Boolean) {
      WeatherStations(testdata: $testdata) {
        results { ...WeatherStationsResult }
      }
    }`,
    { testdata: false }
  );

  const stations = data.WeatherStations?.results ?? [];
  if (!position) return stations.slice(0, 8);
  return stations
    .filter((station) => station.coordinates)
    .map((station) => ({ ...station, distanceM: distanceMeters(position, station.coordinates) }))
    .sort((a, b) => a.distanceM - b.distanceM)
    .slice(0, 5);
}

export async function getRelevantRoadAlerts(roadNumbers: string[] = [], regionKeywords: string[] = []) {
  const [notifications, conditions] = await Promise.all([
    fetchRoadNotifications(),
    fetchRoadConditions().catch(() => undefined)
  ]);
  const terms = [...roadNumbers, ...regionKeywords].map((term) => term.toLowerCase());
  const matchedNotifications = notifications.filter((alert) => {
    const haystack = `${alert.title} ${alert.summary} ${alert.region ?? ""}`.toLowerCase();
    return terms.length === 0 || terms.some((term) => haystack.includes(term));
  });
  const conditionAlerts =
    conditions?.RoadCondition.results
      .filter((road) => roadNumbers.some((nr) => road.roads.some((entry) => entry.nr === nr)))
      .filter((road) => road.condition && !["Easily passable", "Not known"].includes(road.condition.description))
      .map<LiveAlert>((road) => ({
        id: `condition-${road.id}-${road.condition?.code}`,
        source: "Umferdin",
        severity: severityFromText(`${road.condition?.description} ${road.conditionMarkers.map((m) => m.description).join(" ")}`),
        title: `${road.name} road condition`,
        summary: `${road.condition?.description ?? "Road condition update"}. ${road.conditionMarkers
          .map((marker) => marker.description)
          .join(" ")}`.trim(),
        region: road.roads.map((entry) => entry.nr).join(", "),
        url: "https://umferdin.is/en",
        lastUpdated: road.condition?.date
      })) ?? [];
  return [...matchedNotifications, ...conditionAlerts].slice(0, 10);
}

export async function getVolcanoAlerts() {
  const [vedur, safetravel] = await Promise.allSettled([fetchVedurAlerts(), fetchSafeTravelAlerts()]);
  const alerts = [
    ...(vedur.status === "fulfilled" ? vedur.value : []),
    ...(safetravel.status === "fulfilled" ? safetravel.value : [])
  ].filter((alert) =>
    /volcano|eruption|reykjanes|sundhnúkur|grindavík|fagradalsfjall|gas|lava/i.test(
      `${alert.title} ${alert.summary}`
    )
  );

  if (alerts.length) return alerts;
  return [
    {
      id: "volcano-check-links",
      source: "SafeTravel",
      severity: "watch",
      title: "Reykjanes volcano status check",
      summary:
        "No active volcano feed item was found by the app. Open Vedur and SafeTravel before entering Reykjanes, especially for gas, road closures, and lava field access.",
      url: SAFETRAVEL_REYKJANES
    } satisfies LiveAlert
  ];
}

export async function getSafetyAlerts() {
  const settled = await Promise.allSettled([
    fetchVedurAlerts(),
    fetchSafeTravelAlerts(),
    fetchRoadNotifications()
  ]);
  return settled
    .flatMap((result) => (result.status === "fulfilled" ? result.value : []))
    .sort((a, b) => severityRank(b.severity) - severityRank(a.severity))
    .slice(0, 15);
}

function severityRank(severity: LiveAlert["severity"]) {
  return { info: 0, watch: 1, warning: 2, critical: 3 }[severity];
}
