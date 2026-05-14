import { NextRequest, NextResponse } from "next/server";
import { parsePosition } from "@/lib/api";
import { summarizeContext } from "@/lib/geo";

export async function GET(request: NextRequest) {
  const position = parsePosition(request.nextUrl.searchParams);
  const dayId = request.nextUrl.searchParams.get("dayId") ?? undefined;
  return NextResponse.json(summarizeContext(position, dayId));
}
