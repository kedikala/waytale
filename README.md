# Waytale

Waytale is an AI-powered road-trip voice guide for Iceland. It combines a native iPhone driving experience with a Next.js backend that handles OpenAI voice, transcription, realtime conversation, trip context, and live travel/safety lookups.

The app is built for a June 27-July 3, 2026 Iceland itinerary, but the architecture is meant to be reusable for other guided trips. The iOS app keeps secrets off-device and calls the backend for AI features, while the backend combines curated trip data, nearby points of interest, official feeds, and OpenAI models into spoken guidance.

## What It Does

- Provides GPS-aware audio narration for relevant itinerary stops and nearby points of interest.
- Lets passengers ask spoken questions through Waytale while driving.
- Uses OpenAI Realtime sessions for live conversational guidance.
- Generates text-to-speech narration and caches playback on device.
- Transcribes passenger audio questions through the backend.
- Shows in-app route, place search, and destination selection with Google Maps and Places APIs.
- Uses curated Iceland itinerary data, POIs, road legs, and safety notes.
- Pulls official-style context for weather, wind, road disruptions, volcano status, and safety alerts.

## Tech Stack

### iOS App

- SwiftUI for the native iPhone interface.
- CoreLocation for GPS, geofencing, and route-aware context.
- AVFoundation for audio playback, recording, and session routing.
- WebRTC for OpenAI Realtime voice sessions.
- Google Maps SDK for iOS for the in-app map.
- Google Places, Geocoding, Directions, and Routes APIs for destination search and navigation context.
- Local narration caching for downloaded/generated MP3 audio.

### Backend

- Next.js App Router route handlers.
- TypeScript.
- OpenAI APIs:
  - Responses API for question answering and web-search-backed answers.
  - Realtime API client-secret endpoint for live voice sessions.
  - Audio speech endpoint for TTS.
  - Audio transcription endpoint for voice questions.
- Curated TypeScript data files for itinerary stops, POIs, and drive legs.
- Vitest for backend parser/classifier tests.

### Deployment

- Designed for Vercel-hosted backend routes.
- The iOS app points at a configurable `BackendBaseURL`.
- Runtime secrets are expected in local `.env.local` or deployment environment variables, not in source control.

## Project Structure

```text
app/api/                         Next.js backend API routes
app/api/tools/                   Tool endpoints for realtime assistant context
data/                            Curated itinerary and POI data
ios/IcelandTourGuide/            Native SwiftUI iOS app
ios/IcelandTourGuideTests/       iOS unit tests
lib/                             Shared backend types, geo logic, feeds, narration helpers
test/                            Vitest backend tests
```

## Environment Variables

Create `.env.local` for local backend development:

```bash
OPENAI_API_KEY=your-openai-api-key
OPENAI_REALTIME_VOICE=cedar
OPENAI_ASK_MODEL=o4-mini
OPENAI_TTS_MODEL=gpt-4o-mini-tts
OPENAI_TTS_VOICE=cedar
OPENAI_TRANSCRIBE_MODEL=gpt-4o-mini-transcribe
```

For iOS maps, configure `GOOGLE_MAPS_API_KEY` or `GOOGLE_MAPS_EMBED_API_KEY` through Xcode build settings or scheme environment variables. Do not commit real API keys.

## Local Development

Install dependencies and run the backend:

```bash
npm install
npm run dev
```

Run checks:

```bash
npm run test
npm run build
npm audit
```

Open the iOS app with:

```text
ios/IcelandTourGuide.xcodeproj
```

For the iOS Simulator, `http://localhost:3000` can point at the local backend. For a physical iPhone, use a deployed HTTPS backend or an HTTPS tunnel and set `BackendBaseURL` in `Info.plist`.

## Public Repo Security Notes

- Do not commit `.env.local`, `.vercel`, `.next`, `node_modules`, Xcode user data, or build artifacts.
- Rotate any key that has ever been committed before making the repo public.
- If a secret exists in Git history, removing it from the current file is not enough. Rewrite history or publish a clean fresh repository.
- The deployed backend exposes OpenAI-backed endpoints. Before sharing a production URL broadly, add authentication, rate limiting, or origin/device controls to prevent quota abuse.
- Keep Google Maps API keys restricted in Google Cloud by app bundle ID, API scope, and platform where possible.

## Future Expansions

- Multi-trip support with selectable destinations, dates, routes, and travelers.
- A trip editor for importing itineraries from Google Sheets, calendar exports, PDFs, or travel bookings.
- Offline-first packs with pre-generated narration, POI data, and safety notes for low-connectivity drives.
- Personalized narration styles, languages, voice profiles, and family-friendly modes.
- Driver/passenger safety mode with stricter interaction limits while moving.
- Stronger backend auth, per-device session tokens, usage quotas, and abuse monitoring.
- Admin tools for curating POIs, reviewing generated narration, and publishing route packs.
- Real-time itinerary adaptation for weather, road closures, ferry changes, daylight, and reservation times.
- Broader live-data integrations with official road, weather, emergency, park, and tourism feeds.
- App Store production hardening: analytics, crash reporting, privacy disclosures, and subscription/payment options.

## Potential Use Cases

- Self-guided road trips with spoken, location-aware storytelling.
- National park, scenic byway, and heritage-route audio guides.
- Rental-car companion apps for tourism operators.
- Campus, museum, or city walking tours.
- Outdoor adventure guides that combine route context with safety alerts.
- Accessibility-focused travel narration for hands-free exploration.
- Concierge-style trip assistants for hotels, tour companies, and travel creators.

## License

This project is currently marked `UNLICENSED` in `package.json`. Add a license before accepting outside contributions or publishing for reuse.
