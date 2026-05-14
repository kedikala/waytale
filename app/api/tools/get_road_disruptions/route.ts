import { NextRequest, NextResponse } from "next/server";
import { jsonError } from "@/lib/api";
import { getRelevantRoadAlerts } from "@/lib/officialFeeds";

export async function GET(request: NextRequest) {
  try {
    const roads = request.nextUrl.searchParams.get("roads")?.split(",").filter(Boolean) ?? [];
    const regions = request.nextUrl.searchParams.get("regions")?.split(",").filter(Boolean) ?? [];
    return NextResponse.json({ alerts: await getRelevantRoadAlerts(roads, regions) });
  } catch (error) {
    return jsonError(error);
  }
}
