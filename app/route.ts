import { NextResponse } from "next/server";

const body = {
  error: "Waytale backend only.",
  endpoints: ["/api/realtime/session"]
};

const headers = {
  "Cache-Control": "no-store"
};

export function GET() {
  return NextResponse.json(body, { status: 404, headers });
}

export function HEAD() {
  return new Response(null, { status: 404, headers });
}
