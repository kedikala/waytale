import { NextResponse } from "next/server";
import { jsonError } from "@/lib/api";
import { getVolcanoAlerts } from "@/lib/officialFeeds";

export async function GET() {
  try {
    return NextResponse.json({ alerts: await getVolcanoAlerts() });
  } catch (error) {
    return jsonError(error);
  }
}
