export type AskRoute = "fast_trip_context" | "live_weather" | "live_safety" | "live_web";

export type AskClassification = {
  route: AskRoute;
  useWeather: boolean;
  useSafety: boolean;
  useWebSearch: boolean;
};

export function classifyAskQuestion(question: string): AskClassification {
  const normalized = question.trim().toLowerCase();
  const useWeather = /\b(weather|wind|gust|temperature|rain|cold|storm|forecast|visibility|fog|snow|ice)\b/.test(
    normalized
  );
  const useSafety =
    /\b(safe|safety|alert|warning|road|roads|closed|closure|disruption|volcano|eruption|lava|gas|reykjanes|danger|hazard)\b/.test(
      normalized
    );
  const useCurrentWeb =
    /\b(current|currently|today|now|latest|live|open|opening|hours|traffic|near me|nearby|where are we|where am i|can we go|is it open)\b/.test(
      normalized
    );

  if (useWeather) {
    return { route: "live_weather", useWeather: true, useSafety, useWebSearch: true };
  }
  if (useSafety) {
    return { route: "live_safety", useWeather: false, useSafety: true, useWebSearch: true };
  }
  if (useCurrentWeb) {
    return { route: "live_web", useWeather: false, useSafety: false, useWebSearch: true };
  }
  return { route: "fast_trip_context", useWeather: false, useSafety: false, useWebSearch: false };
}
