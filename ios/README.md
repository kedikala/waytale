# IcelandTourGuide iOS

Native SwiftUI iPhone app for GPS-triggered Iceland audio narration and voice questions.

## Open in Xcode

1. Install full Xcode, not only Command Line Tools.
2. Open `ios/IcelandTourGuide.xcodeproj`.
3. Select the `IcelandTourGuide` scheme.
4. In `Info.plist`, change `BackendBaseURL` from `http://localhost:3000` to your deployed Vercel backend URL for device testing.
5. Enable Maps SDK for iOS in Google Cloud, then set `GOOGLE_MAPS_API_KEY` in the Xcode scheme environment or build settings to enable the in-app Google map. The app also accepts `GOOGLE_MAPS_EMBED_API_KEY` as a fallback.
6. Run on iPhone.

## Local Backend

From the repo root:

```bash
npm install
npm run dev
```

`http://localhost:3000` works from the iOS Simulator only. For a physical iPhone, use your Vercel HTTPS URL or a temporary HTTPS tunnel and set `BackendBaseURL` to that URL.

Required environment:

```bash
OPENAI_API_KEY=your-openai-api-key
OPENAI_TTS_VOICE=marin
```

## Backend Requirements

The app expects the existing Next backend to expose:

- `POST /api/ask`
- `POST /api/speech`
- `POST /api/transcribe`

The Swift app never stores the OpenAI API key.

## V1 Behavior

- Drive Mode starts GPS, geofences, audio session, and foreground wake phrase listening.
- Important POIs trigger long OpenAI TTS narration with local MP3 caching.
- “Hey Waytale ...” works while Drive Mode is active and the app is foreground/screen-awake.
- Background behavior focuses on GPS/geofence reminders and queued/cached narration, not indefinite microphone listening.
