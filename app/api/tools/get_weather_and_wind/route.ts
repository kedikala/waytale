import { NextRequest, NextResponse } from "next/server";
import { jsonError, parsePosition } from "@/lib/api";
import { fetchWeatherStations } from "@/lib/officialFeeds";

export async function GET(request: NextRequest) {
  try {
    const position = parsePosition(request.nextUrl.searchParams);
    const stations = await fetchWeatherStations(position);
    const nearest = stations[0];
    return NextResponse.json({
      nearest,
      stations,
      spokenSummary: nearest
        ? `${nearest.name}: temperature ${nearest.temperature ?? "unknown"} C, wind ${nearest.wind?.speed ?? "unknown"} m/s, gusts ${nearest.wind?.gust ?? "unknown"} m/s.`
        : "No nearby official road weather station is available."
    });
  } catch (error) {
    return jsonError(error);
  }
}
