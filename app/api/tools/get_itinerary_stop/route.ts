import { NextRequest, NextResponse } from "next/server";
import { itineraryStops } from "@/data/itinerary";
import { findNearestStop } from "@/lib/geo";
import { parsePosition } from "@/lib/api";

export async function GET(request: NextRequest) {
  const id = request.nextUrl.searchParams.get("id");
  const dayId = request.nextUrl.searchParams.get("dayId") ?? undefined;
  const position = parsePosition(request.nextUrl.searchParams);
  if (id) return NextResponse.json({ stop: itineraryStops.find((stop) => stop.id === id) });
  return NextResponse.json(findNearestStop(position, dayId) ?? { stop: undefined });
}
