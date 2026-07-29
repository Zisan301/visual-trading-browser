import { useEffect, useMemo, useRef, useState } from "react";

type ScannerFrame = {
  capturedAt?: string;
  width?: number;
  height?: number;
  savedPath?: string;
  dataUrl?: string;
  error?: string;
};

type PhaseStatus = "OBSERVING" | "FORMING_SCAN" | "LOCK_WINDOW";

function normalizeUrl(input: string): string {
  const trimmed = input.trim();

  if (!trimmed) return "https://example.com";

  if (trimmed.startsWith("http://") || trimmed.startsWith("https://")) {
    return trimmed;
  }

  return `https://${trimmed}`;
}

function getPredictionPhase(now: Date): PhaseStatus {
  const second = now.getSeconds();

  if (second < 40) return "OBSERVING";
  if (second < 55) return "FORMING_SCAN";
  return "LOCK_WINDOW";
}

function App() {
  const webviewRef = useRef<any>(null);

  const [url, setUrl] = useState("https://example.com");
  const [loadedUrl, setLoadedUrl] = useState("https://example.com");
  const [scannerRunning, setScannerRunning] = useState(false);
  const [latestFrame, setLatestFrame] = useState<ScannerFrame | null>(null);
  const [now, setNow] = useState(new Date());

  const captureTimerRef = useRef<number | null>(null);

  const phase = useMemo(() => getPredictionPhase(now), [now]);

  useEffect(() => {
    const timer = window.setInterval(() => setNow(new Date()), 250);

    return () => {
      window.clearInterval(timer);

      if (captureTimerRef.current !== null) {
        window.clearInterval(captureTimerRef.current);
      }
    };
  }, []);

  function navigate() {
    const nextUrl = normalizeUrl(url);
    setUrl(nextUrl);
    setLoadedUrl(nextUrl);
  }

  function goBack() {
    const webview = webviewRef.current;
    if (webview?.canGoBack?.()) {
      webview.goBack();
    }
  }

  function goForward() {
    const webview = webviewRef.current;
    if (webview?.canGoForward?.()) {
      webview.goForward();
    }
  }

  function reload() {
    webviewRef.current?.reload?.();
  }

  async function captureFrame() {
    const webview = webviewRef.current;

    if (!webview?.capturePage) {
      setLatestFrame({
        capturedAt: new Date().toISOString(),
        error: "Webview capturePage is not available yet."
      });
      return;
    }

    try {
      const image = await webview.capturePage();
      const dataUrl = image.toDataURL();
      const size = image.getSize();
      const saved = await window.vtb.saveLatestCapture(dataUrl);

      setLatestFrame({
        capturedAt: new Date().toISOString(),
        width: size.width,
        height: size.height,
        savedPath: saved.savedPath,
        dataUrl
      });
    } catch (error) {
      setLatestFrame({
        capturedAt: new Date().toISOString(),
        error: String(error)
      });
    }
  }

  function startScanner() {
    if (captureTimerRef.current !== null) {
      window.clearInterval(captureTimerRef.current);
    }

    captureFrame();

    captureTimerRef.current = window.setInterval(() => {
      captureFrame();
    }, 1000);

    setScannerRunning(true);
  }

  function stopScanner() {
    if (captureTimerRef.current !== null) {
      window.clearInterval(captureTimerRef.current);
      captureTimerRef.current = null;
    }

    setScannerRunning(false);
  }

  return (
    <main className="appShell">
      <section className="browserSide">
        <webview
          ref={webviewRef}
          className="platformWebview"
          src={loadedUrl}
          partition="persist:platform"
          allowpopups="true"
        />
      </section>

      <aside className="panel">
        <div className="brand">
          <div>
            <h1>Visual Trading Browser</h1>
            <p>Prediction-only browser shell — M1</p>
          </div>

          <span className={scannerRunning ? "badge live" : "badge"}>
            {scannerRunning ? "Scanner on" : "Scanner off"}
          </span>
        </div>

        <div className="card">
          <h2>Browser controls</h2>

          <label className="label">
            Platform URL
            <input
              className="input"
              value={url}
              onChange={(event) => setUrl(event.target.value)}
              onKeyDown={(event) => {
                if (event.key === "Enter") navigate();
              }}
            />
          </label>

          <div className="buttonGrid">
            <button onClick={navigate}>Go</button>
            <button onClick={goBack}>Back</button>
            <button onClick={goForward}>Forward</button>
            <button onClick={reload}>Reload</button>
          </div>
        </div>

        <div className="card">
          <h2>Scanner</h2>

          <p className="muted">
            This captures the visible website view automatically every second. Later we will crop only the chart area.
          </p>

          <div className="buttonGrid">
            <button onClick={startScanner} disabled={scannerRunning}>
              Start scanner
            </button>

            <button onClick={stopScanner} disabled={!scannerRunning}>
              Stop scanner
            </button>
          </div>
        </div>

        <div className="card">
          <h2>Live timing logic</h2>

          <div className="metric">
            <span>Current second</span>
            <strong>{now.getSeconds()}</strong>
          </div>

          <div className="metric">
            <span>Current phase</span>
            <strong>{phase}</strong>
          </div>

          <div className="phaseList">
            <div className={phase === "OBSERVING" ? "activePhase" : ""}>
              00–40s: observe current candle
            </div>

            <div className={phase === "FORMING_SCAN" ? "activePhase" : ""}>
              40–55s: detect forming strategy
            </div>

            <div className={phase === "LOCK_WINDOW" ? "activePhase" : ""}>
              55–59s: lock prediction
            </div>
          </div>
        </div>

        <div className="card">
          <h2>Latest captured frame</h2>

          {latestFrame?.error && (
            <p className="error">Capture error: {latestFrame.error}</p>
          )}

          {!latestFrame && <p className="muted">No frame captured yet.</p>}

          {latestFrame?.dataUrl && (
            <>
              <img
                className="preview"
                src={latestFrame.dataUrl}
                alt="Latest captured platform frame"
              />

              <div className="smallInfo">
                <p>Captured: {latestFrame.capturedAt}</p>
                <p>
                  Size: {latestFrame.width} × {latestFrame.height}
                </p>
                <p>Saved: {latestFrame.savedPath}</p>
              </div>
            </>
          )}
        </div>
      </aside>
    </main>
  );
}

export default App;
