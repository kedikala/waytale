import type { DriveLeg, GuidePoi, ItineraryStop } from "@/lib/types";

const typeAngles: Record<GuidePoi["type"], string> = {
  geology:
    "Frame this as a landscape story: what the land is made of, why it looks this way, and what a traveler should notice out the window.",
  volcano:
    "Frame this as an active-earth story: explain the volcanic system, why it matters today, and what official warnings should be respected.",
  glacier:
    "Frame this as an ice-and-water story: explain how glaciers shape the road, rivers, lagoons, and black sand plains.",
  waterfall:
    "Frame this as a water-and-cliff story: explain the shape of the falls, where the water comes from, and the practical way to experience it.",
  history:
    "Frame this as a human story: connect the site to Icelandic identity, settlement, parliament, or local culture.",
  folklore:
    "Frame this as a folklore story, but keep one foot in reality by pointing out the natural hazard or landscape feature behind the tale.",
  wildlife:
    "Frame this as a wildlife story: explain what you might see, how to behave around it, and why the habitat matters.",
  "driving-safety":
    "Frame this as a safety-first guide note: make the risk memorable without sounding alarmist, and give a clear action.",
  viewpoint:
    "Frame this as a visual orientation: tell the traveler what they are looking at and why the view helps make sense of Iceland.",
  town:
    "Frame this as a useful traveler reset: explain why this town or area matters for food, fuel, pacing, and route decisions.",
  "fuel-logistics":
    "Frame this as a practical road-trip note: what to do here, why timing matters, and what happens if you skip it."
};

export function richPoiNarration(poi: GuidePoi) {
  const angle = typeAngles[poi.type];
  const safety = poi.safetyNote ? ` Safety note: ${poi.safetyNote}` : "";
  return [
    poi.narration,
    angle.replace("Frame this as", "This is"),
    "From the car, pay attention to the shape of the land, the road conditions, and how quickly the weather can change.",
    safety
  ]
    .filter(Boolean)
    .join(" ");
}

export function richStopNarration(stop: ItineraryStop) {
  const tip = stop.proTip ? ` Practical cue: ${stop.proTip}` : "";
  return `${stop.title}. ${stop.description}${tip} This stop matters because it is one of the planned anchors for this part of the trip. As you arrive, pay attention to the landscape, parking flow, weather, and whether the stop still fits your timing and energy.`;
}

export function routeNarration(leg: DriveLeg) {
  return `${leg.label}. ${leg.summary} You are on or near roads ${leg.roadNumbers.join(
    ", "
  )}. This drive segment is a good time to look at the changing landscape from the car, keep an eye on wind and fatigue, and think ahead to the next practical stop for fuel, food, or a weather check.`;
}
