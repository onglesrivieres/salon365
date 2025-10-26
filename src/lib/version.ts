const VERSION_CHECK_INTERVAL = 60000; // Check every 60 seconds
const VERSION_KEY = 'app_version_hash';

let currentHash: string | null = null;

export async function initializeVersionCheck(): Promise<string | null> {
  try {
    const response = await fetch('/index.html?' + Date.now(), {
      cache: 'no-cache',
      headers: { 'Cache-Control': 'no-cache' }
    });

    if (!response.ok) return null;

    const html = await response.text();
    const hash = await generateHash(html);

    currentHash = hash;
    localStorage.setItem(VERSION_KEY, hash);

    return hash;
  } catch (error) {
    console.error('Failed to initialize version check:', error);
    return null;
  }
}

export async function checkForNewVersion(): Promise<boolean> {
  try {
    const response = await fetch('/index.html?' + Date.now(), {
      cache: 'no-cache',
      headers: { 'Cache-Control': 'no-cache' }
    });

    if (!response.ok) return false;

    const html = await response.text();
    const newHash = await generateHash(html);

    const storedHash = localStorage.getItem(VERSION_KEY) || currentHash;

    if (storedHash && newHash !== storedHash) {
      return true;
    }

    return false;
  } catch (error) {
    console.error('Failed to check for new version:', error);
    return false;
  }
}

export function startVersionCheck(onNewVersion: () => void): () => void {
  const intervalId = setInterval(async () => {
    const hasNewVersion = await checkForNewVersion();
    if (hasNewVersion) {
      onNewVersion();
    }
  }, VERSION_CHECK_INTERVAL);

  return () => clearInterval(intervalId);
}

async function generateHash(text: string): Promise<string> {
  const encoder = new TextEncoder();
  const data = encoder.encode(text);
  const hashBuffer = await crypto.subtle.digest('SHA-256', data);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  const hashHex = hashArray.map(b => b.toString(16).padStart(2, '0')).join('');
  return hashHex;
}
