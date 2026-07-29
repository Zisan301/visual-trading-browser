import { contextBridge, ipcRenderer } from "electron";

contextBridge.exposeInMainWorld("vtb", {
  saveLatestCapture: (dataUrl: string) =>
    ipcRenderer.invoke("capture:save-latest", dataUrl),

  detectCountdownFromImage: (dataUrl: string) =>
    ipcRenderer.invoke("ocr:detect-countdown", dataUrl)
});
