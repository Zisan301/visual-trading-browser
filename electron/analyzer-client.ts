import WebSocket from "ws";

export type AnalyzerStatus = {
  enabled: boolean;
  connected: boolean;
  connecting: boolean;
  url: string;
  lastError: string | null;
  lastSequence: number | null;
  lastMessageAt: string | null;
};

export type AnalyzerFramePayload = {
  sequence: number;
  platform: string;
  asset: string;
  timeframe: string;
  capturedAt: string;
  phase: string;
  imageBase64: string;
};

type StatusListener = (status: AnalyzerStatus) => void;
type ResultListener = (payload: unknown) => void;

const DEFAULT_ANALYZER_WS_URL = "ws://127.0.0.1:8000/ws/analyze";

export class AnalyzerClient {
  private socket: WebSocket | null = null;
  private reconnectTimer: NodeJS.Timeout | null = null;
  private manuallyStopped = true;
  private readonly statusListeners = new Set<StatusListener>();
  private readonly resultListeners = new Set<ResultListener>();

  private status: AnalyzerStatus;

  constructor(private readonly url = DEFAULT_ANALYZER_WS_URL) {
    this.status = {
      enabled: false,
      connected: false,
      connecting: false,
      url,
      lastError: null,
      lastSequence: null,
      lastMessageAt: null
    };
  }

  onStatus(listener: StatusListener) {
    this.statusListeners.add(listener);
    listener(this.status);

    return () => {
      this.statusListeners.delete(listener);
    };
  }

  onResult(listener: ResultListener) {
    this.resultListeners.add(listener);

    return () => {
      this.resultListeners.delete(listener);
    };
  }

  getStatus() {
    return { ...this.status };
  }

  start() {
    this.manuallyStopped = false;
    this.setStatus({
      enabled: true,
      lastError: null
    });

    this.connect();
    return this.getStatus();
  }

  stop() {
    this.manuallyStopped = true;

    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }

    if (this.socket) {
      try {
        this.socket.close();
      } catch {
        // ignore close failure
      }
    }

    this.socket = null;

    this.setStatus({
      enabled: false,
      connected: false,
      connecting: false
    });

    return this.getStatus();
  }

  sendFrame(frame: AnalyzerFramePayload) {
    if (!this.socket || this.socket.readyState !== WebSocket.OPEN) {
      return false;
    }

    const payload = {
      metadata: {
        session_id: "LOCAL_SESSION",
        frame_sequence: frame.sequence,
        platform: frame.platform,
        asset: frame.asset,
        timeframe: frame.timeframe,
        captured_at: frame.capturedAt,
        phase: frame.phase
      },
      image_base64: frame.imageBase64
    };

    try {
      this.socket.send(JSON.stringify(payload));
      return true;
    } catch (error) {
      this.setStatus({
        lastError: error instanceof Error ? error.message : String(error)
      });

      return false;
    }
  }

  private connect() {
    if (this.manuallyStopped) {
      return;
    }

    if (
      this.socket &&
      (this.socket.readyState === WebSocket.OPEN ||
        this.socket.readyState === WebSocket.CONNECTING)
    ) {
      return;
    }

    this.setStatus({
      connecting: true,
      lastError: null
    });

    const socket = new WebSocket(this.url);
    this.socket = socket;

    socket.on("open", () => {
      this.setStatus({
        connected: true,
        connecting: false,
        lastError: null
      });
    });

    socket.on("message", (data) => {
      const text = typeof data === "string" ? data : data.toString("utf8");

      try {
        const payload = JSON.parse(text);

        if (typeof payload.sequence === "number") {
          this.setStatus({
            lastSequence: payload.sequence,
            lastMessageAt: new Date().toISOString()
          });
        } else {
          this.setStatus({
            lastMessageAt: new Date().toISOString()
          });
        }

        for (const listener of this.resultListeners) {
          listener(payload);
        }
      } catch (error) {
        this.setStatus({
          lastError: error instanceof Error ? error.message : String(error)
        });
      }
    });

    socket.on("error", (error) => {
      this.setStatus({
        lastError: error instanceof Error ? error.message : String(error)
      });
    });

    socket.on("close", () => {
      if (this.socket === socket) {
        this.socket = null;
      }

      this.setStatus({
        connected: false,
        connecting: false
      });

      if (!this.manuallyStopped) {
        this.scheduleReconnect();
      }
    });
  }

  private scheduleReconnect() {
    if (this.reconnectTimer) {
      return;
    }

    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = null;
      this.connect();
    }, 1500);
  }

  private setStatus(patch: Partial<AnalyzerStatus>) {
    this.status = {
      ...this.status,
      ...patch
    };

    for (const listener of this.statusListeners) {
      listener(this.getStatus());
    }
  }
}
