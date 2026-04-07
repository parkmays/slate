const BRIDGE_BASE = "http://127.0.0.1:8544";

export async function getBridgeHealth() {
  const res = await fetch(`${BRIDGE_BASE}/api/nle/health`);
  if (!res.ok) {
    throw new Error(`Bridge unavailable: ${res.status}`);
  }
  return res.json();
}

export async function getProjects() {
  const res = await fetch(`${BRIDGE_BASE}/api/nle/projects`);
  if (!res.ok) {
    throw new Error(`Unable to fetch projects: ${res.status}`);
  }
  return res.json();
}

export async function getClips(projectId) {
  const query = projectId ? `?projectId=${encodeURIComponent(projectId)}` : "";
  const res = await fetch(`${BRIDGE_BASE}/api/nle/clips${query}`);
  if (!res.ok) {
    throw new Error(`Unable to fetch clips: ${res.status}`);
  }
  return res.json();
}
