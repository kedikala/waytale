import { NextRequest, NextResponse } from "next/server";
import { parsePosition } from "@/lib/api";
import { findActiveLeg, getNearbyPois } from "@/lib/geo";

export async function GET(request: NextRequest) {
  const position = parsePosition(request.nextUrl.searchParams);
  const dayId = request.nextUrl.searchParams.get("dayId") ?? undefined;
  const activeLeg = findActiveLeg(position, dayId);
  return NextResponse.json({ activeLeg, nearbyPois: getNearbyPois(position, activeLeg, 8) });
}
