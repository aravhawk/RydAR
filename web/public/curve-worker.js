/* Parses curve files off the main thread so the page can scroll while they load. */
const lineCoords = new Map();

self.onmessage = (event) => {
  const message = event.data;
  if (message.kind === "curves") {
    const geojson = JSON.parse(new TextDecoder().decode(message.buffer));
    const list = geojson.features;
    const points = [];
    const coords = [];
    for (let i = 0; i < list.length; i += 1) {
      const feature = list[i];
      const geometry = feature.geometry;
      const line = geometry && geometry.type === "LineString" ? geometry.coordinates : null;
      if (!line || !line.length) continue;
      const mid = line[Math.floor(line.length / 2)];
      if (!mid || typeof mid[0] !== "number") continue;
      const props = feature.properties || {};
      points.push({
        type: "Feature",
        properties: {
          id: props.id,
          county: props.county,
          surface: props.surface,
          road: props.road || "",
          radius_ft: props.radius_ft,
          deflection_deg: props.deflection_deg,
          flags: props.flags || "",
        },
        geometry: { type: "Point", coordinates: mid },
      });
      coords.push(line);
    }
    lineCoords.set(message.index, coords);
    self.postMessage({ kind: "curves", index: message.index, features: points });
    return;
  }
  if (message.kind === "lines") {
    const coords = lineCoords.get(message.index) || [];
    lineCoords.delete(message.index);
    self.postMessage({ kind: "lines", index: message.index, coords });
  }
};
