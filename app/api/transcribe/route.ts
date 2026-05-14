import { NextRequest, NextResponse } from "next/server";

const OPENAI_TRANSCRIPTIONS_URL = "https://api.openai.com/v1/audio/transcriptions";

export async function POST(request: NextRequest) {
  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) {
    return NextResponse.json({ error: "OPENAI_API_KEY is not configured." }, { status: 503 });
  }

  const incoming = await request.formData();
  const file = incoming.get("file");
  if (!(file instanceof File)) {
    return NextResponse.json({ error: "Missing multipart file field named 'file'." }, { status: 400 });
  }

  const form = new FormData();
  form.set("file", file);
  form.set("model", process.env.OPENAI_TRANSCRIBE_MODEL || "gpt-4o-mini-transcribe");
  form.set("language", "en");
  form.set(
    "prompt",
    "Passenger voice questions for an Iceland road trip audio guide. Common phrase: Hey Waytale."
  );
  form.set("response_format", "json");

  const response = await fetch(OPENAI_TRANSCRIPTIONS_URL, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`
    },
    body: form
  });

  const data = await response.json().catch(() => undefined);
  if (!response.ok) {
    return NextResponse.json(
      { error: data?.error?.message ?? "OpenAI transcription request failed." },
      { status: response.status }
    );
  }

  return NextResponse.json({
    transcript: data?.text ?? "",
    raw: data
  });
}
