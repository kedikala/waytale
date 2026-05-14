import { NextResponse } from "next/server";
import { jsonError } from "@/lib/api";
import { getSafetyAlerts } from "@/lib/officialFeeds";

export async function GET() {
  try {
    return NextResponse.json({ alerts: await getSafetyAlerts() });
  } catch (error) {
    return jsonError(error);
  }
}
