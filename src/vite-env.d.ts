interface Window {
  vtb: {
    saveLatestCapture: (dataUrl: string) => Promise<{
      ok: boolean;
      savedPath: string;
    }>;
  };
}

declare namespace JSX {
  interface IntrinsicElements {
    webview: any;
  }
}
