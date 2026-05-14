import { NextRequest, NextResponse } from "next/server";

const OPENAI_SPEECH_URL = "https://api.openai.com/v1/audio/speech";

export async function POST(request: NextRequest) {
  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) {
    return NextResponse.json({ error: "OPENAI_API_KEY is not configured." }, { status: 503 });
  }

  const body = (await request.json()) as {
    text?: string;
    instructions?: string;
  };
  const text = body.text?.trim();
  if (!text) return NextResponse.json({ error: "Missing text." }, { status: 400 });

  const response = await fetch(OPENAI_SPEECH_URL, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      model: process.env.OPENAI_TTS_MODEL || "gpt-4o-mini-tts",
      voice: process.env.OPENAI_TTS_VOICE || "cedar",
      input: text.slice(0, 4096),
      instructions:
        body.instructions ||
        "Speak as a warm, lower-register English documentary storyteller and road-trip audio guide. Use natural pacing, crisp pronunciation, confident narration, and a calm sense of wonder.",
      response_format: "mp3"
    })
  });

  if (!response.ok) {
    let message = "OpenAI speech request failed.";
    try {
      const json = await response.json();
      message = json?.error?.message ?? message;
    } catch {
      message = await response.text();
    }
    return NextResponse.json({ error: message }, { status: response.status });
  }

  return new NextResponse(await response.arrayBuffer(), {
    headers: {
      "Content-Type": "audio/mpeg",
      "Cache-Control": "no-store"
    }
  });
}
