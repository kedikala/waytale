export type LatLng = {
  lat: number;
  lon: number;
};

export type SafetyTag =
  | "volcano"
  | "wind"
  | "road"
  | "reynisfjara"
  | "reservation"
  | "fuel"
  | "deadline"
  | "waterproof"
  | "wildlife"
  | "logistics";

export type StopCategory =
  | "Logistics"
  | "Drive"
  | "Food"
  | "Activity"
  | "Hike"
  | "Optional Hike"
  | "Optional Activity"
  | "Accommodation"
  | "Critical";

export type ItineraryStop = {
  id: string;
  date: string;
  day: string;
  time: string;
  duration: string;
  category: StopCategory;
  title: string;
  description: string;
  proTip?: string;
  coordinates?: LatLng;
  radiusM?: number;
  tags: SafetyTag[];
};

export type DriveLeg = {
  id: string;
  dayId: string;
  label: string;
  from: string;
  to: string;
  roadNumbers: string[];
  corridor: LatLng[];
  summary: string;
};

export type GuidePoiType =
  | "geology"
  | "volcano"
  | "glacier"
  | "waterfall"
  | "history"
  | "folklore"
  | "wildlife"
  | "driving-safety"
  | "viewpoint"
  | "town"
  | "fuel-logistics";

export type GuidePoi = {
  id: string;
  name: string;
  type: GuidePoiType;
  coordinates: LatLng;
  radiusM: number;
  priority: 1 | 2 | 3 | 4 | 5;
  routeTags: string[];
  narration: string;
  safetyNote?: string;
  source: "curated" | "wikidata-osm";
};

export type LiveAlert = {
  id: string;
  source: "Vedur" | "SafeTravel" | "Umferdin" | "Local";
  severity: "info" | "watch" | "warning" | "critical";
  title: string;
  summary: string;
  region?: string;
  url?: string;
  lastUpdated?: string;
};

export type GuideContext = {
  position?: LatLng;
  activeDayId: string;
  nearestStop?: ItineraryStop;
  nextStop?: ItineraryStop;
  activeLeg?: DriveLeg;
  nearbyPois: GuidePoi[];
  alerts: LiveAlert[];
};

export type Callout = {
  id: string;
  kind: "alert" | "stop" | "poi" | "route";
  priority: number;
  title: string;
  text: string;
  distanceM?: number;
  sourceId: string;
};
