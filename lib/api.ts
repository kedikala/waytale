import { NextResponse } from "next/server";
import type { LatLng } from "@/lib/types";

export function parsePosition(searchParams: URLSearchParams): LatLng | undefined {
  const lat = Number(searchParams.get("lat"));
  const lon = Number(searchParams.get("lon"));
  if (Number.isFinite(lat) && Number.isFinite(lon)) return { lat, lon };
  return undefined;
}

export function jsonError(error: unknown, status = 500) {
  const message = error instanceof Error ? error.message : "Unexpected error";
  return NextResponse.json({ error: message }, { status });
}
