import type { GuidePoi } from "@/lib/types";

export const curatedPois: GuidePoi[] = [
  {
    id: "reykjanes-lava-fields",
    name: "Reykjanes Lava Fields",
    type: "geology",
    coordinates: { lat: 63.995, lon: -22.35 },
    radiusM: 3500,
    priority: 4,
    routeTags: ["41", "reykjanes"],
    narration:
      "You are crossing the Reykjanes lava fields, one of the first Iceland landscapes after leaving KEF. This peninsula sits on the Mid-Atlantic Ridge, so the fractured black rock around you is not ancient scenery; much of it is geologically young and still part of an active volcanic system.",
    safetyNote: "Wind can be strong on the open lava plains. Hold car doors with two hands.",
    source: "curated"
  },
  {
    id: "mount-esja",
    name: "Mount Esja",
    type: "viewpoint",
    coordinates: { lat: 64.245, lon: -21.72 },
    radiusM: 9000,
    priority: 3,
    routeTags: ["reykjavik"],
    narration:
      "Across the bay is Mount Esja, Reykjavík's horizon marker. Locals treat it like a weather gauge; if Esja is clear, the city feels open, and if it disappears into cloud, Iceland is reminding you who is in charge.",
    source: "curated"
  },
  {
    id: "thingvellir-rift",
    name: "Þingvellir Rift Zone",
    type: "history",
    coordinates: { lat: 64.2559, lon: -21.1295 },
    radiusM: 3500,
    priority: 5,
    routeTags: ["36", "golden-circle"],
    narration:
      "Þingvellir is both geology and government. The valley is opening as the North American and Eurasian plates pull apart, and it is also where Iceland's parliament first met in 930. You are driving into a place where the island's physical split and national identity overlap.",
    source: "curated"
  },
  {
    id: "laugarvatn-area",
    name: "Laugarvatn Geothermal Area",
    type: "geology",
    coordinates: { lat: 64.214, lon: -20.733 },
    radiusM: 5000,
    priority: 3,
    routeTags: ["365", "golden-circle"],
    narration:
      "Near Laugarvatn, geothermal heat is close enough to everyday life that bread is traditionally baked underground in hot sand. This is a useful mental model for Iceland: the same heat that makes pools and greenhouses possible also drives hazards.",
    source: "curated"
  },
  {
    id: "geysir-geothermal-field",
    name: "Geysir Geothermal Field",
    type: "geology",
    coordinates: { lat: 64.3137, lon: -20.3009 },
    radiusM: 2500,
    priority: 5,
    routeTags: ["35", "golden-circle"],
    narration:
      "The word geyser comes from Geysir here in Iceland. The reliable performer today is Strokkur, which vents pressure every few minutes. Watch the water dome rise right before eruption; that bulge is the cue.",
    safetyNote: "Stay on marked paths. The ground can be thin and boiling water is just below the surface.",
    source: "curated"
  },
  {
    id: "gullfoss-canyon",
    name: "Gullfoss Canyon",
    type: "waterfall",
    coordinates: { lat: 64.3261, lon: -20.1218 },
    radiusM: 2500,
    priority: 5,
    routeTags: ["35", "golden-circle"],
    narration:
      "Gullfoss is not just a pretty waterfall. It is a lesson in scale: the Hvítá river drops in two stages into a canyon that hides the lower fall until you are almost on top of it.",
    safetyNote: "The lower path can be wet and slippery from mist.",
    source: "curated"
  },
  {
    id: "hella-rangarsandur",
    name: "Rangárþing Plains",
    type: "town",
    coordinates: { lat: 63.8354, lon: -20.4002 },
    radiusM: 6000,
    priority: 2,
    routeTags: ["1", "south"],
    narration:
      "Around Hella the route opens into broad south-coast farm country. This is a good place to reset fuel, snacks, and layers before the road starts lining up waterfalls beneath glacier volcanoes.",
    source: "curated"
  },
  {
    id: "eyjafjallajokull",
    name: "Eyjafjallajökull",
    type: "volcano",
    coordinates: { lat: 63.63, lon: -19.62 },
    radiusM: 12000,
    priority: 5,
    routeTags: ["1", "south"],
    narration:
      "The glacier volcano to the north is Eyjafjallajökull, famous for the 2010 eruption that disrupted European air travel. On this stretch of the Ring Road, waterfalls pour off the old sea cliffs while glacier-capped volcanoes sit just inland.",
    source: "curated"
  },
  {
    id: "seljalandsfoss-pass",
    name: "Seljalandsfoss Cliffs",
    type: "waterfall",
    coordinates: { lat: 63.6156, lon: -19.9886 },
    radiusM: 2500,
    priority: 5,
    routeTags: ["1", "south"],
    narration:
      "Seljalandsfoss drops from a former sea cliff. The reason you can walk behind it is the undercut rock at the base, but the same shape also means spray hits from every direction.",
    safetyNote: "Waterproof pants matter here. The path behind the falls is slick.",
    source: "curated"
  },
  {
    id: "skogar-coast",
    name: "Skógar and Skógafoss",
    type: "waterfall",
    coordinates: { lat: 63.5321, lon: -19.5114 },
    radiusM: 3000,
    priority: 5,
    routeTags: ["1", "south"],
    narration:
      "Skógafoss is a clean curtain of water, but the bigger story is what starts above it. The trail follows the Skógá river past a chain of waterfalls into the highland route toward Þórsmörk.",
    source: "curated"
  },
  {
    id: "myrdalsjokull-katla",
    name: "Mýrdalsjökull and Katla",
    type: "volcano",
    coordinates: { lat: 63.65, lon: -19.05 },
    radiusM: 12000,
    priority: 4,
    routeTags: ["1", "south"],
    narration:
      "The ice cap inland is Mýrdalsjökull, which hides Katla, one of Iceland's major volcanoes. Katla is a reminder that glacier scenery here can also mean volcano, floodplain, and evacuation-route planning.",
    source: "curated"
  },
  {
    id: "dyrholaey-puffins",
    name: "Dyrhólaey Puffin Cliffs",
    type: "wildlife",
    coordinates: { lat: 63.3994, lon: -19.1264 },
    radiusM: 2800,
    priority: 5,
    routeTags: ["218", "south"],
    narration:
      "Dyrhólaey is one of the classic puffin stops in late June. The birds nest in grassy cliff edges, so the ropes are not decorative; they protect nests and protect you from fragile cliff edges.",
    safetyNote: "Stay behind barriers and expect strong wind on the promontory.",
    source: "curated"
  },
  {
    id: "reynisfjara-sneaker-waves",
    name: "Reynisfjara Sneaker Wave Zone",
    type: "driving-safety",
    coordinates: { lat: 63.4044, lon: -19.045 },
    radiusM: 2500,
    priority: 5,
    routeTags: ["215", "south"],
    narration:
      "Reynisfjara is beautiful and dangerous. Sneaker waves climb much farther up the beach than normal waves, and the beach uses a traffic-light warning system. Treat this as a safety stop first and a photo stop second.",
    safetyNote: "Never turn your back on the ocean. Red means closed; yellow means stay at least 30 meters back.",
    source: "curated"
  },
  {
    id: "eldhraun",
    name: "Eldhraun Lava Field",
    type: "geology",
    coordinates: { lat: 63.75, lon: -18.25 },
    radiusM: 14000,
    priority: 5,
    routeTags: ["1", "eastbound"],
    narration:
      "The mossy lava around you is Eldhraun, created by the Laki eruption in the 1780s. It is one of the largest lava flows in historical times and had climate effects far beyond Iceland.",
    safetyNote: "Do not walk on the moss; it is fragile and takes decades to recover.",
    source: "curated"
  },
  {
    id: "fjadrargljufur-canyon",
    name: "Fjaðrárgljúfur Canyon",
    type: "geology",
    coordinates: { lat: 63.7713, lon: -18.1728 },
    radiusM: 2500,
    priority: 4,
    routeTags: ["206", "eastbound"],
    narration:
      "Fjaðrárgljúfur looks delicate from above, but it is a deep glacial-river canyon. The boardwalks exist because viral tourism damaged the moss; this is a place to stay on the built path.",
    source: "curated"
  },
  {
    id: "skeidararsandur",
    name: "Skeiðarársandur Outwash Plain",
    type: "glacier",
    coordinates: { lat: 63.94, lon: -17.35 },
    radiusM: 16000,
    priority: 5,
    routeTags: ["1", "eastbound"],
    narration:
      "This wide open plain is Skeiðarársandur, a glacial outwash plain. It was shaped by meltwater and jökulhlaups, sudden glacial floods that can rearrange roads, bridges, and rivers.",
    source: "curated"
  },
  {
    id: "vatnajokull",
    name: "Vatnajökull Ice Cap",
    type: "glacier",
    coordinates: { lat: 64.05, lon: -16.8 },
    radiusM: 20000,
    priority: 5,
    routeTags: ["1", "eastbound"],
    narration:
      "Vatnajökull dominates the southeast. It is Europe's largest ice cap by volume, and many of the tongues and lagoons you see along this road are pieces of that one ice system reaching toward the coast.",
    source: "curated"
  },
  {
    id: "jokulsarlon-lagoon",
    name: "Jökulsárlón Glacier Lagoon",
    type: "glacier",
    coordinates: { lat: 64.0473, lon: -16.1791 },
    radiusM: 3000,
    priority: 5,
    routeTags: ["1", "eastbound", "westbound"],
    narration:
      "Jökulsárlón is young for something that feels timeless. The lagoon expanded as the glacier retreated, and icebergs now drift from Breiðamerkurjökull through the lagoon and out toward Diamond Beach.",
    source: "curated"
  },
  {
    id: "vik-fuel",
    name: "Vík Fuel and Weather Check",
    type: "fuel-logistics",
    coordinates: { lat: 63.4186, lon: -19.006 },
    radiusM: 2500,
    priority: 4,
    routeTags: ["1", "westbound", "south"],
    narration:
      "Vík is the key south-coast reset point. On your long westbound day, this is the last reliable fuel and food stop for a while, and a smart place to reassess wind and fatigue.",
    safetyNote: "Fill up here before continuing west on Day 5.",
    source: "curated"
  },
  {
    id: "solheimasandur-plain",
    name: "Sólheimasandur Black Sand Plain",
    type: "geology",
    coordinates: { lat: 63.4591, lon: -19.3647 },
    radiusM: 3500,
    priority: 4,
    routeTags: ["1", "westbound", "south"],
    narration:
      "Sólheimasandur is visually spare: black sand, wind, and a long flat walk. That emptiness is exactly why the plane wreck became iconic, but it also means weather and fatigue matter more than the distance suggests.",
    safetyNote: "Do not start the walk if wind or energy is poor.",
    source: "curated"
  },
  {
    id: "reykjanes-geopark",
    name: "Reykjanes UNESCO Global Geopark",
    type: "volcano",
    coordinates: { lat: 63.89, lon: -22.45 },
    radiusM: 11000,
    priority: 5,
    routeTags: ["425", "43", "reykjanes"],
    narration:
      "Reykjanes is an active volcanic peninsula, not a museum landscape. The road crosses fissures, geothermal fields, and young lava; this is why SafeTravel and Vedur checks are part of the plan today.",
    safetyNote: "Follow closures for gas, lava crust, and road access without improvising.",
    source: "curated"
  },
  {
    id: "gunnuhver-steam",
    name: "Gunnuhver Steam Field",
    type: "folklore",
    coordinates: { lat: 63.819, lon: -22.6877 },
    radiusM: 2500,
    priority: 4,
    routeTags: ["425", "reykjanes"],
    narration:
      "Gunnuhver combines geothermal force with folklore. The story says a troublesome ghost named Gunna was trapped in the spring, but the real danger is simpler: boiling mud, steam, and unstable ground.",
    safetyNote: "Stay on boardwalks.",
    source: "curated"
  },
  {
    id: "bridge-between-continents",
    name: "Bridge Between Continents",
    type: "geology",
    coordinates: { lat: 63.8685, lon: -22.6764 },
    radiusM: 2500,
    priority: 4,
    routeTags: ["425", "reykjanes"],
    narration:
      "The Bridge Between Continents is a symbolic crossing of the rift between tectonic plates. The actual plate boundary is a broad zone, not a single crack, but this is still a good physical way to understand the island.",
    source: "curated"
  },
  {
    id: "fagradalsfjall-lava",
    name: "Fagradalsfjall and Sundhnúkur Lava Fields",
    type: "volcano",
    coordinates: { lat: 63.889, lon: -22.273 },
    radiusM: 6000,
    priority: 5,
    routeTags: ["43", "reykjanes"],
    narration:
      "This area has been the center of recent Reykjanes eruptions. Lava fields can look solid before they are safe, and volcanic gas can change the risk quickly with wind direction.",
    safetyNote: "Use official closures and gas warnings as hard limits.",
    source: "curated"
  }
];
