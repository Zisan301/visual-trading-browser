param(
  [string]$ProjectDir = "E:\VS Code\visual-trading-browser",
  [switch]$Install,
  [switch]$RunApp
)

$ErrorActionPreference = "Stop"

function Write-Utf8NoBom {
  param(
    [Parameter(Mandatory=$true)][string]$Path,
    [Parameter(Mandatory=$true)][string]$Content
  )

  $Parent = Split-Path -Parent $Path
  if (-not (Test-Path $Parent)) {
    New-Item -ItemType Directory -Force -Path $Parent | Out-Null
  }

  $Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path, $Content, $Utf8NoBom)
}

function Backup-IfExists {
  param(
    [Parameter(Mandatory=$true)][string]$RelativePath,
    [Parameter(Mandatory=$true)][string]$BackupRoot
  )

  $Source = Join-Path $ProjectDir $RelativePath
  if (Test-Path $Source) {
    $Target = Join-Path $BackupRoot $RelativePath
    $TargetParent = Split-Path -Parent $Target
    New-Item -ItemType Directory -Force -Path $TargetParent | Out-Null
    Copy-Item -Path $Source -Destination $Target -Force
  }
}

if (-not (Test-Path $ProjectDir)) {
  throw "Project directory not found: $ProjectDir"
}

$PackageJson = Join-Path $ProjectDir "package.json"
if (-not (Test-Path $PackageJson)) {
  throw "package.json not found. Check ProjectDir: $ProjectDir"
}

