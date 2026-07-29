import { app, BrowserWindow, ipcMain } from "electron";
import path from "path";
import fs from "fs";
import sharp from "sharp";
import { createWorker } from "tesseract.js";

let mainWindow: BrowserWindow | null = null;
let ocrWorker: any = null;
let ocrReady = false;

function createMainWindow() {
  mainWindow = new BrowserWindow({
    width: 1500,
    height: 900,
    minWidth: 1100,
    minHeight: 700,
    title: "Visual Trading Browser",
    webPreferences: {
      preload: path.join(__dirname, "preload.js"),
      nodeIntegration: false,
      contextIsolation: true,
      sandbox: false,
      webSecurity: true,
      webviewTag: true
    }
  });

  mainWindow.loadFile(path.join(__dirname, "../renderer/index.html"));

  mainWindow.on("closed", () => {
    mainWindow = null;
  });
}

async function getOcrWorker() {
  if (ocrReady && ocrWorker) {
    return ocrWorker;
  }

  ocrWorker = await createWorker("eng");

  await ocrWorker.setParameters({
    tessedit_char_whitelist: "0123456789:",
    tessedit_pageseg_mode: "7"
  });

  ocrReady = true;
  return ocrWorker;
}

function getCaptureDir() {
  const captureDir = path.join(app.getPath("userData"), "captures");
  fs.mkdirSync(captureDir, { recursive: true });
  return captureDir;
}

function extractCountdown(text: string) {
  const normalized = text
    .replace(/[Oo]/g, "0")
    .replace(/[Il|]/g, "1")
    .replace(/[;.\-]/g, ":")
    .replace(/\s+/g, " ")
    .trim();

  const mmssMatch = normalized.match(/\b0{1,2}:([0-5][0-9])\b/);

  if (mmssMatch) {
    const seconds = Number(mmssMatch[1]);

    if (!Number.isNaN(seconds) && seconds >= 0 && seconds <= 59) {
      return {
        raw: "00:" + String(seconds).padStart(2, "0"),
        seconds,
        sourceText: normalized
      };
    }
  }

  const compactMatch = normalized.match(/\b0{2}([0-5][0-9])\b/);

  if (compactMatch) {
    const seconds = Number(compactMatch[1]);

    if (!Number.isNaN(seconds) && seconds >= 0 && seconds <= 59) {
      return {
        raw: "00:" + String(seconds).padStart(2, "0"),
        seconds,
        sourceText: normalized
      };
    }
  }

  return null;
}

type CropRatio = {
  name: string;
  x: number;
  y: number;
  width: number;
  height: number;
};

function buildCropCandidates(): CropRatio[] {
  return [
    {
      name: "quotex_timer_tight",
      x: 0.54,
      y: 0.34,
      width: 0.13,
      height: 0.08
    },
    {
      name: "quotex_timer_medium",
      x: 0.50,
      y: 0.30,
      width: 0.22,
      height: 0.15
    },
    {
      name: "quotex_timer_wide",
      x: 0.44,
      y: 0.25,
      width: 0.35,
      height: 0.25
    },
    {
      name: "chart_center_right",
      x: 0.45,
      y: 0.20,
      width: 0.40,
      height: 0.45
    },
    {
      name: "chart_full_middle",
      x: 0.25,
      y: 0.18,
      width: 0.65,
      height: 0.55
    }
  ];
}

function ratioToPixelCrop(candidate: CropRatio, width: number, height: number) {
  const x = Math.max(0, Math.floor(width * candidate.x));
  const y = Math.max(0, Math.floor(height * candidate.y));

  const cropWidth = Math.min(
    width - x,
    Math.max(10, Math.floor(width * candidate.width))
  );

  const cropHeight = Math.min(
    height - y,
    Math.max(10, Math.floor(height * candidate.height))
  );

  return {
    left: x,
    top: y,
    width: cropWidth,
    height: cropHeight
  };
}

async function preprocessTimerCrop(
  sourceBuffer: Buffer,
  crop: {
    left: number;
    top: number;
    width: number;
    height: number;
  },
  invert: boolean,
  thresholdValue: number
) {
  let pipeline = sharp(sourceBuffer)
    .extract(crop)
    .resize({
      width: crop.width * 8,
      height: crop.height * 8,
      kernel: "nearest"
    })
    .grayscale()
    .normalize()
    .sharpen()
    .threshold(thresholdValue);

  if (invert) {
    pipeline = pipeline.negate();
  }

  return pipeline.png().toBuffer();
}

ipcMain.handle("capture:save-latest", async (_event, dataUrl: string) => {
  const captureDir = getCaptureDir();
  const latestPath = path.join(captureDir, "latest-chart-capture.png");

  const base64 = dataUrl.replace(/^data:image\/png;base64,/, "");
  fs.writeFileSync(latestPath, Buffer.from(base64, "base64"));

  return {
    ok: true,
    savedPath: latestPath
  };
});

ipcMain.handle("ocr:detect-countdown", async (_event, dataUrl: string) => {
  const captureDir = getCaptureDir();

  const base64 = dataUrl.replace(/^data:image\/png;base64,/, "");
  const sourceBuffer = Buffer.from(base64, "base64");

  const metadata = await sharp(sourceBuffer).metadata();
  const imageWidth = metadata.width || 1;
  const imageHeight = metadata.height || 1;

  const worker = await getOcrWorker();

  const attempts: any[] = [];
  const candidates = buildCropCandidates();
  const thresholds = [100, 130, 160, 190];

  for (let i = 0; i < candidates.length; i++) {
    const candidate = candidates[i];
    const crop = ratioToPixelCrop(candidate, imageWidth, imageHeight);

    for (const thresholdValue of thresholds) {
      for (const invert of [false, true]) {
        const processedBuffer = await preprocessTimerCrop(
          sourceBuffer,
          crop,
          invert,
          thresholdValue
        );

        const cropPath = path.join(
          captureDir,
          `latest-timer-crop-${i}-${thresholdValue}-${invert ? "invert" : "normal"}.png`
        );

        fs.writeFileSync(cropPath, processedBuffer);

        try {
          const result = await worker.recognize(processedBuffer);
          const text = result?.data?.text || "";
          const countdown = extractCountdown(text);

          const attempt = {
            candidate: candidate.name,
            thresholdValue,
            invert,
            crop,
            cropPath,
            ocrText: text,
            countdown
          };

          attempts.push(attempt);

          if (countdown) {
            const bestCropPath = path.join(captureDir, "latest-timer-crop-best.png");
            fs.writeFileSync(bestCropPath, processedBuffer);

            return {
              ok: true,
              countdown,
              ocrText: text,
              cropPath: bestCropPath,
              cropRect: crop,
              attempts
            };
          }
        } catch (error) {
          attempts.push({
            candidate: candidate.name,
            thresholdValue,
            invert,
            crop,
            cropPath,
            error: String(error)
          });
        }
      }
    }
  }

  return {
    ok: false,
    ocrText: attempts.map((item) => item.ocrText || item.error || "").join(" | "),
    cropPath: attempts.length > 0 ? attempts[0].cropPath : null,
    attempts
  };
});

app.whenReady().then(() => {
  createMainWindow();

  app.on("activate", () => {
    if (mainWindow === null) createMainWindow();
  });
});

app.on("before-quit", async () => {
  if (ocrWorker) {
    await ocrWorker.terminate();
  }
});

app.on("window-all-closed", () => {
  if (process.platform !== "darwin") app.quit();
});
