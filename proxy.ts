import { NextResponse, type NextRequest } from "next/server";

const backendOnlyResponse = {
  error: "Waytale backend only.",
  endpoints: ["/api/realtime/session"]
};

export function proxy(request: NextRequest) {
  if (request.nextUrl.pathname.startsWith("/api/")) {
    return NextResponse.next();
  }

  return NextResponse.json(backendOnlyResponse, {
    status: 404,
    headers: {
      "Cache-Control": "no-store"
    }
  });
}

export const config = {
  matcher: ["/((?!api/).*)"]
};
