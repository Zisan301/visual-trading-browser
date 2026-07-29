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
