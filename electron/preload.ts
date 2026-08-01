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

  connectAnalyzer: () => ipcRenderer.invoke("analyzer:connect"),
  disconnectAnalyzer: () => ipcRenderer.invoke("analyzer:disconnect"),
  getAnalyzerStatus: () => ipcRenderer.invoke("analyzer:get-status"),

  onCaptureFrame: (callback: Listener) => subscribe("capture:frame", callback),
  onCaptureState: (callback: Listener) => subscribe("capture:state", callback),
  onNavigationState: (callback: Listener) => subscribe("browser:navigation-state", callback),
  onAnalyzerStatus: (callback: Listener) => subscribe("analyzer:status", callback),
  onAnalyzerResult: (callback: Listener) => subscribe("analyzer:result", callback)
});