$BackupDir = Join-Path $ProjectDir ("backup-m1-secure-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null

Backup-IfExists -RelativePath "electron\main.ts" -BackupRoot $BackupDir
Backup-IfExists -RelativePath "electron\preload.ts" -BackupRoot $BackupDir
Backup-IfExists -RelativePath "renderer\index.html" -BackupRoot $BackupDir

$MainTs = @'
import {
  app,
  BaseWindow,
  WebContentsView,
  ipcMain,
  session
} from "electron";
import type { Rectangle } from "electron";
import path from "path";
import fs from "fs";

const DEFAULT_HOME_URL = "https://example.com";
const DASHBOARD_WIDTH = 390;
const MIN_PLATFORM_WIDTH = 700;
const CAPTURE_PARTITION = "persist:visual-trading-browser-platform";

type TimingPhase = "WAITING" | "OBSERVING" | "FORMING_SCAN" | "LOCK_WINDOW";

type CaptureState = {
  running: boolean;
  sequence: number;
  phase: TimingPhase;
  candleSecond: number | null;
  candleRemaining: number | null;
  intervalMs: number;
  latestPath: string | null;
};

let mainWindow: BaseWindow | null = null;
let dashboardView: WebContentsView | null = null;
let platformView: WebContentsView | null = null;

let captureRunning = false;
let captureInFlight = false;
let captureTimer: NodeJS.Timeout | null = null;
let captureStartedAt: number | null = null;
let captureSequence = 0;
let latestCapturePath: string | null = null;
let lastCaptureIntervalMs = 1000;

function getCaptureDir() {
  const captureDir = path.join(app.getPath("userData"), "captures");
  fs.mkdirSync(captureDir, { recursive: true });
  return captureDir;
}

function isHttpUrl(value: string) {
  try {
    const parsed = new URL(value);
    return parsed.protocol === "https:" || parsed.protocol === "http:";
  } catch {
    return false;
  }
}

function normalizeUrl(input: string) {
  const trimmed = input.trim();

  if (!trimmed) {
    return DEFAULT_HOME_URL;
  }

  const withProtocol = /^https?:\/\//i.test(trimmed) ? trimmed : `https://${trimmed}`;

  if (!isHttpUrl(withProtocol)) {
    throw new Error("Only http:// and https:// platform URLs are allowed.");
  }

  return new URL(withProtocol).toString();
}

function getTimingPhase(second: number | null): TimingPhase {
  if (second === null) {
    return "WAITING";
  }

  if (second >= 55) {
    return "LOCK_WINDOW";
  }

  if (second >= 40) {
    return "FORMING_SCAN";
  }

  return "OBSERVING";
}

function getCaptureIntervalMs(phase: TimingPhase) {
  if (phase === "LOCK_WINDOW") {
    return 200;
  }

  if (phase === "FORMING_SCAN") {
    return 350;
  }

  return 1000;
}

function getCaptureState(): CaptureState {
  let candleSecond: number | null = null;
  let candleRemaining: number | null = null;

  if (captureStartedAt !== null) {
    candleSecond = Math.floor((Date.now() - captureStartedAt) / 1000) % 60;
    candleRemaining = 60 - candleSecond;
  }

  const phase = getTimingPhase(candleSecond);
  const intervalMs = getCaptureIntervalMs(phase);

  return {
    running: captureRunning,
    sequence: captureSequence,
    phase,
    candleSecond,
    candleRemaining,
    intervalMs,
    latestPath: latestCapturePath
  };
}

function sendDashboard(channel: string, payload: unknown) {
  if (!dashboardView || dashboardView.webContents.isDestroyed()) {
    return;
  }

  dashboardView.webContents.send(channel, payload);
}

function resizeViews() {
  if (!mainWindow || !dashboardView || !platformView) {
    return;
  }

  const [width, height] = mainWindow.getContentSize();
  const dashboardWidth = Math.min(DASHBOARD_WIDTH, Math.max(320, width - MIN_PLATFORM_WIDTH));
  const platformWidth = Math.max(0, width - dashboardWidth);

  const platformBounds: Rectangle = {
    x: 0,
    y: 0,
    width: platformWidth,
    height
  };

  const dashboardBounds: Rectangle = {
    x: platformWidth,
    y: 0,
    width: dashboardWidth,
    height
  };

  platformView.setBounds(platformBounds);
  dashboardView.setBounds(dashboardBounds);
}

function configurePlatformSecurity() {
  const platformSession = session.fromPartition(CAPTURE_PARTITION);

  platformSession.setPermissionRequestHandler((_webContents, _permission, callback) => {
    callback(false);
  });
}

function createMainWindow() {
  configurePlatformSecurity();

  mainWindow = new BaseWindow({
    width: 1500,
    height: 900,
    minWidth: 1100,
    minHeight: 700,
    title: "Visual Trading Browser"
  });

  dashboardView = new WebContentsView({
    webPreferences: {
      preload: path.join(__dirname, "preload.js"),
      nodeIntegration: false,
      contextIsolation: true,
      sandbox: false,
      webSecurity: true
    }
  });

  platformView = new WebContentsView({
    webPreferences: {
      session: session.fromPartition(CAPTURE_PARTITION),
      nodeIntegration: false,
      contextIsolation: true,
      sandbox: true,
      webSecurity: true,
      javascript: true
    }
  });

  mainWindow.contentView.addChildView(platformView);
  mainWindow.contentView.addChildView(dashboardView);

  resizeViews();
  mainWindow.on("resize", resizeViews);
  mainWindow.on("closed", () => {
    stopCaptureLoop();
    mainWindow = null;
    dashboardView = null;
    platformView = null;
  });

  dashboardView.webContents.loadFile(path.join(__dirname, "../renderer/index.html"));
  loadPlatformUrl(DEFAULT_HOME_URL);
}

function emitNavigationState() {
  if (!platformView) {
    return;
  }

  sendDashboard("browser:navigation-state", {
    url: platformView.webContents.getURL(),
    canGoBack: platformView.webContents.canGoBack(),
    canGoForward: platformView.webContents.canGoForward()
  });
}

function attachPlatformEvents() {
  if (!platformView) {
    return;
  }

  platformView.webContents.on("did-navigate", emitNavigationState);
  platformView.webContents.on("did-navigate-in-page", emitNavigationState);
  platformView.webContents.on("did-finish-load", emitNavigationState);

  platformView.webContents.on("will-navigate", (event, url) => {
    if (!isHttpUrl(url)) {
      event.preventDefault();
    }
  });

  platformView.webContents.setWindowOpenHandler(({ url }) => {
    if (isHttpUrl(url)) {
      platformView?.webContents.loadURL(url);
    }

    return { action: "deny" };
  });
}

function loadPlatformUrl(inputUrl: string) {
  if (!platformView) {
    throw new Error("Platform view is not ready.");
  }

  const url = normalizeUrl(inputUrl);
  platformView.webContents.loadURL(url);
  return url;
}

function scheduleNextCapture() {
  if (!captureRunning) {
    return;
  }

  if (captureTimer) {
    clearTimeout(captureTimer);
  }

  const state = getCaptureState();
  lastCaptureIntervalMs = state.intervalMs;
  sendDashboard("capture:state", state);

  captureTimer = setTimeout(() => {
    void captureOnce();
  }, state.intervalMs);
}

async function captureOnce() {
  if (!captureRunning || captureInFlight || !platformView) {
    scheduleNextCapture();
    return;
  }

  captureInFlight = true;

  try {
    const image = await platformView.webContents.capturePage();
    const imageSize = image.getSize();
    const captureDir = getCaptureDir();

    captureSequence += 1;
    latestCapturePath = path.join(captureDir, "latest-platform-capture.png");
    fs.writeFileSync(latestCapturePath, image.toPNG());

    const state = getCaptureState();

    sendDashboard("capture:frame", {
      ok: true,
      sequence: captureSequence,
      capturedAt: new Date().toISOString(),
      imageSize,
      phase: state.phase,
      candleSecond: state.candleSecond,
      candleRemaining: state.candleRemaining,
      intervalMs: lastCaptureIntervalMs,
      savedPath: latestCapturePath,
      previewDataUrl: image.resize({ width: 360 }).toDataURL()
    });
  } catch (error) {
    sendDashboard("capture:frame", {
      ok: false,
      error: String(error),
      capturedAt: new Date().toISOString()
    });
  } finally {
    captureInFlight = false;
    scheduleNextCapture();
  }
}

function startCaptureLoop() {
  captureRunning = true;
  captureStartedAt = Date.now();
  captureSequence = 0;
  latestCapturePath = null;

  void captureOnce();
  return getCaptureState();
}

function stopCaptureLoop() {
  captureRunning = false;

  if (captureTimer) {
    clearTimeout(captureTimer);
    captureTimer = null;
  }

  captureStartedAt = null;
  sendDashboard("capture:state", getCaptureState());
  return getCaptureState();
}

ipcMain.handle("browser:navigate", async (_event, url: string) => {
  const loadedUrl = loadPlatformUrl(url);
  return {
    ...getCaptureState(),
    url: loadedUrl
  };
});

ipcMain.handle("browser:back", async () => {
  if (platformView?.webContents.canGoBack()) {
    platformView.webContents.goBack();
  }

  emitNavigationState();
  return true;
});

ipcMain.handle("browser:forward", async () => {
  if (platformView?.webContents.canGoForward()) {
    platformView.webContents.goForward();
  }

  emitNavigationState();
  return true;
});

ipcMain.handle("browser:reload", async () => {
  platformView?.webContents.reload();
  return true;
});

ipcMain.handle("capture:start", async () => startCaptureLoop());
ipcMain.handle("capture:stop", async () => stopCaptureLoop());
ipcMain.handle("capture:get-state", async () => getCaptureState());

app.whenReady().then(() => {
  createMainWindow();
  attachPlatformEvents();

  app.on("activate", () => {
    if (mainWindow === null) {
      createMainWindow();
      attachPlatformEvents();
    }
  });
});

app.on("window-all-closed", () => {
  if (process.platform !== "darwin") {
    app.quit();
  }
});

'@

$PreloadTs = @'
import { contextBridge, ipcRenderer } from "electron";

type Listener = (payload: unknown) => void;

function subscribe(channel: string, callback: Listener) {
  const listener = (_event: Electron.IpcRendererEvent, payload: unknown) => {
    callback(payload);
  };

  ipcRenderer.on(channel, listener);

  return () => {
    ipcRenderer.removeListener(channel, listener);
  };
}

contextBridge.exposeInMainWorld("vtb", {
  navigate: (url: string) => ipcRenderer.invoke("browser:navigate", url),
  back: () => ipcRenderer.invoke("browser:back"),
  forward: () => ipcRenderer.invoke("browser:forward"),
  reload: () => ipcRenderer.invoke("browser:reload"),

  startCapture: () => ipcRenderer.invoke("capture:start"),
  stopCapture: () => ipcRenderer.invoke("capture:stop"),
  getCaptureState: () => ipcRenderer.invoke("capture:get-state"),

  onCaptureFrame: (callback: Listener) => subscribe("capture:frame", callback),
  onCaptureState: (callback: Listener) => subscribe("capture:state", callback),
  onNavigationState: (callback: Listener) => subscribe("browser:navigation-state", callback)
});

'@

$RendererIndex = @'
<!doctype html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta http-equiv="Content-Security-Policy" content="default-src 'self' data:; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self';" />
  <title>Visual Trading Browser Dashboard</title>
  <style>
    * { box-sizing: border-box; }

    body {
      margin: 0;
      min-height: 100vh;
      overflow: hidden;
      background: linear-gradient(180deg, #111827, #020617);
      color: #e5e7eb;
      font-family: Segoe UI, Arial, sans-serif;
    }

    .panel {
      height: 100vh;
      overflow-y: auto;
      padding: 16px;
      border-left: 1px solid #334155;
    }

    .brand {
      display: flex;
      justify-content: space-between;
      gap: 12px;
      align-items: flex-start;
      margin-bottom: 16px;
    }

    h1 { margin: 0; font-size: 22px; }
    h2 { margin: 0 0 12px; font-size: 16px; }
    p { margin: 6px 0; }

    .muted {
      color: #94a3b8;
      font-size: 14px;
      line-height: 1.4;
    }

    .card {
      background: rgba(15, 23, 42, 0.92);
      border: 1px solid #334155;
      border-radius: 18px;
      padding: 14px;
      margin-bottom: 14px;
    }

    .badge {
      border: 1px solid #334155;
      color: #cbd5e1;
      padding: 6px 10px;
      border-radius: 999px;
      font-size: 13px;
      white-space: nowrap;
    }

    .badge.live {
      border-color: #22c55e;
      color: #bbf7d0;
      background: rgba(34, 197, 94, 0.12);
    }

    label {
      display: block;
      color: #cbd5e1;
      font-size: 14px;
      margin-bottom: 10px;
    }

    input {
      width: 100%;
      margin-top: 6px;
      border-radius: 12px;
      border: 1px solid #475569;
      background: #020617;
      color: #f8fafc;
      padding: 10px 12px;
      outline: none;
    }

    .button-grid {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 8px;
      margin-top: 10px;
    }

    button {
      border: 0;
      border-radius: 12px;
      padding: 10px 12px;
      background: #2563eb;
      color: white;
      font-weight: 600;
      cursor: pointer;
    }

    button:hover { background: #1d4ed8; }

    button:disabled {
      background: #334155;
      color: #94a3b8;
      cursor: not-allowed;
    }

    .metric {
      display: flex;
      justify-content: space-between;
      padding: 10px 0;
      border-bottom: 1px solid #1e293b;
      gap: 12px;
    }

    .metric span { color: #94a3b8; }

    .metric strong {
      color: #f8fafc;
      text-align: right;
    }

    .phase-list {
      display: grid;
      gap: 8px;
      margin-top: 12px;
    }

    .phase-list div {
      padding: 10px;
      border-radius: 12px;
      border: 1px solid #334155;
      color: #cbd5e1;
    }

    .active-phase {
      border-color: #22c55e !important;
      background: rgba(34, 197, 94, 0.12);
      color: #bbf7d0 !important;
    }

    .preview {
      width: 100%;
      border-radius: 14px;
      border: 1px solid #334155;
      background: #020617;
      margin-top: 10px;
    }

    .small-info {
      font-size: 12px;
      color: #94a3b8;
      word-break: break-all;
    }

    .error { color: #fecaca; }
    .success { color: #bbf7d0; }
  </style>
</head>

<body>
  <aside class="panel">
    <div class="brand">
      <div>
        <h1>Visual Trading Browser</h1>
        <p class="muted">Secure M1 shell — platform is isolated in a separate WebContentsView.</p>
      </div>
      <span id="scannerBadge" class="badge">Scanner off</span>
    </div>

    <div class="card">
      <h2>Browser controls</h2>
      <p class="muted">Only http:// and https:// URLs are allowed. Remote pages cannot access this dashboard API.</p>

      <label>
        Platform URL
        <input id="urlInput" value="https://example.com" />
      </label>

      <div class="button-grid">
        <button id="goBtn">Go</button>
        <button id="backBtn">Back</button>
        <button id="forwardBtn">Forward</button>
        <button id="reloadBtn">Reload</button>
      </div>
    </div>

    <div class="card">
      <h2>Scanner</h2>
      <p class="muted">
        This M1 scanner captures the isolated platform view only for local preview/evidence. It does not click CALL/PUT, place trades, read cookies, or send frames to Python yet.
      </p>

      <div class="button-grid">
        <button id="startScannerBtn">Start scanner</button>
        <button id="stopScannerBtn" disabled>Stop scanner</button>
      </div>
    </div>

    <div class="card">
      <h2>Live timing logic</h2>

      <div class="metric">
        <span>Candle remaining</span>
        <strong id="candleRemaining">--</strong>
      </div>

      <div class="metric">
        <span>Current candle second</span>
        <strong id="currentSecond">--</strong>
      </div>

      <div class="metric">
        <span>Current phase</span>
        <strong id="currentPhase">WAITING</strong>
      </div>

      <div class="metric">
        <span>Scan interval</span>
        <strong id="scanInterval">--</strong>
      </div>

      <div class="phase-list">
        <div id="phaseObserve">00–40s: observe current candle</div>
        <div id="phaseForming">40–55s: detect forming strategy</div>
        <div id="phaseLock">55–59s: lock prediction window</div>
      </div>
    </div>

    <div class="card">
      <h2>Latest captured frame</h2>
      <p id="frameStatus" class="muted">No frame captured yet.</p>
      <img id="preview" class="preview" style="display:none;" />
      <div id="frameInfo" class="small-info"></div>
    </div>
  </aside>

  <script>
    const urlInput = document.getElementById("urlInput");

    const goBtn = document.getElementById("goBtn");
    const backBtn = document.getElementById("backBtn");
    const forwardBtn = document.getElementById("forwardBtn");
    const reloadBtn = document.getElementById("reloadBtn");

    const startScannerBtn = document.getElementById("startScannerBtn");
    const stopScannerBtn = document.getElementById("stopScannerBtn");
    const scannerBadge = document.getElementById("scannerBadge");

    const candleRemaining = document.getElementById("candleRemaining");
    const currentSecond = document.getElementById("currentSecond");
    const currentPhase = document.getElementById("currentPhase");
    const scanInterval = document.getElementById("scanInterval");

    const phaseObserve = document.getElementById("phaseObserve");
    const phaseForming = document.getElementById("phaseForming");
    const phaseLock = document.getElementById("phaseLock");

    const frameStatus = document.getElementById("frameStatus");
    const preview = document.getElementById("preview");
    const frameInfo = document.getElementById("frameInfo");

    function updatePhaseDisplay(state) {
      const phase = state.phase || "WAITING";

      candleRemaining.textContent = state.candleRemaining === null || state.candleRemaining === undefined
        ? "--"
        : String(state.candleRemaining) + "s";

      currentSecond.textContent = state.candleSecond === null || state.candleSecond === undefined
        ? "--"
        : String(state.candleSecond);

      currentPhase.textContent = phase;
      scanInterval.textContent = state.intervalMs ? String(state.intervalMs) + "ms" : "--";

      phaseObserve.classList.toggle("active-phase", phase === "OBSERVING");
      phaseForming.classList.toggle("active-phase", phase === "FORMING_SCAN");
      phaseLock.classList.toggle("active-phase", phase === "LOCK_WINDOW");
    }

    function setScannerRunning(running) {
      scannerBadge.textContent = running ? "Scanner on" : "Scanner off";
      scannerBadge.className = running ? "badge live" : "badge";
      startScannerBtn.disabled = running;
      stopScannerBtn.disabled = !running;
    }

    async function navigate() {
      try {
        const result = await window.vtb.navigate(urlInput.value);
        if (result.url) {
          urlInput.value = result.url;
        }
      } catch (error) {
        frameStatus.textContent = String(error);
        frameStatus.className = "error";
      }
    }

    goBtn.addEventListener("click", navigate);

    urlInput.addEventListener("keydown", function(event) {
      if (event.key === "Enter") navigate();
    });

    backBtn.addEventListener("click", function() {
      window.vtb.back();
    });

    forwardBtn.addEventListener("click", function() {
      window.vtb.forward();
    });

    reloadBtn.addEventListener("click", function() {
      window.vtb.reload();
    });

    startScannerBtn.addEventListener("click", async function() {
      const state = await window.vtb.startCapture();
      setScannerRunning(true);
      updatePhaseDisplay(state);
    });

    stopScannerBtn.addEventListener("click", async function() {
      const state = await window.vtb.stopCapture();
      setScannerRunning(false);
      updatePhaseDisplay(state);
    });

    window.vtb.onNavigationState(function(state) {
      if (state && state.url) {
        urlInput.value = state.url;
      }

      backBtn.disabled = !state || !state.canGoBack;
      forwardBtn.disabled = !state || !state.canGoForward;
    });

    window.vtb.onCaptureState(function(state) {
      setScannerRunning(Boolean(state.running));
      updatePhaseDisplay(state);
    });

    window.vtb.onCaptureFrame(function(frame) {
      if (!frame.ok) {
        frameStatus.textContent = "Capture error: " + frame.error;
        frameStatus.className = "error";
        return;
      }

      frameStatus.textContent =
        "Captured #" + frame.sequence +
        " at " + frame.capturedAt +
        " | phase: " + frame.phase;
      frameStatus.className = "success";

      preview.src = frame.previewDataUrl;
      preview.style.display = "block";

      frameInfo.innerHTML =
        "<p>Size: " + frame.imageSize.width + " × " + frame.imageSize.height + "</p>" +
        "<p>Saved: " + frame.savedPath + "</p>";
    });

    window.vtb.getCaptureState().then(function(state) {
      setScannerRunning(Boolean(state.running));
      updatePhaseDisplay(state);
    });
  </script>
</body>
</html>

'@

Write-Utf8NoBom -Path (Join-Path $ProjectDir "electron\main.ts") -Content $MainTs
Write-Utf8NoBom -Path (Join-Path $ProjectDir "electron\preload.ts") -Content $PreloadTs
Write-Utf8NoBom -Path (Join-Path $ProjectDir "renderer\index.html") -Content $RendererIndex

Write-Host "✅ M1 secure refactor applied." -ForegroundColor Green
Write-Host "Backup saved at: $BackupDir" -ForegroundColor Yellow
Write-Host "Changed files:" -ForegroundColor Cyan
Write-Host "- electron\main.ts"
Write-Host "- electron\preload.ts"
Write-Host "- renderer\index.html"

Push-Location $ProjectDir
try {
  if ($Install) {
    Write-Host "
Running npm install..." -ForegroundColor Cyan
    npm install
  }

  Write-Host "
Running npm run build:electron..." -ForegroundColor Cyan
  npm run build:electron

  if ($RunApp) {
    Write-Host "
Starting app with npm run dev..." -ForegroundColor Cyan
    npm run dev
  } else {
    Write-Host "
Build done. Start app with: npm run dev" -ForegroundColor Green
  }
}
finally {
  Pop-Location
}
