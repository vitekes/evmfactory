import fs from 'fs';
import path from 'path';

const CONFIG_PATH = path.join(__dirname, '..', 'demo-config.json');

export function loadDemoConfig(): any {
  try {
    return JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf8'));
  } catch {
    return {};
  }
}

export function saveDemoConfig(data: any) {
  const current = loadDemoConfig();
  const merged: any = { ...current, ...data };
  if (current.modules || data.modules) {
    merged.modules = { ...current.modules, ...data.modules };
  }
  if (current.tokens || data.tokens) {
    merged.tokens = { ...current.tokens, ...data.tokens };
  }
  if (current.core || data.core) {
    merged.core = { ...current.core, ...data.core };
  }
  fs.mkdirSync(path.dirname(CONFIG_PATH), { recursive: true });
  fs.writeFileSync(CONFIG_PATH, JSON.stringify(merged, null, 2));
}
